//
//  AgentGateway.swift
//  PRDomain
//
//  Created by PR.
//
//  Protocolo de gateway del agente (promptMaster §20.5, PR-1603).
//
//  El cliente NUNCA almacena claves de proveedor y conserva capacidad completa de
//  workout sin backend (§20.5). Este archivo define sólo el contrato puro de dominio:
//    - el transporte (`AgentBackendTransport`) que la capa de app implementa con HTTP;
//    - la policy de timing (timeout/retry) ACOTADA y configurable;
//    - un fallback local DETERMINISTA para `interpret` y `explain` cuando el backend
//      falla o no hay transporte (offline-first).
//  No hay aquí ningún código de red ni de claves: la app cliente no guarda secretos.
//

import Foundation

// MARK: - Errores

public enum AgentGatewayError: Error, Sendable, Equatable {
    case timeout
    case backendFailure
    case malformedResponse
    case unsupported
}

/// Resultado seguro de `interpret`. Nunca inventa intents: si no hay entendimiento
/// claro, devuelve `needsClarification` para que el caller pida reformulación.
public enum AgentInterpretation: Sendable, Equatable {
    case intent(AgentIntent)
    case needsClarification
}

// MARK: - Contexto de interpretación

/// Contexto estructurado y mínimo que el backend necesita para interpretar el texto.
/// Campos opcionales; no expone repositorio ni datos sensibles crudos.
public struct AgentContext: Sendable, Hashable {
    public var text: String
    public var activeRestrictionCount: Int
    public var painGateActive: Bool
    public var todaySessionStarted: Bool

    public init(
        text: String = "",
        activeRestrictionCount: Int = 0,
        painGateActive: Bool = false,
        todaySessionStarted: Bool = false
    ) {
        self.text = text
        self.activeRestrictionCount = activeRestrictionCount
        self.painGateActive = painGateActive
        self.todaySessionStarted = todaySessionStarted
    }
}

// MARK: - Requests / Responses (wire shape del transporte)

public struct InterpretRequest: Sendable, Equatable {
    public var text: String
    public var context: AgentContext

    public init(text: String, context: AgentContext) {
        self.text = text
        self.context = context
    }
}

public struct InterpretResponse: Sendable, Equatable {
    public var intent: AgentIntent?
    public var needsClarification: Bool

    public init(intent: AgentIntent? = nil, needsClarification: Bool = false) {
        self.intent = intent
        self.needsClarification = needsClarification
    }
}

public struct ExplainRequest: Sendable, Equatable {
    public var facts: [DecisionFact]

    public init(facts: [DecisionFact]) {
        self.facts = facts
    }
}

public struct ExplainResponse: Sendable, Equatable {
    public var text: String?
    public var reasons: [String]

    public init(text: String? = nil, reasons: [String] = []) {
        self.text = text
        self.reasons = reasons
    }
}

// MARK: - Timing policy (ACOTADA)

/// Policy de timeout/retry con margen ACOTADO.
public struct AgentGatewayTiming: Sendable, Equatable {
    public var timeoutSeconds: TimeInterval
    public var maxRetries: Int
    public var backoffSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval, maxRetries: Int, backoffSeconds: TimeInterval) throws {
        guard timeoutSeconds > 0, maxRetries >= 0, backoffSeconds >= 0 else {
            throw DomainValidationError.invalidAgentGatewayTiming
        }
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.backoffSeconds = backoffSeconds
    }

    /// Intentos totales (1 inicial + reintentos), siempre acotado.
    public var totalAttempts: Int { 1 + maxRetries }
}

// MARK: - Transporte del backend (la capa de app implementa HTTP)

/// Transporte del backend LLM. Implementación real (HTTP) vive fuera del dominio.
public protocol AgentBackendTransport: Sendable {
    func interpret(_ request: InterpretRequest) async throws -> InterpretResponse
    func explain(_ request: ExplainRequest) async throws -> ExplainResponse
}

// MARK: - Fallback local determinista

/// Interpretador local determinista para el flujo offline (PR-1603).
/// Reconoce SÓLO formas cortas y deterministas (sin NLU inventada); ante cualquier
/// duda devuelve `needsClarification` (seguro, §20.1 "unknown intent pide reformulación
/// o falla seguro").
public struct LocalFallbackInterpreter: Sendable {
    public init() {}

    public func interpret(text: String, context: AgentContext) -> AgentInterpretation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Restricción de tiempo: "solo 30 min", "tengo 30 minutos".
        if let minutes = extractMinutes(from: trimmed) {
            return .intent(.setTimeConstraint(.hard(minutes: minutes)))
        }

        // Equipo ocupado: "el bench está ocupado" / "la maquina esta ocupada".
        if let equipment = extractUnavailableEquipment(from: trimmed, pattern: Self.occupiedPattern) {
            return .intent(.equipmentUnavailable(
                EquipmentReference(equipmentType: equipment),
                .occupied
            ))
        }

        // Equipo inexistente en el gym: "no tienen hack squat" / "no hay cable".
        if let equipment = extractUnavailableEquipment(from: trimmed, pattern: Self.missingPattern) {
            return .intent(.equipmentUnavailable(
                EquipmentReference(equipmentType: equipment),
                .doesNotExist
            ))
        }

        // Objetivo / fase / gym deterministas.
        switch trimmed {
        case "cambiar objetivo a hipertrofia", "objetivo hipertrofia":
            return .intent(.changeGoal(.hypertrophy))
        case "objetivo fuerza", "cambiar objetivo a fuerza":
            return .intent(.changeGoal(.strength))
        case "fase de definición", "deficit":
            return .intent(.changePhase(.deficit))
        case "cambiar de gym":
            return .intent(.changeGym(GymID()))
        default:
            return .needsClarification
        }
    }

    // MARK: - Equipamiento (PR-1605)

    private static let occupiedPattern = #"\b(est[áa]|se encuentra)?\s*(ocupad[oa]|en uso|pillad[oa])"#
    private static let missingPattern = #"no (tienen|hay|ten[cg]amos|cuentan)"#

    /// Intenta detectar + mapear un equipo al que se refiere el texto. Devuelve
    /// `nil` si no hay ninguna palabra de equipo conocida (⇒ `needsClarification`).
    private func extractUnavailableEquipment(from text: String, pattern: String) -> EquipmentType? {
        // Mapeo determinista nombre → tipo. El dominio NO inventa instancias de
        // máquina: devuelve el tipo para que el caller resuelva la instancia.
        let keywords: [(EquipmentType, [String])] = [
            (.barbell, ["barra", "barbell", "barra olimpica"]),
            (.dumbbell, ["mancuerna", "dumbbell", "mancuernas"]),
            (.smithMachine, ["smith", "smitch"]),
            (.cable, ["cable", "polea", "crossover"]),
            (.machine, ["maquina", "prensa", "hack squat", "hack", "ackly", "press machine", "leg press", "bench", "banco", "press de banca", "banca"]),
            (.kettlebell, ["kettlebell", "pesa rusa"]),
            (.bands, ["bandas", "goma", "resistencia"]),
            (.sled, ["trineo", "sled"]),
            (.plateLoaded, ["lastre", "discos"]),
        ]

        // Debe haber patrón de ocupado/inexistente Y una palabra de equipo.
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }

        for (type, words) in keywords {
            for word in words where text.contains(word) {
                return type
            }
        }
        return nil
    }

    private func extractMinutes(from text: String) -> Int? {
        // "solo X min", "X minutos", "tengo X minutos"
        guard let range = text.range(of: #"(\d+)\s*(min|minutos|minuto)"#, options: .regularExpression) else {
            return nil
        }
        let token = String(text[range]).lowercased()
        let digits = token.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        return value
    }
}

/// Explicador local determinista (plantilla offline, PR-1606 fallback): construye
/// 1–4 razones concretas SÓLO a partir de los facts suministrados.
public struct LocalFallbackExplainer: Sendable {
    public init() {}

    public func explain(facts: [DecisionFact]) -> ExplainResponse {
        let reasons = facts
            .prefix(4)
            .map { "\($0.key): \($0.value)" }
        return ExplainResponse(
            text: reasons.isEmpty ? "Sin razones disponibles offline." : reasons.joined(separator: "\n"),
            reasons: reasons
        )
    }
}

// MARK: - Gateway coordinador

/// Coordina transporte + fallback local con retry ACOTADO. Si el transporte no está
/// configurado (sin backend) o falla/expira, resuelve localmente (offline-first).
public struct AgentGateway: Sendable {
    public let transport: (any AgentBackendTransport)? 
    public let timing: AgentGatewayTiming
    public let localInterpreter: LocalFallbackInterpreter
    public let localExplainer: LocalFallbackExplainer

    public init(
        transport: (any AgentBackendTransport)?,
        timing: AgentGatewayTiming,
        localInterpreter: LocalFallbackInterpreter = LocalFallbackInterpreter(),
        localExplainer: LocalFallbackExplainer = LocalFallbackExplainer()
    ) {
        self.transport = transport
        self.timing = timing
        self.localInterpreter = localInterpreter
        self.localExplainer = localExplainer
    }

    public func interpret(text: String, context: AgentContext) async -> AgentInterpretation {
        guard let transport else {
            // Sin backend: fallback local directo.
            return localInterpreter.interpret(text: text, context: context)
        }

        let request = InterpretRequest(text: text, context: context)
        let totalAttempts = timing.totalAttempts
        for attempt in 0..<totalAttempts {
            if attempt > 0 {
                // Backoff acotado (0 es instantáneo en tests).
                try? await Task.sleep(nanoseconds: UInt64(timing.backoffSeconds * 1_000_000_000))
            }
            do {
                let response = try await transport.interpret(request)
                if response.needsClarification {
                    return .needsClarification
                }
                if let intent = response.intent {
                    return .intent(intent)
                }
                return .needsClarification
            } catch {
                // timeout/backendFailure → reintentar o caer a fallback en el último intento.
                if attempt == totalAttempts - 1 {
                    return localInterpreter.interpret(text: text, context: context)
                }
            }
        }
        return localInterpreter.interpret(text: text, context: context)
    }

    public func explain(facts: [DecisionFact]) async -> ExplainResponse {
        guard let transport else {
            return localExplainer.explain(facts: facts)
        }
        let request = ExplainRequest(facts: facts)
        let totalAttempts = timing.totalAttempts
        for attempt in 0..<totalAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(timing.backoffSeconds * 1_000_000_000))
            }
            do {
                let response = try await transport.explain(request)
                if response.text != nil {
                    return response
                }
                // Respuesta vacía → tratar como fallo y caer a fallback local.
                if attempt == totalAttempts - 1 {
                    return localExplainer.explain(facts: facts)
                }
            } catch {
                if attempt == totalAttempts - 1 {
                    return localExplainer.explain(facts: facts)
                }
            }
        }
        return localExplainer.explain(facts: facts)
    }
}
