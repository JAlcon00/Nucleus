//
//  AgentActionWriter.swift
//  PRDomain
//
//  Created by PR.
//
//  Phase N4 — Deterministic writes (NEMOTRON_3_5_LIGHTNING_API.md Phase N4; plan §20,
//  promptMaster §20.3). Cierra el pipeline: el `AgentIntent` interpretado por el LLM
//  (N2) se mapea de forma DETERMINISTA a una `AgentAction` candidata, se genera un
//  PREVIEW legible del cambio que se escribiría, se valida con `ActionPolicyValidator`
//  (PR-1602) y, sólo si queda permitido, se expone un COMANDO ESTRECHO auditable.
//
//  Invariantes arquitectónicas (AGENTS / promptMaster):
//  - "LLM interprets → engine decides → policy validates": el LLM NUNCA elige la
//    acción ni escribe. El mapeo intent→acción es dominio puro y determinista.
//  - NUNCA se exponen handles de repositorio/DB: la salida son comandos estrechos
//    (`AgentWriteCommand`). La capa de app despacha el comando a los managers de
//    dominio (RestrictionManager, engines, etc.).
//  - Se genera un preview antes de escribir (las *preview tools* de la fase N4): el
//    usuario/caller ve qué cambiaría antes de cualquier persistencia.
//  - Todo queda auditable (`AgentAuditRecord`), sin retener payload crudo sensible.
//

import Foundation

// MARK: - Mapeo determinista intent → acción candidata

/// Mapea un `AgentIntent` (interpretado por el LLM) a la `AgentAction` candidata
/// que el engine/policy evaluará. Es dominio puro y determinista: el LLM no participa.
public enum AgentIntentActionMapper {

    public static func action(for intent: AgentIntent) -> AgentAction {
        switch intent {
        case .setTimeConstraint:
            return .recomputeSession
        case .equipmentUnavailable:
            return .updateGymKnowledge
        case .requestExerciseSwap:
            return .replaceExercise
        case .reportFatigue:
            // Fatiga subjetiva → evaluación conservadora de la carga (recovery engine).
            return .adjustLoadTarget
        case .reportPain:
            // Dolor → nunca progresar; la validación con pain gate bloquea aumentos.
            return .adjustLoadTarget
        case .changeGoal:
            return .recomputeSession
        case .changePhase:
            return .recomputeSession
        case .changeGym:
            return .updateGymKnowledge
        case .askWhy:
            return .presentExplanation
        case .updateRestriction:
            return .saveRestriction
        case .requestPlanAdjustment(let request):
            switch request.scope {
            case .volume: return .adjustVolume
            case .loadTarget: return .adjustLoadTarget
            case .fullRebuild: return .recomputeSession
            }
        }
    }
}

// MARK: - Preview (antes de escribir)

/// Preview determinista y legible del cambio que una acción produciría. Se muestra
/// ANTES de ejecutar el comando de escritura (nunca se escribe sin preview).
public struct AgentActionPreview: Sendable, Hashable {
    /// Resumen legible (español) de qué cambiaría.
    public let summary: String
    /// ¿Implica una escritura de dominio? (`presentExplanation` no escribe).
    public let isWrite: Bool
    /// Destino por el que la capa de app ejecutará el comando (manager/engine).
    public let destination: String

    public init(summary: String, isWrite: Bool, destination: String) {
        self.summary = summary
        self.isWrite = isWrite
        self.destination = destination
    }
}

/// Contruye el preview a partir del intent + el contexto de política disponible.
/// Determinista: sólo usa hechos estructurados, nunca inventa números.
public enum AgentActionPreviewFactory {

    public static func preview(
        for intent: AgentIntent,
        context: ActionPolicyContext
    ) -> AgentActionPreview {
        switch intent {
        case .setTimeConstraint(let constraint):
            return .init(
                summary: "Ajustar la sesión de hoy al tiempo disponible (\(constraintSummary(constraint))).",
                isWrite: true,
                destination: "TrainingEngine (HardTime/FlexibleTimeOptimizer)"
            )        case .equipmentUnavailable:
            return .init(
                summary: "Registrar la indisponibilidad del equipamiento y reordenar la sesión si procede.",
                isWrite: true,
                destination: "GymProfileManager / ReorderController"
            )
        case .requestExerciseSwap:
            return .init(
                summary: "Sustituir el ejercicio por una alternativa segura y compatible.",
                isWrite: true,
                destination: "SubstitutionScoring / RestrictionPolicyEngine"
            )
        case .reportFatigue:
            return .init(
                summary: "Evaluar la fatiga reportada y ajustar conservadoramente la carga de la sesión.",
                isWrite: true,
                destination: "RecoveryDecisionEngine"
            )
        case .reportPain:
            return .init(
                summary: "Registrar el reporte de dolor y reducir la intensidad; no se progresará hasta que el pain gate se levante.",
                isWrite: true,
                destination: "PainFeedbackEngine / ProgressionEngine"
            )
        case .changeGoal:
            return .init(
                summary: "Recomputar la sesión según el nuevo objetivo (hypertrophy/strength/etc.).",
                isWrite: true,
                destination: "TrainingEngine"
            )
        case .changePhase:
            return .init(
                summary: "Recomputar la sesión según la nueva fase energética/nutricional.",
                isWrite: true,
                destination: "TrainingEngine"
            )
        case .changeGym:
            return .init(
                summary: "Cambiar el perfil de gimnasio activo y ajustar el plan a su equipamiento.",
                isWrite: true,
                destination: "GymProfileManager / TrainingEngine"
            )
        case .askWhy:
            return .init(
                summary: "Explicar el motivo de la decisión (no se escribe nada).",
                isWrite: false,
                destination: "DecisionRecordRepository (sólo lectura) / Explainer"
            )
        case .updateRestriction(let draft):
            let professional = draft.source == .professionalGuidance
                ? " (origen profesional: requiere confirmación)"
                : ""
            return .init(
                summary: "Guardar la restricción de entrenamiento propuesta\(professional).",
                isWrite: true,
                destination: "RestrictionManager"
            )
        case .requestPlanAdjustment(let request):
            return .init(
                summary: "Ajustar el plan según el criterio solicitado (\(request.scope.rawValue)).",
                isWrite: true,
                destination: "TrainingEngine"
            )
        }
    }

    private static func constraintSummary(_ constraint: TimeConstraint) -> String {
        switch constraint {
        case .hard(let minutes):
            return "\(minutes) min"
        case .flexible(let target, let tolerance):
            return "flexible \(target) min ± \(tolerance)"
        case .unconstrained:
            return "sin límite"
        }
    }
}

// MARK: - Comando estrecho de escritura

/// Comando ESTRECHO que la capa de app despacha a un manager/engine de dominio.
/// Es la ÚNICA forma de materializar una decisión del agente (nunca acceso directo
/// a DB). Lleva el payload estructurado mínimo; el auditoría conserva sólo etiquetas.
public enum AgentWriteCommand: Sendable, Hashable {
    case recomputeSession(reason: String)
    case requestSubstitution(forExercise: ExerciseID)
    case adjustLoadOrVolume(scope: PlanAdjustmentRequest.Scope, reduction: Bool)
    case recommendRest
    case rescheduleWorkout
    case updateGymKnowledge(reason: String)
    case saveRestriction(draft: TrainingRestrictionDraft)
    case presentExplanation(decisionID: DecisionID, decisionRecord: DecisionRecord)

    /// Nombre estable para auditoría (mínima, sin PII).
    public var name: String {
        switch self {
        case .recomputeSession: return "recomputeSession"
        case .requestSubstitution: return "requestSubstitution"
        case .adjustLoadOrVolume: return "adjustLoadOrVolume"
        case .recommendRest: return "recommendRest"
        case .rescheduleWorkout: return "rescheduleWorkout"
        case .updateGymKnowledge: return "updateGymKnowledge"
        case .saveRestriction: return "saveRestriction"
        case .presentExplanation: return "presentExplanation"
        }
    }
}

// MARK: - Decisión de escritura

/// Resultado del pipeline determinista de escritura.
public enum AgentWriteDecision: Sendable {
    /// Listo para ejecutar: el comando estrecho está autorizado por la política.
    case execute(command: AgentWriteCommand, verdict: ActionPolicyVerdict, preview: AgentActionPreview)
    /// Requiere confirmación explícita del usuario antes de ejecutar.
    case confirm(command: AgentWriteCommand, verdict: ActionPolicyVerdict, preview: AgentActionPreview)
    /// Rechazada por la política (p. ej. no evadir restricciones, no progresar con pain gate).
    case rejected(reason: String, verdict: ActionPolicyVerdict, preview: AgentActionPreview)
}

/// Resultado completo del pipeline, incluido el audit trail redactado por etapa.
public struct AgentActionPipelineResult: Sendable {
    public let intent: AgentIntent
    public let action: AgentAction
    public let preview: AgentActionPreview
    public let decision: AgentWriteDecision
    /// Filas de auditoría (append-only) para el journal: intent → actionValidation → result.
    public let auditRecords: [AgentAuditRecord]
}

// MARK: - Writer de acciones del agente

/// Coordina el pipeline determinista de escritura (Phase N4).
///
/// Uso: `writer.execute(intent:context:userConfirmed:)`. El LLM NUNCA llama a este
/// tipo directamente en la capa de UI/dominio de forma no mediada: el caller (app)
/// lo invoca tras interpretar el intent, y despacha el `AgentWriteCommand` resultante
/// a los managers de dominio. La capa de app NO guarda el comando crudo sensible como
/// dato de producto; la auditoría usa filas redactadas (`AgentAuditRecord`).
public struct AgentActionWriter: Sendable {
    private let validator: ActionPolicyValidator

    public init(validator: ActionPolicyValidator) {
        self.validator = validator
    }

    /// Procesa un `AgentIntent`: mapea a acción, genera preview, valida con política y
    /// produce un comando estrecho (si procede) + audit trail redactado.
    public func execute(
        intent: AgentIntent,
        context: ActionPolicyContext,
        userConfirmed: Bool = false,
        conversationID: UUID? = nil
    ) throws -> AgentActionPipelineResult {
        let action = AgentIntentActionMapper.action(for: intent)
        let preview = AgentActionPreviewFactory.preview(for: intent, context: context)
        var effectiveContext = context
        effectiveContext.userConfirmed = userConfirmed
        let verdict = try validator.validate(action, context: effectiveContext)

        var audit: [AgentAuditRecord] = [
            .intent(intent, conversationID: conversationID),
            .validation(verdict, conversationID: conversationID),
        ]

        let decision: AgentWriteDecision
        switch verdict.outcome {
        case .allowed:
            let writeCommand = makeCommand(for: intent, action: action, verdict: verdict)
            decision = .execute(command: writeCommand, verdict: verdict, preview: preview)
            audit.append(.result(command: writeCommand.name, conversationID: conversationID, notes: verdict.reasons))

        case .requiresConfirmation:
            let writeCommand = makeCommand(for: intent, action: action, verdict: verdict)
            decision = .confirm(command: writeCommand, verdict: verdict, preview: preview)
            audit.append(.result(command: "confirm:\(writeCommand.name)", conversationID: conversationID, notes: verdict.reasons))

        case .rejected(let reason):
            decision = .rejected(reason: reason, verdict: verdict, preview: preview)
            audit.append(.result(command: "rejected", conversationID: conversationID, notes: [reason]))
        }

        return AgentActionPipelineResult(
            intent: intent,
            action: action,
            preview: preview,
            decision: decision,
            auditRecords: audit
        )
    }

    /// Convierte la acción validada en el comando estrecho concreto para el intent.
    private func makeCommand(
        for intent: AgentIntent,
        action: AgentAction,
        verdict: ActionPolicyVerdict
    ) -> AgentWriteCommand {
        switch intent {
        case .setTimeConstraint(let constraint):
            return .recomputeSession(reason: constraintSummary(constraint))

        case .equipmentUnavailable:
            return .updateGymKnowledge(reason: "equipamiento no disponible")

        case .requestExerciseSwap(let exerciseID):
            return .requestSubstitution(forExercise: exerciseID)

        case .reportFatigue:
            return .adjustLoadOrVolume(scope: .loadTarget, reduction: true)

        case .reportPain:
            return .adjustLoadOrVolume(scope: .loadTarget, reduction: true)

        case .changeGoal:
            return .adjustLoadOrVolume(scope: .fullRebuild, reduction: false)

        case .changePhase:
            return .adjustLoadOrVolume(scope: .fullRebuild, reduction: false)

        case .changeGym:
            return .updateGymKnowledge(reason: "cambio de gym")

        case .askWhy(let decisionID):
            return .presentExplanation(
                decisionID: decisionID,
                decisionRecord: verdict.decisionRecord
            )

        case .updateRestriction(let draft):
            return .saveRestriction(draft: draft)

        case .requestPlanAdjustment(let request):
            return .adjustLoadOrVolume(scope: request.scope, reduction: false)
        }
    }

    private func constraintSummary(_ constraint: TimeConstraint) -> String {
        switch constraint {
        case .hard(let minutes):
            return "\(minutes) min"
        case .flexible(let target, let tolerance):
            return "flexible \(target) min ± \(tolerance)"
        case .unconstrained:
            return "sin límite"
        }
    }
}
