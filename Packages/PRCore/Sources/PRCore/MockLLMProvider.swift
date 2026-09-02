//
//  MockLLMProvider.swift
//  PRCore
//
//  Created by PR.
//
//  Mock determinista del proveedor LLM (NEMOTRON_3_5_LIGHTNING_API.md §23):
//  usado en tests y en flujo offline. No llama a ninguna red.
//

import Foundation

/// Proveedor mock determinista.
public struct MockLLMProvider: LLMProvider {
    public var result: Result<AgentResponse, NVIDIAProviderError>

    public init(result: Result<AgentResponse, NVIDIAProviderError> = .success(AgentResponse(text: "mock"))) {
        self.result = result
    }

    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        try result.get()
    }
}
