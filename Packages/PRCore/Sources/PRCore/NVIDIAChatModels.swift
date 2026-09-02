//
//  NVIDIAChatModels.swift
//  PRCore
//
//  Created by PR.
//
//  DTOs del wire format de NVIDIA Chat Completions (NEMOTRON_3_5_LIGHTNING_API.md §20).
//  Son SÓLO transporte: nunca se reutilizan como entidades de dominio (§20).
//

import Foundation

/// `chat_template_kwargs` de Nemotron (thinking on/off).
public struct ChatTemplateKwargs: Encodable, Sendable {
    public var enableThinking: Bool

    public init(enableThinking: Bool) {
        self.enableThinking = enableThinking
    }

    public enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

// MARK: - Tool calling (Phase N3, spec §13-§14)

/// Schema JSON de un parámetro de una tool (subset de JSON Schema).
public struct NVIDIAToolParameter: Codable, Sendable, Hashable {
    public var type: String
    public var description: String?
    public var enumValues: [String]?

    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}

public struct NVIDIAToolParameters: Codable, Sendable, Hashable {
    public var type: String
    public var properties: [String: NVIDIAToolParameter]
    public var required: [String]
    public var additionalProperties: Bool

    public init(
        type: String = "object",
        properties: [String: NVIDIAToolParameter],
        required: [String] = [],
        additionalProperties: Bool = false
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }
}

/// Función de una tool (OpenAI-compatible `{type:"function", function:{...}}`).
public struct NVIDIAToolFunction: Encodable, Sendable {
    public var name: String
    public var description: String
    public var parameters: NVIDIAToolParameters?

    public init(name: String, description: String, parameters: NVIDIAToolParameters? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Tool declarada en el request.
public struct NVIDIATool: Encodable, Sendable {
    public var type: String
    public var function: NVIDIAToolFunction

    public init(type: String = "function", function: NVIDIAToolFunction) {
        self.type = type
        self.function = function
    }
}

/// Mensaje OpenAI-compatible.
public struct NVIDIAChatMessage: Codable, Sendable, Hashable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Request a `/v1/chat/completions` (§20).
public struct NVIDIAChatRequest: Encodable, Sendable {
    public var model: String
    public var messages: [NVIDIAChatMessage]
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var stream: Bool?
    public var reasoningBudget: Int?
    public var chatTemplateKwargs: ChatTemplateKwargs?
    public var tools: [NVIDIATool]?
    public var toolChoice: String?

    public init(
        model: String,
        messages: [NVIDIAChatMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool? = nil,
        reasoningBudget: Int? = nil,
        chatTemplateKwargs: ChatTemplateKwargs? = nil,
        tools: [NVIDIATool]? = nil,
        toolChoice: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stream = stream
        self.reasoningBudget = reasoningBudget
        self.chatTemplateKwargs = chatTemplateKwargs
        self.tools = tools
        self.toolChoice = toolChoice
    }

    public enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case stream
        case reasoningBudget = "reasoning_budget"
        case chatTemplateKwargs = "chat_template_kwargs"
        case tools
        case toolChoice = "tool_choice"
    }
}

// MARK: - Response

/// `tool_calls` de un assistant message (OpenAI-compatible).
public struct NVIDIAToolCallFunction: Decodable, Sendable {
    public var name: String?
    public var arguments: String?

    public enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }
}

public struct NVIDIAToolCall: Decodable, Sendable {
    public var id: String?
    public var type: String?
    public var function: NVIDIAToolCallFunction?

    public enum CodingKeys: String, CodingKey {
        case id
        case type
        case function
    }
}

public struct NVIDIAChatMessageContent: Decodable, Sendable {
    public var content: String?
    public var reasoningContent: String?
    public var toolCalls: [NVIDIAToolCall]?

    public enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

public struct NVIDIAChatChoice: Decodable, Sendable {
    public var index: Int?
    public var message: NVIDIAChatMessageContent?
    public var finishReason: String?

    public enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

public struct NVIDIAChatUsage: Decodable, Sendable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct NVIDIAChatResponse: Decodable, Sendable {
    public var id: String?
    public var choices: [NVIDIAChatChoice]?
    public var usage: NVIDIAChatUsage?

    public init(id: String? = nil, choices: [NVIDIAChatChoice]? = nil, usage: NVIDIAChatUsage? = nil) {
        self.id = id
        self.choices = choices
        self.usage = usage
    }
}
