//
//  LLMBackendTransportTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del adaptador `LLMBackendTransport` (PR-1608, Phase N2): unir `LLMProvider`
//  con el contrato del dominio `AgentBackendTransport`. El LLM interpreta/explica pero
//  NUNCA decide: la salida se valida por schema local y ante cualquier fallo cae a
//  `needsClarification` (falla segura).
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

@Suite("LLMBackendTransport adapter (PR-1608, Phase N2)")
struct LLMBackendTransportTests {

    private func transport(returning raw: String) -> LLMBackendTransport {
        LLMBackendTransport(
            provider: MockLLMProvider(result: .success(AgentResponse(text: raw, finishReason: .stop)))
        )
    }

    // MARK: - interpret

    @Test("Interpreta JSON válido a AgentIntent")
    func interpretValidIntent() async throws {
        let t = transport(returning: #"{"intent":"setTimeConstraint","payload":{"value":"hard:45"}}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "solo tengo 45 min", context: AgentContext())
        )
        #expect(!response.needsClarification)
        #expect(response.intent == .setTimeConstraint(.hard(minutes: 45)))
    }

    @Test("Interpreta JSON con code fence")
    func interpretCodeFenced() async throws {
        let t = transport(returning: "```json\n{\"intent\":\"changeGoal\",\"payload\":{\"value\":\"hypertrophy\"}}\n```")
        let response = try await t.interpret(
            InterpretRequest(text: "cambiar objetivo a hipertrofia", context: AgentContext())
        )
        #expect(response.intent == .changeGoal(.hypertrophy))
    }

    @Test("Devuelve needsClarification ante intencion ambigua")
    func interpretNeedsClarification() async throws {
        let t = transport(returning: #"{"intent":"needsClarification"}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "haz lo mejor", context: AgentContext())
        )
        #expect(response.needsClarification)
        #expect(response.intent == nil)
    }

    @Test("Devuelve needsClarification ante JSON malformado (falla segura)")
    func interpretMalformed() async throws {
        let t = transport(returning: "no soy JSON")
        let response = try await t.interpret(
            InterpretRequest(text: "algo raro", context: AgentContext())
        )
        #expect(response.needsClarification)
        #expect(response.intent == nil)
    }

    @Test("Devuelve needsClarification ante tipo inválido en el payload (schema local)")
    func interpretInvalidPayload() async throws {
        let t = transport(returning: #"{"intent":"setTimeConstraint","payload":{"value":123}}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "x", context: AgentContext())
        )
        #expect(response.needsClarification)
        #expect(response.intent == nil)
    }

    @Test("El LLM no decide: sólo obtiene intent; sólido ante JSON con payload extra")
    func interpretIgnoresNoise() async throws {
        let t = transport(returning: #"{"intent":"reportPain","payload":{"value":{"level":3,"notes":"no"}},"garbage":42}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "me duele", context: AgentContext())
        )
        #expect(response.intent != nil)
    }

    @Test("Repara comas finales sobrantes en la salida del LLM")
    func interpretTrailingCommaRepair() async throws {
        // Artefacto común: coma antes del cierre `}` al final del objeto.
        let t = transport(returning: #"{"intent":"reportPain","payload":{"value":{"level":3,"notes":"x"}},}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "me duele", context: AgentContext())
        )
        #expect(!response.needsClarification)
        #expect(response.intent != nil)
    }

    @Test("Repara comas finales dentro del payload")
    func interpretTrailingCommaInsidePayload() async throws {
        // Coma dentro del objeto interno del payload.
        let t = transport(returning: #"{"intent":"reportPain","payload":{"value":{"level":3,}}}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "dolor fuerte", context: AgentContext())
        )
        #expect(!response.needsClarification)
        #expect(response.intent != nil)
    }

    @Test("Falla segura si ni siquiera el payload reparado decodifica")
    func interpretUnrepairableMalformed() async throws {
        // Coma final + valor fuera de rango de PainLevel → sigue siendo needsClarification.
        let t = transport(returning: #"{"intent":"reportPain","payload":{"value":{"level":9,}}}"#)
        let response = try await t.interpret(
            InterpretRequest(text: "dolor", context: AgentContext())
        )
        #expect(response.needsClarification)
        #expect(response.intent == nil)
    }

    // MARK: - explain

    @Test("Explica a partir de los facts provistos")
    func explainReasons() async throws {
        let t = transport(returning: "Fatiga alta\nSin recuperación")
        let response = try await t.explain(ExplainRequest(facts: [
            DecisionFact(key: "nivel_fatiga", value: "alto"),
            DecisionFact(key: "recuperacion", value: "baja"),
        ]))
        #expect(response.text?.contains("Fatiga") == true)
        #expect(response.reasons.count == 2)
    }

    @Test("Explica con facts vacíos sin inventar")
    func explainEmptyFacts() async throws {
        let t = transport(returning: "Decision registrada en el plan.")
        let response = try await t.explain(ExplainRequest(facts: []))
        #expect(response.reasons.count == 1)
        #expect(!(response.text?.isEmpty ?? true))
    }

    @Test("Quita bullets y numeración de cada razón")
    func explainStripsBulletsAndNumbers() async throws {
        let t = transport(returning: "- Fatiga alta\n2. Sin recuperación\n")
        let response = try await t.explain(ExplainRequest(facts: [
            DecisionFact(key: "nivel_fatiga", value: "alto"),
            DecisionFact(key: "recuperacion", value: "baja"),
        ]))
        #expect(response.reasons == ["Fatiga alta", "Sin recuperación"])
    }

    @Test("Limpia CRLF y limita a 4 razones")
    func explainLimitsToFourReasons() async throws {
        let raw = (1...6).map { "razón \($0)" }.joined(separator: "\r\n")
        let t = transport(returning: raw)
        let response = try await t.explain(ExplainRequest(facts: [
            DecisionFact(key: "k1", value: "v1"),
        ]))
        #expect(response.reasons.count == 4)
    }

    @Test("Sin razones parseables devuelve texto vacío (el gateway cae a fallback local)")
    func explainUnparseableFallsEmpty() async throws {
        let t = transport(returning: "\n   \n")
        let response = try await t.explain(ExplainRequest(facts: [
            DecisionFact(key: "a", value: "b"),
        ]))
        #expect(response.reasons.isEmpty)
        #expect(response.text == nil)
    }

    // MARK: - Determinismo: failure en transporte → error (el gateway cae a fallback local)

    @Test("Si el provider falla, interpret lanza y el gateway cae a fallback")
    func providerFailurePropagates() async throws {
        let failing = LLMBackendTransport(
            provider: MockLLMProvider(result: .failure(.network))
        )
        do {
            _ = try await failing.interpret(InterpretRequest(text: "solo 30 min", context: AgentContext()))
            Issue.record("debería lanzar")
        } catch {
            let timing = try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 0, backoffSeconds: 0)
            let gateway = AgentGateway(transport: failing, timing: timing)
            let result = await gateway.interpret(text: "solo 30 min", context: AgentContext())
            // Fallback local determinista reconoce el patrón de minutos.
            #expect(result == .intent(.setTimeConstraint(.hard(minutes: 30))))
        }
    }
}
