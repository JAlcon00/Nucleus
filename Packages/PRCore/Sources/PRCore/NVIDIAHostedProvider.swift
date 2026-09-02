//
//  NVIDIAHostedProvider.swift
//  PRCore
//
//  Created by PR.
//
//  Proveedor NVIDIA Hosted (NEMOTRON_3_5_LIGHTNING_API.md §23, Phase N1, PR-1608).
//
//  Mapea un `AgentRequest` provider-agnostic al payload de Chat Completions del hosted
//  endpoint (`https://integrate.api.nvidia.com/v1`), ejecuta la llamada, mapea errores (§34)
//  y aplica retry acotado (§35). Delega el wire OpenAI-compatible en
//  `NVIDIAOpenAICompatibleClient` (compartido con `NVIDIANIMProvider`, Phase N7) para
//  garantizar contratos de proveedor idénticos (§23/§47).
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
    /// El streaming fue cancelado por el cliente/tarea (no es un fallo de red).
    case cancelled
    /// El endpoint de salud de NIM no devolvió un estado esperado (Phase N7).
    case healthUnavailable(status: Int)
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
        // Por defecto el modo `.fast` se usa para routing simple de tools → fastAgent.
        forMode(mode, output: .text)
    }

    /// Preset según modo + requerimiento de salida (Phase N6, §40). El spec separa
    /// `FAST_STRUCTURED` (intent/entidad/JSON, temp 0.0) de `FAST_AGENT` (routing simple,
    /// temp 0.1): `.fast` + salida JSON requiere machine determinista → fastStructured.
    public static func forMode(_ mode: AgentExecutionMode, output: AgentOutputRequirement) -> NVIDIAProviderPreset {
        switch mode {
        case .fast:
            return output == .json ? fastStructured : fastAgent
        case .reasoning:
            return reasoning
        case .deepReasoning:
            return deep
        }
    }
}

/// Proveedor que habla con el endpoint hosted de NVIDIA (Phase N1).
public struct NVIDIAHostedProvider: LLMProvider {
    public let config: NVIDIAHostedConfig
    private let client: NVIDIAOpenAICompatibleClient

    public init(config: NVIDIAHostedConfig = NVIDIAHostedConfig(), session: URLSession? = nil) {
        self.config = config
        self.client = NVIDIAOpenAICompatibleClient(
            baseURL: config.baseURL,
            model: config.model,
            apiKeyProvider: config.apiKeyProvider,
            timeoutSeconds: config.timeoutSeconds,
            maxRetries: config.maxRetries,
            session: session
        )
    }

    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        let apiKey = config.apiKeyProvider()
        guard let apiKey, !apiKey.isEmpty else {
            throw NVIDIAProviderError.missingAPIKey
        }
        return try await client.complete(request)
    }

    public func stream(_ request: AgentRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        guard let apiKey = config.apiKeyProvider(), !apiKey.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NVIDIAProviderError.missingAPIKey)
            }
        }
        return client.stream(request)
    }
}
