//
//  NVIDIAHostedProvider.swift
//  PRCore
//
//  Created by PR.
//
//  Proveedor NVIDIA Hosted (NEMOTRON_3_5_LIGHTNING_API.md §23, Phase N1, PR-1608).
//
//  Mapea un `AgentRequest` provider-agnostic al payload de Chat Completions del hosted
//  endpoint (`https://integrate.api.nvidia.com/v1/chat/completions`), ejecuta la llamada,
//  mapea errores (§34) y aplica retry acotado (§35).
//
//  SEGURIDAD (spec §22/§42, AGENTS "no store secrets in client"): esta clase NUNCA
//  embebe la API key. La key se inyecta en runtime desde el entorno del host vía
//  `apiKeyProvider`. En producción la app debe hablar con NUESTRO backend y esta clase
//  sólo se usa para prototipado (spec §21/§22). Default: mock/offline.
//

import Foundation

/// Configuración del provider NVIDIA Hosted.
public struct NVIDIAHostedConfig: Sendable {
    public var baseURL: URL
    public var model: String
    /// Provee la key en runtime (entorno del host). NUNCA hardcodeada.
    public var apiKeyProvider: @Sendable () -> String?
    public var timeoutSeconds: TimeInterval
    public var maxRetries: Int

    public init(
        baseURL: URL = URL(string: "https://integrate.api.nvidia.com/v1")!,
        model: String = "nvidia/nemotron-3.5-lightning-30b-a3b",
        apiKeyProvider: @escaping @Sendable () -> String? = { NVIDIAKeyLoader.load() },
        timeoutSeconds: TimeInterval = 15,
        maxRetries: Int = 2
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKeyProvider = apiKeyProvider
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
    }
}

/// Errores tipados del proveedor (spec §34).
public enum NVIDIAProviderError: Error, Sendable, Equatable {
    case missingAPIKey
    case authentication
    case forbidden
    case notFound
    case validation
    case rateLimited
    case providerError(status: Int)
    case timeout
    case network
    case invalidResponse
    case malformedResponse
    /// La respuesta no trae `choices` válido.
    case emptyChoices
}

/// Presets de sampling/razonamiento por execution mode (spec §40, §23).
public struct NVIDIAProviderPreset: Sendable, Equatable {
    public var temperature: Double
    public var maxTokens: Int
    public var enableThinking: Bool
    public var reasoningBudget: Int?

    public static let fastStructured = NVIDIAProviderPreset(
        temperature: 0.0, maxTokens: 256, enableThinking: false, reasoningBudget: nil
    )
    public static let fastAgent = NVIDIAProviderPreset(
        temperature: 0.1, maxTokens: 512, enableThinking: false, reasoningBudget: nil
    )
    public static let reasoning = NVIDIAProviderPreset(
        temperature: 0.4, maxTokens: 4096, enableThinking: true, reasoningBudget: 2048
    )
    public static let deep = NVIDIAProviderPreset(
        temperature: 0.5, maxTokens: 8192, enableThinking: true, reasoningBudget: 4096
    )

    /// Preset aplicado según el modo de ejecución (§23).
    public static func forMode(_ mode: AgentExecutionMode) -> NVIDIAProviderPreset {
        switch mode {
        case .fast: return fastAgent
        case .reasoning: return reasoning
        case .deepReasoning: return deep
        }
    }
}

/// Proveedor que habla con el endpoint hosted de NVIDIA (Phase N1).
public struct NVIDIAHostedProvider: LLMProvider {
    public let config: NVIDIAHostedConfig
    private let session: URLSession

    public init(config: NVIDIAHostedConfig = NVIDIAHostedConfig(), session: URLSession? = nil) {
        self.config = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = config.timeoutSeconds
        self.session = session ?? URLSession(configuration: cfg)
    }

    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        let preset = NVIDIAProviderPreset.forMode(request.mode)
        let apiKey = config.apiKeyProvider()
        guard let apiKey, !apiKey.isEmpty else {
            throw NVIDIAProviderError.missingAPIKey
        }

        let endpoint = config.baseURL.appendingPathComponent("chat/completions")
        let chatRequest = NVIDIAChatRequest(
            model: config.model,
            messages: request.messages.map { NVIDIAChatMessage(role: $0.role, content: $0.content) },
            temperature: preset.temperature,
            maxTokens: preset.maxTokens,
            stream: false,
            reasoningBudget: preset.reasoningBudget,
            chatTemplateKwargs: ChatTemplateKwargs(enableThinking: preset.enableThinking),
            tools: request.tools.isEmpty ? nil : request.tools.map(Self.wireTool),
            toolChoice: request.tools.isEmpty ? nil : "auto"
        )

        let totalAttempts = max(1, config.maxRetries + 1)
        var lastAttempt = 0
        for attempt in 0..<totalAttempts {
            lastAttempt = attempt
            if attempt > 0 {
                // Backoff acotado con jitter (§35). 0 en tests.
                let jitterMs = UInt32.random(in: 0...200)
                let base = UInt64(exp2(Double(attempt - 1)) * 0.25 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: base + UInt64(jitterMs) * 1_000_000)
            }
            do {
                return try await send(endpoint: endpoint, payload: chatRequest)
            } catch let error as NVIDIAProviderError {
                if shouldRetry(error), attempt < totalAttempts - 1 { continue }
                throw error
            } catch {
                if lastAttempt < totalAttempts - 1 { continue }
                throw error
            }
        }
        throw NVIDIAProviderError.network
    }

    // MARK: - HTTP

    private func send(endpoint: URL, payload: NVIDIAChatRequest) async throws -> AgentResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(config.apiKeyProvider() ?? "")", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NVIDIAProviderError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw NVIDIAProviderError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try decode(data: data)
        case 400: throw NVIDIAProviderError.validation
        case 401, 403: throw (http.statusCode == 403 ? NVIDIAProviderError.forbidden : NVIDIAProviderError.authentication)
        case 404: throw NVIDIAProviderError.notFound
        case 408: throw NVIDIAProviderError.timeout
        case 422: throw NVIDIAProviderError.validation
        case 429: throw NVIDIAProviderError.rateLimited
        case 500..<600: throw NVIDIAProviderError.providerError(status: http.statusCode)
        default: throw NVIDIAProviderError.providerError(status: http.statusCode)
        }
    }

    private func decode(data: Data) throws -> AgentResponse {
        let response: NVIDIAChatResponse
        do {
            response = try JSONDecoder().decode(NVIDIAChatResponse.self, from: data)
        } catch {
            throw NVIDIAProviderError.malformedResponse
        }
        guard let choice = response.choices?.first, let message = choice.message else {
            throw NVIDIAProviderError.emptyChoices
        }
        let finish: AgentFinishReason
        switch choice.finishReason {
        case "stop": finish = .stop
        case "length": finish = .length
        case "tool_calls": finish = .toolCalls
        default: finish = .unknown
        }
        let toolCalls = (message.toolCalls ?? []).compactMap { call -> AgentToolCall? in
            guard let name = call.function?.name else { return nil }
            return AgentToolCall(id: call.id, name: name, arguments: call.function?.arguments ?? "")
        }
        return AgentResponse(
            text: message.content,
            reasoning: message.reasoningContent,
            finishReason: finish,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            toolCalls: toolCalls
        )
    }

    // MARK: - Tool mapping (Phase N3)

    private static func wireTool(_ definition: AgentToolDefinition) -> NVIDIATool {
        NVIDIATool(
            function: NVIDIAToolFunction(
                name: definition.name,
                description: definition.description,
                parameters: definition.parameters.map { params in
                    NVIDIAToolParameters(
                        type: "object",
                        properties: params.properties.mapValues(Self.wireParameter),
                        required: params.required,
                        additionalProperties: false
                    )
                }
            )
        )
    }

    private static func wireParameter(_ property: AgentToolProperty) -> NVIDIAToolParameter {
        NVIDIAToolParameter(
            type: property.type,
            description: property.description,
            enumValues: property.enumValues
        )
    }

    // MARK: - Retry (§35)

    private func shouldRetry(_ error: NVIDIAProviderError) -> Bool {
        switch error {
        case .timeout, .rateLimited, .network:
            return true
        case .providerError:
            return true
        case .authentication, .forbidden, .notFound, .validation,
             .missingAPIKey, .invalidResponse, .malformedResponse, .emptyChoices:
            return false
        }
    }
}
