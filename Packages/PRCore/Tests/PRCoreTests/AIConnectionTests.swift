//
//  AIConnectionTests.swift
//  PRCoreTests
//
//  SCRUM-204 (IA-3): la IA sólo se conecta en Debug con una llave local; en Release ni
//  siquiera se busca la llave; cualquier falla es "no disponible" y nunca rompe.
//  Ningún test llama a la red.
//

import Foundation
import Testing
import PRCore

/// Cuenta cuántas veces se pidió la llave.
private final class KeyRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

private let request = AgentRequest(messages: [AgentMessage(role: "user", content: "hola")])

@Suite("Conexión con la IA (SCRUM-204)")
struct AIConnectionTests {

    @Test("Release: IA apagada y la llave ni siquiera se busca")
    func releaseNeverReadsTheKey() {
        let requests = KeyRequests()
        let connection = AIConnection.resolve(build: .release, keyLoader: { requests.record(); return "llave-de-prueba" })
        #expect(connection.status == .offline(.releaseBuild))
        #expect(requests.count == 0)
        #expect(connection.provider is OfflineLLMProvider)
    }

    @Test("Debug sin llave (o vacía) queda en modo local")
    func debugWithoutKey() {
        #expect(AIConnection.resolve(build: .debug, keyLoader: { nil }).status == .offline(.missingKey))
        #expect(AIConnection.resolve(build: .debug, keyLoader: { "   " }).status == .offline(.missingKey))
    }

    @Test("Debug con llave local se conecta al proveedor real (sin llamarlo aquí)")
    func debugWithKey() {
        let connection = AIConnection.resolve(build: .debug, keyLoader: { "llave-de-prueba" })
        #expect(connection.status == .live)
        #expect(connection.provider is NVIDIAHostedProvider)
    }

    @Test("Apagada: responde \"no disponible\" sin tocar el proveedor")
    func offlineIsUnavailable() async {
        let coach = AICoach(connection: AIConnection(status: .offline(.missingKey), provider: MockLLMProvider()))
        guard case .unavailable(.missingAPIKey) = await coach.ask(request) else {
            Issue.record("Sin conexión debía ser no disponible"); return
        }
    }

    @Test("Cualquier falla del proveedor es \"no disponible\" con su motivo; nunca lanza")
    func failuresAreSafe() async {
        for failure in [NVIDIAProviderError.timeout, .network, .rateLimited, .malformedResponse, .authentication] {
            let coach = AICoach(connection: AIConnection(status: .live, provider: MockLLMProvider(result: .failure(failure))))
            guard case .unavailable(let reason) = await coach.ask(request) else {
                Issue.record("\(failure) debía ser no disponible"); continue
            }
            #expect(reason == failure)
        }
    }

    @Test("Con conexión y respuesta válida devuelve la respuesta")
    func answer() async {
        let coach = AICoach(connection: AIConnection(status: .live, provider: MockLLMProvider(result: .success(AgentResponse(text: "listo")))))
        guard case .answer(let response) = await coach.ask(request) else {
            Issue.record("Debía responder"); return
        }
        #expect(response.text == "listo")
    }
}
