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
public final class WorkoutSessionCoordinator {
    /// Plantilla de la sesión (lo planeado). Inmutable.
    public let template: SessionTemplate

    /// Fase actual que la UI presenta (idle / active / resting / paused / finished).
    public private(set) var phase: WorkoutSessionPhase

    private let exerciseNames: [ExerciseID: String]
    private var controller: ActiveWorkoutController
    private let completer: SetCompleter
    private let restTimer: RestTimer
    private let summaryBuilder: WorkoutSummaryBuilder
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

    private var rest: RestTimerState = RestTimerState(recommendedSeconds: 0)

    public init(
        template: SessionTemplate,
        exerciseNames: [ExerciseID: String] = [:],
        completer: SetCompleter = SetCompleter(),
        restTimer: RestTimer = RestTimer(),
        summaryBuilder: WorkoutSummaryBuilder = WorkoutSummaryBuilder(),
        lastPerformedWeightLookup: @escaping (ExerciseID) -> Double? = { _ in nil },
        clock: @escaping () -> Date = { Date() },
        initialPhase: WorkoutSessionPhase = .idle,
        pendingQueue: PendingOperationQueueStore? = nil,
        setPersistenceGuard: SetPersistenceGuard = SetPersistenceGuard(),
        onSessionFinished: @escaping (WorkoutSessionRecord) async -> Void = { _ in }
    ) {
        self.template = template
        self.exerciseNames = exerciseNames
        self.controller = ActiveWorkoutController()
        self.completer = completer
        self.restTimer = restTimer
        self.summaryBuilder = summaryBuilder
        self.lastPerformedWeightLookup = lastPerformedWeightLookup
        self.clock = clock
        self.phase = initialPhase
        self.pendingQueue = pendingQueue
        self.setPersistenceGuard = setPersistenceGuard
        self.onSessionFinished = onSessionFinished
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
        do {
            _ = try controller.finish(at: now ?? clock())
            _ = try controller.complete(at: now ?? clock())
        } catch {
            throw WorkoutSessionError.invalidTransition
        }
        return closeAsFinished()
    }

    /// Abandona la sesión activa (no borra los sets ya realizados).
    @discardableResult
    public func abandon(now: Date? = nil) throws -> WorkoutSessionPhase {
        do {
            _ = try controller.abandon(at: now ?? clock())
        } catch {
            throw WorkoutSessionError.notActive
        }
        return closeAsFinished()
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
        guard let session = controller.current?.session else { throw WorkoutSessionError.notActive }
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
        guard let session = controller.current?.session else { throw WorkoutSessionError.notActive }
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

    /// Skip del descanso activo.
    public func skipRest() {
        rest = restTimer.skip(rest)
        publishActivePhase()
    }

    /// Extiende el descanso activo.
    public func extendRest(by seconds: Int = 30) {
        guard rest.isActive else { return }
        rest = restTimer.extend(rest, by: seconds, now: clock())
        publishActivePhase()
    }

    /// Estado del descanso actual (para un ticker de UI).
    public var currentRest: RestTimerState { rest }

    /// Re-sincroniza `phase` con el reloj inyectado (lo llama un ticker de UI).
    public func tick() {
        phase = currentPhase()
    }

    /// Presenta una fase actualizada a partir del reloj inyectado.
    private func currentPhase() -> WorkoutSessionPhase {
        if let current = currentSet() {
            switch controller.current?.session.lifecycle {
            case .paused?:
                return .paused(current)
            case .completed?, .abandoned?:
                return closeAsFinished()
            default:
                return rest.isActive ? .resting(current, rest: rest) : .active(current)
            }
        }
        return closeAsFinished()
    }

    private func publishActivePhase() {
        phase = currentPhase()
    }

    private func applyCompletedSet(
        _ updated: WorkoutSessionRecord,
        planned: PlannedSet
    ) -> WorkoutSessionPhase {
        // Persistir el set en la sesión viva ANTES de transicionar la UI (PR-0603).
        controller = ActiveWorkoutController(
            state: ActiveWorkoutState(session: updated, lastTransitionAt: clock())
        )
        // Encolar el set como operación crítica durabile (offline-first, PR-0203):
        // durable e idempotente → un retry no duplica SetRecord y la app funciona con
        // el backend apagado. La escritura local de la cola es sincrónica y atómica.
        if let set = updated.sets.last, let pendingQueue {
            _ = try? setPersistenceGuard.enqueueSetSave(
                set,
                in: updated.id,
                queue: pendingQueue,
                now: clock()
            )
        }
        if let current = currentSet() {
            rest = restTimer.autoStart(
                afterCompletedWarmup: planned.prescription.isWarmup,
                prescription: planned.prescription,
                now: clock()
            )
            let next: WorkoutSessionPhase =
                rest.isActive ? .resting(current, rest: rest) : .active(current)
            phase = next
            return next
        }
        rest = RestTimerState(recommendedSeconds: 0)
        return closeAsFinished()
    }

    private func closeAsFinished() -> WorkoutSessionPhase {
        let summary: WorkoutSummary
        if let live = controller.current?.session {
            summary = summaryBuilder.summarize(live)
            // Cerrar con persistencia durabile del registro final (best-effort, async):
            // el repositorio local se actualiza fuera del hilo de la UI del coordinador.
            Task { await onSessionFinished(live) }
        } else {
            summary = summaryBuilder.summarize(WorkoutSessionRecord(lifecycle: .completed))
        }
        let next: WorkoutSessionPhase = .finished(summary)
        phase = next
        return next
    }

    private func exerciseFallbackName(_ id: ExerciseID) -> String {
        // No inventar nombres: fallback textual al prefijo del UUID si no está en el catálogo.
        "Ejercicio \(id.rawValue.uuidString.prefix(8))"
    }
}