//
//  NVIDIANIMProvider.swift
//  PRCore
//
//  Created by PR.
//
//  Proveedor self-hosted NVIDIA NIM (NEMOTRON_3_5_LIGHTNING_API.md §24, Phase N7, PR-1608).
//
//  Cuando el modelo se despliega en NIM, el endpoint OpenAI-compatible típico es nuestro
//  host (`http://localhost:8000/v1` o el host real del cluster). `NVIDIANIMProvider` reutiliza
//  `NVIDIAOpenAICompatibleClient` (mismo payload/error mapping/retry/streaming que el hosted)
//  y añade los health endpoints de NIM (§24): `GET /v1/health/live` y `GET /v1/health/ready`.
//
//  CONTRATO (§23/§47): implementa el mismo `LLMProvider` que `NVIDIAHostedProvider`, con
//  parámetros wire idénticos — sólo cambia baseURL, model (served name) y auth (nuestra
//  infraestructura, no la key NVIDIA). El dominio/transporte sólo depende de `LLMProvider`,
//  por lo que migrar `hosted → NIM` no requiere tocar ni el engine ni el transporte.
//

import Foundation

/// Configuración del provider NIM self-hosted.
public struct NVIDIANIMConfig: Sendable {
    /// Endpoint base del NIM (`/v1`); p. ej. `http://localhost:8000/v1`.
    public var baseURL: URL
    /// Nombre del modelo servido por el NIM (ditinto del model ID hosted, §47).
    public var model: String
    /// Auth de NUESTRA infraestructura (token Bearer opcional). `nil` → peticiones sin
    /// header (despliegue NIM sin auth). NUNCA la key NVIDIA del hosted.
    public var apiKeyProvider: (@Sendable () -> String?)?
    public var timeoutSeconds: TimeInterval
    public var maxRetries: Int

    public init(
        baseURL: URL = URL(string: "http://localhost:8000/v1")!,
        model: String = "nemotron-3.5-lightning-30b",
        apiKeyProvider: (@Sendable () -> String?)? = nil,
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

/// Estado de salud de un endpoint NIM (spec §24).
public enum NIMHealthStatus: Sendable, Equatable {
    /// El endpoint responde y el modelo está servido (`/v1/health/live` → 2xx).
    case live
    /// El endpoint responde y está listo para inferencia (`/v1/health/ready` → 2xx).
    case ready
    /// El endpoint respondió pero con estado no exitoso.
    case notLive(status: Int)
    /// El endpoint no fue alcanzable/red inválida.
    case unreachable
}

/// Body de los health endpoints de NIM (§24): `{"object":"health.response","message":"...","status":"..."}`.
public struct NIMHealthResponse: Decodable, Sendable, Equatable {
    public let object: String?
    public let message: String?
    public let status: String?

    public init(object: String? = nil, message: String? = nil, status: String? = nil) {
        self.object = object
        self.message = message
        self.status = status
    }
}

/// Proveedor que habla con un NIM self-hosted (Phase N7).
public struct NVIDIANIMProvider: LLMProvider {
    public let config: NVIDIANIMConfig
    private let client: NVIDIAOpenAICompatibleClient

    public init(config: NVIDIANIMConfig = NVIDIANIMConfig(), session: URLSession? = nil) {
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

    /// Chat Completions OpenAI-compatible (mismo wire contract que el hosted).
    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        try await client.complete(request)
    }

    /// Streaming SSE (mismo wire contract que el hosted).
    public func stream(_ request: AgentRequest) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        client.stream(request)
    }

    // MARK: - Health endpoints (§24)

    /// Consulta `GET /v1/health/live` → `.live` si responde 2xx, `.notLive`/`.unreachable` en otro caso.
    public func isLive() async -> NIMHealthStatus {
        await healthStatus(path: "health/live", target: .live)
    }

    /// Consulta `GET /v1/health/ready` → `.ready` si responde 2xx, `.notLive`/`.unreachable` en otro caso.
    public func isReady() async -> NIMHealthStatus {
        await healthStatus(path: "health/ready", target: .ready)
    }

    /// Consulta ambos endpoints; útil para el chequeo de despliegue previo a usar el provider.
    public func health() async -> (live: NIMHealthStatus, ready: NIMHealthStatus) {
        async let live = isLive()
        async let ready = isReady()
        return await (live, ready)
    }

    private func healthStatus(path: String, target: NIMHealthStatus) async -> NIMHealthStatus {
        do {
            let (status, body) = try await client.get(path)
            guard (200..<300).contains(status) else {
                return .notLive(status: status)
            }
            // Decodificar (best-effort) el body para validar el contrato sin exigirlo.
            if !body.isEmpty {
                if let decoded = try? JSONDecoder().decode(NIMHealthResponse.self, from: body) {
                    _ = decoded // contrato §24: {object,message,status}; no lo exigimos para 2xx
                }
            }
            return target
        } catch {
            return .unreachable
        }
    }
}
