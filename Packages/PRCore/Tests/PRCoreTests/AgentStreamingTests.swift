//
//  AgentStreamingTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de streaming (Phase N5, NEMOTRON §19/§45): parser SSE puro (chunks parciales,
//  buffer, [DONE]), mapping de delta a eventos (content/reasoning/tool_calls/finish),
//  stream end-to-end sobre el provider con mock URLProtocol, y fallback no-streaming
//  del protocolo.
//

import Foundation
import Testing
@testable import PRCore

@Suite("LLM streaming (Phase N5)")
struct AgentStreamingTests {

    // MARK: - SSE parser (puro)

    @Test("SSE decoder maneja chunks parciales y bufferiza líneas")
    func ssePartialLines() {
        var decoder = SSEEventDecoder()
        // La línea se entrega en dos fragmentos: "data: {h" + "ola}\n"
        let first = decoder.append("data: {h")
        #expect(first.isEmpty)
        let second = decoder.append("ola}\n\ndata: [DONE]\n")
        #expect(second == ["{hola}", "[DONE]"])
    }

    @Test("SSE decoder ignora líneas no-data y eventos vacíos")
    func sseIgnoresOtherLines() {
        var decoder = SSEEventDecoder()
        let events = decoder.append(": comment\nevent: x\n\nid: 1\n\n")
        #expect(events.isEmpty)
    }

    @Test("SSE decoder CRLF y CR de fin de línea")
    func sseCrlf() {
        var decoder = SSEEventDecoder()
        let events = decoder.append("data: a\r\n\r\ndata: b\r\n")
        #expect(events == ["a", "b"])
    }

    // MARK: - Mapping delta → eventos

    @Test("Delta content se mapea a .text y finish a .stop")
    func mapperContentAndFinish() {
        let chunk = NVIDIAStreamChunk(id: "1", choices: [
            NVIDIAStreamChoice(index: 0, delta: NVIDIAStreamDelta(content: "Hola", reasoningContent: nil, toolCalls: nil), finishReason: "stop")
        ])
        let events = NVIDIAStreamEventMapper.events(forChunk: chunk)
        #expect(events == [.text("Hola"), .finish(.stop)])
    }

    @Test("Delta reasoning se mapea a .reasoning (no visible al usuario)")
    func mapperReasoning() {
        let chunk = NVIDIAStreamChunk(id: "1", choices: [
            NVIDIAStreamChoice(index: 0, delta: NVIDIAStreamDelta(content: nil, reasoningContent: "raciocino ", toolCalls: nil), finishReason: nil)
        ])
        #expect(NVIDIAStreamEventMapper.events(forChunk: chunk) == [.reasoning("raciocino ")])
    }

    @Test("Delta tool_calls se mapea a .toolCall")
    func mapperToolCall() {
        let chunk = NVIDIAStreamChunk(id: "1", choices: [
            NVIDIAStreamChoice(index: 0, delta: NVIDIAStreamDelta(
                content: nil,
                reasoningContent: nil,
                toolCalls: [NVIDIAToolCall(id: "c1", type: "function", function: NVIDIAToolCallFunction(name: "getTodayContext", arguments: "{}"))]
            ), finishReason: "tool_calls")
        ])
        let events = NVIDIAStreamEventMapper.events(forChunk: chunk)
        #expect(events.count == 2)
        guard case .toolCall(let call) = events[0] else {
            Issue.record("esperaba .toolCall")
            return
        }
        #expect(call.name == "getTodayContext")
        #expect(events[1] == .finish(.toolCalls))
    }

    // MARK: - Parser síncrono SSE → eventos (determinista, sin red)

    @Test("El parser emite deltas y finish desde un cuerpo SSE")
    func parserEmitsDeltasAndFinish() {
        let body = """
        data: {"choices":[{"delta":{"content":"Hola"}}]}

        data: {"choices":[{"delta":{"content":" mundo"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        var decoder = SSEEventDecoder()
        var events: [AgentStreamEvent] = []
        for char in body {
            events.append(contentsOf: NVIDIAStreamEventParser.parse(decoder: &decoder, fragment: String(char)))
        }
        let texts = events.compactMap { if case .text(let t) = $0 { return t }; return nil }
        #expect(texts == ["Hola", " mundo"])
        let finish = events.compactMap { if case .finish(let f) = $0 { return f }; return nil }
        #expect(finish == [.stop])
    }

    @Test("El parser emite reasoning y tool_calls en streaming")
    func parserEmitsReasoningAndToolCall() {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"pensando"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"name":"getTodayContext","arguments":"{}"}}]}}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        var decoder = SSEEventDecoder()
        var events: [AgentStreamEvent] = []
        for char in body {
            events.append(contentsOf: NVIDIAStreamEventParser.parse(decoder: &decoder, fragment: String(char)))
        }
        #expect(events.contains(.reasoning("pensando")))
        #expect(events.contains(.finish(.toolCalls)))
        guard case .toolCall(let call) = events.first(where: { if case .toolCall = $0 { return true }; return false }) else {
            Issue.record("esperaba .toolCall")
            return
        }
        #expect(call.name == "getTodayContext")
    }

    // MARK: - Fallback no-streaming del protocolo

    @Test("Provider sin stream propio cae al fallback (complete → un delta + finish)")
    func protocolDefaultFallback() async throws {
        let provider = MockLLMProvider(result: .success(AgentResponse(text: "respuesta", finishReason: .stop)))
        var events: [AgentStreamEvent] = []
        for try await event in provider.stream(AgentRequest(messages: [AgentMessage(role: "user", content: "x")])) {
            events.append(event)
        }
        #expect(events == [.text("respuesta"), .finish(.stop)])
    }
}
