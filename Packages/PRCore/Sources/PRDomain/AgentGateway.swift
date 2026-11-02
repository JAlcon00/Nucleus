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
    /// Pide un diagnóstico ("me duele el hombro, ¿qué tengo?"): no se responde (SCRUM-33).
    /// La app dice que eso lo valora un profesional y ofrece registrar el dolor.
    case declinesDiagnosis
}

/// Por qué respondió el respaldo local en vez del backend (SCRUM-33): la app sigue
/// funcionando y puede avisarlo.
public enum AgentGatewayFallback: Sendable, Equatable {
    /// No hay backend configurado (offline-first).
    case noBackend
    /// El backend no respondió dentro del tiempo límite.
    case timeout
    /// El backend falló o respondió vacío.
    case backendFailure
}

/// Respuesta del gateway con el aviso de respaldo, si lo hubo.
public struct AgentGatewayReply<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value
    /// `nil`: respondió el backend a tiempo.
    public let fallback: AgentGatewayFallback?

    public init(value: Value, fallback: AgentGatewayFallback?) {
        self.value = value
        self.fallback = fallback
    }
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

/// Policy de timeout/retry con margen ACOTADO. El tiempo límite es por intento y distinto
/// para interpretar y para explicar (SCRUM-33).
public struct AgentGatewayTiming: Sendable, Equatable {
    public var interpretTimeoutSeconds: TimeInterval
    public var explainTimeoutSeconds: TimeInterval
    public var maxRetries: Int
    public var backoffSeconds: TimeInterval

    /// El mismo tiempo límite para interpretar y para explicar.
    public init(timeoutSeconds: TimeInterval, maxRetries: Int, backoffSeconds: TimeInterval) throws {
        try self.init(
            interpretTimeoutSeconds: timeoutSeconds,
            explainTimeoutSeconds: timeoutSeconds,
            maxRetries: maxRetries,
            backoffSeconds: backoffSeconds
        )
    }

    public init(
        interpretTimeoutSeconds: TimeInterval,
        explainTimeoutSeconds: TimeInterval,
        maxRetries: Int,
        backoffSeconds: TimeInterval
    ) throws {
        guard interpretTimeoutSeconds > 0, explainTimeoutSeconds > 0, maxRetries >= 0, backoffSeconds >= 0 else {
            throw DomainValidationError.invalidAgentGatewayTiming
        }
        self.interpretTimeoutSeconds = interpretTimeoutSeconds
        self.explainTimeoutSeconds = explainTimeoutSeconds
        self.maxRetries = maxRetries
        self.backoffSeconds = backoffSeconds
    }

    private init(uncheckedInterpret interpret: TimeInterval, explain: TimeInterval) {
        self.interpretTimeoutSeconds = interpret
        self.explainTimeoutSeconds = explain
        self.maxRetries = 0
        self.backoffSeconds = 0
    }

    /// Lo estándar (SCRUM-33): interpretar en 10 s y explicar en 18 s, sin reintentos (el
    /// cliente del proveedor ya reintenta lo reintentable). Pasado eso responde el respaldo.
    public static let standard = AgentGatewayTiming(uncheckedInterpret: 10, explain: 18)

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

        // Restricción de tiempo: "solo 30 min", "tengo 30 minutos". Dos cantidades distintas
        // ("30 o 45 minutos") no se adivinan (SCRUM-33).
        switch minutesMention(in: trimmed) {
        case .one(let minutes):
            return .intent(.setTimeConstraint(.hard(minutes: minutes)))
        case .ambiguous:
            return .needsClarification
        case .none:
            break
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

        // Objetivo / fase deterministas. "Cambiar de gym" sin decir a cuál pide aclarar:
        // antes inventaba un `GymID()` nuevo (SCRUM-33).
        switch trimmed {
        case "cambiar objetivo a hipertrofia", "objetivo hipertrofia":
            return .intent(.changeGoal(.hypertrophy))
        case "objetivo fuerza", "cambiar objetivo a fuerza":
            return .intent(.changeGoal(.strength))
        case "fase de definición", "deficit":
            return .intent(.changePhase(.deficit))
        default:
            return .needsClarification
        }
    }

    /// Cuántas cantidades de minutos distintas menciona el texto.
    private enum MinutesMention {
        case none
        case one(Int)
        case ambiguous
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

    private func minutesMention(in text: String) -> MinutesMention {
        // "solo X min", "X minutos", "tengo X minutos"; "30 o 45 minutos" cuenta las dos.
        let pattern = #"(\d+)\s*(o|y|a|-)?\s*(\d+)?\s*(min|minutos|minuto)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return .none }
        let values = Set(
            String(text[range])
                .split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
        )
        guard values.count == 1, let value = values.first else {
            return values.isEmpty ? .none : .ambiguous
        }
        return value > 0 ? .one(value) : .none
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
        await interpretReply(text: text, context: context).value
    }

    public func explain(facts: [DecisionFact]) async -> ExplainResponse {
        await explainReply(facts: facts).value
    }

    /// Interpreta y dice si respondió el respaldo local y por qué (SCRUM-33). Antes de nada,
    /// una pregunta de diagnóstico se declina sin llegar al modelo; después, una intención
    /// con datos imposibles pide aclarar y una nota que el usuario no dijo se quita.
    public func interpretReply(text: String, context: AgentContext) async -> AgentGatewayReply<AgentInterpretation> {
        guard !MedicalBoundary.asksForDiagnosis(text) else {
            return AgentGatewayReply(value: .declinesDiagnosis, fallback: nil)
        }
        guard let transport else {
            return AgentGatewayReply(value: checked(localInterpreter.interpret(text: text, context: context), text: text), fallback: .noBackend)
        }

        let request = InterpretRequest(text: text, context: context)
        var failure = AgentGatewayFallback.backendFailure
        for attempt in 0..<timing.totalAttempts {
            if attempt > 0 {
                // Backoff acotado (0 es instantáneo en tests).
                try? await Task.sleep(nanoseconds: UInt64(timing.backoffSeconds * 1_000_000_000))
            }
            do {
                let response = try await Self.withTimeout(timing.interpretTimeoutSeconds) {
                    try await transport.interpret(request)
                }
                guard !response.needsClarification, let intent = response.intent else {
                    return AgentGatewayReply(value: .needsClarification, fallback: nil)
                }
                return AgentGatewayReply(value: checked(.intent(intent), text: text), fallback: nil)
            } catch {
                // timeout/backendFailure → reintentar o caer al respaldo en el último intento.
                failure = Self.fallbackReason(for: error)
            }
        }
        return AgentGatewayReply(value: checked(localInterpreter.interpret(text: text, context: context), text: text), fallback: failure)
    }

    /// Explica y dice si respondió el respaldo local y por qué (SCRUM-33).
    public func explainReply(facts: [DecisionFact]) async -> AgentGatewayReply<ExplainResponse> {
        guard let transport else {
            return AgentGatewayReply(value: localExplainer.explain(facts: facts), fallback: .noBackend)
        }
        let request = ExplainRequest(facts: facts)
        var failure = AgentGatewayFallback.backendFailure
        for attempt in 0..<timing.totalAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(timing.backoffSeconds * 1_000_000_000))
            }
            do {
                let response = try await Self.withTimeout(timing.explainTimeoutSeconds) {
                    try await transport.explain(request)
                }
                if response.text != nil {
                    return AgentGatewayReply(value: response, fallback: nil)
                }
                // Respuesta vacía → tratar como fallo y caer al respaldo local.
                failure = .backendFailure
            } catch {
                failure = Self.fallbackReason(for: error)
            }
        }
        return AgentGatewayReply(value: localExplainer.explain(facts: facts), fallback: failure)
    }

    /// Una intención con datos imposibles pide aclarar; sus notas quedan sólo si son literales.
    private func checked(_ interpretation: AgentInterpretation, text: String) -> AgentInterpretation {
        guard case .intent(let intent) = interpretation else { return interpretation }
        guard AgentIntentValidator.problem(in: intent) == nil else { return .needsClarification }
        return .intent(AgentIntentValidator.keepingOnlyLiteralNotes(intent, userText: text))
    }

    private static func fallbackReason(for error: any Error) -> AgentGatewayFallback {
        (error as? AgentGatewayError) == .timeout ? .timeout : .backendFailure
    }

    /// Corre `operation` con tiempo límite (bug 13: antes no se usaba). Si se pasa, cancela
    /// la operación y lanza `.timeout`; el transporte debe respetar la cancelación, como
    /// `URLSession`.
    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AgentGatewayError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AgentGatewayError.timeout }
            return first
        }
    }
}
