//
//  AgentStreamingUTF8Tests.swift
//  PRCoreTests
//
//  SCRUM-34 (PR-0112): los mensajes del entrenador se leen bien. El stream decodificaba
//  byte por byte, así que á, ñ, ¿ y los emojis llegaban rotos (cada byte suelto de un
//  carácter multibyte se volvía "�"), y el buffer se re-escaneaba completo en cada byte.
//  Ahora `SSEEventDecoder` junta los bytes de cada línea y decodifica UTF-8 sólo con la
//  línea completa: el texto final es el mismo llegue como llegue, en tiempo lineal.
//

import Foundation
import Testing
@testable import PRCore

// URLProtocol propio: entrega el cuerpo en los fragmentos indicados y, si se pide, corta la
// conexión al final. Estado estático separado del de las otras suites (corren en paralelo).
final class StreamingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var chunks: [Data] = []
    nonisolated(unsafe) static var failure: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in Self.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite("SCRUM-34 · Mensajes del entrenador en UTF-8", .serialized)
struct AgentStreamingUTF8Tests {

    /// Respuesta en español con acentos, eñe, signos de apertura y un emoji, en varios deltas.
    private static let spanishBody = """
    data: {"choices":[{"delta":{"content":"¿Qué tal? "}}]}

    data: {"choices":[{"delta":{"content":"Mañana subimos 2,5 kg "}}]}

    data: {"choices":[{"delta":{"content":"💪 ¡Ánimo, campeón!"}}]}

    data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

    data: [DONE]


    """
    private static let spanishText = "¿Qué tal? Mañana subimos 2,5 kg 💪 ¡Ánimo, campeón!"

    /// Alimenta el parser con los fragmentos dados, cierra el stream y une el texto visible.
    private func text(feeding fragments: [ArraySlice<UInt8>]) -> String {
        var decoder = SSEEventDecoder()
        var events: [AgentStreamEvent] = []
        for fragment in fragments {
            events.append(contentsOf: NVIDIAStreamEventParser.parse(decoder: &decoder, bytes: fragment))
        }
        events.append(contentsOf: NVIDIAStreamEventParser.finish(decoder: &decoder))
        return events.compactMap { event -> String? in
            if case .text(let text) = event { return text }
            return nil
        }.joined()
    }

    private func streamingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func request() -> AgentRequest {
        AgentRequest(messages: [AgentMessage(role: "user", content: "¿Qué toca hoy?")])
    }

    // MARK: - Decoder SSE

    @Test("Un carácter de 2, 3 o 4 bytes partido entre dos fragmentos llega entero",
          arguments: [("ñ", 2), ("¿", 2), ("€", 3), ("💪", 4)])
    func multibyteSplitAcrossFragments(character: String, byteCount: Int) {
        #expect(character.utf8.count == byteCount)
        let line = Array("data: a\(character)b\n".utf8)
        let start = "data: a".utf8.count
        // Cada corte posible dentro del carácter.
        for cut in (start + 1)..<(start + byteCount) {
            var decoder = SSEEventDecoder()
            let first = decoder.append(bytes: line[..<cut])
            let second = decoder.append(bytes: line[cut...])
            #expect(first.isEmpty)
            #expect(second == ["a\(character)b"], "corte en el byte \(cut)")
        }
    }

    @Test("Un CRLF partido entre dos fragmentos cierra la línea")
    func crlfSplitAcrossFragments() {
        var decoder = SSEEventDecoder()
        #expect(decoder.append(bytes: Array("data: Mañana\r".utf8)).isEmpty)
        #expect(decoder.append(bytes: Array("\n".utf8)) == ["Mañana"])
    }

    @Test("Una última línea sin salto final no se pierde al terminar el stream")
    func lastLineWithoutNewline() {
        var decoder = SSEEventDecoder()
        #expect(decoder.append("data: a\n\ndata: ¡fin!") == ["a"])
        #expect(decoder.finish() == ["¡fin!"])
        #expect(decoder.finish().isEmpty, "terminar dos veces no repite el evento")
    }

    // MARK: - Parser SSE → eventos

    @Test("La misma respuesta da el mismo texto de golpe, byte por byte o partida en cualquier punto")
    func sameTextHoweverItArrives() {
        let bytes = Array(Self.spanishBody.utf8)
        #expect(text(feeding: [bytes[...]]) == Self.spanishText)
        #expect(text(feeding: bytes.indices.map { bytes[$0...$0] }) == Self.spanishText)
        let failingCuts = (1..<bytes.count).filter { cut in
            text(feeding: [bytes[..<cut], bytes[cut...]]) != Self.spanishText
        }
        #expect(failingCuts.isEmpty, "cortes que rompen el texto: \(failingCuts)")
    }

    @Test("Una respuesta de más de 10 000 caracteres en una sola línea se procesa en tiempo lineal")
    func longResponseIsLinear() {
        let content = String(repeating: "Mañana subimos ¿más? 💪 ", count: 450)
        #expect(content.count >= 10_000)
        let body = Array(#"data: {"choices":[{"delta":{"content":"\#(content)"}}]}"#.utf8) + Array("\n\n".utf8)
        var decoder = SSEEventDecoder()
        var events: [AgentStreamEvent] = []
        // Byte por byte, como llega de `URLSession.AsyncBytes`. Re-escanear el buffer en cada
        // byte (lo de antes) tarda segundos con esta línea; en lineal son milisegundos.
        let elapsed = ContinuousClock().measure {
            for byte in body {
                events.append(contentsOf: NVIDIAStreamEventParser.parse(decoder: &decoder, bytes: CollectionOfOne(byte)))
            }
        }
        #expect(events == [.text(content)])
        #expect(elapsed < .seconds(1), "tardó \(elapsed)")
    }

    // MARK: - Integración: proveedor con el stream real de URLSession

    @Test("Con el SSE en fragmentos que parten caracteres, el proveedor entrega el texto exacto")
    func providerStreamsSpanishText() async throws {
        let bytes = Array(Self.spanishBody.utf8)
        // Cortes de red dentro de "¿" (al inicio), de "ñ" y del emoji.
        let cuts = [
            Self.offset(of: "¿Qué", in: bytes) + 1,
            Self.offset(of: "ñana", in: bytes) + 1,
            Self.offset(of: "💪", in: bytes) + 2,
        ]
        StreamingURLProtocol.chunks = Self.split(bytes, at: cuts)
        StreamingURLProtocol.failure = nil

        let provider = NVIDIANIMProvider(session: streamingSession())
        var texts: [String] = []
        var finishes: [AgentFinishReason] = []
        for try await event in provider.stream(request()) {
            switch event {
            case .text(let text): texts.append(text)
            case .finish(let reason): finishes.append(reason)
            case .reasoning, .toolCall: break
            }
        }
        #expect(texts.joined() == Self.spanishText)
        #expect(finishes == [.stop])
    }

    @Test("Si el servidor cierra sin salto final, el último evento igual llega")
    func providerDeliversLastEventWithoutNewline() async throws {
        StreamingURLProtocol.chunks = [Data(#"""
        data: {"choices":[{"delta":{"content":"Listo, señor"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}
        """#.utf8)]
        StreamingURLProtocol.failure = nil

        let provider = NVIDIANIMProvider(session: streamingSession())
        var events: [AgentStreamEvent] = []
        for try await event in provider.stream(request()) {
            events.append(event)
        }
        #expect(events == [.text("Listo, señor"), .finish(.stop)])
    }

    /// Lo que alcanzó a llegar antes del corte, con el último delta a medias.
    private static let interruptedBody = #"""
    data: {"choices":[{"delta":{"content":"¿Listo? "}}]}

    data: {"choices":[{"delta":{"content":"Mañana "}}]}

    data: {"choices":[{"delta":{"content":"y lue
    """#

    @Test("Si la conexión se corta a mitad, llega lo recibido y se avisa que se interrumpió")
    func relayDeliversWhatArrivedBeforeTheCut() async {
        let (bytes, input) = AsyncThrowingStream<UInt8, any Error>.makeStream()
        for byte in Self.interruptedBody.utf8 {
            input.yield(byte)
        }
        input.finish(throwing: URLError(.networkConnectionLost))

        var texts: [String] = []
        var thrown: (any Error)?
        do {
            try await NVIDIAStreamEventParser.relay(bytes) { event in
                if case .text(let text) = event { texts.append(text) }
            }
        } catch {
            thrown = error
        }
        #expect(texts.joined() == "¿Listo? Mañana ", "la línea a medias se descarta")
        #expect(thrown as? NVIDIAProviderError == .interrupted)
    }

    @Test("Una cancelación de la tarea no se confunde con un corte de la conexión")
    func relayReportsCancellation() async {
        let (bytes, input) = AsyncThrowingStream<UInt8, any Error>.makeStream()
        input.finish(throwing: CancellationError())
        var thrown: (any Error)?
        do {
            try await NVIDIAStreamEventParser.relay(bytes) { _ in }
        } catch {
            thrown = error
        }
        #expect(thrown as? NVIDIAProviderError == .cancelled)
    }

    @Test("Si la conexión se corta, el proveedor avisa que se interrumpió en vez de un error crudo")
    func providerReportsInterruption() async {
        // Aquí los datos y el corte llegan juntos y `URLSession` descarta los bytes que aún no
        // se leían; con la red real llegan poco a poco y se entregan conforme llegan (lo
        // prueba `relayDeliversWhatArrivedBeforeTheCut`). Esta prueba fija el aviso.
        StreamingURLProtocol.chunks = [Data(Self.interruptedBody.utf8)]
        StreamingURLProtocol.failure = URLError(.networkConnectionLost)

        let provider = NVIDIANIMProvider(session: streamingSession())
        var thrown: (any Error)?
        do {
            for try await _ in provider.stream(request()) {}
        } catch {
            thrown = error
        }
        #expect(thrown as? NVIDIAProviderError == .interrupted)
    }

    @Test("La interrupción tiene su código de diagnóstico")
    func interruptedDiagnosticCode() {
        #expect("\(NVIDIAProviderError.interrupted.diagnosticCode)" == "interrupted")
    }

    // MARK: - Utilidades

    private static func offset(of needle: String, in bytes: [UInt8]) -> Int {
        let pattern = Array(needle.utf8)
        let index = (0...(bytes.count - pattern.count)).first { start in
            Array(bytes[start..<(start + pattern.count)]) == pattern
        }
        return index ?? 0
    }

    private static func split(_ bytes: [UInt8], at cuts: [Int]) -> [Data] {
        var chunks: [Data] = []
        var start = 0
        for cut in cuts.sorted() where cut > start && cut < bytes.count {
            chunks.append(Data(bytes[start..<cut]))
            start = cut
        }
        chunks.append(Data(bytes[start...]))
        return chunks
    }
}
