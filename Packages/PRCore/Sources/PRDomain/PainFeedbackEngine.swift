//
//  PainFeedbackEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de feedback de molestia durante el workout (plan §15 Fase 12,
//  promptMaster §16.3, PR-1403). Modela el nivel de dolor como `PainLevel`
//  (none/mild/moderate/high). `moderate/high` suspenden la progresión automática de
//  carga y disparan un flujo conservador con recomendación de UI — SIN diagnosticar.
//  Determinista y auditable vía `DecisionRecord`. La regla es `.safety` y la UI sólo
//  recomienda detener/modificar, nunca diagnostica.
//

import Foundation

/// Nivel de dolor/ reacción reportado por el usuario durante un set (§16.3).
/// NO es un diagnóstico: es feedback subjetivo que el motor traduce a un flujo seguro.
public enum PainLevel: Int, Codable, Sendable, CaseIterable, Hashable {
    case none = 0
    case mild = 1
    case moderate = 2
    case high = 3

    /// ¿Nivel que dispara el flujo conservador y suspende la progresión? (§16.3)
    public var isConservativeDisruptive: Bool {
        self == .moderate || self == .high
    }
}

/// Recomendación de UI para el usuario (nunca un diagnóstico).
public enum PainRecommendation: Equatable, Sendable {
    /// Ninguna reacción especial: continuar según plan.
    case continueNormal
    /// Reducir intensidad y monitorizar (moderate).
    case reduceIntensityAndMonitor
    /// Detener/ modificar el movimiento (high).
    case stopAndRest
}

/// Entrada del motor de feedback de dolor (PR-1403).
public struct PainFeedbackInput: Sendable {
    public let level: PainLevel
    /// ¿Existe una restricción activa relacionada (contexto de PR-1402)? Sólo informa.
    public let hasActiveRelatedRestriction: Bool
    /// Nombre del ejercicio para los facts auditables (opcional).
    public let exerciseName: String?

    public init(
        level: PainLevel,
        hasActiveRelatedRestriction: Bool = false,
        exerciseName: String? = nil
    ) {
        self.level = level
        self.hasActiveRelatedRestriction = hasActiveRelatedRestriction
        self.exerciseName = exerciseName
    }
}

/// Resultado auditable de la evaluación de dolor.
public struct PainEvaluation: Equatable, Sendable {
    public let recommendation: PainRecommendation
    /// `moderate/high` ⇒ se suspende la progresión de carga de ese movimiento.
    public let suspendsLoadProgression: Bool
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    public let decisionRecord: DecisionRecord

    public init(
        recommendation: PainRecommendation,
        suspendsLoadProgression: Bool,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.recommendation = recommendation
        self.suspendsLoadProgression = suspendsLoadProgression
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

/// Claves canónicas de la policy de feedback de dolor.
public enum PainFeedbackPolicyKeys {
    /// Severidad mínima que suspende la progresión (2 = moderate).
    public static let suspendProgressionFromSeverity = "suspendProgressionFromSeverity"

    public static let allRequired: Set<String> = [suspendProgressionFromSeverity]

    public static func defaults() -> [String: Double] {
        [suspendProgressionFromSeverity: 2]
    }
}

/// Regla de evidencia por defecto (categoría `.safety`).
public enum PainFeedbackPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "safety.painFeedback")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Pain feedback: moderate/high suspend load progression and trigger conservative flow, without diagnosing",
            source: "Plan §15 / promptMaster §16.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Pain feedback policy",
            category: .safety,
            confidence: .established,
            version: version,
            parameters: PainFeedbackPolicyKeys.defaults(),
            references: [reference]
        )
    }
}

/// Problemas de entrada del motor.
public enum PainFeedbackEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case wrongCategory
}

/// Configuración versionada de la policy de dolor.
public struct PainFeedbackConfig: Sendable {
    public let rule: EvidenceRule

    /// Severidad (índice de `PainLevel`) a partir de la cual se suspende progresión.
    public var suspendProgressionFromSeverity: Int {
        Int(rule.parameters[PainFeedbackPolicyKeys.suspendProgressionFromSeverity] ?? 2)
    }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .safety else {
            throw PainFeedbackEngineError.wrongCategory
        }
        let missing = PainFeedbackPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw PainFeedbackEngineError.missingConfig(keys: Array(missing).sorted())
        }
        let threshold = Int(rule.parameters[PainFeedbackPolicyKeys.suspendProgressionFromSeverity] ?? 2)
        guard (0...3).contains(threshold) else {
            throw PainFeedbackEngineError.missingConfig(keys: ["suspendProgressionFromSeverity out of range"])
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Motor determinista de feedback de dolor (PR-1403). Sin diagnóstico.
public struct PainFeedbackEngine: Sendable {
    public let config: PainFeedbackConfig

    public init(config: PainFeedbackConfig) throws {
        self.config = config
    }

    /// ¿La carga debe dejar de progresar para este nivel (§16.3, gate de progresión)?
    public func suspendsLoadProgression(_ level: PainLevel) -> Bool {
        level.rawValue >= config.suspendProgressionFromSeverity
    }

    public func evaluate(_ input: PainFeedbackInput) throws -> PainEvaluation {
        let reference = try config.reference()
        let name = input.exerciseName ?? "ejercicio"
        let suspends = suspendsLoadProgression(input.level)

        var reasons: [String] = []
        let recommendation: PainRecommendation

        switch input.level {
        case .none, .mild:
            recommendation = .continueNormal
            reasons.append("\(name): nivel \(input.level.rawValue) — sin reacción especial")
        case .moderate:
            recommendation = .reduceIntensityAndMonitor
            reasons.append("\(name): malestar moderado — reducir intensidad y monitorizar (sin diagnóstico)")
            if input.hasActiveRelatedRestriction {
                reasons.append("se combina con restricción activa relacionada (PR-1402): reforzar precaución")
            }
        case .high:
            recommendation = .stopAndRest
            reasons.append("\(name): dolor alto — detener/modificar el movimiento (sin diagnóstico)")
            if input.hasActiveRelatedRestriction {
                reasons.append("se combina con restricción activa relacionada (PR-1402): reforzar precaución")
            }
        }

        if suspends {
            reasons.append("se suspende la progresión de carga (moderate/high)")
        }

        let record = DecisionRecord(
            type: .intensityChange,
            inputFacts: [
                DecisionFact(key: "level", value: input.level.rawValue.description),
                DecisionFact(key: "recommendation", value: recommendationDescription(recommendation)),
                DecisionFact(key: "suspendsLoadProgression", value: String(suspends)),
                DecisionFact(key: "exercise", value: name),
            ],
            action: DecisionActionSummary(
                title: recommendationTitle(recommendation),
                detail: reasons.joined(separator: "; ")
            ),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )

        return PainEvaluation(
            recommendation: recommendation,
            suspendsLoadProgression: suspends,
            reasons: reasons,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    // MARK: - Helpers

    private func recommendationDescription(_ r: PainRecommendation) -> String {
        switch r {
        case .continueNormal: return "continueNormal"
        case .reduceIntensityAndMonitor: return "reduceIntensityAndMonitor"
        case .stopAndRest: return "stopAndRest"
        }
    }

    private func recommendationTitle(_ r: PainRecommendation) -> String {
        switch r {
        case .continueNormal: return "Continuar normal"
        case .reduceIntensityAndMonitor: return "Reducir intensidad y monitorizar"
        case .stopAndRest: return "Detener/modificar"
        }
    }
}