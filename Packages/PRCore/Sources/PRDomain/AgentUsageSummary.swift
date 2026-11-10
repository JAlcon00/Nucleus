//
//  AgentUsageSummary.swift
//  PRDomain
//
//  SCRUM-273 (PR-I004, RNF-012, ADR-0005): cuánto gasta cada llamada a la IA. El registro
//  no lleva texto del usuario ni del modelo, ni identificadores personales: sólo la
//  operación, los tokens, los milisegundos y si respondió o falló (y por qué). El resumen es
//  puro y determinista; el LLM no participa. El costo en dinero no se calcula: falta el
//  precio del proveedor (ADR-0005).
//

import Foundation

/// Qué se le pidió a la IA.
public enum AgentOperation: String, Codable, Sendable, Hashable, CaseIterable {
    /// El entrenador interpretando una frase (SCRUM-272). "¿Por qué?" no llama a la IA.
    case coachInterpret
    /// Proponer ajustes del plan (SCRUM-205).
    case planPersonalization
    /// Explicar el plan, "Por qué tu plan es así" (SCRUM-205).
    case planRationale
}

/// Por qué no respondió la IA.
public enum AgentCallFailure: String, Codable, Sendable, Hashable, CaseIterable {
    case timeout
    case network
    case invalidResponse
    case cancelled
    case unavailable
}

/// Cómo terminó una llamada.
public enum AgentCallOutcome: Codable, Sendable, Hashable {
    case answered
    case failed(AgentCallFailure)

    public var isFallback: Bool {
        switch self {
        case .answered: return false
        case .failed: return true
        }
    }
}

/// Una llamada a la IA, sin texto.
public struct AgentUsageRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: Date
    public let operation: AgentOperation
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let reasoningTokens: Int?
    public let durationMilliseconds: Int
    public let outcome: AgentCallOutcome

    public init(
        id: UUID,
        date: Date,
        operation: AgentOperation,
        promptTokens: Int?,
        completionTokens: Int?,
        reasoningTokens: Int?,
        durationMilliseconds: Int,
        outcome: AgentCallOutcome
    ) {
        self.id = id
        self.date = date
        self.operation = operation
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.outcome = outcome
    }

    /// Entrada más salida, si el proveedor reportó las dos.
    public var totalTokens: Int? {
        guard let promptTokens, let completionTokens else { return nil }
        return promptTokens + completionTokens
    }
}

/// El resumen de una operación.
public struct AgentUsageRow: Sendable, Equatable {
    public let operation: AgentOperation
    public let calls: Int
    /// Mediana de la latencia (rango más cercano), en milisegundos.
    public let medianMilliseconds: Int
    /// Percentil 95 de la latencia (rango más cercano), en milisegundos.
    public let p95Milliseconds: Int
    /// Promedio de tokens totales de las llamadas que los reportaron; `nil` si ninguna.
    public let averageTotalTokens: Int?
    /// Cuántas cayeron al respaldo local.
    public let fallbacks: Int
}

public enum AgentUsageSummary {
    /// Una fila por operación con al menos una llamada, en el orden de `AgentOperation`.
    /// Sin llamadas, ninguna fila: no se inventan números.
    public static func rows(for records: [AgentUsageRecord]) -> [AgentUsageRow] {
        AgentOperation.allCases.compactMap { operation in
            let calls = records.filter { $0.operation == operation }
            guard !calls.isEmpty else { return nil }
            let durations = calls.map(\.durationMilliseconds).sorted()
            let tokens = calls.compactMap(\.totalTokens)
            return AgentUsageRow(
                operation: operation,
                calls: calls.count,
                medianMilliseconds: nearestRank(0.5, of: durations),
                p95Milliseconds: nearestRank(0.95, of: durations),
                averageTotalTokens: tokens.isEmpty ? nil : Int((Double(tokens.reduce(0, +)) / Double(tokens.count)).rounded()),
                fallbacks: calls.filter(\.outcome.isFallback).count
            )
        }
    }

    /// Percentil por rango más cercano: el valor en la posición ⌈p·n⌉ de la lista ordenada.
    /// `sorted` no está vacía.
    static func nearestRank(_ percentile: Double, of sorted: [Int]) -> Int {
        let rank = Int((percentile * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
