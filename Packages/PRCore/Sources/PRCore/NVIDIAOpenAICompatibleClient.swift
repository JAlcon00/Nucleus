//
//  NVIDIAOpenAICompatibleClient.swift
//  PRCore
//
//  Created by PR.
//
//  Cliente OpenAI-compatible compartido por NVIDIAHostedProvider (NEMOTRON_3_5_LIGHTNING_API.md
//  §21, Phase N1) y NVIDIANIMProvider (self-hosted NIM, §24, Phase N7). Centraliza el building
//  del payload de Chat Completions, el transporte HTTP, el mapa de errores (§34), el retry
//  acotado (§35), el streaming (Phase N5) y el mapeo de tools (Phase N3).
//
//  Esto garantiza que AMBOS proveedores satisfagan el MISMO contrato `LLMProvider` (§23) con
//  parámetros wire idénticos — la "provider contract" que permite migrar `hosted → NIM` sin
//  tocar dominio ni transporte (§47). El dominio/transporte sólo conoce `LLMProvider`.
//
//  SEGURIDAD (spec §22/§42, AGENTS "no store secrets in client"): la key/token se inyecta en
//  runtime desde `apiKeyProvider` y se coloca en el header `Authorization`. NUNCA embebida.
//  Si `apiKeyProvider` es nil, la petición va sin header (típico despliegue NIM sin auth).
//

import Foundation

/// Cliente HTTP OpenAI-compatible compartido por los proveedores NVIDIA (internal).
struct NVIDIAOpenAICompatibleClient: Sendable {
    let baseURL: URL
    let model: String
    /// Inyecta la key/token de auth en runtime (hosted: NVIDIA key; NIM: auth de nuestra
    /// infraestructura). Si devuelve nil/empty, la petición va sin header `Authorization`.
    let apiKeyProvider: (@Sendable () -> String?)?
    let timeoutSeconds: TimeInterval
    let maxRetries: Int
    private let session: URLSession

    init(
        baseURL: URL,
        model: String,
        apiKeyProvider: (@Sendable () -> String?)?,
        timeoutSeconds: TimeInterval,
        maxRetries: Int,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKeyProvider = apiKeyProvider
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSeconds
        self.session = session ?? URLSession(configuration: cfg)
    }

    // MARK: - Payload building (§20, presets §23/§40)

    /// Construye el request de Chat Completions a partir de un `AgentRequest` provider-agnostic.
    func buildChatRequest(for request: AgentRequest, stream: Bool) -> NVIDIAChatRequest {
        let preset = NVIDIAProviderPreset.forMode(request.mode, output: request.output)
        return NVIDIAChatRequest(
            model: model,
            messages: request.messages.map { NVIDIAChatMessage(role: $0.role, content: $0.content) },
            temperature: preset.temperature,
            maxTokens: preset.maxTokens,
            stream: stream,
            reasoningBudget: preset.reasoningBudget,
            chatTemplateKwargs: ChatTemplateKwargs(enableThinking: preset.enableThinking),
            tools: request.tools.isEmpty ? nil : request.tools.map(Self.wireTool),
            toolChoice: request.tools.isEmpty ? nil : "auto"
        )
    }

    // MARK: - HTTP complete (con retry acotado §35)

    func complete(_ request: AgentRequest) async throws -> AgentResponse {
        let chatRequest = buildChatRequest(for: request, stream: false)
        return try await send(chatRequest)
    }

    private func send(_ chatRequest: NVIDIAChatRequest) async throws -> AgentResponse {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        let totalAttempts = max(1, maxRetries + 1)
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
                return try await perform(endpoint: endpoint, payload: chatRequest)
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

    private func perform(endpoint: URL, payload: NVIDIAChatRequest) async throws -> AgentResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        if let key = apiKeyProvider?(), !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        let started = Date()
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NVIDIAProviderError.network
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw NVIDIAProviderError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return try decode(data: data, durationMilliseconds: elapsedMs)
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

    private func decode(data: Data, durationMilliseconds: Int? = nil) throws -> AgentResponse {
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
        let usage: AgentUsage? = {
            guard let u = response.usage else { return nil }
            return AgentUsage(
                promptTokens: u.promptTokens,
                completionTokens: u.completionTokens,
                reasoningTokens: u.reasoningTokens,
                durationMilliseconds: durationMilliseconds
            )
        }()
        return AgentResponse(
            text: message.content,
            reasoning: message.reasoningContent,
            finishReason: finish,
            toolCalls: toolCalls,
            usage: usage
        )
    }

    // MARK: - Streaming (Phase N5)

    func stream(_ request: AgentRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = self.baseURL.appendingPathComponent("chat/completions")
                    let chatRequest = self.buildChatRequest(for: request, stream: true)

                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    if let key = self.apiKeyProvider?(), !key.isEmpty {
                        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(chatRequest)

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await self.session.bytes(for: urlRequest)
                    } catch {
                        if self.isCancellation(error) { throw NVIDIAProviderError.cancelled }
                        throw NVIDIAProviderError.network
                    }

                    guard let http = response as? HTTPURLResponse else {
                        throw NVIDIAProviderError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw self.mapStatus(http.statusCode)
                    }

                    var decoder = SSEEventDecoder()
                    for try await byte in bytes {
                        if Task.isCancelled { throw NVIDIAProviderError.cancelled }
                        let events = NVIDIAStreamEventParser.parse(
                            decoder: &decoder,
                            fragment: String(decoding: [byte], as: UTF8.self)
                        )
                        for event in events {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    // MARK: - GET helper (health endpoints §24)

    /// Ejecuta un GET simple y devuelve `(statusCode, body)`. Sin retry: un health check es
    /// ligero y debe ser determinista/instantáneo.
    func get(_ path: String) async throws -> (status: Int, body: Data) {
        let url = baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        if let key = apiKeyProvider?(), !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
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
        return (http.statusCode, data)
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

    // MARK: - Status/retry (§34/§35)

    private func mapStatus(_ statusCode: Int) -> NVIDIAProviderError {
        switch statusCode {
        case 400: return .validation
        case 401: return .authentication
        case 403: return .forbidden
        case 404: return .notFound
        case 408: return .timeout
        case 422: return .validation
        case 429: return .rateLimited
        case 500..<600: return .providerError(status: statusCode)
        default: return .providerError(status: statusCode)
        }
    }

    private func shouldRetry(_ error: NVIDIAProviderError) -> Bool {
        switch error {
        case .timeout, .rateLimited, .network:
            return true
        case .providerError:
            return true
        case .authentication, .forbidden, .notFound, .validation,
             .missingAPIKey, .invalidResponse, .malformedResponse, .emptyChoices,
             .cancelled, .healthUnavailable:
            return false
        }
    }
}
