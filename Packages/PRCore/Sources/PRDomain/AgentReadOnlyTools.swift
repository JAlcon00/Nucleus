//
//  AgentReadOnlyTools.swift
//  PRDomain
//
//  Created by PR.
//
//  Phase N3 — Tool gateway (NEMOTRON_3_5_LIGHTNING_API.md §13-§15): herramientas
//  READ-ONLY que el agente puede consultar para obtener contexto. Refuerza el
//  invariante "LLM interprets, engine decides":
//    - el LLM NUNCA escribe: sólo le consulta contexto tipado;
//    - allow-list estricta: cualquier tool fuera de la lista se REHAZA (fail-safe);
//    - el resultado es determinista y auditable (vía `AgentAuditRecord`).
//  Las escrituras se delegan a fases N4+ (ActionPolicyValidator + managers), nunca aquí.
//

import Foundation

// MARK: - Allow-list de tools read-only

/// Nombre de una tool de solo lectura. La lista es estricta: son las ÚNICAS tools
/// expuestas al LLM (promptMaster §20.4) y todas son de LECTURA.
public enum AgentReadOnlyToolName: String, Codable, Sendable, CaseIterable, Hashable {
    case getTodayContext
    case getTrainingHistory
    case getActiveRestrictions
    case getGymProfile

    /// Definición provider-agnostic (para exponerla al LLM en el request).
    public var definition: AgentToolGatewayDefinition {
        switch self {
        case .getTodayContext:
            return .init(name: rawValue, description: "Obtener la sesión y contexto del día de hoy (read-only).")
        case .getTrainingHistory:
            return .init(name: rawValue, description: "Obtener historial reciente de entrenamiento (read-only).")
        case .getActiveRestrictions:
            return .init(name: rawValue, description: "Obtener las restricciones de entrenamiento activas (read-only).")
        case .getGymProfile:
            return .init(name: rawValue, description: "Obtener el perfil del gimnasio activo (read-only).")
        }
    }
}

/// Definición de tool de dominio (idéntica en forma a `AgentToolDefinition` de la
/// capa de app, pero en dominio para no acoplarlo a PRCore). El provider la traduce.
public struct AgentToolGatewayDefinition: Sendable, Hashable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// El conjunto público de tool definitions read-only para exponer al LLM.
public enum AgentReadOnlyToolCatalog {
    public static let all: [AgentReadOnlyToolName] = AgentReadOnlyToolName.allCases

    public static func definitions() -> [AgentToolGatewayDefinition] {
        all.map(\.definition)
    }
}

// MARK: - Contexto read-only tipado

/// Contexto determinista que las tools read-only devuelven. La app lo implementa
/// leyendo de sus repositorios; aquí se transporta como valor tipado.
public struct AgentReadOnlyContext: Sendable, Hashable {
    public var todaySummary: String
    public var trainingHistorySummary: String
    public var activeRestrictionCount: Int
    public var gymProfileSummary: String
    public var painGateActive: Bool

    public init(
        todaySummary: String = "",
        trainingHistorySummary: String = "",
        activeRestrictionCount: Int = 0,
        gymProfileSummary: String = "",
        painGateActive: Bool = false
    ) {
        self.todaySummary = todaySummary
        self.trainingHistorySummary = trainingHistorySummary
        self.activeRestrictionCount = activeRestrictionCount
        self.gymProfileSummary = gymProfileSummary
        self.painGateActive = painGateActive
    }
}

// MARK: - Resultado tipado

/// Resultado de ejecutar una tool read-only. `payload` es texto estructurado JSON
/// construido en el dominio (determinista, sin PII); `auditNotes` opcional.
public struct AgentToolResult: Sendable, Hashable {
    public let name: String
    public let payload: String
    public let auditNotes: [String]

    public init(name: String, payload: String, auditNotes: [String] = []) {
        self.name = name
        self.payload = payload
        self.auditNotes = auditNotes
    }
}

public enum AgentToolError: Error, Sendable, Equatable {
    /// La tool no está en la allow-list (fail-safe: se niega).
    case unknownTool(name: String)
    /// Argumentos JSON inválidos para la tool (fail-safe).
    case invalidArguments(name: String)
}

// MARK: - Gateway read-only

/// Ejecuta tools de solo lectura de forma determinista. Valida contra la allow-list
/// y decodifica argumentos; nunca escribe.
public struct AgentReadOnlyToolGateway: Sendable {
    private let context: AgentReadOnlyContext

    public init(context: AgentReadOnlyContext) {
        self.context = context
    }

    public static var allowedNames: Set<String> {
        Set(AgentReadOnlyToolName.allCases.map(\.rawValue))
    }

    /// ¿Está la tool en la allow-list? (fail-safe anti tool-call arbitrario).
    public func isAllowListed(_ name: String) -> Bool {
        Self.allowedNames.contains(name)
    }

    /// Ejecuta una tool read-only por nombre. Lanza si no está en la allow-list o
    /// si los argumentos no decodifican.
    public func execute(name: String, arguments: String = "{}") throws -> AgentToolResult {
        guard let tool = AgentReadOnlyToolName(rawValue: name) else {
            // No está en la allow-list → se niega (el LLM nunca escribe/arbitrariedad).
            throw AgentToolError.unknownTool(name: name)
        }
        try decodeArgumentsIfAny(arguments, tool: tool)
        switch tool {
        case .getTodayContext:
            return .init(
                name: name,
                payload: json([("session", context.todaySummary), ("painGateActive", String(context.painGateActive))])
            )
        case .getTrainingHistory:
            return .init(
                name: name,
                payload: json([("history", context.trainingHistorySummary)])
            )
        case .getActiveRestrictions:
            return .init(
                name: name,
                payload: json([("activeRestrictionCount", String(context.activeRestrictionCount))])
            )
        case .getGymProfile:
            return .init(
                name: name,
                payload: json([("gym", context.gymProfileSummary)])
            )
        }
    }

    private func decodeArgumentsIfAny(_ arguments: String, tool: AgentReadOnlyToolName) throws {
        // Las 4 tools read-only no requieren argumentos; ante el más mínimo JSON
        // no-objeto se rechaza. Se acepta "{}" o vacío.
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return }
        guard let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentToolError.invalidArguments(name: tool.rawValue)
        }
        _ = obj
    }

    private func json(_ pairs: [(String, String)]) -> String {
        let object = pairs.reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        guard let data = try? JSONEncoder().encode(object),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }
}
