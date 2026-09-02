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

    public init(
        model: String,
        messages: [NVIDIAChatMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool? = nil,
        reasoningBudget: Int? = nil,
        chatTemplateKwargs: ChatTemplateKwargs? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stream = stream
        self.reasoningBudget = reasoningBudget
        self.chatTemplateKwargs = chatTemplateKwargs
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
    }
}

// MARK: - Response

public struct NVIDIAChatMessageContent: Decodable, Sendable {
    public var content: String?
    public var reasoningContent: String?

    public enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
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
