//
//  StrengthProgression.swift
//  PRDomain
//
//  Created by PR.
//
//  Strength progression strategies (promptMaster §12.2, PR-1002). Modela al menos
//  linearLoad / repGoal / topSetBackoff de forma diferenciada: cada estrategia decide
//  la siguiente carga/reps con sus propias reglas deterministas — NUNCA una única
//  fórmula para todos (§12.1). La estrategia es explícita por block/exercise y se
//  versiona via EvidenceRule. Gate conservador común (dolor, fallo excesivo, caída)
//  y double progression delega en el motor PR-1001. Auditable con `DecisionRecord`.
//

import Foundation

// MARK: - Strategy (promptMaster §12.2)

/// Estrategia de progresión para un ejercicio/bloque.
public enum ProgressionStrategy: String, Codable, Sendable, CaseIterable, Hashable {
    case doubleProgression
    case linearLoad
    case repGoal
    case rirAutoregulated
    case strengthTopSetBackoff
    case maintain

    /// Estrategias de fuerza de básicos que PR-1002 modela por su propia regla.
    public static let strengthStrategies: [ProgressionStrategy] = [
        .linearLoad, .repGoal, .strengthTopSetBackoff,
    ]
}

// MARK: - Config versionada

/// Claves canónicas de la regla de progresión de fuerza.
public enum StrengthProgressionKeys {
    /// Incremento lineal (kg) por sesión (linearLoad / top set).
    public static let linearIncrement = "linearIncrement"
    /// Fracción del top set para las back-off sets (topSetBackoff).
    public static let backoffFraction = "backoffFraction"
    /// Umbral de dolor (moderate/high ⇒ >=3) que bloquea la progresión.
    public static let painSeverityThreshold = "painSeverityThreshold"
    /// RIR bajo (<= threshold) que permite subir carga en autoregulación.
    public static let lowRIRThreshold = "lowRIRThreshold"
    /// Incremento por defecto cuando la carga es continua (extensible/bodyweight).
    public static let continuousDefaultIncrement = "continuousDefaultIncrement"

    public static let allRequired: Set<String> = [
        linearIncrement, backoffFraction, painSeverityThreshold,
        lowRIRThreshold, continuousDefaultIncrement,
    ]

    public static func defaults() -> [String: Double] {
        [
            linearIncrement: 2.5,
            backoffFraction: 0.85,
            painSeverityThreshold: 3,
            lowRIRThreshold: 1,
            continuousDefaultIncrement: 2.5,
        ]
    }
}

/// Regla versionada por defecto de progresión de fuerza (categoría progression).
public enum StrengthProgressionDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "progression.strength")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Strength progression strategies: linear/repGoal/topSetBackoff with conservative joint gate",
            source: "Plan §4E / promptMaster §12.2"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Strength progression engine",
            category: .progression,
            confidence: .emerging,
            version: version,
            parameters: StrengthProgressionKeys.defaults(),
            references: [reference]
        )
    }
}

/// Configuración versionada de progresión de fuerza.
public struct StrengthProgressionConfig: Sendable {
    public let rule: EvidenceRule

    public var linearIncrement: Double { rule.parameters[StrengthProgressionKeys.linearIncrement] ?? 2.5 }
    public var backoffFraction: Double { rule.parameters[StrengthProgressionKeys.backoffFraction] ?? 0.85 }
    public var painSeverityThreshold: Int { Int(rule.parameters[StrengthProgressionKeys.painSeverityThreshold] ?? 3) }
    public var lowRIRThreshold: Int { Int(rule.parameters[StrengthProgressionKeys.lowRIRThreshold] ?? 1) }
    public var continuousDefaultIncrement: Double { rule.parameters[StrengthProgressionKeys.continuousDefaultIncrement] ?? 2.5 }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .progression else {
            throw StrengthProgressionError.wrongCategory
        }
        let missing = StrengthProgressionKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw StrengthProgressionError.missingConfig(keys: Array(missing).sorted())
        }
        let fraction = rule.parameters[StrengthProgressionKeys.backoffFraction] ?? 0.85
        guard (0.0...1.0).contains(fraction) else {
            throw StrengthProgressionError.invalidBackoffFraction(fraction)
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

// MARK: - Errores

public enum StrengthProgressionError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case wrongCategory
    case invalidBackoffFraction(Double)
    case noPrescription
    case invalidStrategy(ProgressionStrategy)
}

// MARK: - Input

/// Resultado llevado a cabo de la sesión para un ejercicio (working sets + top/back-off).
public struct StrengthSetEvidence: Sendable {
    public let isTopSet: Bool
    public let weight: Double
    public let reps: Int
    public let rir: Int?
    public var perceivedDifficulty: DifficultyFeedback?
    public var painFeedback: PainFeedback?

    public init(
        isTopSet: Bool,
        weight: Double,
        reps: Int,
        rir: Int? = nil,
        perceivedDifficulty: DifficultyFeedback? = nil,
        painFeedback: PainFeedback? = nil
    ) {
        self.isTopSet = isTopSet
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.perceivedDifficulty = perceivedDifficulty
        self.painFeedback = painFeedback
    }
}

/// Entrada del motor de fuerza para decidir la siguiente carga.
public struct StrengthProgressionInput: Sendable {
    /// Estrategia explícita para este ejercicio/bloque.
    public let strategy: ProgressionStrategy
    /// Prescripción planeada (para rango de reps objetivo).
    public let prescription: SetPrescription
    /// Sets realizados en la sesión (working sets; el top set se marca en `evidence`).
    public let performed: [StrengthSetEvidence]
    /// Carga actual. nil ⇒ primera vez (confidence low).
    public let currentWeight: Double?
    public let unit: LoadUnit
    /// Incremento disponible de la máquina/equipo (nil si se desconoce).
    public let availableIncrement: Double?
    public let loadability: Loadability
    /// Caída significativa reciente que justifica mantener.
    public let hasRecentSignificantDrop: Bool

    public init(
        strategy: ProgressionStrategy,
        prescription: SetPrescription,
        performed: [StrengthSetEvidence] = [],
        currentWeight: Double?,
        unit: LoadUnit,
        availableIncrement: Double? = nil,
        loadability: Loadability = .discreteIncrements,
        hasRecentSignificantDrop: Bool = false
    ) {
        self.strategy = strategy
        self.prescription = prescription
        self.performed = performed
        self.currentWeight = currentWeight
        self.unit = unit
        self.availableIncrement = availableIncrement
        self.loadability = loadability
        self.hasRecentSignificantDrop = hasRecentSignificantDrop
    }
}

// MARK: - Out come

/// Decisión de carga/reps de la estrategia.
public enum StrengthProgressionDecision: Equatable, Sendable {
    /// Sube la carga un incremento disponible.
    case increaseLoad(newWeight: Double, from: Double)
    /// Mantiene la carga (reglas no satisfechas o estrategia conservadora).
    case holdLoad(weight: Double)
    /// repGoal: sin cambiar peso, sube el objetivo de reps dentro del rango.
    case advanceRepTarget(to: Int, weight: Double)
    /// repGoal: rango completado → sube carga y reinicia el objetivo a reps del rango inferior.
    case repGoalLoadIncrease(newWeight: Double, from: Double, resetRepsTo: Int)
}

/// Evaluación auditable de la estrategia de fuerza.
public struct StrengthProgressionEvaluation: Equatable, Sendable {
    public let decision: StrengthProgressionDecision
    public let reason: String
    public let ruleReference: EvidenceRuleReference
    public let decisionRecord: DecisionRecord

    public init(
        decision: StrengthProgressionDecision,
        reason: String,
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.decision = decision
        self.reason = reason
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

// MARK: - Engine

/// Motor determinista de estrategias de progresión de fuerza (PR-1002).
///
/// Cada estrategia tiene su propia regla (no una fórmula única):
/// - `linearLoad`: sube un incremento fijo cuando todas las working sets alcanzan el
///   objetivo de reps (sin fallo/pain/caída).
/// - `repGoal`: no toca el peso; sube el objetivo de reps hasta el tope del rango y
///   entonces sube la carga y reinicia el objetivo al tramo inferior.
/// - `strengthTopSetBackoff`: el top set que cumple su objetivo sube de carga; las
///   back-off sets se prescriben a una fracción configurada del top set.
/// - `rirAutoregulated`: la carga reacciona al RIR reportado (bajo ⇒ sube; alto ⇒ hold).
/// - `doubleProgression`: delega en `ProgressionEngine` (PR-1001).
/// - `maintain`: conserva siempre.
public struct StrengthProgressionEngine: Sendable {
    public let config: StrengthProgressionConfig

    public init(config: StrengthProgressionConfig) throws {
        self.config = config
    }

    public func evaluate(_ input: StrengthProgressionInput) throws -> StrengthProgressionEvaluation {
        let reference = try config.reference()

        // Gate conservador común: dolor moderado/alto cancela cualquier progresión.
        let painGate = input.performed.contains {
            Self.isModerateOrHigherPain($0.painFeedback, threshold: config.painSeverityThreshold)
        }
        if painGate {
            return make(.holdLoad(weight: input.currentWeight ?? 0), reason: "dolor moderado/alto: progresión cancelada", reference: reference)
        }

        // Primera vez: sin carga base no hay nada que aumentar (§12.4).
        guard let current = input.currentWeight, current.isFinite, current >= 0 else {
            return make(.holdLoad(weight: 0), reason: "primera vez con este ejercicio: loadConfidence low, sin carga base", reference: reference)
        }

        switch input.strategy {
        case .linearLoad:
            return linearLoad(input, current: current, reference: reference)
        case .repGoal:
            return repGoal(input, current: current, reference: reference)
        case .strengthTopSetBackoff:
            return topSetBackoff(input, current: current, reference: reference)
        case .rirAutoregulated:
            return rirAutoregulated(input, current: current, reference: reference)
        case .doubleProgression:
            return try doubleProgression(input, current: current, reference: reference)
        case .maintain:
            return make(.holdLoad(weight: current), reason: "estrategia maintain: se conserva la carga", reference: reference)
        }
    }

    // MARK: - Estrategias

    private func linearLoad(_ input: StrengthProgressionInput, current: Double, reference: EvidenceRuleReference) -> StrengthProgressionEvaluation {
        let working = input.performed
        let upper = input.prescription.targetRepRange.upperBound
        let allOnTarget = !working.isEmpty && working.allSatisfy { $0.reps >= upper }
        let failed = input.performed.contains { $0.perceivedDifficulty == .failed }

        guard allOnTarget, !failed, !input.hasRecentSignificantDrop else {
            let why = !allOnTarget ? "alguna working set no alcanzó las \(upper) reps" :
                       failed ? "fallo excesivo en un set" : "caída de rendimiento reciente"
            return make(.holdLoad(weight: current), reason: "linearLoad: \(why)", reference: reference)
        }
        guard let increment = stepIncrement(for: input) else {
            return make(.holdLoad(weight: current), reason: "linearLoad: incremento de equipo desconocido (conservador)", reference: reference)
        }
        let next = current + increment
        return make(.increaseLoad(newWeight: next, from: current), reason: "linearLoad: todas las working sets ≥ \(upper) reps → +\(format(increment))", reference: reference)
    }

    private func repGoal(_ input: StrengthProgressionInput, current: Double, reference: EvidenceRuleReference) -> StrengthProgressionEvaluation {
        let range = input.prescription.targetRepRange
        let lastReps = input.performed.map(\.reps).max() ?? 0

        // Completar el rango superior → subir carga y reiniciar objetivo al tramo inferior.
        if lastReps >= range.upperBound {
            guard let increment = stepIncrement(for: input) else {
                return make(.holdLoad(weight: current), reason: "repGoal: rango completado pero incremento desconocido (conservador)", reference: reference)
            }
            let next = current + increment
            return make(.repGoalLoadIncrease(newWeight: next, from: current, resetRepsTo: range.lowerBound), reason: "repGoal: alcanzadas \(lastReps) (>= \(range.upperBound)) → +\(format(increment)) y reset a \(range.lowerBound) reps", reference: reference)
        }

        // Dentro del rango: sube el objetivo de reps sin tocar el peso.
        let nextReps = lastReps + 1
        return make(.advanceRepTarget(to: min(nextReps, range.upperBound), weight: current), reason: "repGoal: mantener peso, objetivo de reps → \(min(nextReps, range.upperBound))", reference: reference)
    }

    private func topSetBackoff(_ input: StrengthProgressionInput, current: Double, reference: EvidenceRuleReference) -> StrengthProgressionEvaluation {
        guard let topSet = input.performed.first(where: { $0.isTopSet }) else {
            return make(.holdLoad(weight: current), reason: "topSetBackoff: no hay top set en la sesión", reference: reference)
        }
        let upper = input.prescription.targetRepRange.upperBound
        let topMetTarget = topSet.reps >= upper
        let failed = input.performed.contains { $0.perceivedDifficulty == .failed }

        guard topMetTarget, !failed, !input.hasRecentSignificantDrop else {
            let why = !topMetTarget ? "top set no alcanzó su objetivo de \(upper) reps" :
                       failed ? "fallo excesivo en un set" : "caída de rendimiento reciente"
            return make(.holdLoad(weight: current), reason: "topSetBackoff: \(why)", reference: reference)
        }
        guard let increment = stepIncrement(for: input) else {
            return make(.holdLoad(weight: current), reason: "topSetBackoff: sin incremento de equipo conocido (conservador)", reference: reference)
        }
        let next = current + increment
        let backoff = next * config.backoffFraction
        return make(.increaseLoad(newWeight: next, from: current), reason: "topSetBackoff: top set ≥ \(upper) reps → top +\(format(increment)); back-off a \(format(backoff)) (\(Int(config.backoffFraction * 100))%)", reference: reference)
    }

    private func rirAutoregulated(_ input: StrengthProgressionInput, current: Double, reference: EvidenceRuleReference) -> StrengthProgressionEvaluation {
        let rirs = input.performed.compactMap(\.rir)
        guard !rirs.isEmpty else {
            return make(.holdLoad(weight: current), reason: "rirAutoregulated: sin feedback de RIR en la sesión", reference: reference)
        }
        // RIR consistentemente bajo (duro) y en target ⇒ subir. RIR alto ⇒ mantener.
        let averageRIR = Double(rirs.reduce(0, +)) / Double(rirs.count)
        let upper = input.prescription.targetRepRange.upperBound
        let onTarget = input.performed.allSatisfy { $0.reps >= upper }

        if onTarget, averageRIR <= Double(config.lowRIRThreshold), !input.hasRecentSignificantDrop {
            guard let increment = stepIncrement(for: input) else {
                return make(.holdLoad(weight: current), reason: "rirAutoregulated: RIR bajo pero incremento desconocido (conservador)", reference: reference)
            }
            let next = current + increment
            return make(.increaseLoad(newWeight: next, from: current), reason: "rirAutoregulated: RIR medio \(format(averageRIR)) ≤ \(config.lowRIRThreshold) y en target → +\(format(increment))", reference: reference)
        }
        return make(.holdLoad(weight: current), reason: "rirAutoregulated: RIR medio \(format(averageRIR)) en zona → se mantiene carga", reference: reference)
    }

    private func doubleProgression(_ input: StrengthProgressionInput, current: Double, reference: EvidenceRuleReference) throws -> StrengthProgressionEvaluation {
        // Reusa el engine de PR-1001 mediante sus tipos públicos.
        let progressionConfig = try DoubleProgressionConfig(rule: try DoubleProgressionDefaults.makeRule())
        let engine = try ProgressionEngine(config: progressionConfig)
        let records = input.performed.compactMap { evidence -> SetRecord? in
            guard !evidence.isTopSet else { return nil }
            return try? SetRecord(
                exerciseID: ExerciseID(),
                performedAt: Date(),
                weight: evidence.weight,
                unit: input.unit,
                reps: evidence.reps,
                rir: evidence.rir,
                perceivedDifficulty: evidence.perceivedDifficulty,
                painFeedback: evidence.painFeedback,
                lifecycle: .completed
            )
        }
        let evaluation = try engine.evaluate(ProgressionEvaluationInput(
            prescription: input.prescription,
            performedSets: records,
            currentWeight: current,
            unit: input.unit,
            availableIncrement: input.availableIncrement,
            loadability: input.loadability,
            hasRecentSignificantDrop: input.hasRecentSignificantDrop
        ))
        let decision: StrengthProgressionDecision
        switch evaluation.outcome {
        case .increase(let newWeight, let from):
            decision = .increaseLoad(newWeight: newWeight, from: from)
        case .hold(let weight):
            decision = .holdLoad(weight: weight)
        }
        return StrengthProgressionEvaluation(
            decision: decision,
            reason: evaluation.reasons.joined(separator: "; "),
            ruleReference: reference,
            decisionRecord: evaluation.decisionRecord
        )
    }

    // MARK: - Helpers

    private func stepIncrement(for input: StrengthProgressionInput) -> Double? {
        switch input.loadability {
        case .fixedStack, .discreteIncrements:
            return input.availableIncrement
        case .continuous, .resisted, .bodyweight:
            return input.availableIncrement ?? config.continuousDefaultIncrement
        }
    }

    private static func isModerateOrHigherPain(_ pain: PainFeedback?, threshold: Int) -> Bool {
        guard let pain else { return false }
        switch pain {
        case .none:
            return false
        case .discomfort(_, let severity), .sharpPain(_, let severity):
            return severity >= threshold
        }
    }

    private func make(_ decision: StrengthProgressionDecision, reason: String, reference: EvidenceRuleReference) -> StrengthProgressionEvaluation {
        let record = DecisionRecord(
            type: .loadChange,
            inputFacts: [DecisionFact(key: "reason", value: reason)],
            action: DecisionActionSummary(title: "Transición de progresión", detail: reason),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )
        return StrengthProgressionEvaluation(
            decision: decision,
            reason: reason,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}