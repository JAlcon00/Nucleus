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
    /// Llamadas a tool emitidas por el modelo (Phase N3).
    public var toolCalls: [AgentToolCall]
    /// Uso del run (tokens + latencia + reasoning), Phase N6 budget measurements.
    public var usage: AgentUsage?

    public init(
        text: String? = nil,
        reasoning: String? = nil,
        finishReason: AgentFinishReason = .stop,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        toolCalls: [AgentToolCall] = [],
        usage: AgentUsage? = nil
    ) {
        self.text = text
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.toolCalls = toolCalls
        // Si no hay `usage` pero sí vienen tokens sueltos (legado), construimos uno.
        self.usage = usage ?? (promptTokens != nil || completionTokens != nil
            ? AgentUsage(promptTokens: promptTokens, completionTokens: completionTokens)
            : nil)
    }

    // Conveniencia legado: accesso directo a los tokens sin requerir `usage`.
    public var promptTokens: Int? { usage?.promptTokens }
    public var completionTokens: Int? { usage?.completionTokens }

    public var isComplete: Bool { finishReason != .length }
}

/// Protocolo de proveedor LLM. Implementaciones: NVIDIAHostedProvider, MockLLMProvider.
public protocol LLMProvider: Sendable {
    func complete(_ request: AgentRequest) async throws -> AgentResponse
}

// MARK: - Streaming (Phase N5)

/// Evento incremental de una respuesta en streaming. El proving solo emite delta de
/// contenido visible y del reasoning, y en último término un `.finish`. El cliente
/// reconcilia los deltas en texto final; NUNCA muestra el reasoning trace interno.
public enum AgentStreamEvent: Sendable, Equatable {
    /// Delta de contenido visible (`content`).
    case text(String)
    /// Delta de reasoning (`reasoning_content`) — NO mostrar al usuario.
    case reasoning(String)
    /// Llamada a tool completa emitida por el modelo (finalizada).
    case toolCall(AgentToolCall)
    /// Fin de la generación.
    case finish(AgentFinishReason)
}

extension LLMProvider {
    /// Streaming con fallback: si el provider no lo implementa, se emite el contenido
    /// completo de `complete` como un único delta. Determínistico y no rompe contratos.
    public func stream(_ request: AgentRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await self.complete(request)
                    if let text = response.text {
                        continuation.yield(.text(text))
                    }
                    for call in response.toolCalls {
                        continuation.yield(.toolCall(call))
                    }
                    continuation.yield(.finish(response.finishReason))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

