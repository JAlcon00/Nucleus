//
//  RecoveryDecisionEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de recovery (plan §15 Fase 12, promptMaster §13, PR-1302).
//  Considera rendimiento reciente, feedback subjetivo pre-workout (PR-1301) y
//  contexto opcional de HealthKit, y produce un OUTCOME CATEGÓRICO — NUNCA un score
//  de recuperación 0-100 (regla de honestidad §13.3 / plan Riesgo G). Cada decisión
//  genera un `DecisionRecord` con facts explicables y la referencia versionada de la
//  regla usada. No diagnostica lesiones: el malestar subjetivo sólo moldea una salida
//  conservadora (`avoidRegion`), el manejo real de restricciones vive en PR-1303.
//  Determinista y sin Views.
//

import Foundation

/// Estado de recuperación interpretable (§13.3). Es ESTADO, no score.
public enum RecoveryState: String, Codable, Sendable, CaseIterable, Hashable {
    case normal
    case moderateFatigue
    case highFatigue
    case restRecommended
}

/// Ajuste concreto para entrenar con fatiga (nunca un diagnóstico).
public enum RecoveryAdjustment: Equatable, Sendable {
    /// Reducir intensidad / alejarse del fallo.
    case reduceIntensity
    /// Evitar la región de malestar (contexto subjetivo; no es diagnóstico).
    case avoidRegion(MuscleGroup.ID)
    /// Acortar la sesión.
    case shortenSession
    /// Convertir la sesión en un día de recuperación activo (sesión ligera).
    case recoverySession
}

/// Decisión de recovery (outcome) devuelta por el motor (§13.2).
public enum RecoveryDecision: Equatable, Sendable {
    case trainAsPlanned
    case trainWithAdjustments([RecoveryAdjustment])
    case recoverySession
    case restRecommended

    public var isRest: Bool {
        if case .restRecommended = self { return true }
        return false
    }
}

/// Contexto de HealthKit opcional. Sólo aporta context cambiable; jamás diagnóstico.
/// El sueño sólo se considera si el usuario autorizó y la app realmente lo usa (§13.1).
public struct HealthRecoveryContext: Sendable {
    /// Sueño deficiente indicado (sólo si autorizado y usado).
    public let poorSleepIndicated: Bool?

    public init(poorSleepIndicated: Bool? = nil) {
        self.poorSleepIndicated = poorSleepIndicated
    }
}

/// Entrada del motor de recovery (PR-1302). Todas las señales son CUALITATIVAS/
/// SUBJETIVAS; no hay score.
public struct RecoveryContext: Sendable {
    /// Check-in subjetivo pre-workout (PR-1301). nil = no registrado hoy.
    public let checkIn: PreWorkoutCheckIn?
    /// Caída de rendimiento reciente (set fallado / reps muy por debajo del objetivo).
    public let hasRecentPerformanceDecline: Bool
    /// Sets recientes cercanos al fallo (acumulación de fatiga).
    public let hasRecentNearFailureSets: Bool
    /// Alta carga reciente acumulada (frecuencia de sesiones / volumen alto).
    public let highRecentLoad: Bool
    /// Contexto opcional de HealthKit (autorizado y usado).
    public let healthContext: HealthRecoveryContext?

    public init(
        checkIn: PreWorkoutCheckIn? = nil,
        hasRecentPerformanceDecline: Bool = false,
        hasRecentNearFailureSets: Bool = false,
        highRecentLoad: Bool = false,
        healthContext: HealthRecoveryContext? = nil
    ) {
        self.checkIn = checkIn
        self.hasRecentPerformanceDecline = hasRecentPerformanceDecline
        self.hasRecentNearFailureSets = hasRecentNearFailureSets
        self.highRecentLoad = highRecentLoad
        self.healthContext = healthContext
    }
}

/// Claves canónicas de la policy de recovery.
public enum RecoveryPolicyKeys {
    /// ¿`veryTired` obliga a sesión de recovery? (1 = sí)
    public static let recoveryOnVeryTired = "recoveryOnVeryTired"
    /// ¿Caída de rendimiento + sets al fallo ⇒ recovery? (1 = sí)
    public static let recoveryOnDeclineAndNearFailure = "recoveryOnDeclineAndNearFailure"
    /// ¿`veryTired` + caída de rendimiento ⇒ descanso? (1 = sí)
    public static let restOnVeryTiredAndDecline = "restOnVeryTiredAndDecline"
    /// ¿`veryTired` + carga alta reciente ⇒ descanso? (1 = sí)
    public static let restOnVeryTiredAndHighLoad = "restOnVeryTiredAndHighLoad"
    /// ¿Malestar subjetivo siempre degrada a ajuste conservador? (1 = sí)
    public static let adjustOnSomethingHurts = "adjustOnSomethingHurts"

    public static let allRequired: Set<String> = [
        recoveryOnVeryTired,
        recoveryOnDeclineAndNearFailure,
        restOnVeryTiredAndDecline,
        restOnVeryTiredAndHighLoad,
        adjustOnSomethingHurts,
    ]

    public static func defaults() -> [String: Double] {
        [
            recoveryOnVeryTired: 1,
            recoveryOnDeclineAndNearFailure: 1,
            restOnVeryTiredAndDecline: 1,
            restOnVeryTiredAndHighLoad: 1,
            adjustOnSomethingHurts: 1,
        ]
    }
}

/// Regla de evidencia por defecto de recovery (categoría `.recovery`).
public enum RecoveryPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "recovery.dao")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Recovery: categorical outcome with explainable facts (no fake score)",
            source: "Plan §15 / promptMaster §13.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Recovery decision policy (categorical)",
            category: .recovery,
            confidence: .expertConsensus,
            version: version,
            parameters: RecoveryPolicyKeys.defaults(),
            references: [reference]
        )
    }
}

/// Problemas de entrada del motor de recovery.
public enum RecoveryEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    /// Check-in incoherente (malestar sin región, etc.).
    case invalidCheckIn
}

/// Configuración versionada de la policy de recovery.
public struct RecoveryPolicy: Sendable {
    public let rule: EvidenceRule

    public var recoveryOnVeryTired: Bool { (rule.parameters[RecoveryPolicyKeys.recoveryOnVeryTired] ?? 1) > 0 }
    public var recoveryOnDeclineAndNearFailure: Bool { (rule.parameters[RecoveryPolicyKeys.recoveryOnDeclineAndNearFailure] ?? 1) > 0 }
    public var restOnVeryTiredAndDecline: Bool { (rule.parameters[RecoveryPolicyKeys.restOnVeryTiredAndDecline] ?? 1) > 0 }
    public var restOnVeryTiredAndHighLoad: Bool { (rule.parameters[RecoveryPolicyKeys.restOnVeryTiredAndHighLoad] ?? 1) > 0 }
    public var adjustOnSomethingHurts: Bool { (rule.parameters[RecoveryPolicyKeys.adjustOnSomethingHurts] ?? 1) > 0 }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .recovery else {
            throw RecoveryEngineError.missingConfig(keys: ["category=.recovery"])
        }
        let missing = RecoveryPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw RecoveryEngineError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Resultado auditable del motor de recovery.
public struct RecoveryEvaluation: Equatable, Sendable {
    public let decision: RecoveryDecision
    /// Estado de recuperación interpretable (§13.3), para mensajes honestos.
    public let state: RecoveryState
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    /// Registro persistible (plan §21).
    public let decisionRecord: DecisionRecord

    public init(
        decision: RecoveryDecision,
        state: RecoveryState,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.decision = decision
        self.state = state
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

/// Motor determinista de recovery (PR-1302). Sin score: outcome categórico + facts.
///
/// Precedencia (alta → baja):
/// 1. `restRecommended`: `veryTired` + caída de rendimiento, o `veryTired` + carga alta reciente.
/// 2. `recoverySession`: `veryTired`, o caída + sets al fallo.
/// 3. malestar subjetivo (`somethingHurts`) ⇒ ajuste conservador `avoidRegion` (nunca diagnóstico).
/// 4. `trainWithAdjustments`: `tired`, sets al fallo, o caída de rendimiento.
/// 5. `trainAsPlanned`: sin señales.
public struct RecoveryDecisionEngine: Sendable {
    public let policy: RecoveryPolicy

    public init(policy: RecoveryPolicy) throws {
        self.policy = policy
    }

    public func evaluate(_ input: RecoveryContext) throws -> RecoveryEvaluation {
        let reference = try policy.reference()
        var reasons: [String] = []

        if let checkIn = input.checkIn, !checkIn.isCoherent {
            throw RecoveryEngineError.invalidCheckIn
        }

        let feeling = input.checkIn?.feeling
        let isVeryTired = feeling == .veryTired
        let isTired = feeling == .tired || isVeryTired
        let somethingHurts = feeling == .somethingHurts
        let poorSleep = input.healthContext?.poorSleepIndicated == true

        let decline = input.hasRecentPerformanceDecline
        let nearFailure = input.hasRecentNearFailureSets
        let highLoad = input.highRecentLoad

        // 1) Descanso recomendado.
        if policy.restOnVeryTiredAndDecline && isVeryTired && decline {
            reasons.append("fatiga subjetiva alta (veryTired) + caída de rendimiento reciente")
            return completed(.restRecommended, state: .restRecommended, reasons: reasons, reference: reference)
        }
        if policy.restOnVeryTiredAndHighLoad && isVeryTired && highLoad {
            reasons.append("fatiga subjetiva alta (veryTired) + carga alta reciente")
            return completed(.restRecommended, state: .restRecommended, reasons: reasons, reference: reference)
        }
        if healthDowngradeToRest(isVeryTired: isVeryTired, decl: decline, highLoad: highLoad, poorSleep: poorSleep) {
            reasons.append("sueño deficiente autorizado como contexto + señales de fatiga")
            return completed(.restRecommended, state: .restRecommended, reasons: reasons, reference: reference)
        }

        // 2) Sesión de recovery.
        if policy.recoveryOnVeryTired && isVeryTired {
            reasons.append("fatiga subjetiva alta (veryTired)")
            return completed(.recoverySession, state: .highFatigue, reasons: reasons, reference: reference)
        }
        if policy.recoveryOnDeclineAndNearFailure && decline && nearFailure {
            reasons.append("caída de rendimiento + sets cercanos al fallo")
            return completed(.recoverySession, state: .highFatigue, reasons: reasons, reference: reference)
        }

        // 3) Malestar subjetivo ⇒ ajuste conservador (evitar región); nunca diagnóstico.
        let region = input.checkIn?.region
        if policy.adjustOnSomethingHurts && somethingHurts {
            reasons.append("malestar subjetivo indicado (evitar región; no es diagnóstico)")
            var adjustments: [RecoveryAdjustment] = [.reduceIntensity]
            if let region { adjustments.append(.avoidRegion(region)) }
            return completed(.trainWithAdjustments(adjustments), state: .highFatigue, reasons: reasons, reference: reference)
        }

        // 4) Ajuste por fatiga.
        if isTired || nearFailure || (decline && !highLoad) {
            reasons.append("fatiga moderada (subjetiva o por resultados recientes)")
            let adjustments: [RecoveryAdjustment] = [.reduceIntensity]
            return completed(.trainWithAdjustments(adjustments), state: .moderateFatigue, reasons: reasons, reference: reference)
        }
        if highLoad {
            reasons.append("carga alta reciente acumulada")
            return completed(.trainWithAdjustments([.shortenSession]), state: .moderateFatigue, reasons: reasons, reference: reference)
        }
        if decline {
            reasons.append("caída de rendimiento reciente")
            return completed(.trainWithAdjustments([.reduceIntensity]), state: .moderateFatigue, reasons: reasons, reference: reference)
        }

        // 5) Sin señales ⇒ entrenar según plan.
        reasons.append("sin señales de fatiga relevantes")
        return completed(.trainAsPlanned, state: .normal, reasons: reasons, reference: reference)
    }

    // MARK: - Helpers

    private func healthDowngradeToRest(isVeryTired: Bool, decl: Bool, highLoad: Bool, poorSleep: Bool) -> Bool {
        guard poorSleep else { return false }
        return (isVeryTired || decl) || highLoad
    }

    private func completed(
        _ decision: RecoveryDecision,
        state: RecoveryState,
        reasons: [String],
        reference: EvidenceRuleReference
    ) -> RecoveryEvaluation {
        let record = DecisionRecord(
            type: recordType(for: decision),
            inputFacts: [DecisionFact(key: "outcome", value: String(describing: decision)),
                         DecisionFact(key: "reasons", value: reasons.joined(separator: "; "))],
            action: DecisionActionSummary(title: Self.title(for: decision), detail: reasons.joined(separator: "; ")),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )
        return RecoveryEvaluation(
            decision: decision,
            state: state,
            reasons: reasons,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    private func recordType(for decision: RecoveryDecision) -> DecisionType {
        switch decision {
        case .trainAsPlanned: return .loadChange
        case .trainWithAdjustments: return .intensityChange
        case .recoverySession: return .deload
        case .restRecommended: return .restChange
        }
    }

    private static func title(for decision: RecoveryDecision) -> String {
        switch decision {
        case .trainAsPlanned: return "Entrenar según plan (recuperación normal)"
        case .trainWithAdjustments: return "Entrenar con ajustes por fatiga"
        case .recoverySession: return "Sesión de recovery"
        case .restRecommended: return "Descanso recomendado"
        }
    }
}