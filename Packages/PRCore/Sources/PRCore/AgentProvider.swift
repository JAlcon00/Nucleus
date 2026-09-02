//
//  AgentProvider.swift
//  PRCore
//
//  Created by PR.
//
//  Abstracción de proveedor LLM (NEMOTRON_3_5_LIGHTNING_API.md §23, PR-1608, Phase N1).
//
//  `AgentRequest`/`AgentResponse` son provider-agnostic: no contienen parámetros
//  específicos de NVIDIA. Cada `LLMProvider` traduce al dialecto de su proveedor.
//  El dominio NO conoce ni usa estos tipos (networking vive en la capa de core/app;
//  PR-1603 define el contrato puro `AgentBackendTransport` que un provider implementa).
//

import Foundation

/// Modo de ejecución del modelo (mapea a presets de reasoning del proveedor, §23).
public enum AgentExecutionMode: String, Sendable, Hashable {
    /// Determinista: thinking OFF (intent/estructura/JSON). §40 FAST_STRUCTURED.
    case fast
    /// Reasoning acotado: multi-tool, ambigüedad. §40 REASONING_AGENT.
    case reasoning
    /// Reasoning profundo: análisis de bloque, transiciones complejas. §40 DEEP_AGENT.
    case deepReasoning
}

/// Requerimiento de salida del provider.
public enum AgentOutputRequirement: String, Sendable, Hashable {
    case text
    case json
}

/// Mensaje de la conversación (rol OpenAI-compatible).
public struct AgentMessage: Codable, Sendable, Hashable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Schema JSON de un parámetro de tool (provider-agnostic; el provider lo traduce).
public struct AgentToolProperty: Codable, Sendable, Hashable {
    public var type: String
    public var description: String?
    public var enumValues: [String]?

    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

public struct AgentToolParameters: Codable, Sendable, Hashable {
    public var type: String
    public var properties: [String: AgentToolProperty]
    public var required: [String]

    public init(
        type: String = "object",
        properties: [String: AgentToolProperty],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

/// Definición de tool (Phase N3: nombre + descripción + schema de parámetros opcional).
public struct AgentToolDefinition: Codable, Sendable, Hashable {
    public var name: String
    public var description: String
    public var parameters: AgentToolParameters?

    public init(name: String, description: String, parameters: AgentToolParameters? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Una llamada a tool emitida por el modelo (Phase N3). `arguments` es el JSON crudo
/// que el proveedor devuelve; el gateway lo valida/decodifica antes de ejecutar.
public struct AgentToolCall: Codable, Sendable, Hashable {
    public var id: String?
    public var name: String
    public var arguments: String

    public init(id: String? = nil, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Request provider-agnostic hacia el LLM (§23). No tiene props de proveedor.
public struct AgentRequest: Sendable {
    public var messages: [AgentMessage]
    public var mode: AgentExecutionMode
    public var tools: [AgentToolDefinition]
    public var output: AgentOutputRequirement

    public init(
        messages: [AgentMessage],
        mode: AgentExecutionMode = .fast,
        tools: [AgentToolDefinition] = [],
        output: AgentOutputRequirement = .text
    ) {
        self.messages = messages
        self.mode = mode
        self.tools = tools
        self.output = output
    }
}

/// Motivo de finalización de la generación.
public enum AgentFinishReason: String, Sendable, Hashable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case contentFilter
    case unknown
}

/// Response provider-agnostic.
public struct AgentResponse: Sendable {
    public var text: String?
    public var reasoning: String?
    public var finishReason: AgentFinishReason
    public var promptTokens: Int?
    public var completionTokens: Int?
    /// Llamadas a tool emitidas por el modelo (Phase N3).
    public var toolCalls: [AgentToolCall]

    public init(
        text: String? = nil,
        reasoning: String? = nil,
        finishReason: AgentFinishReason = .stop,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        toolCalls: [AgentToolCall] = []
    ) {
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.toolCalls = toolCalls
    }

    public var isComplete: Bool { finishReason != .length }
}

/// Protocolo de proveedor LLM. Implementaciones: NVIDIAHostedProvider, MockLLMProvider.
public protocol LLMProvider: Sendable {
    func complete(_ request: AgentRequest) async throws -> AgentResponse
}
