//
//  SubstitutionScoring.swift
//  PRDomain
//
//  Created by PR.
//
//  Substitution scoring engine (promptMaster §10.3, PR-0904). Cuando una máquina
//  está ocupada o falta equipo, el sistema recomienda sustituciones equivalentes
//  por rol/patrón/músculo/seguridad. El ranking es reproducible (mismos inputs →
//  mismo orden) y las restricciones/safety son un gate obligatorio: un candidato
//  prohibido por la política jamás se adopta. Determinista y auditable.
//

import Foundation

// MARK: - Keys de configuración (versión rule)

/// Claves canónicas de los pesos del scoring de sustitución (§10.3).
/// Los pesos son configuración versionada (EvidenceRegistry), no constantes sueltas.
public enum SubstitutionScoringKeys {
    public static let muscleMatch = "muscleMatch"                 // 0.30
    public static let movementPatternMatch = "movementPatternMatch" // 0.20
    public static let trainingRoleMatch = "trainingRoleMatch"     // 0.15
    public static let angleMatch = "angleMatch"                   // 0.10
    public static let fatigueProfileMatch = "fatigueProfileMatch" // 0.08
    public static let stabilityMatch = "stabilityMatch"           // 0.05
    public static let userHistoryConfidence = "userHistoryConfidence" // 0.05
    public static let preferenceMatch = "preferenceMatch"         // 0.04
    public static let equipmentConfidence = "equipmentConfidence" // 0.03

    public static let allRequired: Set<String> = [
        muscleMatch, movementPatternMatch, trainingRoleMatch, angleMatch,
        fatigueProfileMatch, stabilityMatch, userHistoryConfidence,
        preferenceMatch, equipmentConfidence,
    ]

    /// Pesos por defecto del spec §10.3 (suman 1.00).
    public static func defaults() -> [String: Double] {
        [
            muscleMatch: 0.30,
            movementPatternMatch: 0.20,
            trainingRoleMatch: 0.15,
            angleMatch: 0.10,
            fatigueProfileMatch: 0.08,
            stabilityMatch: 0.05,
            userHistoryConfidence: 0.05,
            preferenceMatch: 0.04,
            equipmentConfidence: 0.03,
        ]
    }
}

/// Regla de evidencia por defecto del scoring de sustitución (categoría `.safety`).
public enum SubstitutionScoringDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "safety.substitutionScoring")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Substitution ranking weights (promptMaster §10.3)",
            source: "Plan §9 / promptMaster §10.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Substitution scoring engine",
            category: .safety,
            confidence: .expertConsensus,
            version: version,
            parameters: SubstitutionScoringKeys.defaults(),
            references: [reference]
        )
    }
}

// MARK: - Errores y config

/// Problemas de entrada del scoring de sustitución.
public enum SubstitutionScoringError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case wrongCategory
    case weightsDoNotSumToOne(Double)
}

/// Configuración versionada de los pesos del scoring (§10.3).
public struct SubstitutionScoringConfig: Sendable {
    public let rule: EvidenceRule

    public var muscleMatch: Double { weight(SubstitutionScoringKeys.muscleMatch) }
    public var movementPatternMatch: Double { weight(SubstitutionScoringKeys.movementPatternMatch) }
    public var trainingRoleMatch: Double { weight(SubstitutionScoringKeys.trainingRoleMatch) }
    public var angleMatch: Double { weight(SubstitutionScoringKeys.angleMatch) }
    public var fatigueProfileMatch: Double { weight(SubstitutionScoringKeys.fatigueProfileMatch) }
    public var stabilityMatch: Double { weight(SubstitutionScoringKeys.stabilityMatch) }
    public var userHistoryConfidence: Double { weight(SubstitutionScoringKeys.userHistoryConfidence) }
    public var preferenceMatch: Double { weight(SubstitutionScoringKeys.preferenceMatch) }
    public var equipmentConfidence: Double { weight(SubstitutionScoringKeys.equipmentConfidence) }

    public init(rule: EvidenceRule, requireUnityWeights: Bool = true) throws {
        guard rule.category == .safety else {
            throw SubstitutionScoringError.wrongCategory
        }
        let missing = SubstitutionScoringKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw SubstitutionScoringError.missingConfig(keys: Array(missing).sorted())
        }
        if requireUnityWeights {
            let total = SubstitutionScoringKeys.allRequired.reduce(0.0) { sum, key in
                sum + (rule.parameters[key] ?? 0)
            }
            // Tolerancia razonable a redondeo, pero exige que reflejen el modelo.
            guard abs(total - 1.0) <= 0.001 else {
                throw SubstitutionScoringError.weightsDoNotSumToOne(total)
            }
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }

    private func weight(_ key: String) -> Double {
        rule.parameters[key] ?? 0
    }
}

// MARK: - Inputs

/// Métricas del usuario que matizan el ranking (§10.3 9-10).
public struct SubstitutionUserSignal: Sendable {
    /// Confianza del historial (0...1) por ejercicio candidato.
    public var historyConfidence: [ExerciseID: Double]
    /// Ejercicios preferidos por el usuario.
    public var preferredExerciseIDs: Set<ExerciseID>

    public init(
        historyConfidence: [ExerciseID: Double] = [:],
        preferredExerciseIDs: Set<ExerciseID> = []
    ) {
        self.historyConfidence = historyConfidence
        self.preferredExerciseIDs = preferredExerciseIDs
    }
}

/// Contexto de la sustitución: ejercicio objetivo + candidatos.
public struct SubstitutionRequest: Sendable {
    /// Ejercicio a sustituir (el que está ocupado / falta).
    public let target: Exercise
    /// Rol programático que debe preservar el sustituto (si se conoce).
    public let targetRole: ExerciseRole?
    /// Candidatas a evaluación (usualmente de la misma familia de sustitución).
    public let candidates: [Exercise]
    /// Recursos del perfil para preferencia/equipamiento/historial.
    public let userSignal: SubstitutionUserSignal
    /// Perfil del gym para confianza de equipamiento (opcional).
    public let gymProfile: GymProfile?
    /// Restricciones activas para el safety gate (opcional; si vacío no filtra).
    public let activeRestrictions: [TrainingRestriction]
    /// Fecha respecto a la que refrescar restricciones.
    public let asOf: Date
    /// Config de la policy de restricciones (safety gate).
    public var restrictionPolicyConfig: RestrictionPolicyConfig?
    /// Nivel de prioridad del ejercicio objetivo (para explicar el ranking).
    public var targetPriority: PriorityTier?

    public init(
        target: Exercise,
        targetRole: ExerciseRole? = nil,
        candidates: [Exercise],
        userSignal: SubstitutionUserSignal = SubstitutionUserSignal(),
        gymProfile: GymProfile? = nil,
        activeRestrictions: [TrainingRestriction] = [],
        asOf: Date = Date(),
        restrictionPolicyConfig: RestrictionPolicyConfig? = nil,
        targetPriority: PriorityTier? = nil
    ) {
        self.target = target
        self.targetRole = targetRole
        self.candidates = candidates
        self.userSignal = userSignal
        self.gymProfile = gymProfile
        self.activeRestrictions = activeRestrictions
        self.asOf = asOf
        self.restrictionPolicyConfig = restrictionPolicyConfig
        self.targetPriority = targetPriority
    }
}

// MARK: - Resultado

/// Desglose de una dimensión del scoring.
public struct ScoreComponent: Equatable, Sendable {
    public let key: String
    /// Valor normalizado de la dimensión (0...1), independiente del peso.
    public let match: Double
    /// Contribución al total = peso × match.
    public let contribution: Double

    public init(key: String, match: Double, weight: Double) {
        self.key = key
        self.match = min(max(match, 0), 1)
        self.contribution = weight * self.match
    }
}

/// Sustituto evaluado con su ranking reproducible.
public struct ScoredSubstitute: Identifiable, Equatable, Sendable {
    public let exercise: Exercise
    public let totalScore: Double
    public let components: [ScoreComponent]

    public var id: ExerciseID { exercise.id }

    public init(exercise: Exercise, totalScore: Double, components: [ScoreComponent]) {
        self.exercise = exercise
        self.totalScore = totalScore
        self.components = components
    }
}

/// Veredicto de la sustitución (PR-0904 AC: "devuelve no safe substitute si corresponde").
public enum SubstitutionVerdict: Equatable, Sendable {
    /// Sustitutos seguros rankeados (mejor primero). Vacío si no hay candidatas seguras.
    case safe([ScoredSubstitute])
    /// No existe sustituto seguro (ninguna candidata pasó el gate o no hay candidatas).
    case noSafeSubstitute([String])

    public var ranked: [ScoredSubstitute] {
        switch self {
        case .safe(let list): return list
        case .noSafeSubstitute: return []
        }
    }
}

// MARK: - Engine

/// Motor determinista de scoring de sustitución (PR-0904).
///
/// Flujo:
/// 1. El **safety gate** (`RestrictionPolicyEngine`) filtra candidatas: un sustituto
///    prohibido por la política NUNCA se adopta.
/// 2. Se puntúa cada candidata superviviente por los componentes del §10.3 con los
///    pesos de configuración (regla versionada).
/// 3. Ranking reproducible: mayor score primero; empate → nombre canónico.
///
/// Mismos inputs ⇒ mismo orden (determinista, sin dependencias de tiempo/azar).
public struct SubstitutionScoringEngine: Sendable {
    public let config: SubstitutionScoringConfig

    public init(config: SubstitutionScoringConfig) {
        self.config = config
    }

    /// Evalúa la sustitución y devuelve un veredicto reproducible.
    public func substitutes(for request: SubstitutionRequest) throws -> SubstitutionVerdict {
        let reference = try config.reference()

        // 1. Candidatas que superan el gate de restricciones/safety.
        let safe = try safeCandidates(from: request)

        // 2. Sin candidatas seguras → no hay sustituto seguro.
        guard !safe.isEmpty else {
            let reasons = request.activeRestrictions.isEmpty
                ? ["no candidate exercises to substitute"]
                : ["all candidates are forbidden by the restriction policy"]
            return .noSafeSubstitute(reasons)
        }

        // 3. Rankear.
        let scored: [ScoredSubstitute] = try safe.map { candidate in
            try score(candidate, request: request)
        }.sorted { lhs, rhs in
            if lhs.totalScore != rhs.totalScore { return lhs.totalScore > rhs.totalScore }
            return lhs.exercise.canonicalName.localizedStandardCompare(rhs.exercise.canonicalName) == .orderedAscending
        }

        return .safe(scored)
    }

    // MARK: - Safety gate

    private func safeCandidates(from request: SubstitutionRequest) throws -> [Exercise] {
        guard !request.activeRestrictions.isEmpty else {
            // Sin restricciones declaradas no hay gate; se respeta la disponibilidad básica.
            return request.candidates
        }
        let policyConfig: RestrictionPolicyConfig
        if let injected = request.restrictionPolicyConfig {
            policyConfig = injected
        } else {
            policyConfig = try RestrictionPolicyConfig(
                rule: try RestrictionPolicyDefaults.makeRule()
            )
        }
        let engine = try RestrictionPolicyEngine(config: policyConfig)
        return try engine.safeSubstitutes(
            among: request.candidates,
            restrictions: request.activeRestrictions,
            asOf: request.asOf
        )
    }

    // MARK: - Scoring

    private func score(_ candidate: Exercise, request: SubstitutionRequest) throws -> ScoredSubstitute {
        var components: [ScoreComponent] = []
        append(SubstitutionScoringKeys.muscleMatch, match: muscleMatch(request.target, candidate), weight: config.muscleMatch, into: &components)
        append(SubstitutionScoringKeys.movementPatternMatch, match: movementPatternMatch(request.target, candidate), weight: config.movementPatternMatch, into: &components)
        append(SubstitutionScoringKeys.trainingRoleMatch, match: roleMatch(request, candidate), weight: config.trainingRoleMatch, into: &components)
        append(SubstitutionScoringKeys.angleMatch, match: angleMatch(request.target, candidate), weight: config.angleMatch, into: &components)
        append(SubstitutionScoringKeys.fatigueProfileMatch, match: fatigueMatch(request.target, candidate), weight: config.fatigueProfileMatch, into: &components)
        append(SubstitutionScoringKeys.stabilityMatch, match: stabilityMatch(request.target, candidate), weight: config.stabilityMatch, into: &components)
        append(SubstitutionScoringKeys.userHistoryConfidence, match: historyConfidence(request.userSignal, candidate), weight: config.userHistoryConfidence, into: &components)
        append(SubstitutionScoringKeys.preferenceMatch, match: preferenceMatch(request.userSignal, candidate), weight: config.preferenceMatch, into: &components)
        append(SubstitutionScoringKeys.equipmentConfidence, match: equipmentConfidence(request.gymProfile, candidate), weight: config.equipmentConfidence, into: &components)

        let total = components.reduce(0.0) { $0 + $1.contribution }
        return ScoredSubstitute(exercise: candidate, totalScore: total, components: components)
    }

    private func append(_ key: String, match: Double, weight: Double, into components: inout [ScoreComponent]) {
        components.append(ScoreComponent(key: key, match: match, weight: weight))
    }

    // MARK: - Dimensiones (§10.3)

    private func muscleMatch(_ target: Exercise, _ candidate: Exercise) -> Double {
        jaccard(
            Set(target.primaryMuscles.map(\.muscleGroupID)),
            Set(candidate.primaryMuscles.map(\.muscleGroupID))
        )
    }

    private func movementPatternMatch(_ target: Exercise, _ candidate: Exercise) -> Double {
        target.movementPattern == candidate.movementPattern ? 1 : 0
    }

    private func roleMatch(_ request: SubstitutionRequest, _ candidate: Exercise) -> Double {
        guard let role = request.targetRole else {
            // Sin rol asignado: se premia cubrir cualquier rol por defecto del objetivo.
            return request.target.defaultRoles.isEmpty ? 0 : (candidate.defaultRoles.intersection(request.target.defaultRoles).isEmpty ? 0 : 1)
        }
        return candidate.defaultRoles.contains(role) ? 1 : 0
    }

    private func angleMatch(_ target: Exercise, _ candidate: Exercise) -> Double {
        guard let targetAngle = target.movementAngle else { return 1 } // sin constricción
        guard let candidateAngle = candidate.movementAngle else { return 0.5 }
        return targetAngle == candidateAngle ? 1 : 0
    }

    private func fatigueMatch(_ target: Exercise, _ candidate: Exercise) -> Double {
        let targetFatigue = fatigueVector(target)
        let candidateFatigue = fatigueVector(candidate)
        guard !targetFatigue.isEmpty else { return 1 }
        let numerator = Set(targetFatigue.keys).union(candidateFatigue.keys).reduce(0.0) { sum, key in
            sum + (targetFatigue[key] ?? 0) * (candidateFatigue[key] ?? 0)
        }
        let normTarget = sqrt(targetFatigue.values.reduce(0) { $0 + $1 * $1 })
        let normCandidate = sqrt(candidateFatigue.values.reduce(0) { $0 + $1 * $1 })
        guard normTarget > 0, normCandidate > 0 else { return 0 }
        let cos = numerator / (normTarget * normCandidate)
        // Similitud coseno en [0,1] para vectores de fatiga normalizados.
        return max(0, cos)
    }

    private func stabilityMatch(_ target: Exercise, _ candidate: Exercise) -> Double {
        levelValue(candidate.stabilityDemand) == levelValue(target.stabilityDemand) ? 1 : 0.5
    }

    private func historyConfidence(_ signal: SubstitutionUserSignal, _ candidate: Exercise) -> Double {
        signal.historyConfidence[candidate.id] ?? 0
    }

    private func preferenceMatch(_ signal: SubstitutionUserSignal, _ candidate: Exercise) -> Double {
        signal.preferredExerciseIDs.contains(candidate.id) ? 1 : 0
    }

    private func equipmentConfidence(_ profile: GymProfile?, _ candidate: Exercise) -> Double {
        guard let profile else { return 1 }
        switch profile.state(of: candidate.equipment) {
        case .available: return 1
        case .unknown: return 0.5
        case .doesNotExist, .occupied: return 0
        }
    }

    // MARK: - Helpers

    private func fatigueVector(_ exercise: Exercise) -> [MuscleGroup.ID: Double] {
        var vector = exercise.localFatigue.mapValues { $0.normalized }
        // Añade el coste sistémico como componente ("systemic") para comparar fatiga global.
        vector[.core] = max(vector[.core] ?? 0, exercise.systemicFatigueCost.normalized)
        return vector
    }

    private func jaccard(_ a: Set<MuscleGroup>, _ b: Set<MuscleGroup>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    private func levelValue(_ level: DemandLevel) -> Int {
        switch level {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }
}