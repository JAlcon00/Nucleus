//
//  SplitSelector.swift
//  PRDomain
//
//  Created by PR.
//
//  Split selector (promptMaster §8.2, PR-0501). Selecciona una estructura de
//  bloques por disponibilidad (días/semana), objetivo y adherencia; es
//  determinista y explicable, y nunca depende de un LLM. Las reglas de selección
//  están versionadas y se documentan para el usuario (facts).
//

import Foundation

/// Estructura de bloques soportada en MVP (promptMaster §8.2).
public enum TrainingSplit: String, Codable, Sendable, CaseIterable, Hashable {
    case fullBody
    case upperLower
    case pushPullLegs
}

/// Factor que motivó la elección del split (para explainability).
public enum SplitReason: String, Codable, Sendable, CaseIterable, Hashable {
    case trainingDays
    case goalRequirement
    case adherence
    case defaultLowFrequency
}

/// Devoluciones del selector: el split elegido + los días que se le asignan
/// + los facts que lo explican.
public struct SplitSelection: Codable, Sendable, Hashable {
    public let split: TrainingSplit
    public let trainingDaysPerWeek: Int
    public let goal: TrainingGoal
    public let experience: ExperienceLevel
    public let reason: SplitReason

    public init(
        split: TrainingSplit,
        trainingDaysPerWeek: Int,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        reason: SplitReason
    ) {
        self.split = split
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.goal = goal
        self.experience = experience
        self.reason = reason
    }

    /// Facts legibles para la UI/"por qué este split".
    public var explanationFacts: [DecisionFact] {
        [
            DecisionFact(key: "split", value: split.rawValue),
            DecisionFact(key: "trainingDaysPerWeek", value: String(trainingDaysPerWeek)),
            DecisionFact(key: "reason", value: reason.rawValue),
        ]
    }
}

/// Problemas de entrada que el selector rechaza (superficie de dominio).
public enum SplitSelectionError: Error, Equatable, Sendable {
    case invalidTrainingDays(value: Int)
    case unsupportedGoal(goal: TrainingGoal, experience: ExperienceLevel)
}

/// Selecciona una estructura de bloques de forma determinista y explicable.
///
/// Reglas (MVP, en orden de prioridad):
/// - 2–3 días → `fullBody` (adherencia; frecuencia requiere cuerpo completo).
/// - 4 días → `upperLower`; salvo experiencia avanzada con objetivo de
///   bodybuilding en surplus, que opta por `pushPullLegs` más especialización.
/// - 5 días → `pushPullLegs` + 2º día de pierna / densidad.
/// - 6–7 días → `pushPullLegs` (con rotación de pierna o acceso adicional según
///   objetivo) para dejar frecuencia viable y evitar sesiones únicas de aislamiento.
///
/// Nunca depende de LLM; misma entrada → mismo split.
public struct SplitSelector: Sendable {
    public init() {}

    public func select(
        trainingDaysPerWeek: Int,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        phase: BodyCompositionPhase
    ) throws -> SplitSelection {
        guard (2...7).contains(trainingDaysPerWeek) else {
            throw SplitSelectionError.invalidTrainingDays(value: trainingDaysPerWeek)
        }
        guard trainingDaysPerWeek != 1 else {
            throw SplitSelectionError.invalidTrainingDays(value: trainingDaysPerWeek)
        }

        switch trainingDaysPerWeek {
        case 2, 3:
            return SplitSelection(
                split: .fullBody,
                trainingDaysPerWeek: trainingDaysPerWeek,
                goal: goal,
                experience: experience,
                reason: .trainingDays
            )
        case 4:
            // Un split simple de upper/lower es la opción por defecto; sólo en
            // bodybuilding avanzado/surplus dejamos espacio a la especialización.
            let specialized = goal == .bodybuilding
                && experience == .advanced
                && phase == .surplus
            if specialized {
                return SplitSelection(split: .pushPullLegs, trainingDaysPerWeek: 4, goal: goal, experience: experience, reason: .goalRequirement)
            }
            return SplitSelection(split: .upperLower, trainingDaysPerWeek: 4, goal: goal, experience: experience, reason: .goalRequirement)
        case 5:
            return SplitSelection(split: .pushPullLegs, trainingDaysPerWeek: 5, goal: goal, experience: experience, reason: .goalRequirement)
        default: // 6, 7
            return SplitSelection(split: .pushPullLegs, trainingDaysPerWeek: trainingDaysPerWeek, goal: goal, experience: experience, reason: .adherence)
        }
    }
}