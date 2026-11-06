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
//  SCRUM-232 (DE-3): sólo es equivalente lo que hace el mismo movimiento, es seguro,
//  está disponible, no está ya en la sesión y llega al puntaje mínimo de la regla v2.
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
    /// Puntaje mínimo para ser sustituto equivalente (DE-3).
    public static let minimumScore = "minimumScore"               // 0.60
    /// Opciones que se ofrecen como máximo (DE-3).
    public static let maxOptions = "maxOptions"                   // 3

    /// Los pesos del puntaje: son los que deben sumar 1.00.
    public static let weights: Set<String> = [
        muscleMatch, movementPatternMatch, trainingRoleMatch, angleMatch,
        fatigueProfileMatch, stabilityMatch, userHistoryConfidence,
        preferenceMatch, equipmentConfidence,
    ]

    public static let allRequired: Set<String> = weights.union([minimumScore, maxOptions])

    /// Parámetros por defecto: pesos del spec §10.3 (suman 1.00) y límites de DE-3.
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
            minimumScore: 0.60,
            maxOptions: 3,
        ]
    }
}

/// Regla de evidencia por defecto del scoring de sustitución (categoría `.safety`).
public enum SubstitutionScoringDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "safety.substitutionScoring")

    /// v2 (SCRUM-232, DE-3): agrega `minimumScore` y `maxOptions`.
    public static func makeRule(version: Int = 2) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Substitution ranking weights (promptMaster §10.3)",
            source: "Plan §9 / promptMaster §10.3 / SCRUM-231 DE-3"
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
    /// `minimumScore` fuera de 0...1 o `maxOptions` que no es un entero positivo.
    case invalidLimit(key: String)
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
    public var minimumScore: Double { weight(SubstitutionScoringKeys.minimumScore) }
    public var maxOptions: Int { Int(weight(SubstitutionScoringKeys.maxOptions)) }

    public init(rule: EvidenceRule, requireUnityWeights: Bool = true) throws {
        guard rule.category == .safety else {
            throw SubstitutionScoringError.wrongCategory
        }
        let missing = SubstitutionScoringKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw SubstitutionScoringError.missingConfig(keys: Array(missing).sorted())
        }
        if requireUnityWeights {
            let total = SubstitutionScoringKeys.weights.reduce(0.0) { sum, key in
                sum + (rule.parameters[key] ?? 0)
            }
            // Tolerancia razonable a redondeo, pero exige que reflejen el modelo.
            guard abs(total - 1.0) <= 0.001 else {
                throw SubstitutionScoringError.weightsDoNotSumToOne(total)
            }
        }
        let minimum = rule.parameters[SubstitutionScoringKeys.minimumScore] ?? 0
        guard (0...1).contains(minimum) else {
            throw SubstitutionScoringError.invalidLimit(key: SubstitutionScoringKeys.minimumScore)
        }
        let options = rule.parameters[SubstitutionScoringKeys.maxOptions] ?? 0
        guard options >= 1, options == options.rounded() else {
            throw SubstitutionScoringError.invalidLimit(key: SubstitutionScoringKeys.maxOptions)
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
    /// Ejercicios ocupados hoy o marcados "no hay" en el gimnasio activo. Es por ejercicio,
    /// no por tipo de equipo (DE-1): `gymProfile` sólo matiza el puntaje.
    public let unavailableExerciseIDs: Set<ExerciseID>
    /// Ejercicios que ya están en la sesión del día.
    public let sessionExerciseIDs: Set<ExerciseID>
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
        unavailableExerciseIDs: Set<ExerciseID> = [],
        sessionExerciseIDs: Set<ExerciseID> = [],
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
        self.unavailableExerciseIDs = unavailableExerciseIDs
        self.sessionExerciseIDs = sessionExerciseIDs
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
    /// Regla y versión que produjeron el puntaje (RD-007).
    public let ruleReference: EvidenceRuleReference

    public var id: ExerciseID { exercise.id }

    public init(exercise: Exercise, totalScore: Double, components: [ScoreComponent], ruleReference: EvidenceRuleReference) {
        self.exercise = exercise
        self.totalScore = totalScore
        self.components = components
        self.ruleReference = ruleReference
    }
}

/// Por qué no hay sustituto equivalente: la etapa de la regla que dejó la lista vacía.
public enum NoEquivalentReason: String, Sendable, CaseIterable {
    /// Ninguna candidata hace el mismo movimiento, o las que lo hacen ya están en la sesión.
    case noCandidates
    /// Una restricción prohíbe todas las que hacen el mismo movimiento.
    case allForbidden
    /// Las permitidas están ocupadas o no las hay en el gimnasio activo.
    case allUnavailable
    /// Las disponibles quedan bajo el puntaje mínimo de la regla.
    case allBelowMinimum
}

/// Por qué una candidata no hace el mismo movimiento que el objetivo.
public enum MovementMismatch: Sendable, Equatable {
    case differentMuscle
    case differentPattern
    case differentJointClass
}

/// Veredicto de la sustitución (PR-0904 AC: "devuelve no safe substitute si corresponde").
public enum SubstitutionVerdict: Equatable, Sendable {
    /// Sustitutos equivalentes rankeados (mejor primero), `maxOptions` como máximo.
    case safe([ScoredSubstitute])
    /// Sin sustituto equivalente, con la razón.
    case noEquivalent(NoEquivalentReason)

    public var ranked: [ScoredSubstitute] {
        switch self {
        case .safe(let list): return list
        case .noEquivalent: return []
        }
    }
}

// MARK: - Engine

/// Motor determinista de scoring de sustitución (PR-0904).
///
/// Flujo (DE-3, SCRUM-232: mismo músculo no es ejercicio equivalente):
/// 1. **Mismo movimiento:** mismo patrón, al menos un músculo principal en común y misma
///    clase articular; ni el objetivo ni lo que ya está en la sesión.
/// 2. El **safety gate** (`RestrictionPolicyEngine`) filtra candidatas: un sustituto
///    prohibido por la política NUNCA se adopta.
/// 3. **Disponibles:** ni ocupadas hoy ni marcadas "no hay" en el gimnasio activo.
/// 4. Se puntúa cada candidata superviviente por los componentes del §10.3 con los
///    pesos de configuración y se quedan las que llegan a `minimumScore`.
/// 5. Ranking reproducible, hasta `maxOptions`: mayor score primero; empate → nombre
///    canónico y, con el mismo nombre, ID.
///
/// Si una etapa deja la lista vacía, el veredicto dice cuál (`NoEquivalentReason`).
/// Mismos inputs ⇒ mismo orden (determinista, sin dependencias de tiempo/azar).
public struct SubstitutionScoringEngine: Sendable {
    public let config: SubstitutionScoringConfig

    public init(config: SubstitutionScoringConfig) {
        self.config = config
    }

    /// Evalúa la sustitución y devuelve un veredicto reproducible.
    public func substitutes(for request: SubstitutionRequest) throws -> SubstitutionVerdict {
        let reference = try config.reference()

        // 1. Mismo movimiento.
        let equivalent = request.candidates.filter { candidate in
            candidate.id != request.target.id
                && !request.sessionExerciseIDs.contains(candidate.id)
                && Self.movementMismatch(candidate, target: request.target) == nil
        }
        guard !equivalent.isEmpty else { return .noEquivalent(.noCandidates) }

        // 2. Restricciones.
        let safe = try safeCandidates(from: equivalent, request: request)
        guard !safe.isEmpty else { return .noEquivalent(.allForbidden) }

        // 3. Disponibilidad en el gimnasio activo.
        let available = safe.filter { !request.unavailableExerciseIDs.contains($0.id) }
        guard !available.isEmpty else { return .noEquivalent(.allUnavailable) }

        // 4. Puntaje mínimo.
        let scored = try available.map { candidate in
            try score(candidate, request: request, reference: reference)
        }.filter { $0.totalScore >= config.minimumScore }
        guard !scored.isEmpty else { return .noEquivalent(.allBelowMinimum) }

        // 5. Rankear.
        let ranked = scored.sorted { lhs, rhs in
            if lhs.totalScore != rhs.totalScore { return lhs.totalScore > rhs.totalScore }
            if lhs.exercise.canonicalName != rhs.exercise.canonicalName {
                return lhs.exercise.canonicalName < rhs.exercise.canonicalName
            }
            return lhs.exercise.id.rawValue.uuidString < rhs.exercise.id.rawValue.uuidString
        }
        return .safe(Array(ranked.prefix(config.maxOptions)))
    }

    /// La primera parte de "mismo movimiento" que falla (DE-3); `nil` si lo es. Es la única
    /// definición: la personalización con IA también la usa (SCRUM-240).
    public static func movementMismatch(_ candidate: Exercise, target: Exercise) -> MovementMismatch? {
        let targetMuscles = Set(target.primaryMuscles.map(\.muscleGroupID))
        if targetMuscles.isDisjoint(with: candidate.primaryMuscles.map(\.muscleGroupID)) { return .differentMuscle }
        if candidate.movementPattern != target.movementPattern { return .differentPattern }
        if candidate.jointClass != target.jointClass { return .differentJointClass }
        return nil
    }

    // MARK: - Safety gate

    private func safeCandidates(from candidates: [Exercise], request: SubstitutionRequest) throws -> [Exercise] {
        guard !request.activeRestrictions.isEmpty else {
            // Sin restricciones declaradas no hay gate.
            return candidates
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
            among: candidates,
            restrictions: request.activeRestrictions,
            asOf: request.asOf
        )
    }

    // MARK: - Scoring

    private func score(
        _ candidate: Exercise, request: SubstitutionRequest, reference: EvidenceRuleReference
    ) throws -> ScoredSubstitute {
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
        return ScoredSubstitute(exercise: candidate, totalScore: total, components: components, ruleReference: reference)
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