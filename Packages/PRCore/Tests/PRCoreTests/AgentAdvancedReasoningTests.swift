//
//  AgentAdvancedReasoningTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de Phase N6 — Advanced reasoning (NEMOTRON §40, §44, §45). Tres ejes:
//    1) selection de presets de reasoning según modo + salida (FAST_STRUCTURED vs FAST_AGENT);
//    2) budget measurements: `AgentUsage` (tokens + latencia + reasoningTokens),
//       decoding de usage del wire con `completion_tokens_details.reasoning_tokens`, y
//       `ReasoningBudgetPolicy` (rango seguro §35 + detección de overrun);
//    3) corpus de evals permanente de casos complejos (§44): se corre ante cambios de
//       prompt/modelo/proveedor/schema/contrato del engine. Determinista (sin red).
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

// MARK: - Mock local (no reusa el `MockURLProtocol` privado de NVIDIAProviderTests)

final class EvalURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: EvalURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = EvalURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func evalSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EvalURLProtocol.self]
    return URLSession(configuration: configuration)
}

// MARK: - 1) Reasoning presets (output-aware, §40)

@Suite("N6 · Reasoning presets (output-aware, §40)")
struct N6PresetSelectionTests {

    @Test("fast + JSON → FAST_STRUCTURED (temp 0.0, thinking OFF)")
    func fastJsonUsesStructured() {
        let preset = NVIDIAProviderPreset.forMode(.fast, output: .json)
        #expect(!preset.enableThinking)
        #expect(preset.reasoningBudget == nil)
        #expect(preset.temperature == 0.0)
    }

    @Test("fast + text (routing) → FAST_AGENT (temp 0.1)")
    func fastTextUsesAgent() {
        let preset = NVIDIAProviderPreset.forMode(.fast, output: .text)
        #expect(!preset.enableThinking)
        #expect(preset.temperature == 0.1)
    }

    @Test("reasoning y deepReasoning mantienen budget por §40")
    func reasoningAndDeepPresets() {
        let r = NVIDIAProviderPreset.forMode(.reasoning, output: .json)
        #expect(r.enableThinking)
        #expect(r.reasoningBudget == 2048)
        #expect(r.temperature == 0.4)

        let d = NVIDIAProviderPreset.forMode(.deepReasoning, output: .text)
        #expect(d.enableThinking)
        #expect(d.reasoningBudget == 4096)
        #expect(d.temperature == 0.5)
    }

    @Test("forMode(_:) por defecto mantiene compat (fast → fastAgent .text)")
    func legacyForModeUnchanged() {
        let preset = NVIDIAProviderPreset.forMode(.fast)
        #expect(preset.temperature == 0.1)
    }
}

// MARK: - 2) Budget measurements

@Suite("N6 · Budget measurements (§35, §45)")
struct N6BudgetMeasurementTests {

    // MARK: AgentUsage

    @Test("AgentUsage deduce total de prompt+completion")
    func usageTotal() {
        let u = AgentUsage(promptTokens: 100, completionTokens: 40)
        #expect(u.totalTokens == 140)
        let empty = AgentUsage(promptTokens: nil, completionTokens: 40)
        #expect(empty.totalTokens == nil)
    }

    @Test("AgentResponse expone usage + conveniencia legacy de tokens")
    func responseUsage() {
        let r = AgentResponse(
            text: "ok",
            usage: AgentUsage(promptTokens: 10, completionTokens: 5, reasoningTokens: 3, durationMilliseconds: 120)
        )
        #expect(r.usage?.promptTokens == 10)
        #expect(r.usage?.reasoningTokens == 3)
        #expect(r.usage?.durationMilliseconds == 120)
        #expect(r.promptTokens == 10)
        #expect(r.completionTokens == 5)
    }

    @Test("AgentResponse construye usage a partir de tokens legacy")
    func legacyTokensBuildUsage() {
        let r = AgentResponse(text: "ok", promptTokens: 7, completionTokens: 2)
        #expect(r.usage?.promptTokens == 7)
        #expect(r.usage?.completionTokens == 2)
    }

    // MARK: Decoding del usage wire (reasoning_tokens)

    @Test("Decodifica usage con completion_tokens_details.reasoning_tokens")
    func decodeReasoningTokens() throws {
        let data = Data("""
        {"prompt_tokens":20,"completion_tokens":30,"total_tokens":50,
         "completion_tokens_details":{"reasoning_tokens":12}}
        """.utf8)
        let usage = try JSONDecoder().decode(NVIDIAChatUsage.self, from: data)
        #expect(usage.promptTokens == 20)
        #expect(usage.completionTokens == 30)
        #expect(usage.totalTokens == 50)
        #expect(usage.reasoningTokens == 12)
    }

    @Test("Decodifica usage sin details (reasoningTokens nil)")
    func decodeWithoutDetails() throws {
        let data = Data("{\"prompt_tokens\":1,\"completion_tokens\":2}".utf8)
        let usage = try JSONDecoder().decode(NVIDIAChatUsage.self, from: data)
        #expect(usage.reasoningTokens == nil)
        #expect(usage.completionTokens == 2)
    }

    @Test("El provider compone AgentResponse.usage con reasoning y latencia")
    func providerPopulatesUsage() async throws {
        EvalURLProtocol.statusCode = 200
        EvalURLProtocol.responseData = Data("""
        {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],
         "usage":{"prompt_tokens":9,"completion_tokens":4,"completion_tokens_details":{"reasoning_tokens":2}}}
        """.utf8)
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }),
            session: evalSession()
        )
        let response = try await provider.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))
        #expect(response.usage?.promptTokens == 9)
        #expect(response.usage?.completionTokens == 4)
        #expect(response.usage?.reasoningTokens == 2)
        #expect(response.usage?.durationMilliseconds != nil)
    }

    // MARK: ReasoningBudgetPolicy

    @Test("Thinking OFF → noReasoningMetrics, sin budget")
    func policyThinkingOff() {
        let a = ReasoningBudgetPolicy.assess(requestedBudget: 2048, thinkingEnabled: false, usage: AgentUsage(reasoningTokens: 10))
        #expect(a.status == .noReasoningMetrics)
        #expect(a.requestedBudget == nil)
        #expect(!a.isOverrun)
    }

    @Test("Budget fuera del rango seguro → outOfSafeRange (§35: no 16384 por rutina)")
    func policyOutOfSafeRange() {
        let a = ReasoningBudgetPolicy.assess(requestedBudget: 16384, thinkingEnabled: true, usage: AgentUsage(reasoningTokens: 100))
        #expect(a.status == .outOfSafeRange)
        #expect(a.requestedBudget == 16384)
    }

    @Test("Sin métricas de reasoning → noReasoningMetrics")
    func policyNoMetrics() {
        let a = ReasoningBudgetPolicy.assess(requestedBudget: 2048, thinkingEnabled: true, usage: nil)
        #expect(a.status == .noReasoningMetrics)
    }

    @Test("Consumo dentro de budget → withinBudget")
    func policyWithinBudget() {
        let a = ReasoningBudgetPolicy.assess(requestedBudget: 2048, thinkingEnabled: true, usage: AgentUsage(reasoningTokens: 512))
        #expect(a.status == .withinBudget)
        #expect(!a.isOverrun)
    }

    @Test("Consumo que excede budget → overrun")
    func policyOverrun() {
        let a = ReasoningBudgetPolicy.assess(requestedBudget: 2048, thinkingEnabled: true, usage: AgentUsage(reasoningTokens: 3000))
        #expect(a.status == .overrun)
        #expect(a.isOverrun)
        #expect(a.consumedReasoningTokens == 3000)
    }
}

// MARK: - 3) Corpus de evals permanente (§44)

/// Corpus de evaluación permanente (§44): se re-ejecuta ante cambios de prompt,
/// modelo, proveedor, schema de tools o contrato del TrainingEngine. Aquí se ejecuta
/// de forma DETERMINISTA sobre el pipeline (transporte + fallback + schema), sin red.
@Suite("N6 · Complex evals (§44, corpus permanente)")
struct ComplexEvalCorpus {

    private func transport(_ raw: String) -> LLMBackendTransport {
        LLMBackendTransport(provider: MockLLMProvider(result: .success(AgentResponse(text: raw, finishReason: .stop))))
    }

    // MARK: Casos §44

    @Test("Eval: 'Hoy tengo 35 minutos.' → time adaptation (setTimeConstraint)")
    func evalTimeConstraint() async throws {
        let t = transport(#"{"intent":"setTimeConstraint","payload":{"value":"hard:35"}}"#)
        let r = try await t.interpret(InterpretRequest(text: "Hoy tengo 35 minutos.", context: AgentContext()))
        #expect(r.intent == .setTimeConstraint(.hard(minutes: 35)))
    }

    @Test("Eval: 'La máquina está ocupada.' → reorder/substitution (equipmentUnavailable)")
    func evalOccupiedMachine() async throws {
        let t = transport(#"{"intent":"equipmentUnavailable","payload":{"value":{"reference":{"equipmentType":"machine"},"reason":"occupied"}}}"#)
        let r = try await t.interpret(InterpretRequest(text: "La máquina está ocupada", context: AgentContext()))
        #expect(r.intent == .equipmentUnavailable(EquipmentReference(equipmentType: .machine), .occupied))
    }

    @Test("Eval invariable: el agente NUNCA diagnostica lesiones (reportPain, no diagnóstico)")
    func evalNoDiagnosis() async throws {
        // El intérprete estructura el reporte de dolor con región/notes; no produce una
        // afirmación diagnóstica en el JSON (el diagnóstico está prohibido por el prompt).
        let t = transport(#"{"intent":"reportPain","payload":{"value":{"level":3,"bodyRegion":"shoulder","notes":"dolor al elevar"}}}"#)
        let r = try await t.interpret(InterpretRequest(text: "Me duele el hombro", context: AgentContext()))
        #expect(r.intent == .reportPain(PainReport(level: .high, bodyRegion: .shoulder, notes: "dolor al elevar")))
    }

    @Test("Eval invariable: el agente nunca suma/decide doble conteo calórico")
    func evalNoDoubleCountCalories() async throws {
        // No existe intent para sumar kcal ni aprobar cifras: el schema no puede producir
        // un veredicto numérico de "700". Ante un mensaje así, el intérprete requiere
        // clarificación (la reconciliación de doble conteo es del engine/reporting, no del LLM).
        let t = transport(#"{"intent":"needsClarification"}"#)
        let r = try await t.interpret(InterpretRequest(text: "Quemé 400 en Apple Watch y 300 en la app, ¿son 700?", context: AgentContext()))
        #expect(r.needsClarification)
    }

    @Test("Eval invariable: tres horas NO triplican volumen ciegamente")
    func evalNoBlindTripleVolume() async throws {
        // setTimeConstraint es un DATO; la decisión de volumen es del engine. El intent no
        // contiene volumen calculado ⇒ el LLM jamás puede triplicar nada (scheme de intents).
        let t = transport(#"{"intent":"setTimeConstraint","payload":{"value":"flexible:180:15"}}"#)
        let r = try await t.interpret(InterpretRequest(text: "Hoy tengo tres horas.", context: AgentContext()))
        #expect(r.intent == .setTimeConstraint(.flexible(targetMinutes: 180, toleranceMinutes: 15)))
    }

    @Test("Eval invariable: subir 20kg→bench exige validación del engine, NO aprobación LLM")
    func evalNoBlindLoadApproval() async throws {
        // El agente no tiene intent para aprobar cargas; un pedido así es ambiguo/out-of-scope
        // y debe requerir clarificación (la validación de progresión es del engine).
        let r = LocalFallbackInterpreter().interpret(text: "Quiero subir 20 kg al bench hoy", context: AgentContext())
        #expect(r == .needsClarification)
    }

    // MARK: Fallback determinista (offline eval)

    @Test("Eval fallback: sin backend cae a intérprete local determinista")
    func evalFallbackInterpreter() async throws {
        let gateway = try AgentGateway(
            transport: nil,
            timing: AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 0, backoffSeconds: 0)
        )
        let time = await gateway.interpret(text: "solo tengo 30 min", context: AgentContext())
        #expect(time == .intent(.setTimeConstraint(.hard(minutes: 30))))
        let noIntent = await gateway.interpret(text: "haz lo mejor", context: AgentContext())
        #expect(noIntent == .needsClarification)
    }
}
