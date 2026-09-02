//
//  AgentAuditTrail.swift
//  PRDomain
//
//  Created by PR.
//
//  Agent audit trail (promptMaster §20, PR-1607): traza el pipeline del agente
//  (intent → action → result) de forma auditable y con mínima retención de datos
//  sensibles.
//
//  Invariantes:
//  - Los tres eslabones son trazables: qué se entendió (`AgentIntent`), qué se
//    validó (`AgentAction` + `ActionPolicyOutcome`) y qué produjo (resultado/comando).
//  - Se minimizan datos sensibles: NUNCA se guarda el texto crudo del usuario, ni el
//    reasoning trace del LLM, ni identificadores personales. Sólo etiquetas estables,
//    nombres legibles y comandos/veredictos estructurados.
//  - El journal es append-only y de semántica de valor (Sendable): el caller decide
//    la persistencia durable en la capa de app (PRCore), igual que `DecisionRecord`.
//

import Foundation

// MARK: - Etapa del pipeline

/// Etapa del pipeline del agente que un registro de auditoría describe.
public enum AgentAuditStage: String, Codable, Sendable, Hashable, CaseIterable {
    /// Se resolvió la intención a partir del mensaje del usuario.
    case inboundIntent
    /// Se validó la acción candidata con la política de seguridad.
    case actionValidation
    /// Se produjo el resultado (comando estrecho / rechazo / confirmación / explicación).
    case result
}

// MARK: - Registro de auditoría

/// Una fila del audit trail. Cada fila describe UNA etapa; el conjunto de filas con
/// el mismo `conversationID` reconstruye la trazabilidad completa intent→action→result.
public struct AgentAuditRecord: Codable, Sendable, Hashable {
    public typealias ID = UUID

    public let id: UUID
    public let date: Date
    /// Identificador opaco del turno/pipeline (agrupa las etapas de un mismo mensaje).
    public let conversationID: UUID?
    public let stage: AgentAuditStage

    // Etapas (sólo la pertinente se rellena por fila; el resto queda nil).
    public let intentTag: String?
    public let intentDisplayName: String?
    public let actionName: String?
    public let outcome: String?
    public let resultCommand: String?

    /// Regla de evidencia usada (política/validator), con versión — para auditar
    /// qué versión aplicó (mirror de DecisionRecord).
    public let ruleReference: EvidenceRuleReference?

    /// Notas mínimas y no sensibles (p. ej. motivo de rechazo legible sin PII).
    public let notes: [String]

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        conversationID: UUID? = nil,
        stage: AgentAuditStage,
        intentTag: String? = nil,
        intentDisplayName: String? = nil,
        actionName: String? = nil,
        outcome: String? = nil,
        resultCommand: String? = nil,
        ruleReference: EvidenceRuleReference? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.date = date
        self.conversationID = conversationID
        self.stage = stage
        self.intentTag = intentTag
        self.intentDisplayName = intentDisplayName
        self.actionName = actionName
        self.outcome = outcome
        self.resultCommand = resultCommand
        self.ruleReference = ruleReference
        self.notes = notes
    }
}

// MARK: - Construcción redactada (mini-PII)

extension AgentAuditRecord {
    /// Fila de la etapa `inboundIntent` a partir de un `AgentIntent` resuelto.
    /// Sólo guarda el tag estable y el nombre legible — nunca el payload crudo
    /// (p. ej. notas de dolor) ni el texto del usuario.
    public static func intent(_ intent: AgentIntent, conversationID: UUID? = nil, date: Date = Date()) -> AgentAuditRecord {
        AgentAuditRecord(
            date: date,
            conversationID: conversationID,
            stage: .inboundIntent,
            intentTag: intent.tag,
            intentDisplayName: intent.displayName
        )
    }

    /// Fila de la etapa `inboundIntent` cuando no hubo intent claro.
    public static func needsClarification(conversationID: UUID? = nil, date: Date = Date()) -> AgentAuditRecord {
        AgentAuditRecord(
            date: date,
            conversationID: conversationID,
            stage: .inboundIntent,
            intentTag: "needsClarification",
            intentDisplayName: "Requiere aclaración"
        )
    }

    /// Fila de la etapa `actionValidation` a partir del veredicto de política.
    public static func validation(
        _ verdict: ActionPolicyVerdict,
        conversationID: UUID? = nil,
        ruleReference: EvidenceRuleReference? = nil,
        date: Date = Date()
    ) -> AgentAuditRecord {
        AgentAuditRecord(
            date: date,
            conversationID: conversationID,
            stage: .actionValidation,
            actionName: verdict.action.displayName,
            outcome: outcomeDescription(verdict.outcome),
            ruleReference: ruleReference ?? verdict.ruleReference,
            notes: verdict.reasons
        )
    }

    /// Fila de la etapa `result`: el comando estrecho que el sistema ejecutará/decidió.
    public static func result(
        command: String,
        conversationID: UUID? = nil,
        ruleReference: EvidenceRuleReference? = nil,
        notes: [String] = [],
        date: Date = Date()
    ) -> AgentAuditRecord {
        AgentAuditRecord(
            date: date,
            conversationID: conversationID,
            stage: .result,
            resultCommand: command,
            ruleReference: ruleReference,
            notes: notes
        )
    }

    private static func outcomeDescription(_ outcome: ActionPolicyOutcome) -> String {
        switch outcome {
        case .allowed(let command): return "allowed:\(command)"
        case .rejected(let reason): return "rejected:\(reason)"
        case .requiresConfirmation(let command): return "requiresConfirmation:\(command)"
        }
    }
}

// MARK: - Journal append-only

/// Journal append-only del audit trail. Semántica de valor (Sendable). El caller
/// (capa de app) decide la persistencia durable; aquí sólo se acumulan filas en
/// memoria con orden estable y consultas de trazabilidad.
public struct AgentAuditJournal: Sendable {
    private var records: [AgentAuditRecord]

    public init(records: [AgentAuditRecord] = []) {
        self.records = records
    }

    /// Añade una fila (append-only: no hay borrado ni edición).
    public mutating func append(_ record: AgentAuditRecord) {
        records.append(record)
    }

    /// Añade varias filas manteniendo el orden.
    public mutating func append(contentsOf new: [AgentAuditRecord]) {
        records.append(contentsOf: new)
    }

    public var count: Int { records.count }

    public var isEmpty: Bool { records.isEmpty }

    /// Todas las filas, orden cronológico estable.
    public var all: [AgentAuditRecord] { records }

    /// Fila más recientes primero (límite opcional).
    public func latest(limit: Int? = nil) -> [AgentAuditRecord] {
        let sorted = records.sorted { $0.date > $1.date }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    /// Fila de un mismo turno (trazabilidad intent→action→result agrupada).
    public func records(conversationID: UUID) -> [AgentAuditRecord] {
        records
            .filter { $0.conversationID == conversationID }
            .sorted { $0.date < $1.date }
    }

    /// Cadena de trazabilidad legible para UI/log (mínima, sin PII).
    public func traceSummary(conversationID: UUID) -> String {
        records(conversationID: conversationID)
            .map { row in
                switch row.stage {
                case .inboundIntent:
                    return "intent=\(row.intentTag ?? "?")"
                case .actionValidation:
                    return "action=\(row.actionName ?? "?") \(row.outcome ?? "")"
                case .result:
                    return "result=\(row.resultCommand ?? "?")"
                }
            }
            .joined(separator: " → ")
    }
}
