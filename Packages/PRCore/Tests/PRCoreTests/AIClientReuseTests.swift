//
//  AIClientReuseTests.swift
//  PRCoreTests
//
//  SCRUM-38 (PR-0116): la app usa un solo cliente de IA y una sola URLSession, y el
//  transporte no lleva código sin efecto: las comas finales del LLM las acepta Foundation.
//  Ningún test llama a la red.
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

@Suite("Un solo cliente de IA y sin código sin efecto (SCRUM-38)")
struct AIClientReuseTests {

    private static func hostedProvider(_ connection: AIConnection) -> NVIDIAHostedProvider? {
        connection.provider as? NVIDIAHostedProvider
    }

    // MARK: - Una sola instancia

    @Test("Pedir el coach varias veces reutiliza el mismo cliente y la misma URLSession")
    func coachReusesTheSession() throws {
        let connection = AIConnection.resolve(build: .debug, keyLoader: { "llave-de-prueba" })
        let first = try #require(Self.hostedProvider(AICoach(connection: connection).connection))
        for _ in 0..<5 {
            let again = try #require(Self.hostedProvider(AICoach(connection: connection).connection))
            #expect(again.session === first.session)
        }
    }

    @Test("La URLSession inyectada es la que usa el proveedor")
    func injectedSessionIsUsed() throws {
        let session = URLSession(configuration: .ephemeral)
        let connection = AIConnection.resolve(build: .debug, keyLoader: { "llave-de-prueba" }, session: session)
        let provider = try #require(Self.hostedProvider(connection))
        #expect(provider.session === session)
    }

    @Test("Cada resolve crea su propia sesión: la prueba de identidad sí distingue instancias")
    func separateResolvesAreSeparateSessions() throws {
        let one = try #require(Self.hostedProvider(AIConnection.resolve(build: .debug, keyLoader: { "llave-de-prueba" })))
        let two = try #require(Self.hostedProvider(AIConnection.resolve(build: .debug, keyLoader: { "llave-de-prueba" })))
        #expect(one.session !== two.session)
    }

    // MARK: - Comas finales: las acepta Foundation

    @Test("Foundation acepta comas finales en objetos y arreglos", arguments: [
        #"{"a":1,}"#,
        #"{"a":[1,2,],}"#,
        #"[{"a":1,},]"#,
    ])
    func foundationAcceptsTrailingCommas(_ json: String) throws {
        let data = Data(json.utf8)
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
        #expect((try? JSONDecoder().decode(JSONValueProbe.self, from: data)) != nil)
    }

    @Test("Una coma final no cambia el texto del usuario que viene dentro de un string")
    func trailingCommaKeepsStringContent() async throws {
        let raw = #"{"intent":"reportPain","payload":{"value":{"level":3,"notes":"rodilla, }] izquierda",}},}"#
        let transport = LLMBackendTransport(
            provider: MockLLMProvider(result: .success(AgentResponse(text: raw, finishReason: .stop)))
        )
        let response = try await transport.interpret(InterpretRequest(text: "me duele", context: AgentContext()))
        guard case .reportPain(let report) = try #require(response.intent) else {
            Issue.record("Debía entender el reporte de dolor"); return
        }
        #expect(report.notes == "rodilla, }] izquierda")
        #expect(!response.needsClarification)
    }

    @Test("JSON roto sigue cayendo en pedir aclaración, sin reparos")
    func brokenJSONAsksForClarification() async throws {
        let transport = LLMBackendTransport(
            provider: MockLLMProvider(result: .success(AgentResponse(text: #"{"intent":"reportPain",,}"#, finishReason: .stop)))
        )
        let response = try await transport.interpret(InterpretRequest(text: "me duele", context: AgentContext()))
        #expect(response.needsClarification)
        #expect(response.intent == nil)
    }
}

/// Decodifica cualquier JSON sin guardarlo: sólo prueba que `JSONDecoder` lo acepta.
private struct JSONValueProbe: Decodable {
    init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd { _ = try array.decode(JSONValueProbe.self) }
            return
        }
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            for key in object.allKeys { _ = try object.decode(JSONValueProbe.self, forKey: key) }
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { return }
        if (try? value.decode(Bool.self)) != nil { return }
        if (try? value.decode(Double.self)) != nil { return }
        _ = try value.decode(String.self)
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}
