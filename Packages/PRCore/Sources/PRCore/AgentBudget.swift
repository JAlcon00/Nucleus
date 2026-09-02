//
//  AgentBudget.swift
//  PRCore
//
//  Created by PR.
//
//  Medición de uso y presupuesto de reasoning (NEMOTRON_3_5_LIGHTNING_API.md §40, §45,
//  Phase N6 "budget measurements"). Provider-agnostic y determinista:
//    - `AgentUsage`: token usage + latencia + reasoning tokens consumidos.
//    - `ReasoningBudgetPolicy`: valida que el presupuesto solicitado esté en un rango
//      seguro (§35 no usar 16384 por rutina) y detecta overrun del budget de reasoning.
//
//  INVARIANTES (promptMaster §20.5, AGENTS "no rely on LLM for deterministic calcs"):
//  la medición de tokens y el presupuesto son cálculos deterministas locales; el LLM
//  nunca participa. Estos datos sirven para trazabilidad de coste/latencia, no para
//  decisiones de entrenamiento.
//

import Foundation

/// Uso provider-agnostic de un único run del LLM (Phase N6). `NVIDIAChatUsage` es del
/// wire format; `AgentUsage` es el valor de dominio que viaja en `AgentResponse`.
public struct AgentUsage: Sendable, Equatable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var reasoningTokens: Int?
    /// Milisegundos transcurridos del run (latencia, §45 "latency is measured").
    public var durationMilliseconds: Int?

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.durationMilliseconds = durationMilliseconds
    }

    /// Tokens totales deducidos de prompt+completion (cuando ambos están presentes).
    public var totalTokens: Int? {
        if let promptTokens, let completionTokens { return promptTokens + completionTokens }
        return nil
    }
}

// MARK: - Budget de reasoning

/// Evaluación determinista del presupuesto de reasoning de un run.
public struct ReasoningBudgetAssessment: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        /// El run usó thinking pero el provider no reportó reasoning tokens (sin dato).
        case noReasoningMetrics
        /// El budget solicitado excede el rango seguro de operación (§35) o es inválido.
        case outOfSafeRange
        /// El run se mantuvo dentro del budget solicitado.
        case withinBudget
        /// El run excedió el budget de reasoning solicitado.
        case overrun
    }

    public var status: Status
    /// Budget de reasoning solicitado (nil si thinking OFF/inválido).
    public var requestedBudget: Int?
    /// Reasoning tokens efectivamente consumidos (nil si no medidos).
    public var consumedReasoningTokens: Int?

    public init(status: Status, requestedBudget: Int?, consumedReasoningTokens: Int?) {
        self.status = status
        self.requestedBudget = requestedBudget
        self.consumedReasoningTokens = consumedReasoningTokens
    }

    /// ¿El run consumió más reasoning tokens de los presupuestados?
    public var isOverrun: Bool { status == .overrun }
}

/// Aplica el rango seguro de operación del budget de reasoning (§35) y mide overrun.
public enum ReasoningBudgetPolicy {

    /// Rango seguro de budget razonable por operación de gimnasio (§35: NO usar 16384
    /// por rutina). Valores fuera de 0...8192 se consideran potencialmente inapropiados
    /// para interacciones habituales (coste/latencia), salvo análisis complejos explícitos.
    public static let safeBudgetRange = 0...(8192)

    /// Evalúa un run de reasoning contra el budget solicitado de forma determinista.
    ///
    /// - Parameters:
    ///   - requestedBudget: `reasoning_budget` enviado en el request (preset).
    ///   - thinkingEnabled: si el preset tenía thinking ON.
    ///   - usage: medición del run (para `reasoningTokens`/`completionTokens`).
    public static func assess(
        requestedBudget: Int?,
        thinkingEnabled: Bool,
        usage: AgentUsage?
    ) -> ReasoningBudgetAssessment {
        let consumed = usage?.reasoningTokens

        if !thinkingEnabled {
            return ReasoningBudgetAssessment(status: .noReasoningMetrics, requestedBudget: nil, consumedReasoningTokens: consumed)
        }

        if let budget = requestedBudget, !safeBudgetRange.contains(budget) {
            return ReasoningBudgetAssessment(status: .outOfSafeRange, requestedBudget: budget, consumedReasoningTokens: consumed)
        }

        guard let budget = requestedBudget, let consumed else {
            return ReasoningBudgetAssessment(status: .noReasoningMetrics, requestedBudget: requestedBudget, consumedReasoningTokens: consumed)
        }

        let status: ReasoningBudgetAssessment.Status = consumed > budget ? .overrun : .withinBudget
        return ReasoningBudgetAssessment(status: status, requestedBudget: budget, consumedReasoningTokens: consumed)
    }
}
