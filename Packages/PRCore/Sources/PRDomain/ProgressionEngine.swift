//
//  ProgressionEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Double progression (plan §4E, §12 Fase 9, RF-014, PR-1001). La carga sólo aumenta
//  bajo reglas conservadoras: todas las working sets relevantes alcanzan el rango
//  superior, sin fallo excesivo, sin dolor moderado/alto, sin caída reciente, y
//  respetando el incremento disponible de la máquina/equipo (RN-013). El motor
//  produce un `DecisionRecord` auditable. Determinista.
//

import Foundation

/// Claves canónicas de la regla de double progression.
public enum ProgressionConfigKeys {
    /// Severidad mínima de dolor que bloquea la progresión (moderate/high ⇒ >=3).
    public static let painSeverityThreshold = "painSeverityThreshold"
    /// ¿Exigir el rango superior de reps para subir carga? 1 = doble progresión clásica.
    public static let requireUpperBoundReps = "requireUpperBoundReps"
    /// Incremento por defecto cuando la carga es continua (extensible/bodyweight).
    public static let continuousDefaultIncrement = "continuousDefaultIncrement"

    public static let allRequired: Set<String> = [
        painSeverityThreshold, requireUpperBoundReps, continuousDefaultIncrement,
    ]

    public static func defaults() -> [String: Double] {
        [
            painSeverityThreshold: 3,
            requireUpperBoundReps: 1,
            continuousDefaultIncrement: 2.5,
        ]
    }
}

/// Regla versionada por defecto de double progression (categoría progression).
public enum DoubleProgressionDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "progression.double")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Double progression: increase load only when upper rep range is met",
            source: "Plan §4E / promptMaster §12.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Double progression conservative rule",
            category: .progression,
            confidence: .emerging,
            version: version,
            parameters: ProgressionConfigKeys.defaults(),
            references: [reference]
        )
    }
}

/// Configuración versionada de double progression.
public struct DoubleProgressionConfig: Sendable {
    public let rule: EvidenceRule

    public var painSeverityThreshold: Int {
        Int(rule.parameters[ProgressionConfigKeys.painSeverityThreshold] ?? 3)
    }

    public var requireUpperBoundReps: Bool {
        (rule.parameters[ProgressionConfigKeys.requireUpperBoundReps] ?? 1) > 0
    }

    public var continuousDefaultIncrement: Double {
        rule.parameters[ProgressionConfigKeys.continuousDefaultIncrement] ?? 2.5
    }

    public init(rule: EvidenceRule) throws {
        let missing = ProgressionConfigKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw ProgressionEngineError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Problemas de entrada del motor de progresión.
public enum ProgressionEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case noPrescription
}

/// Entrada de doble progresión para un ejercicio/máquina.
public struct ProgressionEvaluationInput: Sendable {
    public let prescription: SetPrescription
    /// Working sets relevantes realizados (completed).
    public let performedSets: [SetRecord]
    /// Carga actual del ejercicio/máquina. nil ⇒ primera vez (confidence low).
    public let currentWeight: Double?
    public let unit: LoadUnit
    /// Incremento disponible de la máquina/equipo (nil si se desconoce).
    public let availableIncrement: Double?
    public let loadability: Loadability
    /// Caída de rendimiento reciente que justifica mantener en lugar de subir.
    public let hasRecentSignificantDrop: Bool

    public init(
        prescription: SetPrescription,
        performedSets: [SetRecord] = [],
        currentWeight: Double?,
        unit: LoadUnit,
        availableIncrement: Double? = nil,
        loadability: Loadability = .discreteIncrements,
        hasRecentSignificantDrop: Bool = false
    ) {
        self.prescription = prescription
        self.performedSets = performedSets
        self.currentWeight = currentWeight
        self.unit = unit
        self.availableIncrement = availableIncrement
        self.loadability = loadability
        self.hasRecentSignificantDrop = hasRecentSignificantDrop
    }
}

/// Resultado de la doble progresión para un ejercicio.
public enum ProgressionOutcome: Equatable, Sendable {
    /// Sube la carga un incremento disponible.
    case increase(newWeight: Double, from: Double)
    /// Conservador: mantiene la carga (reglas no satisfechas / sin incremento).
    case hold(weight: Double)
}

/// Evaluación auditable de doble progresión.
public struct ProgressionEvaluation: Equatable, Sendable {
    public let outcome: ProgressionOutcome
    /// ¿La progresión se bloqueó por dolor moderado/alto?
    public let blockedByPain: Bool
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    /// Registro de decisión persistible (plan §21, RC-010).
    public let decisionRecord: DecisionRecord

    public init(
        outcome: ProgressionOutcome,
        blockedByPain: Bool,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.outcome = outcome
        self.blockedByPain = blockedByPain
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

/// Motor de doble progresión (plan §4E, PR-1001).
///
/// Reglas deterministas — subir carga SÓLO si todas se cumplen:
/// 1. todas las working sets relevantes alcanzan el rango superior de reps;
/// 2. ningún set falló de forma excesiva (`failed`);
/// 3. no hay dolor moderado/alto (severity >= config);
/// 4. no hay caída significativa reciente;
/// 5. se respeta el incremento disponible del equipo (RN-013): para equipos con
///    paso discreto/fijo se usa `availableIncrement`; si se desconoce, se mantiene
///    (conservador, promptMaster §12.3). Para carga continua, incremento por defecto.
public struct ProgressionEngine: Sendable {
    public let config: DoubleProgressionConfig

    public init(config: DoubleProgressionConfig) throws {
        self.config = config
    }

    public func evaluate(_ input: ProgressionEvaluationInput) throws -> ProgressionEvaluation {
        let reference = try config.reference()
        var reasons: [String] = []

        // 3) Gate de dolor moderado/alto cancela la progresión (RF-024).
        let painGate = input.performedSets.contains { Self.isModerateOrHigherPain($0.painFeedback, threshold: config.painSeverityThreshold) }
        if painGate {
            reasons.append("dolor moderado/alto detectado: progresión cancelada")
            return holdEvaluation(input, reference: reference, blockedByPain: true, reasons: reasons)
        }

        // Primera vez con el ejercicio: sin carga base no hay nada que aumentar (§12.4).
        guard let current = input.currentWeight, current.isFinite, current >= 0 else {
            reasons.append("primera vez con este ejercicio: loadConfidence=low, sin carga base")
            return holdEvaluation(input, reference: reference, blockedByPain: false, reasons: reasons)
        }

        // 1) Rango superior de reps alcanzado en todas las working sets relevantes.
        let relevant = input.performedSets
        if config.requireUpperBoundReps {
            for set in relevant where set.reps < input.prescription.targetRepRange.upperBound {
                reasons.append("set de \(set.reps) reps < rango superior \(input.prescription.targetRepRange.upperBound)")
            }
        }

        // 2) Ningún fallo excesivo.
        if relevant.contains(where: { $0.perceivedDifficulty == .failed }) {
            reasons.append("se registró un fallo excesivo en un set")
        }

        // 4) Sin caída reciente.
        if input.hasRecentSignificantDrop {
            reasons.append("caída de rendimiento reciente: se mantiene carga")
        }

        if !reasons.isEmpty {
            return holdEvaluation(input, reference: reference, blockedByPain: false, reasons: reasons)
        }

        // 5) Incremento disponible del equipo (RN-013).
        guard let increment = stepIncrement(for: input) else {
            reasons.append("incremento de equipo desconocido: se mantiene carga (conservador)")
            return holdEvaluation(input, reference: reference, blockedByPain: false, reasons: reasons)
        }

        let newWeight = current + increment
        let facts = [
            DecisionFact(key: "exercise", value: "set-records"),
            DecisionFact(key: "currentLoad", value: String(format: "%.1f", current)),
            DecisionFact(key: "newLoad", value: String(format: "%.1f", newWeight)),
            DecisionFact(key: "increment", value: String(format: "%.1f", increment)),
            DecisionFact(key: "unit", value: input.unit.rawValue),
            DecisionFact(key: "rule", value: Self.ruleFact(reference)),
        ]
        let record = DecisionRecord(
            type: .loadChange,
            inputFacts: facts,
            action: DecisionActionSummary(
                title: "Subir carga \(String(format: "%.1f", increment)) (double progression)",
                detail: "\(String(format: "%.1f", current)) → \(String(format: "%.1f", newWeight)) \(input.unit.rawValue)"
            ),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )

        return ProgressionEvaluation(
            outcome: .increase(newWeight: newWeight, from: current),
            blockedByPain: false,
            reasons: [],
            ruleReference: reference,
            decisionRecord: record
        )
    }

    // MARK: - Helpers

    private static func isModerateOrHigherPain(_ pain: PainFeedback?, threshold: Int) -> Bool {
        guard let pain else { return false }
        switch pain {
        case .none:
            return false
        case .discomfort(_, let severity), .sharpPain(_, let severity):
            return severity >= threshold
        }
    }

    private func stepIncrement(for input: ProgressionEvaluationInput) -> Double? {
        switch input.loadability {
        case .fixedStack, .discreteIncrements:
            return input.availableIncrement
        case .continuous, .resisted, .bodyweight:
            return input.availableIncrement ?? config.continuousDefaultIncrement
        }
    }

    private func holdEvaluation(
        _ input: ProgressionEvaluationInput,
        reference: EvidenceRuleReference,
        blockedByPain: Bool,
        reasons: [String]
    ) -> ProgressionEvaluation {
        let weight = input.currentWeight ?? 0
        let record = DecisionRecord(
            type: .loadChange,
            inputFacts: [DecisionFact(key: "reason", value: reasons.joined(separator: "; "))],
            action: DecisionActionSummary(title: "Mantener carga (double progression conservador)", detail: reasons.joined(separator: "; ")),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )
        return ProgressionEvaluation(
            outcome: .hold(weight: weight),
            blockedByPain: blockedByPain,
            reasons: reasons,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    private static func ruleFact(_ reference: EvidenceRuleReference) -> String {
        "\(reference.ruleID.rawValue)#v\(reference.version)"
    }
}