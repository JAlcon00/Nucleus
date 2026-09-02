//
//  NIMProviderTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de N7 — NIM migration readiness (NEMOTRON §24, §23, §47, PR-1608):
//  - provider contract: NVIDIAHostedProvider y NVIDIANIMProvider comparten el MISMO
//    wire OpenAI-compatible (payload, error mapping, tools, decoding) → migrar hosted→NIM
//    sin tocar dominio/transporte.
//  - health endpoints: /v1/health/live y /v1/health/ready → NIMHealthStatus tipado.
//  - auth de infra del NIM (token opcional, nunca la key NVIDIA; keyless dev).
//  Usa su propio NIMURLProtocol (estado estático separado del MockURLProtocol de
//  NVIDIAProviderTests) para que las suites no interfieran al correr en paralelo.
//

import Foundation
import Testing
@testable import PRCore

// Mock URLProtocol propio del suite N7: separa el estado estático del `MockURLProtocol`
// usado por NVIDIAProviderTests. Swift Testing ejecuta suites en paralelo; si ambos
// compartieran los mismos statics, las suites de hosted y NIM se corromperían entre sí.
final class NIMURLProtocol: URLProtocol {
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
        NIMURLProtocol.requestCount += 1
        if NIMURLProtocol.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        NIMURLProtocol.captured = request
        NIMURLProtocol.capturedBody = NIMURLProtocol.bodyData(of: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: NIMURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = NIMURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func nimSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NIMURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func resetMock(statusCode: Int = 200, body: Data? = nil) {
    NIMURLProtocol.requestCount = 0
    NIMURLProtocol.statusCode = statusCode
    NIMURLProtocol.responseData = body
    NIMURLProtocol.shouldFail = false
}

private func defaultBody() -> Data {
    Data(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#.utf8)
}

@Suite("NIM provider + provider contract (N7, §24/§23/§47)", .serialized)
struct NIMProviderTests {

    // MARK: - NIM Chat Completions (mismo wire que el hosted)

    @Test("NIM usa baseURL propio y model servido en el payload")
    func nimUsesOwnBases() async throws {
        resetMock(body: defaultBody())
        let provider = NVIDIANIMProvider(
            config: NVIDIANIMConfig(baseURL: URL(string: "http://nim:8000/v1")!, model: "mi-modelo"),
            session: nimSession()
        )
        _ = try await provider.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))

        guard let url = NIMURLProtocol.captured?.url else {
            Issue.record("no request"); return
        }
        #expect(url.absoluteString.hasPrefix("http://nim:8000/v1/chat/completions"))
        let json = try JSONSerialization.jsonObject(with: NIMURLProtocol.capturedBody!) as! [String: Any]
        #expect(json["model"] as? String == "mi-modelo")
        #expect(json["stream"] as? Bool == false)
    }

    // MARK: - Provider contract: hosted y NIM idénticos

    @Test("Contract: hosted y NIM producen el mismo payload para el mismo AgentRequest")
    func contractIdenticalPayload() async throws {
        resetMock(body: defaultBody())
        let request = AgentRequest(
            messages: [AgentMessage(role: "user", content: "Hoy 45 minutos")],
            mode: .reasoning,
            tools: [AgentToolDefinition(name: "getTodayContext", description: "ctx")]
        )

        let hosted = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(model: "hosted-model", apiKeyProvider: { "nvapi-h" }),
            session: nimSession()
        )
        _ = try await hosted.complete(request)
        let hostedJSON = try JSONSerialization.jsonObject(with: NIMURLProtocol.capturedBody!) as! [String: Any]

        resetMock(body: defaultBody())
        let nim = NVIDIANIMProvider(
            config: NVIDIANIMConfig(baseURL: URL(string: "http://nim/v1")!, model: "nim-model"),
            session: nimSession()
        )
        _ = try await nim.complete(request)
        let nimJSON = try JSONSerialization.jsonObject(with: NIMURLProtocol.capturedBody!) as! [String: Any]

        // Model difiere por diseño (§47): hosted model ID vs NIM served name.
        #expect(hostedJSON["model"] as? String == "hosted-model")
        #expect(nimJSON["model"] as? String == "nim-model")

        // Todo lo demás del wire es IDÉNTICO (mismo contrato §23): serialización canónica.
        var hostedRest = hostedJSON
        var nimRest = nimJSON
        hostedRest.removeValue(forKey: "model")
        nimRest.removeValue(forKey: "model")
        let hostedData = try JSONSerialization.data(withJSONObject: hostedRest, options: [.sortedKeys])
        let nimData = try JSONSerialization.data(withJSONObject: nimRest, options: [.sortedKeys])
        #expect(hostedData == nimData, "payload (sin model) debe ser idéntico entre hosted y NIM")
    }

    @Test("Contract: hosted y NIM mapean errores igual (429 reintenta acotado)")
    func contractErrorMapping429() async throws {
        resetMock(statusCode: 429)

        let hosted = NVIDIAHostedProvider(
            config: NVIDIAHostedConfig(apiKeyProvider: { "k" }, timeoutSeconds: 0.01, maxRetries: 2),
            session: nimSession()
        )
        await #expect(throws: NVIDIAProviderError.rateLimited) {
            _ = try await hosted.complete(AgentRequest(messages: []))
        }
        let hostedAttempts = NIMURLProtocol.requestCount

        resetMock(statusCode: 429)
        let nim = NVIDIANIMProvider(
            config: NVIDIANIMConfig(timeoutSeconds: 0.01, maxRetries: 2),
            session: nimSession()
        )
        await #expect(throws: NVIDIAProviderError.rateLimited) {
            _ = try await nim.complete(AgentRequest(messages: []))
        }
        #expect(NIMURLProtocol.requestCount == hostedAttempts, "mismo retry acotado")
    }

    @Test("Contract: hosted y NIM decodifican reasoning_content y usage igual")
    func contractDecoding() async throws {
        resetMock(body: Data("""
        {"choices":[{"message":{"content":"r","reasoning_content":"pensó"},"finish_reason":"length"}],
         "usage":{"prompt_tokens":5,"completion_tokens":9}}
        """.utf8))
        let nim = NVIDIANIMProvider(session: nimSession())
        let response = try await nim.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))
        #expect(response.text == "r")
        #expect(response.reasoning == "pensó")
        #expect(response.finishReason == .length)
        #expect(!response.isComplete)
        #expect(response.promptTokens == 5)
        #expect(response.completionTokens == 9)
    }

    @Test("NIM wire de tools: tool_choice auto + tools")
    func nimToolsWire() async throws {
        resetMock(body: defaultBody())
        let nim = NVIDIANIMProvider(session: nimSession())
        _ = try await nim.complete(AgentRequest(
            messages: [AgentMessage(role: "user", content: "x")],
            tools: [AgentToolDefinition(name: "getTodayContext", description: "ctx")]
        ))
        let json = try JSONSerialization.jsonObject(with: NIMURLProtocol.capturedBody!) as! [String: Any]
        #expect(json["tool_choice"] as? String == "auto")
        #expect((json["tools"] as? [[String: Any]])?.count == 1)
    }

    // MARK: - Keyless NIM dev (auth de infra opcional, no key NVIDIA)

    @Test("NIM sin key no falla por missingAPIKey (keyless dev) ni envía Authorization")
    func nimKeyless() async throws {
        resetMock(body: defaultBody())
        let nim = NVIDIANIMProvider(session: nimSession())
        let response = try await nim.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))
        #expect(response.text == "ok")
        #expect(NIMURLProtocol.captured?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("NIM con token lo manda en header, nunca en el body")
    func nimAuthHeaderOnly() async throws {
        resetMock(body: defaultBody())
        let nim = NVIDIANIMProvider(
            config: NVIDIANIMConfig(apiKeyProvider: { "nim-infra-token" }),
            session: nimSession()
        )
        _ = try await nim.complete(AgentRequest(messages: [AgentMessage(role: "user", content: "x")]))
        let auth = NIMURLProtocol.captured?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer nim-infra-token")
        let body = String(data: NIMURLProtocol.capturedBody!, encoding: .utf8)!
        #expect(!body.contains("nim-infra-token"))
    }

    // MARK: - Health endpoints (§24)

    @Test("health/live 2xx → .live")
    func healthLive() async {
        resetMock(body: Data(#"{"object":"health.response","message":"live","status":"live"}"#.utf8))
        let nim = NVIDIANIMProvider(session: nimSession())
        let status = await nim.isLive()
        #expect(status == .live)
        #expect(NIMURLProtocol.captured?.url?.absoluteString.contains("/v1/health/live") == true)
    }

    @Test("health/ready 2xx → .ready")
    func healthReady() async {
        resetMock(body: Data(#"{"object":"health.response","message":"ready","status":"ready"}"#.utf8))
        let nim = NVIDIANIMProvider(session: nimSession())
        let status = await nim.isReady()
        #expect(status == .ready)
        #expect(NIMURLProtocol.captured?.url?.absoluteString.contains("/v1/health/ready") == true)
    }

    @Test("health 503 → .notLive(status:)")
    func healthNotLive() async {
        resetMock(statusCode: 503, body: Data())
        let nim = NVIDIANIMProvider(session: nimSession())
        let status = await nim.isLive()
        #expect(status == .notLive(status: 503))
    }

    @Test("health sin red → .unreachable")
    func healthUnreachable() async {
        resetMock(body: Data())
        NIMURLProtocol.shouldFail = true
        let nim = NVIDIANIMProvider(session: nimSession())
        let status = await nim.isReady()
        #expect(status == .unreachable)
        NIMURLProtocol.shouldFail = false
    }

    @Test("health() reporta live y ready")
    func healthBoth() async {
        resetMock(body: Data(#"{"object":"health.response","message":"live","status":"live"}"#.utf8))
        let nim = NVIDIANIMProvider(session: nimSession())
        let (live, ready) = await nim.health()
        #expect(live == .live)
        #expect(ready == .ready)
    }

    // MARK: - Streaming (mismo contrato que hosted)

    @Test("NIM stream mapea delta SSE a .text/.finish")
    func nimStreams() async throws {
        NIMURLProtocol.requestCount = 0
        NIMURLProtocol.statusCode = 200
        NIMURLProtocol.shouldFail = false
        NIMURLProtocol.responseData = Data("""
        data: {"choices":[{"delta":{"content":"Hola"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """.utf8)
        let nim = NVIDIANIMProvider(session: nimSession())
        var events: [AgentStreamEvent] = []
        for try await event in nim.stream(AgentRequest(messages: [AgentMessage(role: "user", content: "x")])) {
            events.append(event)
        }
        #expect(events.contains(.text("Hola")))
        #expect(events.contains(.finish(.stop)))
    }
}
