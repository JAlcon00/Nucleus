//
//  NVIDIAProviderTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del proveedor LLM NVIDIA Hosted (PR-1608, Phase N1): abstracción provider-
//  agnostic, mapeo de payload a Chat Completions, decoding de response, mapa de errores
//  y retry acotado. El key se inyecta en runtime — nunca embebido ni en tests.
//

import Foundation
import Testing
@testable import PRCore

// MARK: - URLProtocol mock para capturar requests y devolver respuestas controladas

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var captured: URLRequest?
    nonisolated(unsafe) static var capturedBody: Data?
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var shouldFail = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        MockURLProtocol.requestCount += 1
        if MockURLProtocol.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        MockURLProtocol.captured = request
        MockURLProtocol.capturedBody = MockURLProtocol.bodyData(of: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func jsonData(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

@Suite("NVIDIA Hosted LLM provider (PR-1608, Phase N1)", .serialized)
struct NVIDIAProviderTests {

    // MARK: - Presets por modo (§23, §40)

    @Test("Mapea presets por execution mode")
    func presetMapping() {
        let fast = NVIDIAProviderPreset.forMode(.fast)
        #expect(!fast.enableThinking)
        #expect(fast.temperature == 0.1)

        let reasoning = NVIDIAProviderPreset.forMode(.reasoning)
        #expect(reasoning.enableThinking)
        #expect(reasoning.reasoningBudget == 2048)
        #expect(reasoning.temperature == 0.4)

        let deep = NVIDIAProviderPreset.forMode(.deepReasoning)
        #expect(deep.enableThinking)
        #expect(deep.reasoningBudget == 4096)
        #expect(deep.temperature == 0.5)
    }

    // MARK: - Payload mapping a Chat Completions (§20, Appendix A)

    @Test("Mapea AgentRequest al payload de Fast")
    func fastPayloadMapping() async throws {
        MockURLProtocol.requestCount = 0
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "OK"], "finish_reason": "stop"]],
        ])

        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "nvapi-runtime" }),
            session: makeSession()
        )

        let request = AgentRequest(
            messages: [AgentMessage(role: "user", content: "Hoy solo tengo 45 minutos")],
            mode: .fast
        )
        let response = try await provider.complete(request)
        #expect(response.text == "OK")
        #expect(MockURLProtocol.requestCount == 1)

        let body = MockURLProtocol.capturedBody!
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["model"] as? String == "nvidia/nemotron-3.5-lightning-30b-a3b")
        #expect(json["temperature"] as? Double == 0.1)
        #expect(json["stream"] as? Bool == false)
        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "Hoy solo tengo 45 minutos")
    }

    @Test("Mapea AgentRequest al payload de Reasoning")
    func reasoningPayloadMapping() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = Data("""
        {"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
        """.utf8)

        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "nvapi-runtime" }),
            session: makeSession()
        )
        let request = AgentRequest(messages: [AgentMessage(role: "user", content: "x")], mode: .reasoning)

        _ = try await provider.complete(request)
        let body = MockURLProtocol.capturedBody!
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        #expect(json["temperature"] as? Double == 0.4)
        #expect(json["reasoning_budget"] as? Int == 2048)
        let kwargs = json["chat_template_kwargs"] as! [String: Any]
        #expect(kwargs["enable_thinking"] as? Bool == true)
    }

    @Test("Lee reasoning_content y finish_reason=length")
    func replyDecoding() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = Data("""
        {"choices":[{"message":{"content":"respuesta","reasoning_content":"raciocino"},"finish_reason":"length"}],
         "usage":{"prompt_tokens":10,"completion_tokens":20}}
        """.utf8)
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }),
            session: makeSession()
        )
        let response = try await provider.complete(
            AgentRequest(messages: [AgentMessage(role: "user", content: "x")])
        )
        #expect(response.text == "respuesta")
        #expect(response.reasoning == "raciocino")
        #expect(response.finishReason == .length)
        #expect(!response.isComplete)
        #expect(response.promptTokens == 10)
        #expect(response.completionTokens == 20)
    }

    // MARK: - Error mapping (§34)

    @Test("401 mapea a authentication (no reintenta)")
    func error401() async throws {
        MockURLProtocol.statusCode = 401
        MockURLProtocol.responseData = Data()
        MockURLProtocol.requestCount = 0
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }, maxRetries: 3),
            session: makeSession()
        )
        await #expect(throws: NVIDIAProviderError.authentication) {
            _ = try await provider.complete(AgentRequest(messages: []))
        }
        #expect(MockURLProtocol.requestCount == 1, "401 no se reintenta")
    }

    @Test("429 mapea a rateLimited y reintenta acotado")
    func error429() async throws {
        MockURLProtocol.statusCode = 429
        MockURLProtocol.responseData = Data()
        MockURLProtocol.requestCount = 0
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }, timeoutSeconds: 0.01, maxRetries: 2),
            session: makeSession()
        )
        await #expect(throws: NVIDIAProviderError.rateLimited) {
            _ = try await provider.complete(AgentRequest(messages: []))
        }
        #expect(MockURLProtocol.requestCount == 3, "429 se reintenta (1 + maxRetries acotado)")
    }

    @Test("422 mapea a validation (no reintenta)")
    func error422() async throws {
        MockURLProtocol.statusCode = 422
        MockURLProtocol.responseData = Data()
        MockURLProtocol.requestCount = 0
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }, maxRetries: 5),
            session: makeSession()
        )
        await #expect(throws: NVIDIAProviderError.validation) {
            _ = try await provider.complete(AgentRequest(messages: []))
        }
        #expect(MockURLProtocol.requestCount == 1)
    }

    @Test("Missing API key falla antes de la red")
    func missingKey() async throws {
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { nil }),
            session: makeSession()
        )
        await #expect(throws: NVIDIAProviderError.missingAPIKey) {
            _ = try await provider.complete(AgentRequest(messages: []))
        }
    }

    @Test("Red no disponible mapea a network y degrada")
    func networkError() async throws {
        MockURLProtocol.requestCount = 0
        MockURLProtocol.shouldFail = true
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }, timeoutSeconds: 0.01, maxRetries: 1),
            session: makeSession()
        )
        await #expect(throws: NVIDIAProviderError.network) {
            _ = try await provider.complete(AgentRequest(messages: []))
        }
        MockURLProtocol.shouldFail = false
    }

    // MARK: - Mock provider (§23)

    @Test("MockLLMProvider devuelve resultado determinista")
    func mockProvider() async throws {
        let provider = MockLLMProvider(result: .success(AgentResponse(text: "hola", finishReason: .stop)))
        let response = try await provider.complete(
            AgentRequest(messages: [AgentMessage(role: "user", content: "x")])
        )
        #expect(response.text == "hola")
    }

    // MARK: - Security: la key nunca está en el payload ni en el bundle

    @Test("La key va en header Authorization, nunca en el body")
    func apiKeyInHeaderOnly() async throws {
        MockURLProtocol.statusCode = 200
        MockURLProtocol.responseData = Data("{\"choices\":[{\"message\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}".utf8)
        let provider = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "nvapi-super-secreta" }),
            session: makeSession()
        )
        _ = try await provider.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))
        let bodyString = String(data: MockURLProtocol.capturedBody!, encoding: .utf8)!
        let authHeader = MockURLProtocol.captured!.value(forHTTPHeaderField: "Authorization")
        #expect(!bodyString.contains("super-secreta"))
        #expect(authHeader == "Bearer nvapi-super-secreta")
    }
}
