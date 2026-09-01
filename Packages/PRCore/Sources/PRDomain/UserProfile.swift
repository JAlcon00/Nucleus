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
