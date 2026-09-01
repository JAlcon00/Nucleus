//
//  SubstitutionScoring.swift
//  PRDomain
//
//  Created by PR.
//
//  Substitution scoring engine (plan §9, RF-012, PR-0904). Rankea sustitutos de un
//  ejercicio con un gate de seguridad y pesos versionados (pattern/muscle/role/angle/
//  fatigue/stability/history/preference/availability). Reproducible y con desglose
//  auditable; devuelve "no safe substitute" cuando ningún candidato pasa el gate.
//

import Foundation

/// Pesos versionados del scoring de sustitución (promptMaster §10.3).
public struct SubstitutionWeights: Sendable {
    public var muscleMatch: Double
    public var movementPatternMatch: Double
    public var trainingRoleMatch: Double
    public var angleMatch: Double
    public var fatigueProfileMatch: Double
    public var stabilityMatch: Double
    public var userHistoryConfidence: Double
    public var preferenceMatch: Double
    public var equipmentConfidence: Double

    /// Defaults del spec; los pesos son configuración versionada, no constantes dispersas.
    public static func defaultConfig() -> SubstitutionWeights {
        SubstitutionWeights(
            muscleMatch: 0.30,
            movementPatternMatch: 0.20,
            trainingRoleMatch: 0.15,
            angleMatch: 0.10,
            fatigueProfileMatch: 0.08,
            stabilityMatch: 0.05,
            userHistoryConfidence: 0.05,
            preferenceMatch: 0.04,
            equipmentConfidence: 0.03
        )
    }
}

/// Desglose auditable del score de un candidato.
public struct SubstitutionScoreBreakdown: Equatable, Sendable {
    public var muscleMatch: Double
    public var movementPatternMatch: Double
    public var trainingRoleMatch: Double
    public var angleMatch: Double
    public var fatigueProfileMatch: Double
    public var stabilityMatch: Double
    public var userHistoryConfidence: Double
    public var preferenceMatch: Double
    public var equipmentConfidence: Double

    public var total: Double {
        muscleMatch + movementPatternMatch + trainingRoleMatch + angleMatch
            + fatigueProfileMatch + stabilityMatch + userHistoryConfidence
            + preferenceMatch + equipmentConfidence
    }
}

/// Candidato con score calculado.
public struct SubstitutionCandidate: Equatable, Sendable {
    public let exercise: Exercise
    public let score: Double
    public let breakdown: SubstitutionScoreBreakdown
    public let passesSafetyGate: Bool

    public init(exercise: Exercise, score: Double, breakdown: SubstitutionScoreBreakdown, passesSafetyGate: Bool) {
        self.exercise = exercise
        self.score = score
        self.breakdown = breakdown
        self.passesSafetyGate = passesSafetyGate
    }
}

/// Resultado rankeado del motor de sustitución.
public struct SubstitutionResult: Equatable, Sendable {
    /// Candidatos que pasan el gate, ordenados de mayor a menor score.
    public let safeSubstitutes: [SubstitutionCandidate]
    /// Todos los candidatos evaluados (incluye los que fallaron el gate).
    public let allEvaluated: [SubstitutionCandidate]
    /// ¿No hay ningún sustituto seguro?
    public let noSafeSubstitute: Bool

    public init(safeSubstitutes: [SubstitutionCandidate], allEvaluated: [SubstitutionCandidate]) {
        self.safeSubstitutes = safeSubstitutes
        self.allEvaluated = allEvaluated
        self.noSafeSubstitute = safeSubstitutes.isEmpty
    }
}

/// Entrada del motor de sustitución.
public struct SubstitutionInput: Sendable {
    public let target: Exercise
    public let requestedRole: ExerciseRole
    public let activeRestrictions: Set<RestrictionTag>
    public let candidates: [Exercise]
    public let preferences: [ExerciseID: Double]
    public let historyConfidence: [ExerciseID: Double]
    public let equipmentAvailability: [EquipmentType: EquipmentAvailabilityState]

    public init(
        target: Exercise,
        requestedRole: ExerciseRole,
        activeRestrictions: Set<RestrictionTag> = [],
        candidates: [Exercise],
        preferences: [ExerciseID: Double] = [:],
        historyConfidence: [ExerciseID: Double] = [:],
        equipmentAvailability: [EquipmentType: EquipmentAvailabilityState] = [:]
    ) {
        self.target = target
        self.requestedRole = requestedRole
        self.activeRestrictions = activeRestrictions
        self.candidates = candidates
        self.preferences = preferences
        self.historyConfidence = historyConfidence
        self.equipmentAvailability = equipmentAvailability
    }
}

/// Rankea sustitutos con gate de seguridad y pesos versionados (PR-0904).
public struct SubstitutionScoringEngine: Sendable {
    public var weights: SubstitutionWeights

    public init(weights: SubstitutionWeights = .defaultConfig()) {
        self.weights = weights
    }

    public func rank(_ input: SubstitutionInput) -> SubstitutionResult {
        var evaluated: [SubstitutionCandidate] = input.candidates.map { candidate in
            let passesGate = passesSafetyGate(candidate, restrictions: input.activeRestrictions)
            let breakdown = scoreBreakdown(candidate, input: input)
            let total = passesGate ? breakdown.total : 0
            return SubstitutionCandidate(
                exercise: candidate,
                score: total,
                breakdown: breakdown,
                passesSafetyGate: passesGate
            )
        }
        // Reproducible: orden desc por score, ties por canonicalName.
        evaluated.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.exercise.canonicalName < $1.exercise.canonicalName
        }
        let safe = evaluated.filter { $0.passesSafetyGate }
        return SubstitutionResult(safeSubstitutes: safe, allEvaluated: evaluated)
    }

    /// Gate de seguridad: NINGÚN tag de contraindicación del candidato puede
    /// solaparse con una restricción activa (el sustituto no evade restrictiones).
    public func passesSafetyGate(_ candidate: Exercise, restrictions: Set<RestrictionTag>) -> Bool {
        candidate.contraindicationTags.isDisjoint(with: restrictions)
    }

    // MARK: - Scoring

    private func scoreBreakdown(_ candidate: Exercise, input: SubstitutionInput) -> SubstitutionScoreBreakdown {
        SubstitutionScoreBreakdown(
            muscleMatch: muscleMatch(candidate, target: input.target) * weights.muscleMatch,
            movementPatternMatch: movementPatternMatch(candidate, target: input.target) * weights.movementPatternMatch,
            trainingRoleMatch: roleMatch(candidate, requested: input.requestedRole) * weights.trainingRoleMatch,
            angleMatch: angleMatch(candidate, target: input.target) * weights.angleMatch,
            fatigueProfileMatch: fatigueMatch(candidate, target: input.target) * weights.fatigueProfileMatch,
            stabilityMatch: stabilityMatch(candidate, target: input.target) * weights.stabilityMatch,
            userHistoryConfidence: (input.historyConfidence[candidate.id] ?? 0) * weights.userHistoryConfidence,
            preferenceMatch: (input.preferences[candidate.id] ?? 0) * weights.preferenceMatch,
            equipmentConfidence: equipmentConfidence(candidate, availability: input.equipmentAvailability) * weights.equipmentConfidence
        )
    }

    private func muscleMatch(_ candidate: Exercise, target: Exercise) -> Double {
        let targetMuscles = Dictionary(
            uniqueKeysWithValues: target.primaryMuscles.map { ($0.muscleGroupID, $0.activation) }
        )
        let matches = candidate.primaryMuscles.compactMap { contrib in
            targetMuscles[contrib.muscleGroupID].map { min($0, contrib.activation) }
        }
        guard !target.primaryMuscles.isEmpty else { return 0 }
        let overlap = matches.reduce(0, +)
        let base = overlap / Double(target.primaryMuscles.count)
        return min(1, base)
    }

    private func movementPatternMatch(_ candidate: Exercise, target: Exercise) -> Double {
        if candidate.substitutionFamilyID == target.substitutionFamilyID { return 1.0 }
        return candidate.movementPattern == target.movementPattern ? 0.7 : 0.0
    }

    private func roleMatch(_ candidate: Exercise, requested: ExerciseRole) -> Double {
        candidate.defaultRoles.contains(requested) ? 1.0 : 0.0
    }

    private func angleMatch(_ candidate: Exercise, target: Exercise) -> Double {
        if target.movementAngle == nil { return 1.0 }
        return candidate.movementAngle == target.movementAngle ? 1.0 : 0.3
    }

    private func fatigueMatch(_ candidate: Exercise, target: Exercise) -> Double {
        let a = candidate.systemicFatigueCost.normalized
        let b = target.systemicFatigueCost.normalized
        return max(0, 1 - abs(a - b))
    }

    private func stabilityMatch(_ candidate: Exercise, target: Exercise) -> Double {
        candidate.stabilityDemand == target.stabilityDemand ? 1.0 : 0.5
    }

    private func equipmentConfidence(
        _ candidate: Exercise,
        availability: [EquipmentType: EquipmentAvailabilityState]
    ) -> Double {
        let state = availability[candidate.equipment] ?? .unknown
        switch state {
        case .available: return 1.0
        case .unknown: return 0.5
        case .doesNotExist, .occupied: return 0.0
        }
    }
}