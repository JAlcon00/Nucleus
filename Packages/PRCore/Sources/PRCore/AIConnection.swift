//
//  AIConnection.swift
//  PRCore
//
//  SCRUM-204 (IA-3): conexión con la IA (NVIDIA) para desarrollo, sin exponer la llave.
//
//  Reglas (AGENTS §8 "never store secrets in client", promptMaster §5.4):
//  - Release: la IA queda apagada y la llave NI SIQUIERA se busca. La app funciona con
//    el motor local y textos de respaldo.
//  - Debug: la llave se lee en tiempo de ejecución sólo de la Mac del desarrollador
//    (variable `NVIDIA_API_KEY` o el `.env` ignorado por git; ver `NVIDIAKeyLoader`).
//    Nunca en el repo, nunca en el scheme compartido (guard `check_secrets.sh`).
//  - Antes de TestFlight la llave se mueve a un backend (historia aparte).
//  - Cualquier falla de la IA (sin red, tiempo agotado, respuesta inválida, cuota) se
//    convierte en "no disponible": nunca rompe ni bloquea el plan.
//

import Foundation

/// Tipo de compilación que corre (lo decide la app con `#if DEBUG`).
public enum AIBuildKind: Sendable, Hashable {
    case debug
    case release
}

/// Por qué la IA está apagada.
public enum AIOfflineReason: String, Sendable, Hashable, CaseIterable {
    /// Compilación Release: no lleva llave (hasta tener backend).
    case releaseBuild
    /// Debug sin llave configurada en esta Mac.
    case missingKey
    /// Pruebas de UI: siempre sin IA (deterministas y sin red).
    case uiTesting
}

/// Estado de la conexión, para mostrarlo y decidir si se intenta la IA.
public enum AIConnectionStatus: Sendable, Hashable {
    case live
    case offline(AIOfflineReason)

    public var isLive: Bool {
        switch self {
        case .live: return true
        case .offline: return false
        }
    }
}

/// Proveedor de la IA apagada: nunca llama a la red y siempre responde "no disponible".
public struct OfflineLLMProvider: LLMProvider {
    public init() {}

    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        throw NVIDIAProviderError.missingAPIKey
    }
}

/// Conexión resuelta: estado y proveedor listo para usar.
public struct AIConnection: Sendable {
    public let status: AIConnectionStatus
    public let provider: any LLMProvider

    public init(status: AIConnectionStatus, provider: any LLMProvider) {
        self.status = status
        self.provider = provider
    }

    /// Decide la conexión. En Release devuelve el proveedor apagado sin llamar a
    /// `keyLoader`; en Debug sólo se conecta si hay una llave no vacía.
    public static func resolve(
        build: AIBuildKind,
        keyLoader: @Sendable () -> String? = { NVIDIAKeyLoader.load() },
        session: URLSession? = nil
    ) -> AIConnection {
        switch build {
        case .release:
            return AIConnection(status: .offline(.releaseBuild), provider: OfflineLLMProvider())
        case .debug:
            guard let key = keyLoader()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                return AIConnection(status: .offline(.missingKey), provider: OfflineLLMProvider())
            }
            let config = NVIDIAHostedConfig(apiKeyProvider: { key })
            return AIConnection(status: .live, provider: NVIDIAHostedProvider(config: config, session: session))
        }
    }
}

extension NVIDIAProviderError {
    /// Código fijo para el log de diagnóstico (sin estados HTTP ni datos de la respuesta).
    public var diagnosticCode: StaticString {
        switch self {
        case .missingAPIKey: return "missingAPIKey"
        case .authentication: return "authentication"
        case .forbidden: return "forbidden"
        case .notFound: return "notFound"
        case .validation: return "validation"
        case .rateLimited: return "rateLimited"
        case .providerError: return "providerError"
        case .timeout: return "timeout"
        case .network: return "network"
        case .invalidResponse: return "invalidResponse"
        case .malformedResponse: return "malformedResponse"
        case .emptyChoices: return "emptyChoices"
        case .cancelled: return "cancelled"
        case .healthUnavailable: return "healthUnavailable"
        }
    }
}

/// Resultado de pedirle algo a la IA: una respuesta o "no disponible" con el motivo.
public enum AICoachOutcome: Sendable {
    case answer(AgentResponse)
    case unavailable(NVIDIAProviderError)
}

/// Fachada que la app usa para hablar con la IA: nunca lanza errores hacia la UI.
/// El llamador decide el respaldo (texto local) cuando la respuesta es `.unavailable`.
public struct AICoach: Sendable {
    public let connection: AIConnection

    public init(connection: AIConnection) {
        self.connection = connection
    }

    public func ask(_ request: AgentRequest) async -> AICoachOutcome {
        guard connection.status.isLive else { return .unavailable(.missingAPIKey) }
        do {
            return .answer(try await connection.provider.complete(request))
        } catch let error as NVIDIAProviderError {
            return .unavailable(error)
        } catch is CancellationError {
            return .unavailable(.cancelled)
        } catch {
            return .unavailable(.network)
        }
    }
}
