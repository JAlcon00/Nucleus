//
//  Training.swift
//  PRDomain
//
//  Created by PR.
//
//  Dominio de bloque/sesión/set (promptMaster §6.6-6.8, §30, PR-0103).
//  Separa lo planeado (SessionTemplate) de lo ejecutado (WorkoutSessionRecord)
//  y valida transiciones de lifecycle y límites de sets.
//

import Foundation

// MARK: - Lifecycle states (promptMaster §30)

/// Estado del lifecycle de un workout. Las transiciones inválidas se rechazan.
public enum WorkoutLifecycleState: String, Codable, Sendable, CaseIterable, Hashable {
    case planned
    case preparing
    case active
    case paused
    case finishing
    case completed
    case abandoned

    private static let transitions: [WorkoutLifecycleState: Set<WorkoutLifecycleState>] = [
        .planned: [.preparing, .active, .abandoned],
        .preparing: [.active, .abandoned],
        .active: [.paused, .finishing, .abandoned],
        .paused: [.active, .abandoned],
        .finishing: [.completed],
        .completed: [],
        .abandoned: [],
    ]

    /// Estados alcanzables directamente desde el actual.
    public var allowedNext: Set<WorkoutLifecycleState> {
        Self.transitions[self] ?? []
    }

    public func canTransition(to next: WorkoutLifecycleState) -> Bool {
        allowedNext.contains(next)
    }

    /// Llama a la transición y devuelve el nuevo estado, o lanza si es inválida.
    @discardableResult
    public func transitioning(to next: WorkoutLifecycleState) throws -> WorkoutLifecycleState {
        guard canTransition(to: next) else {
            throw DomainValidationError.invalidStateTransition(from: rawValue, to: next.rawValue)
        }
        return next
    }
}

/// Estado del lifecycle de un set. Las transiciones inválidas se rechazan.
public enum SetLifecycleState: String, Codable, Sendable, CaseIterable, Hashable {
    case planned
    case ready
    case completed
    case skipped
    case replaced

    private static let transitions: [SetLifecycleState: Set<SetLifecycleState>] = [
        .planned: [.ready, .skipped, .replaced],
        .ready: [.completed, .skipped, .replaced],
        .completed: [],
        .skipped: [],
        .replaced: [],
    ]

    public var allowedNext: Set<SetLifecycleState> {
        Self.transitions[self] ?? []
    }

    public func canTransition(to next: SetLifecycleState) -> Bool {
        allowedNext.contains(next)
    }

    @discardableResult
    public func transitioning(to next: SetLifecycleState) throws -> SetLifecycleState {
        guard canTransition(to: next) else {
            throw DomainValidationError.invalidStateTransition(from: rawValue, to: next.rawValue)
        }
        return next
    }
}

// MARK: - Feedback (promptMaster §6.8)

/// Dificultad percibida por el usuario tras un set.
public enum DifficultyFeedback: String, Codable, Sendable, CaseIterable, Hashable {
    case easy
    case manageable
    case hard
    case veryHard
    case failed
}

/// Feedback de dolor/reacción en un set.
public enum PainFeedback: Codable, Sendable, Hashable {
    case none
    case discomfort(muscleGroup: MuscleGroup.ID, severity: Int)
    case sharpPain(muscleGroup: MuscleGroup.ID, severity: Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "none":
            self = .none
        case "discomfort":
            let muscle = try container.decode(MuscleGroup.ID.self, forKey: .muscle)
            let severity = try container.decode(Int.self, forKey: .severity)
            self = try Self.validated(.discomfort(muscleGroup: muscle, severity: severity))
        case "sharpPain":
            let muscle = try container.decode(MuscleGroup.ID.self, forKey: .muscle)
            let severity = try container.decode(Int.self, forKey: .severity)
            self = try Self.validated(.sharpPain(muscleGroup: muscle, severity: severity))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown PainFeedback kind: \(kind)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .kind)
        case .discomfort(let muscle, let severity):
            try container.encode("discomfort", forKey: .kind)
            try container.encode(muscle, forKey: .muscle)
            try container.encode(severity, forKey: .severity)
        case .sharpPain(let muscle, let severity):
            try container.encode("sharpPain", forKey: .kind)
            try container.encode(muscle, forKey: .muscle)
            try container.encode(severity, forKey: .severity)
        }
    }

    private static func validated(_ value: PainFeedback) throws -> PainFeedback {
        switch value {
        case .discomfort(_, let s), .sharpPain(_, let s):
            guard (1...5).contains(s) else {
                throw DomainValidationError.invalidSeverity(value: s)
            }
        case .none:
            break
        }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case muscle
        case severity
    }
}

// MARK: - SetPrescription (promptMaster §6.8)

/// Prescripción de un set (lo planeado). No representa lo realizado.
public struct SetPrescription: Codable, Sendable, Hashable {
    public var targetRepRange: ClosedRange<Int>
    public var targetRIR: ClosedRange<Int>?
    public var targetLoad: Double?
    public var loadUnit: LoadUnit
    public var restSeconds: ClosedRange<Int>
    public var isWarmup: Bool

    public init(
        targetRepRange: ClosedRange<Int>,
        targetRIR: ClosedRange<Int>? = nil,
        targetLoad: Double? = nil,
        loadUnit: LoadUnit = .kilograms,
        restSeconds: ClosedRange<Int>,
        isWarmup: Bool = false
    ) throws {
        guard targetRepRange.lowerBound >= 1, targetRepRange.upperBound >= targetRepRange.lowerBound else {
            throw DomainValidationError.invalidRepRange(
                lower: targetRepRange.lowerBound,
                upper: targetRepRange.upperBound
            )
        }
        guard restSeconds.lowerBound >= 0, restSeconds.upperBound >= restSeconds.lowerBound else {
            throw DomainValidationError.invalidRestRange(
                lower: restSeconds.lowerBound,
                upper: restSeconds.upperBound
            )
        }
        if let targetRIR {
            guard targetRIR.lowerBound >= 0, targetRIR.upperBound >= targetRIR.lowerBound else {
                throw DomainValidationError.invalidRIR(value: targetRIR.lowerBound)
            }
        }
        if let targetLoad {
            guard targetLoad.isFinite, targetLoad >= 0 else {
                throw DomainValidationError.invalidLoad(value: targetLoad)
            }
        }
        self.targetRepRange = targetRepRange
        self.targetRIR = targetRIR
        self.targetLoad = targetLoad
        self.loadUnit = loadUnit
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
    }
}

// MARK: - SetRecord (promptMaster §6.8)

/// Registro de un set realmente realizado. Valida repos no negativos y peso no negativo.
public struct SetRecord: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = SetRecordID

    public let id: SetRecordID
    public var exerciseID: ExerciseID
    public var machineProfileID: UUID?
    public var performedAt: Date
    public var weight: Double
    public var unit: LoadUnit
    public var reps: Int
    public var rir: Int?
    public var perceivedDifficulty: DifficultyFeedback?
    public var painFeedback: PainFeedback?
    public var lifecycle: SetLifecycleState

    public init(
        id: SetRecordID = SetRecordID(),
        exerciseID: ExerciseID,
        machineProfileID: UUID? = nil,
        performedAt: Date = Date(),
        weight: Double,
        unit: LoadUnit,
        reps: Int,
        rir: Int? = nil,
        perceivedDifficulty: DifficultyFeedback? = nil,
        painFeedback: PainFeedback? = nil,
        lifecycle: SetLifecycleState = .planned
    ) throws {
        guard weight.isFinite, weight >= 0 else {
            throw DomainValidationError.invalidLoad(value: weight)
        }
        guard reps >= 1 else {
            throw DomainValidationError.invalidReps(value: reps)
        }
        if let rir {
            guard rir >= 0 else {
                throw DomainValidationError.invalidRIR(value: rir)
            }
        }
        self.id = id
        self.exerciseID = exerciseID
        self.machineProfileID = machineProfileID
        self.performedAt = performedAt
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.rir = rir
        self.perceivedDifficulty = perceivedDifficulty
        self.painFeedback = painFeedback
        self.lifecycle = lifecycle
    }
}

// MARK: - SessionTemplate (lo planeado, promptMaster §6.7)

/// Un set planeado dentro de una template de sesión.
public struct PlannedSet: Codable, Sendable, Hashable {
    public var exerciseID: ExerciseID
    public var prescription: SetPrescription

    public init(exerciseID: ExerciseID, prescription: SetPrescription) {
        self.exerciseID = exerciseID
        self.prescription = prescription
    }
}

/// Template de sesión: lo planeado. Inmutable respecto a lo realizado.
public struct SessionTemplate: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = UUID

    public let id: UUID
    public var title: String
    public var plannedSets: [PlannedSet]
    public var estimatedMinutes: ClosedRange<Int>?

    public init(
        id: UUID = UUID(),
        title: String,
        plannedSets: [PlannedSet],
        estimatedMinutes: ClosedRange<Int>? = nil
    ) {
        self.id = id
        self.title = title
        self.plannedSets = plannedSets
        self.estimatedMinutes = estimatedMinutes
    }
}

// MARK: - WorkoutSessionRecord (lo realizado, promptMaster §6.7)

/// Registro de lo realmente realizado en una sesión. Nunca se muta para
/// que coincida con el plan; guarda su propio lifecycle y set records.
public struct WorkoutSessionRecord: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = WorkoutID

    public let id: WorkoutID
    public var templateID: SessionTemplate.ID?
    public var startedAt: Date
    public var endedAt: Date?
    public var lifecycle: WorkoutLifecycleState
    public var sets: [SetRecord]
    /// Referencia estable al workout de HealthKit asociado (para reconciliar, §14.2/§15.2).
    public var healthWorkoutReferenceID: UUID?

    public init(
        id: WorkoutID = WorkoutID(),
        templateID: SessionTemplate.ID? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        lifecycle: WorkoutLifecycleState = .planned,
        sets: [SetRecord] = [],
        healthWorkoutReferenceID: UUID? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lifecycle = lifecycle
        self.sets = sets
        self.healthWorkoutReferenceID = healthWorkoutReferenceID
    }

    /// Aplica una transición de lifecycle validada.
    public mutating func transition(to next: WorkoutLifecycleState) throws {
        self.lifecycle = try lifecycle.transitioning(to: next)
    }

    /// Registra la ejecución de un set (sin mutar el histórico planeado).
    public func performedSet(_ set: SetRecord) -> WorkoutSessionRecord {
        var copy = self
        copy.sets.append(set)
        return copy
    }
}

// MARK: - TrainingBlock aggregate (promptMaster §6.6)

/// Estado de un bloque de entrenamiento.
public enum BlockStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case planned
    case active
    case deloading
    case completed
}

/// Política de progresión del bloque.
public enum ProgressionPolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case loadProgression
    case repRangeProgression
    case doubleProgression
}

/// Política de deload del bloque.
public enum DeloadPolicy: String, Codable, Sendable, CaseIterable, Hashable {
    case none
    case afterSixWeeks
    case afterEightWeeks
}

/// Objetivo de volumen por grupo muscular (sets por semana).
public struct MuscleVolumeTarget: Codable, Sendable, Hashable {
    public var muscleGroupID: MuscleGroup.ID
    /// Series semanales objetivo (>= 0).
    public var targetSetsPerWeek: Int

    public init(muscleGroupID: MuscleGroup.ID, targetSetsPerWeek: Int) throws {
        guard targetSetsPerWeek >= 0 else {
            throw DomainValidationError.invalidReps(value: targetSetsPerWeek)
        }
        self.muscleGroupID = muscleGroupID
        self.targetSetsPerWeek = targetSetsPerWeek
    }
}

/// Política de variedad del bloque: proporción de ejercicios estables.
public struct VarietyPolicy: Codable, Sendable, Hashable {
    /// Proporción (0...1) de ejercicios que permanecen dentro del bloque.
    public var percentStable: Double

    public init(percentStable: Double) throws {
        guard percentStable.isFinite, (0...1).contains(percentStable) else {
            throw DomainValidationError.invalidNormalized(value: percentStable)
        }
        self.percentStable = percentStable
    }
}

/// Bloque de entrenamiento persistible (spec §6.6).
public struct TrainingBlock: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = TrainingBlockID

    public let id: TrainingBlockID
    public var name: String
    public var goal: TrainingGoal
    public var phase: BodyCompositionPhase
    public var startDate: Date
    public var plannedWeeks: Int
    public var sessions: [SessionTemplate]
    public var muscleTargets: [MuscleVolumeTarget]
    public var priorities: [MusclePriority]
    public var progressionPolicy: ProgressionPolicy
    public var deloadPolicy: DeloadPolicy
    public var varietyPolicy: VarietyPolicy
    public var status: BlockStatus

    public init(
        id: TrainingBlockID = TrainingBlockID(),
        name: String,
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        startDate: Date = Date(),
        plannedWeeks: Int,
        sessions: [SessionTemplate] = [],
        muscleTargets: [MuscleVolumeTarget] = [],
        priorities: [MusclePriority] = [],
        progressionPolicy: ProgressionPolicy,
        deloadPolicy: DeloadPolicy,
        varietyPolicy: VarietyPolicy,
        status: BlockStatus = .planned
    ) throws {
        guard (4...8).contains(plannedWeeks) else {
            throw DomainValidationError.invalidMinutes(value: plannedWeeks)
        }
        self.id = id
        self.name = name
        self.goal = goal
        self.phase = phase
        self.startDate = startDate
        self.plannedWeeks = plannedWeeks
        self.sessions = sessions
        self.muscleTargets = muscleTargets
        self.priorities = priorities
        self.progressionPolicy = progressionPolicy
        self.deloadPolicy = deloadPolicy
        self.varietyPolicy = varietyPolicy
        self.status = status
    }
}
