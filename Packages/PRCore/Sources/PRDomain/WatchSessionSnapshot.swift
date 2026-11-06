//
//  WatchSessionSnapshot.swift
//  PRDomain
//
//  SCRUM-253 (PR-G002): lo que el iPhone le dice al reloj. El iPhone manda (DG-1): aquí se
//  calcula el orden de TODO lo que falta con la misma cola que usa su pantalla (saltados,
//  diferidos, superset y sustituciones), y el reloj sólo recorre esa lista. Así puede seguir
//  solo sin conexión y no existen dos fuentes del orden.
//
//  No lleva restricciones, notas de dolor ni datos de Salud. Puro y determinista.
//

import Foundation

/// Una serie por hacer, ya lista para mostrarse en el reloj.
public struct WatchPlannedSet: Codable, Sendable, Hashable, Identifiable {
    /// Ejercicio y número de serie dentro de él: identifica la serie en los dos dispositivos.
    public let slot: SetSlot
    public let exerciseName: String
    /// Total de series planeadas del ejercicio ("Serie X de Y").
    public let totalInExercise: Int
    public let targetRepRange: ClosedRange<Int>
    public let targetReps: Int
    /// Peso a precargar. `nil` = vacío: nunca se inventa un 0 (RN-007).
    public var weight: Double?
    public let unit: LoadUnit
    public let isWarmup: Bool
    /// Descanso al terminar esta serie. `nil` = no hay: calentamiento, mitad de ronda de un
    /// superset o la última serie.
    public let restSecondsAfter: Int?
    /// Pareja de superset, si siguen juntos en la cola.
    public let supersetPartner: String?

    public var id: SetSlot { slot }

    public init(
        slot: SetSlot,
        exerciseName: String,
        totalInExercise: Int,
        targetRepRange: ClosedRange<Int>,
        targetReps: Int,
        weight: Double?,
        unit: LoadUnit,
        isWarmup: Bool,
        restSecondsAfter: Int?,
        supersetPartner: String?
    ) {
        self.slot = slot
        self.exerciseName = exerciseName
        self.totalInExercise = totalInExercise
        self.targetRepRange = targetRepRange
        self.targetReps = targetReps
        self.weight = weight
        self.unit = unit
        self.isWarmup = isWarmup
        self.restSecondsAfter = restSecondsAfter
        self.supersetPartner = supersetPartner
    }
}

/// En qué momento va la sesión, visto desde el reloj.
public enum WatchSessionStage: String, Codable, Sendable, Hashable {
    case active
    case paused
    case finished
}

/// Estado completo de la sesión que el iPhone publica al reloj.
public struct WatchSessionSnapshot: Codable, Sendable, Hashable {
    /// Hasta cuánto mide, en bytes, para caber en el transporte con margen.
    public static let transportBudgetBytes = 60_000

    public let sessionID: WorkoutID
    /// Crece con cada cambio de la sesión: uno viejo nunca reemplaza a uno nuevo.
    public let revision: Int
    public let title: String
    public let stage: WatchSessionStage
    /// Series ya guardadas en el iPhone. Al verlas, el reloj las puede soltar (SCRUM-256).
    public let confirmedSetIDs: [SetRecordID]
    /// De ésas, las que ya tienen reporte guardado (SCRUM-260). Sólo ids: no lleva el reporte.
    public let annotatedSetIDs: [SetRecordID]
    /// Comandos del reloj ya aplicados (SCRUM-259).
    public let confirmedCommandIDs: [UUID]
    /// Inicio y fin de la sesión, para el resumen corto del reloj.
    public let startedAt: Date?
    public let endedAt: Date?
    /// ¿El reloj debe abrir su sesión de entrenamiento del sistema? (SCRUM-258).
    public let opensWorkoutSession: Bool
    /// Fin del descanso en curso. Es una hora, no un contador: sobrevive a bajar la muñeca.
    public let restEndsAt: Date?
    /// Lo que falta, en el orden en que se va a hacer.
    public let remaining: [WatchPlannedSet]

    public init(
        sessionID: WorkoutID,
        revision: Int,
        title: String,
        stage: WatchSessionStage,
        confirmedSetIDs: [SetRecordID],
        restEndsAt: Date?,
        remaining: [WatchPlannedSet],
        annotatedSetIDs: [SetRecordID] = [],
        confirmedCommandIDs: [UUID] = [],
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        opensWorkoutSession: Bool = false
    ) {
        self.sessionID = sessionID
        self.revision = revision
        self.title = title
        self.stage = stage
        self.confirmedSetIDs = confirmedSetIDs
        self.annotatedSetIDs = annotatedSetIDs
        self.confirmedCommandIDs = confirmedCommandIDs
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.opensWorkoutSession = opensWorkoutSession
        self.restEndsAt = restEndsAt
        self.remaining = remaining
    }

    /// Series de la sesión: las confirmadas más las que faltan.
    public var totalSets: Int { confirmedSetIDs.count + remaining.count }

    /// ¿Dicen lo mismo, sin contar la revisión? Si sí, no hace falta reenviarlo.
    public func hasSameContent(as other: WatchSessionSnapshot) -> Bool {
        sessionID == other.sessionID && title == other.title && stage == other.stage
            && confirmedSetIDs == other.confirmedSetIDs && annotatedSetIDs == other.annotatedSetIDs
            && confirmedCommandIDs == other.confirmedCommandIDs && endedAt == other.endedAt
            && restEndsAt == other.restEndsAt
            && remaining == other.remaining
    }
}

/// Lo que la sesión necesita saber de fuera para armar el estado.
public struct WatchSessionSnapshotInput: Sendable {
    public let session: WorkoutSessionRecord
    public let template: SessionTemplate
    public let revision: Int
    public let exerciseName: @Sendable (ExerciseID) -> String
    /// El mismo borrador que usa la pantalla del iPhone.
    public let draft: @Sendable (PlannedSet) -> SetCompletionDraft
    public let opensWorkoutSession: Bool

    public init(
        session: WorkoutSessionRecord,
        template: SessionTemplate,
        revision: Int,
        exerciseName: @escaping @Sendable (ExerciseID) -> String,
        draft: @escaping @Sendable (PlannedSet) -> SetCompletionDraft,
        opensWorkoutSession: Bool = false
    ) {
        self.session = session
        self.template = template
        self.revision = revision
        self.exerciseName = exerciseName
        self.draft = draft
        self.opensWorkoutSession = opensWorkoutSession
    }
}

/// Arma el estado para el reloj. Con las mismas entradas da siempre lo mismo.
public enum WatchSessionSnapshotBuilder {

    public static func snapshot(_ input: WatchSessionSnapshotInput) -> WatchSessionSnapshot {
        let session = input.session
        let stage = stage(of: session.lifecycle)
        let confirmed = (session.sets.map(\.id) + (session.setConflicts ?? []).map(\.set.id))
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        let annotated = (session.sets + (session.setConflicts ?? []).map(\.set))
            .filter { $0.painFeedback != nil }
            .map(\.id)
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        return WatchSessionSnapshot(
            sessionID: session.id,
            revision: input.revision,
            title: input.template.title,
            stage: stage,
            confirmedSetIDs: confirmed,
            restEndsAt: stage == .finished ? nil : session.rest?.endDate,
            remaining: stage == .finished ? [] : remaining(input),
            annotatedSetIDs: annotated,
            confirmedCommandIDs: session.appliedCommandIDs ?? [],
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            opensWorkoutSession: input.opensWorkoutSession
        )
    }

    private static func stage(of lifecycle: WorkoutLifecycleState) -> WatchSessionStage {
        switch lifecycle {
        case .planned, .preparing, .active, .finishing: return .active
        case .paused: return .paused
        case .completed, .abandoned: return .finished
        }
    }

    /// Recorre la cola como si cada serie se hiciera en orden: es la misma cuenta que hace la
    /// pantalla del iPhone al completar una serie.
    private static func remaining(_ input: WatchSessionSnapshotInput) -> [WatchPlannedSet] {
        let template = input.template
        let state = input.session.queue ?? .empty
        var sets = input.session.sets
        var result: [WatchPlannedSet] = []
        while let index = WorkoutQueue.nextPlannedIndex(template: template, sets: sets, state: state) {
            let planned = template.plannedSets[index]
            guard let walked = try? SetRecord(
                exerciseID: planned.exerciseID, weight: 0, unit: planned.prescription.loadUnit, reps: 1
            ) else { break }
            sets.append(walked)
            result.append(plannedSet(at: index, walked: sets, state: state, input: input))
        }
        return result
    }

    private static func plannedSet(
        at index: Int,
        walked sets: [SetRecord],
        state: ExerciseQueueState,
        input: WatchSessionSnapshotInput
    ) -> WatchPlannedSet {
        let template = input.template
        let planned = template.plannedSets[index]
        let prescription = planned.prescription
        let sameExercise = template.plannedSets.indices.filter { template.plannedSets[$0].exerciseID == planned.exerciseID }
        let number = (sameExercise.firstIndex(of: index) ?? 0) + 1
        let draft = input.draft(planned)
        return WatchPlannedSet(
            slot: SetSlot(exerciseID: planned.exerciseID, slotIndex: number),
            exerciseName: input.exerciseName(planned.exerciseID),
            totalInExercise: sameExercise.count,
            targetRepRange: prescription.targetRepRange,
            targetReps: draft.targetReps,
            weight: prescription.targetLoad != nil || draft.weightFromHistory ? draft.targetWeight : nil,
            unit: draft.targetUnit,
            isWarmup: prescription.isWarmup,
            restSecondsAfter: restSeconds(after: planned, sets: sets, state: state, template: template),
            supersetPartner: partner(of: planned.exerciseID, state: state, input: input)
        )
    }

    /// La misma regla que `WorkoutSessionCoordinator`: sin descanso en un calentamiento, a
    /// mitad de la ronda de un superset ni después de la última serie.
    private static func restSeconds(
        after planned: PlannedSet,
        sets: [SetRecord],
        state: ExerciseQueueState,
        template: SessionTemplate
    ) -> Int? {
        guard !planned.prescription.isWarmup,
              WorkoutQueue.nextPlannedIndex(template: template, sets: sets, state: state) != nil,
              !WorkoutQueue.continuesSupersetRound(after: planned.exerciseID, template: template, sets: sets, state: state)
        else { return nil }
        return RestTimer().recommendedSeconds(for: planned.prescription)
    }

    private static func partner(
        of exercise: ExerciseID,
        state: ExerciseQueueState,
        input: WatchSessionSnapshotInput
    ) -> String? {
        guard let pair = input.template.superset(containing: exercise),
              WorkoutQueue.isTogether(pair, state: state),
              let partner = pair.partner(of: exercise) else { return nil }
        return input.exerciseName(partner)
    }
}

/// Una serie hecha en el reloj que todavía cuenta para saber qué sigue.
public struct WatchDoneSet: Codable, Sendable, Hashable {
    public let slot: SetSlot
    public let weight: Double
    public let unit: LoadUnit

    public init(slot: SetSlot, weight: Double, unit: LoadUnit) {
        self.slot = slot
        self.weight = weight
        self.unit = unit
    }
}

/// Qué sigue en el reloj. No calcula el orden: recorre lo que recibió y salta lo ya hecho.
public enum WatchSessionCursor {

    /// La serie que toca. Sin conexión, el peso es el de la serie anterior de ese ejercicio
    /// (si es de la misma unidad): lo último que la persona hizo manda sobre lo planeado.
    public static func current(in snapshot: WatchSessionSnapshot, done: [WatchDoneSet]) -> WatchPlannedSet? {
        let doneSlots = Set(done.map(\.slot))
        guard var next = snapshot.remaining.first(where: { !doneSlots.contains($0.slot) }) else { return nil }
        if !next.isWarmup, let previous = done.last(where: {
            $0.slot.exerciseID == next.slot.exerciseID && $0.unit == next.unit
        }) {
            next.weight = previous.weight
        }
        return next
    }

    /// Lo que falta por hacer en el reloj.
    public static func remainingCount(in snapshot: WatchSessionSnapshot, done: [WatchDoneSet]) -> Int {
        let doneSlots = Set(done.map(\.slot))
        return snapshot.remaining.filter { !doneSlots.contains($0.slot) }.count
    }
}

/// Bytes de lo que viaja entre iPhone y reloj. Con claves ordenadas, dos valores iguales
/// siempre dan los mismos bytes.
public enum WatchWireCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}
