//
//  UserProfile.swift
//  PRDomain
//
//  Created by PR.
//
//  Perfil de entrenamiento del usuario (promptMaster §3, PR-0104).
//

import Foundation

/// Nivel de experiencia declarado por el usuario.
public enum ExperienceLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case novice
    case beginner
    case intermediate
    case advanced
    case competitive
}

/// Objetivo principal de entrenamiento.
public enum TrainingGoal: String, Codable, Sendable, CaseIterable, Hashable {
    case generalHealth
    case hypertrophy
    case strength
    case powerbuilding
    case recomposition
    case bodybuilding
}

/// Fase energética / física. Independiente del objetivo.
public enum BodyCompositionPhase: String, Codable, Sendable, CaseIterable, Hashable {
    case surplus
    case deficit
    case maintenance
    case unspecified
}

/// Preferencia de variedad dentro del bloque.
public enum VarietyPreference: String, Codable, Sendable, CaseIterable, Hashable {
    case stable
    case balanced
    case varied
}

/// Nivel de detalle educativo del coaching.
public enum CoachingDetailLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case guided
    case balanced
    case advanced
}

/// Tier de prioridad muscular.
public enum PriorityTier: Int, Codable, Sendable, Hashable {
    case maintain = 0
    case normal = 1
    case emphasize = 2
    case specialize = 3
}

/// Prioridad de un grupo muscular (promptMaster §3.4).
public struct MusclePriority: Codable, Sendable, Hashable, Equatable {
    public var muscleGroupID: MuscleGroup.ID
    public var priority: PriorityTier

    public init(muscleGroupID: MuscleGroup.ID, priority: PriorityTier) {
        self.muscleGroupID = muscleGroupID
        self.priority = priority
    }
}

// MARK: - Schedule / time preferences (PR-0104)

/// Día de la semana.
public enum WeekDay: String, Codable, Sendable, CaseIterable, Hashable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

/// Ventana de tiempo preferida para entrenar.
public struct PreferredDayTime: Codable, Sendable, Hashable {
    public var daysOfWeek: Set<WeekDay>
    /// Hora de inicio en minutos desde medianoche (0...1439).
    public var startTimeMinutes: Int
    /// Duración en minutos (> 0).
    public var durationMinutes: Int

    public init(daysOfWeek: Set<WeekDay>, startTimeMinutes: Int, durationMinutes: Int) throws {
        guard !daysOfWeek.isEmpty else {
            throw DomainValidationError.invalidMinutes(value: -1)
        }
        guard (0...1439).contains(startTimeMinutes) else {
            throw DomainValidationError.invalidMinutes(value: startTimeMinutes)
        }
        guard durationMinutes > 0 else {
            throw DomainValidationError.invalidMinutes(value: durationMinutes)
        }
        self.daysOfWeek = daysOfWeek
        self.startTimeMinutes = startTimeMinutes
        self.durationMinutes = durationMinutes
    }
}

/// Preferencias de horario/semana del usuario (PR-0104).
public struct SchedulePreference: Codable, Sendable, Hashable {
    /// Días de entrenamiento por semana (2...7).
    public var trainingDaysPerWeek: Int
    /// Minutos habituales por sesión (20...240).
    public var usualSessionMinutes: Int
    /// Ventanas de tiempo preferidas (opcional).
    public var preferredTimeWindows: [PreferredDayTime]

    public init(
        trainingDaysPerWeek: Int,
        usualSessionMinutes: Int,
        preferredTimeWindows: [PreferredDayTime] = []
    ) throws {
        guard (2...7).contains(trainingDaysPerWeek) else {
            throw DomainValidationError.invalidMinutes(value: trainingDaysPerWeek)
        }
        guard (20...240).contains(usualSessionMinutes) else {
            throw DomainValidationError.invalidMinutes(value: usualSessionMinutes)
        }
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.usualSessionMinutes = usualSessionMinutes
        self.preferredTimeWindows = preferredTimeWindows
    }
}

/// Perfil de entrenamiento persistible del usuario.
public struct UserTrainingProfile: Codable, Sendable, Hashable {
    public var experience: ExperienceLevel
    public var goal: TrainingGoal
    public var phase: BodyCompositionPhase
    public var trainingDaysPerWeek: Int
    public var usualSessionMinutes: Int
    public var varietyPreference: VarietyPreference
    public var coachingDetail: CoachingDetailLevel

    public init(
        experience: ExperienceLevel,
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        trainingDaysPerWeek: Int,
        usualSessionMinutes: Int,
        varietyPreference: VarietyPreference,
        coachingDetail: CoachingDetailLevel
    ) throws {
        guard (2...7).contains(trainingDaysPerWeek) else {
            throw DomainValidationError.invalidMinutes(value: trainingDaysPerWeek)
        }
        guard (20...240).contains(usualSessionMinutes) else {
            throw DomainValidationError.invalidMinutes(value: usualSessionMinutes)
        }
        self.experience = experience
        self.goal = goal
        self.phase = phase
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.usualSessionMinutes = usualSessionMinutes
        self.varietyPreference = varietyPreference
        self.coachingDetail = coachingDetail
    }
}
