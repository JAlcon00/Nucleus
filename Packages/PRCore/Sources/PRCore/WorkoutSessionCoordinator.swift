//
//  WorkoutSessionCoordinator.swift
//  PRCore
//
//  Created by PR.
//
//  App-core coordinador del estreno de sesión (WORKOUT MODE, plan §8, PR-0602/0603/
//  0604/0605 wiring). Orquesta los engines de dominio deterministas que DECIDEN
//  (`ActiveWorkoutController`, `SetCompleter`, `RestTimer`, `WorkoutSummaryBuilder`)
//  y conserva un estado observable que la UI sólo presenta. No contiene reglas de
//  negocio: delega en el dominio y mapea a un modelo de presentación reutilizable.
//  Funciona offline y persiste el set ANTES de cualquier transición de UI final.
//

import Foundation
import Observation
import PRDomain

/// Modelo de presentación del set actual que la UI renderiza (sin reglas de negocio).
public struct ActiveWorkoutSetUI: Equatable, Sendable {
    /// Índice del set dentro de `plannedSets` de la plantilla (0-based).
    public let index: Int
    /// Total de sets planeados en la plantilla.
    public let total: Int
    /// Nombre canónico del ejercicio (lookup del catálogo; fallback al ID si no existe).
    public let exerciseName: String
    /// ¿Es set de calentamiento?
    public let isWarmup: Bool
    /// Borrador con target precargados (one-tap si coincide).
    public let draft: SetCompletionDraft

    public init(index: Int, total: Int, exerciseName: String, isWarmup: Bool, draft: SetCompletionDraft) {
        self.index = index
        self.total = total
        self.exerciseName = exerciseName
        self.isWarmup = isWarmup
        self.draft = draft
    }
}

/// Estado observable que expone la pantalla de entrenamiento activo (WORKOUT MODE).
public enum WorkoutSessionPhase: Equatable, Sendable {
    case idle
    /// Hay una sesión activa y se muestra el set actual (mapa del set + input uno-tap).
    case active(ActiveWorkoutSetUI)
    /// Descanso automático tras un working set; `next` describe el siguiente set.
    case resting(ActiveWorkoutSetUI, rest: RestTimerState)
    /// Sesión en pausa.
    case paused(ActiveWorkoutSetUI)
    /// Sesión terminada; `summary` lista para presentación.
    case finished(WorkoutSummary)
}

/// Problemas del coordinador de sesión (mapea errores de dominio al caso de uso).
public enum WorkoutSessionError: Error, Equatable, Sendable {
    case noTemplate
    case notActive
    case alreadyActive
    case invalidTransition
    case allSetsCompleted
    case setValidation(String)
}

/// Coordinador de una sesión de entrenamiento activa (WORKOUT MODE).
///
/// Fuente única de verdad: `ActiveWorkoutController` (la sesión viva). El set actual
/// es el siguiente de `plannedSets` según lo ya realizado. Responsabilidades (sólo
/// orquestación; el dominio decide):
/// - ciclo de vida: start/pause/resume/finish/complete/abandon.
/// - completar set: uno-tap si coincide con el target; edición accesible de peso/reps;
///   SIEMPRE persiste en la sesión ANTES de transicionar la UI.
/// - descanso: arranque automático tras working set; skip/extend; sobrevive vía wall-clock.
/// - resumen: `WorkoutSummaryBuilder` tras completar (o abandonar) la sesión.
@MainActor
@Observable
public final class WorkoutSessionCoordinator: Identifiable {
    /// Plantilla de la sesión (lo planeado). Inmutable.
    public let template: SessionTemplate

    /// Identidad estable (la de la plantilla): permite presentar la sesión con
    /// `fullScreenCover(item:)`, que entrega el coordinador ya no opcional.
    public nonisolated var id: UUID { template.id }

    /// Fase actual que la UI presenta (idle / active / resting / paused / finished).
    public private(set) var phase: WorkoutSessionPhase

    private let exerciseNames: [ExerciseID: String]
    private var controller: ActiveWorkoutController
    private let completer: SetCompleter
    private let restTimer: RestTimer
    private let summaryBuilder: WorkoutSummaryBuilder
    /// Baselines de PR derivados del historial local (PR-1004). Vacío ⇒ no se celebra
    /// ningún récord (nunca se inventa uno sin referencia previa).
    private let recordBaselines: [ExerciseID: PersonalRecordBaseline]
    private let celebrationBuilder = PRCelebrationBuilder()
    private let celebrationPresenter: PRCelebrationPresenter
    private let lastPerformedWeightLookup: (ExerciseID) -> Double?
    private let clock: () -> Date

    /// Cola de operaciones críticas pendientes (PR-0203): en ella se encola, persistida y
    /// de forma idempotente, cada set completado. Durable → la app funciona con el backend
    /// apagado y un retry no duplica SetRecord. `nil` si no hay infraestructura de cola.
    private let pendingQueue: PendingOperationQueueStore?
    /// Guardia que encola el `saveSet` crítico con clave de idempotencia estable.
    private let setPersistenceGuard: SetPersistenceGuard
    /// Hook (async, best-effort) al cerrar la sesión para persistir el registro durabile
    /// en el repositorio local. La UI del coordinador permanece sincrónica (PR-0203/PR-0302).
    private let onSessionFinished: (WorkoutSessionRecord) async -> Void
    /// Escritura durable y SÍNCRONA del registro de la sesión (SCRUM-24). Se llama al
    /// iniciar y en cada cambio de estado (serie, pausa, reanudar, descanso, fin) ANTES de
    /// que la UI avance; nunca desde `tick()`. `nil` = sin disco (sólo memoria).
    private let persistSession: ((WorkoutSessionRecord) throws -> Void)?

    /// `true` si la última escritura a disco falló: la sesión sigue viva en memoria pero la
    /// UI debe avisar (nunca se traga el error de un dato de entrenamiento).
    public private(set) var persistenceFailed = false

    /// Resumen de la sesión ya cerrada. Se calcula UNA vez; después `tick()` sólo lo lee.
    private var finalSummary: WorkoutSummary?

    private var rest: RestTimerState = RestTimerState(recommendedSeconds: 0)

    public init(
        template: SessionTemplate,
        exerciseNames: [ExerciseID: String] = [:],
        completer: SetCompleter = SetCompleter(),
        restTimer: RestTimer = RestTimer(),
        summaryBuilder: WorkoutSummaryBuilder = WorkoutSummaryBuilder(),
        recordBaselines: [ExerciseID: PersonalRecordBaseline] = [:],
        celebrationPresenter: PRCelebrationPresenter = PRCelebrationPresenter(),
        lastPerformedWeightLookup: @escaping (ExerciseID) -> Double? = { _ in nil },
        clock: @escaping () -> Date = { Date() },
        initialPhase: WorkoutSessionPhase = .idle,
        pendingQueue: PendingOperationQueueStore? = nil,
        setPersistenceGuard: SetPersistenceGuard = SetPersistenceGuard(),
        onSessionFinished: @escaping (WorkoutSessionRecord) async -> Void = { _ in },
        persistSession: ((WorkoutSessionRecord) throws -> Void)? = nil,
        restoring record: WorkoutSessionRecord? = nil
    ) {
        self.template = template
        self.exerciseNames = exerciseNames
        self.controller = ActiveWorkoutController()
        self.completer = completer
        self.restTimer = restTimer
        self.summaryBuilder = summaryBuilder
        self.recordBaselines = recordBaselines
        self.celebrationPresenter = celebrationPresenter
        self.lastPerformedWeightLookup = lastPerformedWeightLookup
        self.clock = clock
        self.phase = initialPhase
        self.pendingQueue = pendingQueue
        self.setPersistenceGuard = setPersistenceGuard
        self.onSessionFinished = onSessionFinished
        self.persistSession = persistSession
        if let record {
            // Retomar una sesión guardada (SCRUM-24): el descanso se recalcula contra el
            // reloj con la hora de fin guardada; si ya pasó, queda en 0 y la serie lista.
            do {
                self.controller = try ActiveWorkoutController.restore(
                    from: ActiveWorkoutSnapshot(session: record, lastTransitionAt: clock())
                )
                self.rest = record.rest?.timerState(at: clock()) ?? RestTimerState(recommendedSeconds: 0)
                self.phase = currentPhase()
            } catch {
                // Estado final: no se restaura (se queda idle; quien llama decide).
                self.phase = .idle
            }
        }
    }
}

// MARK: - Lifecycle

extension WorkoutSessionCoordinator {

    /// Abre la sesión activa a partir de la plantilla (se queda idle si ya hay una).
    public func start(now: Date? = nil) -> WorkoutSessionPhase {
        guard !template.plannedSets.isEmpty else { return .idle }
        do {
            _ = try controller.start(from: template, at: now ?? clock())
            rest = RestTimerState(recommendedSeconds: 0)
            persistLive()   // la sesión ya está en disco como `active` desde el primer momento
            let next = currentPhase()
            phase = next
            return next
        } catch {
            // Si ya hay sesión activa, no sobrescribir (mismo contrato que la pantalla Hoy).
            return .idle
        }
    }

    /// Pausa la sesión activa.
    public func pause(now: Date? = nil) throws -> WorkoutSessionPhase {
        guard let current = currentSet() else { throw WorkoutSessionError.notActive }
        do {
            _ = try controller.pause(at: now ?? clock())
            persistLive()
            let next: WorkoutSessionPhase = .paused(current)
            phase = next
            return next
        } catch {
            throw WorkoutSessionError.invalidTransition
        }
    }

    /// Reanuda la sesión pausada.
    public func resume(now: Date? = nil) throws -> WorkoutSessionPhase {
        guard let current = currentSet() else { throw WorkoutSessionError.notActive }
        do {
            _ = try controller.resume(at: now ?? clock())
            persistLive()
            let next: WorkoutSessionPhase =
                rest.isActive ? .resting(current, rest: rest) : .active(current)
            phase = next
            return next
        } catch {
            throw WorkoutSessionError.invalidTransition
        }
    }

    /// Cierra la sesión (finish → complete) y genera el resumen (PR-0605).
    @discardableResult
    public func complete(now: Date? = nil) throws -> WorkoutSessionPhase {
        // Completar una sesión ya completada es idempotente (p. ej. la última serie la cerró
        // y la UI vuelve a pedir el cierre): no cambia nada ni vuelve a escribir. Cualquier
        // OTRA transición desde un estado final se rechaza.
        if controller.current?.session.lifecycle == .completed {
            return finalizeSession()
        }
        try completeSession(at: now ?? clock())
        return finalizeSession()
    }

    /// Abandona la sesión activa (no borra los sets ya realizados).
    @discardableResult
    public func abandon(now: Date? = nil) throws -> WorkoutSessionPhase {
        do {
            _ = try controller.abandon(at: now ?? clock())
        } catch {
            throw WorkoutSessionError.notActive
        }
        return finalizeSession()
    }

    /// Celebración de los récords del resumen (PR-1004): el dominio decide qué y la
    /// explicación según nivel; el presentador produce los textos localizados.
    /// `nil` si no hay récords.
    public func celebration(for summary: WorkoutSummary, level: CoachingDetailLevel) -> PRCelebrationPresentation? {
        celebrationBuilder
            .celebration(for: summary.records, exerciseNames: exerciseNames, level: level)
            .map(celebrationPresenter.present)
    }

    /// Snapshot persistible para restaurar tras kill/relaunch.
    public func snapshot() throws -> ActiveWorkoutSnapshot {
        try controller.snapshot()
    }
}

// MARK: - Current set & completion

extension WorkoutSessionCoordinator {

    /// Set siguiente a realizar (= `session.sets.count` dentro de `plannedSets`).
    public func currentSet() -> ActiveWorkoutSetUI? {
        guard let session = controller.current?.session else { return nil }
        let index = session.sets.count
        guard index < template.plannedSets.count else { return nil }
        let planned = template.plannedSets[index]
        let draft = completer.preload(
            for: planned,
            lastPerformedWeight: lastPerformedWeightLookup(planned.exerciseID)
        )
        return ActiveWorkoutSetUI(
            index: index,
            total: template.plannedSets.count,
            exerciseName: exerciseNames[planned.exerciseID] ?? exerciseFallbackName(planned.exerciseID),
            isWarmup: planned.prescription.isWarmup,
            draft: draft
        )
    }

    /// Completa el set actual con uno-tap si el input coincide con el target; si no,
    /// lanza `.setValidation` para que la UI ofrezca edición. Persiste ANTES de
    /// transicionar la UI (PR-0603).
    public func completeCurrentSet(
        input: SetCompletionInput? = nil,
        now: Date? = nil
    ) throws -> WorkoutSessionPhase {
        let session = try activeSessionForSet()
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let planned = template.plannedSets[current.index]

        let resolved = try completer.oneTap(
            input: input ?? SetCompletionInput(
                weight: current.draft.targetWeight,
                unit: current.draft.targetUnit,
                reps: current.draft.targetReps
            ),
            matches: current.draft,
            planned: planned,
            in: session,
            performedAt: now ?? clock()
        )
        guard let updated = resolved else {
            throw WorkoutSessionError.setValidation("input no coincide con target; edición requerida")
        }
        return applyCompletedSet(updated, planned: planned)
    }

    /// Registra un working set editado (peso/reps accesibles) y persiste antes de la UI final.
    public func recordEditedSet(
        weight: Double,
        reps: Int,
        unit: LoadUnit? = nil,
        now: Date? = nil
    ) throws -> WorkoutSessionPhase {
        let session = try activeSessionForSet()
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let planned = template.plannedSets[current.index]
        do {
            let updated = try completer.recordSet(
                input: SetCompletionInput(
                    weight: weight,
                    unit: unit ?? current.draft.targetUnit,
                    reps: reps
                ),
                planned: planned,
                in: session,
                performedAt: now ?? clock()
            )
            return applyCompletedSet(updated, planned: planned)
        } catch {
            throw WorkoutSessionError.setValidation("\(error)")
        }
    }

    /// La sesión en la que se puede registrar una serie: sólo una sesión `active`. En un
    /// estado final (completada/abandonada) no se agrega nada; en pausa hay que reanudar.
    private func activeSessionForSet() throws -> WorkoutSessionRecord {
        guard let session = controller.current?.session else { throw WorkoutSessionError.notActive }
        switch session.lifecycle {
        case .active: return session
        case .completed, .abandoned: throw WorkoutSessionError.notActive
        case .planned, .preparing, .paused, .finishing: throw WorkoutSessionError.invalidTransition
        }
    }

    /// Skip del descanso activo.
    public func skipRest() {
        rest = restTimer.skip(rest)
        persistRest()
        publishActivePhase()
    }

    /// Extiende el descanso activo.
    public func extendRest(by seconds: Int = 30) {
        guard rest.isActive else { return }
        rest = restTimer.extend(rest, by: seconds, now: clock())
        persistRest()
        publishActivePhase()
    }

    /// Estado del descanso actual (para un ticker de UI).
    public var currentRest: RestTimerState { rest }

    /// Re-sincroniza `phase` con el reloj inyectado (lo llama un ticker de UI).
    public func tick() {
        phase = currentPhase()
    }

    /// Presenta una fase actualizada a partir del reloj inyectado. NUNCA escribe en disco:
    /// `tick()` se llama cada segundo y sólo los cambios de estado persisten.
    private func currentPhase() -> WorkoutSessionPhase {
        guard let session = controller.current?.session else { return phase }
        switch session.lifecycle {
        case .completed, .abandoned:
            return finalSummary.map(WorkoutSessionPhase.finished) ?? finalizeSession()
        case .planned, .preparing, .active, .paused, .finishing:
            break
        }
        guard let current = currentSet() else {
            // Todas las series hechas pero la sesión no llegó a cerrarse (p. ej. cierre
            // forzado justo después de la última serie): se completa ahora.
            do {
                try completeSession(at: clock())
            } catch {
                return phase
            }
            return finalizeSession()
        }
        if session.lifecycle == .paused { return .paused(current) }
        return rest.isActive ? .resting(current, rest: rest) : .active(current)
    }

    private func publishActivePhase() {
        phase = currentPhase()
    }

    private func applyCompletedSet(
        _ updated: WorkoutSessionRecord,
        planned: PlannedSet
    ) -> WorkoutSessionPhase {
        // El descanso nace junto con la serie: se guarda como hora de fin en el MISMO
        // registro, en una sola escritura atómica.
        var session = updated
        let hasNext = updated.sets.count < template.plannedSets.count
        let nextRest = hasNext
            ? restTimer.autoStart(
                afterCompletedWarmup: planned.prescription.isWarmup,
                prescription: planned.prescription,
                now: clock()
            )
            : RestTimerState(recommendedSeconds: 0)
        session.rest = nextRest.isActive ? RestSnapshot(nextRest) : nil
        controller.replaceSession(session, at: clock())

        // Encolar el set como operación crítica durable (offline-first, PR-0203): idempotente,
        // un retry no duplica SetRecord. Un fallo se registra en `persistenceFailed`.
        if let set = session.sets.last, let pendingQueue {
            do {
                _ = try setPersistenceGuard.enqueueSetSave(set, in: session.id, queue: pendingQueue, now: clock())
            } catch {
                persistenceFailed = true
            }
        }
        // Persistir ANTES de transicionar la UI (PR-0603).
        persistLive()

        guard hasNext else {
            // Última serie: la sesión pasa a `completed` y se muestra el resumen (SCRUM-25).
            do {
                try completeSession(at: clock())
            } catch {
                persistenceFailed = true
            }
            rest = RestTimerState(recommendedSeconds: 0)
            return finalizeSession()
        }
        rest = nextRest
        guard let current = currentSet() else { return finalizeSession() }
        let next: WorkoutSessionPhase = rest.isActive ? .resting(current, rest: rest) : .active(current)
        phase = next
        return next
    }

    // MARK: - Persistencia (SCRUM-24)

    /// Guarda la sesión viva. Un fallo no interrumpe el entrenamiento (sigue en memoria) pero
    /// queda a la vista en `persistenceFailed`; una escritura posterior exitosa lo limpia
    /// porque contiene todas las series.
    private func persistLive() {
        guard let persistSession, let live = controller.current?.session else { return }
        do {
            try persistSession(live)
            persistenceFailed = false
        } catch {
            persistenceFailed = true
        }
    }

    /// Refleja el descanso actual (omitir/extender) en el registro y lo guarda.
    private func persistRest() {
        guard var session = controller.current?.session else { return }
        session.rest = rest.isActive ? RestSnapshot(rest) : nil
        controller.replaceSession(session, at: clock())
        persistLive()
    }

    // MARK: - Cierre (SCRUM-25)

    /// finishing → completed (desde pausa reanuda primero). Una sesión en estado final
    /// rechaza cualquier otra transición.
    private func completeSession(at now: Date) throws {
        do {
            if controller.current?.session.lifecycle == .paused {
                _ = try controller.resume(at: now)
            }
            _ = try controller.finish(at: now)
            _ = try controller.complete(at: now)
        } catch {
            throw WorkoutSessionError.invalidTransition
        }
    }

    /// Cierra la presentación: guarda el registro final UNA vez, calcula el resumen UNA vez
    /// y avisa UNA vez. Llamarla de nuevo (p. ej. desde `tick()`) sólo devuelve el resumen.
    @discardableResult
    private func finalizeSession() -> WorkoutSessionPhase {
        if let finalSummary {
            let done: WorkoutSessionPhase = .finished(finalSummary)
            phase = done
            return done
        }
        let summary: WorkoutSummary
        if let live = controller.current?.session {
            persistLive()
            summary = summaryBuilder.summarize(live, now: clock(), baselines: recordBaselines)
            let hook = onSessionFinished
            Task { await hook(live) }
        } else {
            summary = summaryBuilder.summarize(WorkoutSessionRecord(lifecycle: .completed))
        }
        finalSummary = summary
        let next: WorkoutSessionPhase = .finished(summary)
        phase = next
        return next
    }

    private func exerciseFallbackName(_ id: ExerciseID) -> String {
        // No inventar nombres: fallback textual al prefijo del UUID si no está en el catálogo.
        "Ejercicio \(id.rawValue.uuidString.prefix(8))"
    }
}