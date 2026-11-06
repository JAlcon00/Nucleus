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

/// La serie actual va en superset (SCRUM-224): con quién y en qué lado del par.
public struct ActiveSupersetUI: Equatable, Sendable {
    /// ¿Es el primero del par (A1)? Si no, el segundo (A2).
    public let isFirst: Bool
    /// Nombre de la pareja.
    public let partnerName: String

    public init(isFirst: Bool, partnerName: String) {
        self.isFirst = isFirst
        self.partnerName = partnerName
    }
}

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
    /// RIR objetivo de esta serie (lo planeó el motor; SCRUM-200). `nil` en calentamiento.
    public let targetRIR: ClosedRange<Int>?
    /// Sólo en la última serie de trabajo del ejercicio: si conviene dropset.
    public let dropset: DropsetAdvice?
    /// Número de esta serie entre las de la sesión ("Serie X de Y"): hechas + 1. Con
    /// ejercicios en espera no coincide con `index` (SCRUM-212).
    public let position: Int
    /// Si va en superset con su pareja todavía junta (SCRUM-224); `nil` si va solo.
    public let superset: ActiveSupersetUI?
    /// ¿El peso depende de la máquina? Para decir "en esta máquina" (SCRUM-237).
    public let loadIsPerMachine: Bool

    public init(
        index: Int,
        total: Int,
        exerciseName: String,
        isWarmup: Bool,
        draft: SetCompletionDraft,
        targetRIR: ClosedRange<Int>? = nil,
        dropset: DropsetAdvice? = nil,
        position: Int? = nil,
        superset: ActiveSupersetUI? = nil,
        loadIsPerMachine: Bool = false
    ) {
        self.index = index
        self.total = total
        self.exerciseName = exerciseName
        self.isWarmup = isWarmup
        self.draft = draft
        self.targetRIR = targetRIR
        self.dropset = dropset
        self.position = position ?? index + 1
        self.superset = superset
        self.loadIsPerMachine = loadIsPerMachine
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

/// Qué pasó al tocar "Máquina ocupada" (SCRUM-233), con los nombres para la pantalla.
public enum OccupiedOutcome: Equatable, Sendable {
    /// `next` se adelantó y `after` va justo después.
    case advanced(next: String, after: String)
    /// Nada se pudo adelantar: la persona decide (SCRUM-234). No cambió nada todavía.
    case needsChoice(OccupiedChoice)
    /// Eligió esperar: `exercise` va al final.
    case movedToEnd(exercise: String)
}

/// Un sustituto equivalente que se ofrece en la hoja (SCRUM-234).
public struct SubstituteOption: Identifiable, Equatable, Sendable {
    public let id: ExerciseID
    public let name: String
    /// ¿Trabaja exactamente los mismos músculos principales? Para la razón corta.
    public let sameMuscles: Bool

    public init(id: ExerciseID, name: String, sameMuscles: Bool) {
        self.id = id
        self.name = name
        self.sameMuscles = sameMuscles
    }
}

/// Lo que se ofrece cuando no hay nada que adelantar.
public struct OccupiedChoice: Equatable, Sendable, Identifiable {
    public let exercise: String
    /// Hasta 3, el mejor primero. Vacío si no hay ninguno equivalente y seguro.
    public let options: [SubstituteOption]
    /// Con dolor moderado o alto en esta sesión no se ofrecen sustitutos (SCRUM-231).
    public let painRecommendation: PainRecommendation?
    /// Es lo único que queda: esperar no lo mueve de lugar.
    public let isOnlyExercise: Bool

    public var id: String { exercise }

    public init(exercise: String, options: [SubstituteOption], painRecommendation: PainRecommendation?, isOnlyExercise: Bool) {
        self.exercise = exercise
        self.options = options
        self.painRecommendation = painRecommendation
        self.isOnlyExercise = isOnlyExercise
    }
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
    /// Plantilla de la sesión (lo planeado para hoy). Sólo cambia con una sustitución en vivo
    /// (SCRUM-234), que toca lo pendiente y nunca lo hecho.
    public private(set) var template: SessionTemplate

    /// Identidad estable (la de la plantilla): permite presentar la sesión con
    /// `fullScreenCover(item:)`, que entrega el coordinador ya no opcional.
    public nonisolated let id: UUID

    /// Fase actual que la UI presenta (idle / active / resting / paused / finished).
    public private(set) var phase: WorkoutSessionPhase

    private let exerciseNames: [ExerciseID: String]
    /// Consejo de dropset por ejercicio (lo decide `IntensityAdvisor`; SCRUM-200).
    private let dropsetAdvice: [ExerciseID: DropsetAdvice]
    /// Músculos de cada ejercicio para decir dónde dolió (SCRUM-226; `PainMuscleOptions`).
    private let exerciseMuscles: [ExerciseID: [MuscleGroup.ID]]
    /// Catálogo por ID: el gate de fatiga de "Máquina ocupada" necesita los ejercicios.
    private let exercises: [ExerciseID: Exercise]
    /// Restricciones al empezar: ningún sustituto las salta (SCRUM-234).
    private let restrictions: [TrainingRestriction]
    /// Gimnasio de esta sesión y última carga de cada ejercicio (SCRUM-237).
    private let gymID: GymID?
    private let loads: LastLoadIndex
    /// El último "Máquina ocupada" y cuántas series había entonces (SCRUM-233).
    private var lastOccupied: (outcome: OccupiedOutcome, setCount: Int)?
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
        dropsetAdvice: [ExerciseID: DropsetAdvice] = [:],
        exerciseMuscles: [ExerciseID: [MuscleGroup.ID]] = [:],
        catalog: [Exercise] = [],
        restrictions: [TrainingRestriction] = [],
        gymID: GymID? = nil,
        loadHistory: [WorkoutSessionRecord] = [],
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
        self.id = template.id
        self.restrictions = restrictions
        self.gymID = gymID
        self.loads = LastLoadIndex(history: loadHistory)
        self.exerciseNames = exerciseNames
        self.dropsetAdvice = dropsetAdvice
        self.exerciseMuscles = exerciseMuscles
        self.exercises = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// Lo que el reloj necesita saber de esta sesión (SCRUM-253): la misma cola y la misma
    /// precarga que esta pantalla. `nil` sin sesión.
    public func watchSnapshot() -> WatchSessionSnapshot? {
        guard let state = controller.current else { return nil }
        let session = state.session
        let names = exerciseNames
        let drafts = template.plannedSets.reduce(into: [PlannedSet: SetCompletionDraft]()) { result, planned in
            result[planned] = completer.preload(for: planned, lastPerformedWeight: lastWeight(for: planned, session: session))
        }
        let completer = self.completer
        return WatchSessionSnapshotBuilder.snapshot(WatchSessionSnapshotInput(
            session: session,
            template: template,
            revision: Int(state.lastTransitionAt.timeIntervalSince1970 * 1_000),
            exerciseName: { id in names[id] ?? "Ejercicio \(id.rawValue.uuidString.prefix(8))" },
            draft: { planned in drafts[planned] ?? completer.preload(for: planned) }
        ))
    }

    /// Set siguiente a realizar: por ejercicio, siguiendo la cola (esperas y saltos,
    /// SCRUM-212). Sin cambios en la cola es `plannedSets[sets.count]`, como antes.
    public func currentSet() -> ActiveWorkoutSetUI? {
        guard let session = controller.current?.session,
              let index = WorkoutQueue.nextPlannedIndex(
                template: template, sets: session.sets, state: session.queue ?? .empty
              ) else { return nil }
        let planned = template.plannedSets[index]
        let draft = completer.preload(for: planned, lastPerformedWeight: lastWeight(for: planned, session: session))
        let isWarmup = planned.prescription.isWarmup
        // El dropset sólo se sugiere en la última serie de trabajo de ese ejercicio.
        let isLastWorkSet = !isWarmup && !template.plannedSets[(index + 1)...].contains {
            $0.exerciseID == planned.exerciseID && !$0.prescription.isWarmup
        }
        // Lo pendiente de un saltado ya no cuenta para "de Y".
        let skippedPending = (session.queue?.skipped ?? []).reduce(0) { total, exercise in
            let planned = template.plannedSets.filter { $0.exerciseID == exercise }.count
            let done = session.sets.filter { $0.exerciseID == exercise }.count
            return total + max(0, planned - done)
        }
        // SCRUM-224: el par sólo se muestra mientras los dos sigan juntos en la cola.
        let superset: ActiveSupersetUI? = template.superset(containing: planned.exerciseID).flatMap { pair in
            guard WorkoutQueue.isTogether(pair, state: session.queue ?? .empty),
                  let partner = pair.partner(of: planned.exerciseID) else { return nil }
            return ActiveSupersetUI(
                isFirst: pair.first == planned.exerciseID,
                partnerName: exerciseNames[partner] ?? exerciseFallbackName(partner)
            )
        }
        return ActiveWorkoutSetUI(
            index: index,
            total: template.plannedSets.count - skippedPending,
            exerciseName: exerciseNames[planned.exerciseID] ?? exerciseFallbackName(planned.exerciseID),
            isWarmup: isWarmup,
            draft: draft,
            targetRIR: isWarmup ? nil : planned.prescription.targetRIR,
            dropset: isLastWorkSet ? dropsetAdvice[planned.exerciseID] : nil,
            position: session.sets.count + 1,
            superset: superset,
            loadIsPerMachine: exercises[planned.exerciseID]?.equipment.loadIsPerMachine ?? false
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
        // SCRUM-237: la serie queda con su máquina, sin preguntar nada.
        if let index = session.sets.indices.last {
            session.sets[index].machineProfileID = machine(for: planned.exerciseID)
        }
        let hasNext = WorkoutQueue.nextPlannedIndex(
            template: template, sets: updated.sets, state: updated.queue ?? .empty
        ) != nil
        // SCRUM-224: a mitad de la ronda del superset (A → B) no hay descanso.
        let midRound = WorkoutQueue.continuesSupersetRound(
            after: planned.exerciseID, template: template, sets: updated.sets, state: updated.queue ?? .empty
        )
        let nextRest = hasNext && !midRound
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

    // MARK: - SCRUM-32: reportar dolor

    /// Reporta el dolor sentido en la última serie registrada, en la escala única
    /// (`PainLevel`). Se guarda ANTES de devolver la recomendación, como una serie. No
    /// diagnostica: la recomendación sale de `PainFeedbackEngine`. Moderado o alto bloquea
    /// la progresión de carga de ese ejercicio (`PainFeedback.blocksProgression`).
    /// Reportar otra vez reemplaza lo anterior: gana el último nivel elegido (SCRUM-226).
    /// "Sin dolor" se guarda sin músculo.
    @discardableResult
    public func reportPain(_ level: PainLevel, muscleGroup: MuscleGroup.ID? = nil) throws -> PainRecommendation {
        var session = try activeSessionForSet()
        guard let index = session.sets.indices.last else { throw WorkoutSessionError.invalidTransition }
        let muscle = level == .none ? nil : muscleGroup
        session.sets[index].painFeedback = PainFeedback(level: level, muscleGroup: muscle)
        controller.replaceSession(session, at: clock())
        persistLive()
        return try painRecommendation(for: level, exercise: session.sets[index].exerciseID)
    }

    /// SCRUM-226: la última serie hecha, para la hoja "¿Te dolió?" del descanso. Lee lo
    /// guardado, así que al reabrir la app sigue el nivel reportado. `nil` sin series o
    /// fuera de una sesión en curso.
    public var painReport: PainReportUI? {
        guard let session = controller.current?.session,
              session.lifecycle == .active,
              let last = session.sets.last else { return nil }
        let exercise = last.exerciseID
        let reported = last.painFeedback
        let recommendation: PainRecommendation = reported.map { feedback in
            // El motor siempre responde con su regla por defecto (lo prueba
            // `PainReportFlowTests`). Si no pudiera, lo más seguro: moderado o alto se
            // tratan como alto.
            (try? painRecommendation(for: feedback.level, exercise: exercise))
                ?? (feedback.level.isConservativeDisruptive ? .stopAndRest : .continueNormal)
        } ?? .continueNormal
        return PainReportUI(
            exerciseName: exerciseNames[exercise] ?? exerciseFallbackName(exercise),
            level: reported?.level,
            muscleGroup: reported?.muscleGroup,
            muscleOptions: exerciseMuscles[exercise] ?? [],
            recommendation: recommendation,
            canSkipExercise: !(session.queue?.skipped ?? []).contains(exercise)
                && WorkoutQueue.hasPendingSets(exercise, template: template, sets: session.sets)
        )
    }

    /// SCRUM-226: salta el ejercicio que dolió (el de la última serie), aunque no sea el
    /// que sigue. Mismas reglas que "Saltar ejercicio" (SCRUM-212): las series hechas se
    /// quedan, no se crean series y se puede retomar antes de terminar.
    @discardableResult
    public func skipPainfulExercise() throws -> WorkoutSessionPhase {
        guard let exercise = try activeSessionForSet().sets.last?.exerciseID else {
            throw WorkoutSessionError.invalidTransition
        }
        return try changeQueue(on: exercise) { exercise, state, session in
            WorkoutQueue.skipping(exercise, in: state, template: template, sets: session.sets)
        }
    }

    private func painRecommendation(for level: PainLevel, exercise: ExerciseID) throws -> PainRecommendation {
        let engine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
        return try engine.evaluate(PainFeedbackInput(level: level, exerciseName: exerciseNames[exercise])).recommendation
    }

    // MARK: - SCRUM-212: dejar para después, saltar y retomar

    /// Ejercicios saltados de la sesión (para mostrarlos y retomarlos), con su nombre.
    public var skippedExercises: [(id: ExerciseID, name: String)] {
        (controller.current?.session.queue?.skipped ?? []).map {
            ($0, exerciseNames[$0] ?? exerciseFallbackName($0))
        }
    }

    /// Manda el ejercicio actual al final de la cola ("la máquina está ocupada"). Las
    /// series hechas no cambian; el descanso en curso sigue. Si es lo único que queda, no
    /// cambia nada.
    @discardableResult
    public func deferCurrentExercise() throws -> WorkoutSessionPhase {
        try changeQueue { exercise, state, session in
            WorkoutQueue.deferring(exercise, in: state, template: template, sets: session.sets)
        }
    }

    /// Lo que la pantalla dice tras "Máquina ocupada", hasta completar la siguiente serie.
    public var occupiedNotice: OccupiedOutcome? {
        guard let lastOccupied, controller.current?.session.sets.count == lastOccupied.setCount else { return nil }
        return lastOccupied.outcome
    }

    /// SCRUM-233: "Máquina ocupada" sobre el ejercicio actual. Adelanta el primer pendiente
    /// que no suba la interferencia por fatiga; si ninguno, lo manda al final; si es lo único
    /// que queda, no cambia nada. Las series hechas no cambian, el descanso sigue y la cola
    /// se guarda antes de cambiar la pantalla. La ocupación sólo vive en esta sesión (RN-005).
    @discardableResult
    public func markCurrentExerciseOccupied() throws -> OccupiedOutcome {
        let session = try activeSessionForSet()
        switch phase {
        case .active, .resting: break
        case .idle, .paused, .finished: throw WorkoutSessionError.invalidTransition
        }
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let exercise = template.plannedSets[current.index].exerciseID
        let state = session.queue ?? .empty
        let others = WorkoutQueue.pendingOthers(than: exercise, template: template, sets: session.sets, state: state)
        guard let candidate = advanceCandidate(for: exercise, others: others, state: state) else {
            return .needsChoice(occupiedChoice(for: exercise, isOnlyExercise: others.isEmpty, session: session))
        }
        _ = try changeQueue { exercise, state, _ in
            WorkoutQueue.advancing(candidate, before: exercise, in: state, template: template)
        }
        let outcome = OccupiedOutcome.advanced(next: name(of: candidate), after: name(of: exercise))
        lastOccupied = (outcome, session.sets.count)
        return outcome
    }

    /// "Esperar": el ejercicio ocupado va al final. Si es lo único que queda no cambia nada.
    @discardableResult
    public func waitForOccupiedExercise() throws -> OccupiedOutcome {
        let session = try activeSessionForSet()
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let exercise = template.plannedSets[current.index].exerciseID
        _ = try changeQueue { exercise, state, session in
            WorkoutQueue.deferring(exercise, in: WorkoutQueue.markingOccupied(exercise, in: state), template: template, sets: session.sets)
        }
        let outcome = OccupiedOutcome.movedToEnd(exercise: name(of: exercise))
        lastOccupied = (outcome, session.sets.count)
        return outcome
    }

    /// SCRUM-234: cambia lo pendiente del ejercicio actual por `replacement`, sólo por hoy.
    /// Tiene que ser uno de los sustitutos que se ofrecen: la regla se aplica otra vez aquí.
    /// Lo hecho se queda como está y se guarda antes de cambiar la pantalla.
    @discardableResult
    public func substituteCurrentExercise(
        with replacement: ExerciseID,
        reason: SessionSubstitution.Reason = .occupied
    ) throws -> WorkoutSessionPhase {
        var session = try activeSessionForSet()
        let wasResting: Bool
        switch phase {
        case .active: wasResting = false
        case .resting: wasResting = true
        case .idle, .paused, .finished: throw WorkoutSessionError.invalidTransition
        }
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let exercise = template.plannedSets[current.index].exerciseID
        let state = session.queue ?? .empty
        guard !hadDisruptivePain(exercise, session: session),
              let chosen = equivalents(for: exercise, session: session).first(where: { $0.id == replacement }) else {
            throw WorkoutSessionError.invalidTransition
        }
        let adapted = WorkoutQueue.substituting(exercise, with: replacement, in: template, sets: session.sets)
        session.queue = WorkoutQueue.replacing(exercise, with: replacement, in: state, template: adapted)
        session.template = adapted
        session.substitutions = (session.substitutions ?? []) + [SessionSubstitution(
            original: exercise, replacement: replacement, reason: reason,
            score: chosen.totalScore, rule: chosen.ruleReference, date: clock()
        )]
        template = adapted
        controller.replaceSession(session, at: clock())
        persistLive()
        guard let upcoming = currentSet() else { return phase }
        let result: WorkoutSessionPhase = wasResting && rest.isActive ? .resting(upcoming, rest: rest) : .active(upcoming)
        phase = result
        return result
    }

    /// El ejercicio de la serie actual.
    public var currentExerciseID: ExerciseID? {
        currentSet().map { template.plannedSets[$0.index].exerciseID }
    }

    /// "A → B" de cada sustitución de la sesión, para el resumen.
    public var substitutionSummaries: [(from: String, to: String)] {
        (controller.current?.session.substitutions ?? []).map { (name(of: $0.original), name(of: $0.replacement)) }
    }

    private func occupiedChoice(for exercise: ExerciseID, isOnlyExercise: Bool, session: WorkoutSessionRecord) -> OccupiedChoice {
        if let pain = session.sets.last(where: { set in
            set.exerciseID == exercise && set.painFeedback?.level.isConservativeDisruptive == true
        })?.painFeedback?.level {
            return OccupiedChoice(
                exercise: name(of: exercise), options: [],
                painRecommendation: (try? painRecommendation(for: pain, exercise: exercise)) ?? .stopAndRest,
                isOnlyExercise: isOnlyExercise
            )
        }
        let muscles = exercises[exercise].map { Set($0.primaryMuscles.map(\.muscleGroupID)) } ?? []
        let options = equivalents(for: exercise, session: session).map { option in
            SubstituteOption(
                id: option.exercise.id, name: name(of: option.exercise.id),
                sameMuscles: Set(option.exercise.primaryMuscles.map(\.muscleGroupID)) == muscles
            )
        }
        return OccupiedChoice(exercise: name(of: exercise), options: options, painRecommendation: nil, isOnlyExercise: isOnlyExercise)
    }

    /// Los sustitutos de PR-E001 para `exercise`: sin lo que ya está en la sesión ni lo ocupado.
    private func equivalents(for exercise: ExerciseID, session: WorkoutSessionRecord) -> [ScoredSubstitute] {
        guard let target = exercises[exercise] else { return [] }
        do {
            let engine = SubstitutionScoringEngine(config: try SubstitutionScoringConfig(rule: SubstitutionScoringDefaults.makeRule()))
            return try engine.substitutes(for: SubstitutionRequest(
                target: target,
                candidates: Array(exercises.values),
                unavailableExerciseIDs: Set(session.queue?.occupied ?? []),
                sessionExerciseIDs: Set(template.plannedSets.map(\.exerciseID)),
                activeRestrictions: restrictions,
                asOf: clock()
            )).ranked
        } catch {
            return []
        }
    }

    private func hadDisruptivePain(_ exercise: ExerciseID, session: WorkoutSessionRecord) -> Bool {
        session.sets.contains { $0.exerciseID == exercise && $0.painFeedback?.level.isConservativeDisruptive == true }
    }

    /// Sin los datos del ejercicio no se adelanta a ciegas: nunca se arriesga lo prioritario.
    private func advanceCandidate(for exercise: ExerciseID, others: [ExerciseID], state: ExerciseQueueState) -> ExerciseID? {
        guard let blocked = exercises[exercise] else { return nil }
        do {
            let config = try FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule())
            return try ReorderBeforeReplaceController().advanceCandidate(
                blocked: blocked, remaining: others.compactMap { exercises[$0] },
                excluded: Set(state.occupied ?? []), config: config
            )?.id
        } catch {
            return nil
        }
    }

    /// La máquina implícita (gimnasio + ejercicio) si la carga es por máquina (DE-4).
    private func machine(for exercise: ExerciseID) -> UUID? {
        guard let gymID, exercises[exercise]?.equipment.loadIsPerMachine == true else { return nil }
        return ImplicitMachine.id(gym: gymID, exercise: exercise)
    }

    /// El peso para precargar: el último realmente hecho. Un calentamiento no se precarga con
    /// el peso de trabajo. Un ejercicio por máquina sin gimnasio se queda vacío (RN-007).
    private func lastWeight(for planned: PlannedSet, session: WorkoutSessionRecord) -> Double? {
        guard !planned.prescription.isWarmup else { return nil }
        guard let exercise = exercises[planned.exerciseID] else {
            return lastPerformedWeightLookup(planned.exerciseID)
        }
        let machine = machine(for: exercise.id)
        if exercise.equipment.loadIsPerMachine && machine == nil { return nil }
        return loads.lastWeight(of: exercise.id, machine: machine, unit: planned.prescription.loadUnit, session: session)
    }

    private func name(of exercise: ExerciseID) -> String {
        exerciseNames[exercise] ?? exerciseFallbackName(exercise)
    }

    /// Salta el ejercicio actual: queda marcado como saltado, sin crear series. Si no
    /// queda nada más por hacer, la sesión termina y el resumen lo muestra.
    @discardableResult
    public func skipCurrentExercise() throws -> WorkoutSessionPhase {
        try changeQueue { exercise, state, session in
            WorkoutQueue.skipping(exercise, in: state, template: template, sets: session.sets)
        }
    }

    /// Retoma un ejercicio saltado: vuelve a la cola, al final.
    @discardableResult
    public func resumeSkipped(_ exercise: ExerciseID) throws -> WorkoutSessionPhase {
        try changeQueue { _, state, _ in WorkoutQueue.resuming(exercise, in: state) }
    }

    /// Aplica un cambio a la cola sobre el ejercicio actual (o sobre `target`). Guarda ANTES
    /// de cambiar la pantalla (como una serie). Sólo con la sesión activa o en descanso (no
    /// en pausa).
    private func changeQueue(
        on target: ExerciseID? = nil,
        _ change: (ExerciseID, ExerciseQueueState, WorkoutSessionRecord) -> ExerciseQueueState
    ) throws -> WorkoutSessionPhase {
        let session = try activeSessionForSet()
        let wasResting: Bool
        switch phase {
        case .active: wasResting = false
        case .resting: wasResting = true
        case .idle, .paused, .finished: throw WorkoutSessionError.invalidTransition
        }
        let state = session.queue ?? .empty
        guard let current = currentSet() else { throw WorkoutSessionError.allSetsCompleted }
        let exercise = target ?? template.plannedSets[current.index].exerciseID
        let next = change(exercise, state, session)
        guard next != state else { return phase }
        var updated = session
        updated.queue = next.isEmpty ? nil : next
        controller.replaceSession(updated, at: clock())
        persistLive()

        guard let upcoming = currentSet() else {
            // Lo que queda está saltado: se cierra la sesión (el resumen muestra lo saltado).
            do {
                try completeSession(at: clock())
            } catch {
                persistenceFailed = true
            }
            rest = RestTimerState(recommendedSeconds: 0)
            return finalizeSession()
        }
        let result: WorkoutSessionPhase = wasResting && rest.isActive ? .resting(upcoming, rest: rest) : .active(upcoming)
        phase = result
        return result
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