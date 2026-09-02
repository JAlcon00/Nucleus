//
//  ActionPolicyValidator.swift
//  PRDomain
//
//  Created by PR.
//
//  ActionPolicyValidator (promptMaster §20.3, PR-1602): garante del invariante
//  arquitectónico "Policy Validator protects".
//
//  El LLM propone una `AgentAction` candidata; el validator decide si se permite,
//  si requiere confirmación, o si se rechaza. Refuerza:
//   1. una acción del agente NO puede evadir restricciones activas;
//   2. el validator NUNCA recibe acceso a repositorio/DB (sólo expone comandos
//      estrechos y auditables; la escritura es responsabilidad de los managers);
//   3. sin progresión de carga/volumen cuando el pain gate está activo (PR-1403);
//   4. todo se registra en un DecisionRecord auditable.
// Determinista y configurable vía policy `.safety` (`safety.actionPolicy`).
//

import Foundation

// MARK: - AgentAction (promptMaster §20.3)

/// Acción candidata que el agente propone. El agente no decide por sí mismo:
/// toda acción pasa por `ActionPolicyValidator`.
public enum AgentAction: Sendable, Hashable {
    case recomputeSession
    case reorderExercises
    case replaceExercise
    case adjustVolume
    case adjustLoadTarget
    case recommendRest
    case rescheduleWorkout
    case updateGymKnowledge
    case saveRestriction
    case presentExplanation

    public var displayName: String {
        switch self {
        case .recomputeSession: return "Recomputar sesión"
        case .reorderExercises: return "Reordenar ejercicios"
        case .replaceExercise: return "Sustituir ejercicio"
        case .adjustVolume: return "Ajustar volumen"
        case .adjustLoadTarget: return "Ajustar objetivo de carga"
        case .recommendRest: return "Recomendar descanso"
        case .rescheduleWorkout: return "Reagendar workout"
        case .updateGymKnowledge: return "Actualizar conocimiento del gym"
        case .saveRestriction: return "Guardar restricción"
        case .presentExplanation: return "Presentar explicación"
        }
    }
}

// MARK: - Contexto

/// Contexto que el caller (engine real) aporta para validar la acción candidata.
/// Sólo hechos de dominio estructurados — nunca un handle de repositorio/DB.
public struct ActionPolicyContext: Sendable, Hashable {
    /// El pain gate de PR-1403 está activo (moderate/high ⇒ suspende progresión).
    public var painGateActive: Bool
    /// ¿La acción propuesta AUMENTA la progresión (carga/volumen)? Una reducción o
    /// cambio neutral nunca queda bloqueada por el pain gate.
    public var proposedProgressionIncrease: Bool
    /// `replaceExercise`: el sustituto propuesto está prohibido por la política de
    /// restricciones (PR-1402) — no se puede evadir la restricción.
    public var proposedSubstituteIsForbidden: Bool
    /// `saveRestriction`: el cambio debilita/elimina una restricción de origen
    /// profesional. Requiere confirmación explícita del usuario.
    public var weakeningProfessionalRestriction: Bool
    /// ¿El usuario ya confirmó la acción (para los casos que lo requieren)?
    public var userConfirmed: Bool

    public init(
        painGateActive: Bool = false,
        proposedProgressionIncrease: Bool = false,
        proposedSubstituteIsForbidden: Bool = false,
        weakeningProfessionalRestriction: Bool = false,
        userConfirmed: Bool = false
    ) {
        self.painGateActive = painGateActive
        self.proposedProgressionIncrease = proposedProgressionIncrease
        self.proposedSubstituteIsForbidden = proposedSubstituteIsForbidden
        self.weakeningProfessionalRestriction = weakeningProfessionalRestriction
        self.userConfirmed = userConfirmed
    }
}

// MARK: - Outcome / Verdict

/// Resultado de la validación de política.
public enum ActionPolicyOutcome: Equatable, Sendable {
    /// Permitida; el campo indica el comando estrecho a invocar (nunca un acceso
    /// genérico a DB).
    case allowed(command: String)
    /// Rechazada (por ejemplo, no evadir restricciones o no progresar con pain gate).
    case rejected(reason: String)
    /// Permitida sólo tras confirmación explícita del usuario.
    case requiresConfirmation(command: String)
}

/// Veredicto auditable de la validación.
public struct ActionPolicyVerdict: Equatable, Sendable {
    public let action: AgentAction
    public let outcome: ActionPolicyOutcome
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    public let decisionRecord: DecisionRecord

    public var isAllowed: Bool {
        if case .allowed = outcome { return true }
        return false
    }

    public var isRejected: Bool {
        if case .rejected = outcome { return true }
        return false
    }

    public init(
        action: AgentAction,
        outcome: ActionPolicyOutcome,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.action = action
        self.outcome = outcome
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

// MARK: - Policy rule (versionada, categoría .safety)

public enum ActionPolicyKeys {
    /// 1 = bloquear aumento de carga/volumen cuando el pain gate está activo.
    public static let denyProgressionOnPainGate = "denyProgressionOnPainGate"
    /// 1 = rechazar sustitución que evadiría una restricción activa.
    public static let denyForbiddenSubstitute = "denyForbiddenSubstitute"
    /// 1 = exigir confirmación al debilitar una restricción profesional.
    public static let requireConfirmationForProfessionalRestriction = "requireConfirmationForProfessionalRestriction"

    public static let allRequired: Set<String> = [
        denyProgressionOnPainGate, denyForbiddenSubstitute, requireConfirmationForProfessionalRestriction,
    ]

    public static func defaults() -> [String: Double] {
        [
            denyProgressionOnPainGate: 1,
            denyForbiddenSubstitute: 1,
            requireConfirmationForProfessionalRestriction: 1,
        ]
    }
}

public enum ActionPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "safety.actionPolicy")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Action policy: agent cannot bypass restrictions, cannot progress load under pain gate, no direct repository writes, auditable",
            source: "Plan §20 / promptMaster §20.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Action policy validator",
            category: .safety,
            confidence: .established,
            version: version,
            parameters: ActionPolicyKeys.defaults(),
            references: [reference]
        )
    }
}

public enum ActionPolicyError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case wrongCategory
}

public struct ActionPolicyConfig: Sendable {
    public let rule: EvidenceRule

    public var denyProgressionOnPainGate: Bool { (rule.parameters[ActionPolicyKeys.denyProgressionOnPainGate] ?? 1) > 0 }
    public var denyForbiddenSubstitute: Bool { (rule.parameters[ActionPolicyKeys.denyForbiddenSubstitute] ?? 1) > 0 }
    public var requireConfirmationForProfessionalRestriction: Bool {
        (rule.parameters[ActionPolicyKeys.requireConfirmationForProfessionalRestriction] ?? 1) > 0
    }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .safety else {
            throw ActionPolicyError.wrongCategory
        }
        let missing = ActionPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw ActionPolicyError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

// MARK: - Validator

/// Garante determinista de política de acciones del agente (PR-1602).
///
/// Nota estructural: este tipo NO expone ningún repositorio ni acceso a DB. Su
/// entrada es un `AgentAction` + `ActionPolicyContext` estructurados; su salida es
/// un `ActionPolicyVerdict` auditable con un comando estrecho. La persistencia la
/// invocan los managers de dominio (RestrictionManager, etc.), nunca el agente.
public struct ActionPolicyValidator: Sendable {
    public let config: ActionPolicyConfig

    public init(config: ActionPolicyConfig) throws {
        self.config = config
    }

    public func validate(
        _ action: AgentAction,
        context: ActionPolicyContext
    ) throws -> ActionPolicyVerdict {
        let reference = try config.reference()
        var reasons: [String] = []

        let outcome: ActionPolicyOutcome

        switch action {
        case .recomputeSession:
            outcome = .allowed(command: "recomputeSession")
            reasons.append("recalcular la sesión con los engines de dominio")

        case .reorderExercises:
            outcome = .allowed(command: "reorderExercises")
            reasons.append("reordenar respetando reglas de orden y restricciones")

        case .replaceExercise:
            if config.denyForbiddenSubstitute && context.proposedSubstituteIsForbidden {
                reasons.append("el sustituto propuesto está prohibido por una restricción activa (no se evade §16.2)")
                outcome = .rejected(reason: reasons.joined(separator: "; "))
            } else {
                outcome = .allowed(command: "requestSubstitution")
                reasons.append("el sustituto propuesto no evita restricciones")
            }

        case .adjustVolume, .adjustLoadTarget:
            if config.denyProgressionOnPainGate && context.painGateActive && context.proposedProgressionIncrease {
                reasons.append("pain gate activo (moderate/high, PR-1403): no se puede aumentar la progresión de carga/volumen")
                outcome = .rejected(reason: reasons.joined(separator: "; "))
            } else {
                outcome = .allowed(command: "adjustLoadOrVolume")
                reasons.append(context.painGateActive
                              ? "pain gate activo pero el cambio no aumenta la progresión (reducción/neutro permitido)"
                              : "sin pain gate: progresión permitida")
            }

        case .recommendRest:
            outcome = .allowed(command: "recommendRest")
            reasons.append("recomendar descanso (recovery engine)")

        case .rescheduleWorkout:
            outcome = .allowed(command: "rescheduleWorkout")
            reasons.append("reagendar conservando reglas de descanso")

        case .updateGymKnowledge:
            outcome = .allowed(command: "updateGymKnowledge")
            reasons.append("actualizar conocimiento del gym vía manager, sin acceso directo a DB")

        case .saveRestriction:
            if config.requireConfirmationForProfessionalRestriction
                && context.weakeningProfessionalRestriction {
                if context.userConfirmed {
                    outcome = .allowed(command: "saveRestriction")
                    reasons.append("usuario confirmó el debilitamiento de la restricción profesional")
                } else {
                    outcome = .requiresConfirmation(command: "saveRestriction")
                    reasons.append("debilita una restricción de origen profesional: requiere confirmación explícita (restricciones no se eliminan unilateralmente)")
                }
            } else {
                outcome = .allowed(command: "saveRestriction")
                reasons.append("guardar restricción vía RestrictionManager (usuario confirma antes de persistir)")
            }

        case .presentExplanation:
            outcome = .allowed(command: "presentExplanation")
            reasons.append("explicar usando sólo los facts suministrados (PR-1606)")
        }

        reasons.sort()
        let record = makeRecord(action: action, outcome: outcome, reasons: reasons, reference: reference)
        return ActionPolicyVerdict(
            action: action,
            outcome: outcome,
            reasons: reasons,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    // MARK: - Helpers

    private func makeRecord(
        action: AgentAction,
        outcome: ActionPolicyOutcome,
        reasons: [String],
        reference: EvidenceRuleReference
    ) -> DecisionRecord {
        DecisionRecord(
            type: .policyValidation,
            inputFacts: [
                DecisionFact(key: "action", value: action.displayName),
                DecisionFact(key: "outcome", value: outcomeDescription(outcome)),
                DecisionFact(key: "reasons", value: reasons.joined(separator: "; ")),
            ],
            action: DecisionActionSummary(title: "Policy \(outcomeDescription(outcome)): \(action.displayName)", detail: reasons.joined(separator: "; ")),
            ruleReferences: [reference],
            userOverrideAllowed: false
        )
    }

    private func outcomeDescription(_ outcome: ActionPolicyOutcome) -> String {
        switch outcome {
        case .allowed: return "allowed"
        case .rejected: return "rejected"
        case .requiresConfirmation: return "requiresConfirmation"
        }
    }
}
