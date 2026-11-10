//
//  AgentUsageTests.swift
//  PRCoreTests
//
//  SCRUM-273 (PR-I004, DI-4 A): cada llamada a la IA deja un registro sin texto con su
//  operación, tokens, milisegundos y si respondió o cayó al respaldo; el resumen da mediana,
//  p95, tokens promedio y respaldos por operación, sin inventar números.
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

/// Reloj monótono que avanza lo que diga la prueba en cada lectura.
private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: UInt64 = 1_000_000_000
    private var steps: [UInt64]

    init(stepsMilliseconds: [UInt64]) {
        steps = stepsMilliseconds.map { $0 * 1_000_000 }
    }

    func read() -> UInt64 {
        lock.withLock {
            let value = now
            if !steps.isEmpty { now += steps.removeFirst() }
            return value
        }
    }
}

/// Proveedor que responde con tokens, falla o se tarda.
private struct ScriptedProvider: LLMProvider {
    enum Script: Sendable {
        case answer(prompt: Int?, completion: Int?)
        case fail(NVIDIAProviderError)
        case hang
    }

    let script: Script

    func complete(_ request: AgentRequest) async throws -> AgentResponse {
        switch script {
        case .answer(let prompt, let completion):
            return AgentResponse(text: "texto del modelo que no se guarda", usage: AgentUsage(promptTokens: prompt, completionTokens: completion))
        case .fail(let error):
            throw error
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return AgentResponse(text: "tarde")
        }
    }
}

private func record(_ operation: AgentOperation, ms: Int, tokens: (Int, Int)? = nil, outcome: AgentCallOutcome = .answered) -> AgentUsageRecord {
    AgentUsageRecord(
        id: UUID(), date: Date(timeIntervalSince1970: 0), operation: operation,
        promptTokens: tokens?.0, completionTokens: tokens?.1, reasoningTokens: nil,
        durationMilliseconds: ms, outcome: outcome
    )
}

private let request = AgentRequest(messages: [AgentMessage(role: "user", content: "me duele un poco la rodilla")])

@Suite("SCRUM-273 · Tokens y latencia de cada llamada a la IA")
struct AgentUsageTests {

    // MARK: Resumen

    @Test("Mediana y p95 por rango más cercano, tokens promedio y respaldos, por operación")
    func summaryRows() throws {
        let records = [100, 200, 300, 400, 1_000].map { record(.coachInterpret, ms: $0, tokens: (100, 20)) }
            + [record(.coachInterpret, ms: 50, outcome: .failed(.timeout))]
            + [record(.planRationale, ms: 900, tokens: (300, 100))]
        let rows = AgentUsageSummary.rows(for: records)
        #expect(rows.map(\.operation) == [.coachInterpret, .planRationale], "Sólo las operaciones con llamadas, en orden")
        let coach = try #require(rows.first)
        #expect(coach.calls == 6)
        #expect(coach.medianMilliseconds == 200, "⌈0.5·6⌉ = 3.ª de [50, 100, 200, 300, 400, 1000]")
        #expect(coach.p95Milliseconds == 1_000)
        #expect(coach.averageTotalTokens == 120, "Sólo las que reportaron tokens")
        #expect(coach.fallbacks == 1)
        #expect(rows[1].averageTotalTokens == 400)
    }

    @Test("Sin llamadas no hay filas; sin tokens reportados, sin promedio")
    func emptyAndWithoutTokens() {
        #expect(AgentUsageSummary.rows(for: []).isEmpty)
        let rows = AgentUsageSummary.rows(for: [record(.planPersonalization, ms: 10)])
        #expect(rows.first?.averageTotalTokens == nil)
        #expect(rows.first?.medianMilliseconds == 10 && rows.first?.p95Milliseconds == 10)
    }

    // MARK: Medición

    @Test("Mide con el reloj inyectado al responder, al fallar y al cancelarse, sin guardar texto")
    func meteredProviderRecordsEveryOutcome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = SteppingClock(stepsMilliseconds: [250, 0, 40, 0, 15, 0])
        let recorder = AgentUsageRecorder(
            store: try persistence.agentUsageStore(),
            clock: { Date(timeIntervalSince1970: 1_792_000_000) },
            elapsedNanoseconds: { clock.read() }
        )

        let answered = MeteredLLMProvider(base: ScriptedProvider(script: .answer(prompt: 120, completion: 30)), operation: .coachInterpret, recorder: recorder)
        _ = try await answered.complete(request)
        let failing = MeteredLLMProvider(base: ScriptedProvider(script: .fail(.network)), operation: .planPersonalization, recorder: recorder)
        await #expect(throws: NVIDIAProviderError.self) { try await failing.complete(request) }
        let hanging = MeteredLLMProvider(base: ScriptedProvider(script: .hang), operation: .planRationale, recorder: recorder)
        let task = Task { try await hanging.complete(request) }
        task.cancel()
        _ = await task.result

        let records = try persistence.agentUsageStore().all()
        #expect(records.count == 3)
        let byOperation = Dictionary(uniqueKeysWithValues: records.map { ($0.operation, $0) })
        #expect(byOperation[.coachInterpret]?.durationMilliseconds == 250)
        #expect(byOperation[.coachInterpret]?.totalTokens == 150)
        #expect(byOperation[.coachInterpret]?.outcome == .answered)
        #expect(byOperation[.planPersonalization]?.outcome == .failed(.network))
        #expect(byOperation[.planPersonalization]?.durationMilliseconds == 40, "También se mide cuando falla")
        #expect(byOperation[.planRationale]?.outcome == .failed(.cancelled))

        let stored = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("agent-usage"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }
            .joined()
        #expect(!stored.contains("rodilla") && !stored.contains("modelo"), "Ni el texto de la persona ni el del modelo")
    }

    @Test("Un error al guardar se avisa y no rompe la llamada")
    func saveFailureDoesNotBreakTheCall() async throws {
        let failed = SaveFlag()
        let recorder = AgentUsageRecorder(store: AgentUsageStore(store: FailingStore()), onSaveFailure: { failed.set() })
        let provider = MeteredLLMProvider(base: ScriptedProvider(script: .answer(prompt: 1, completion: 1)), operation: .coachInterpret, recorder: recorder)
        let response = try await provider.complete(request)
        #expect(response.text != nil, "La respuesta llega igual")
        #expect(await recorder.lastSaveFailed)
        #expect(failed.value)
    }

    @Test("Sin IA no se mide nada: la conexión apagada se devuelve igual")
    func offlineConnectionIsNotMetered() async throws {
        let recorder = AgentUsageRecorder(store: nil)
        let offline = AIConnection(status: .offline(.releaseBuild), provider: OfflineLLMProvider())
        #expect(offline.metered(.coachInterpret, by: recorder).provider is OfflineLLMProvider)
        let live = AIConnection(status: .live, provider: MockLLMProvider())
        #expect(live.metered(.coachInterpret, by: recorder).provider is MeteredLLMProvider)
        #expect(live.metered(.coachInterpret, by: nil).provider is MockLLMProvider)
    }

    // MARK: Integración

    @Test("Integración: dos llamadas, reabrir y el resumen es el mismo")
    func summarySurvivesReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-usage-r-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = AgentUsageRecorder(store: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).agentUsageStore())
        let provider = MeteredLLMProvider(base: ScriptedProvider(script: .answer(prompt: 80, completion: 20)), operation: .coachInterpret, recorder: first)
        _ = try await provider.complete(request)
        _ = try await provider.complete(request)
        let before = try await first.summary()

        let reopened = AgentUsageRecorder(store: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).agentUsageStore())
        let after = try await reopened.summary()
        #expect(after == before)
        #expect(after.first?.calls == 2)
        #expect(after.first?.averageTotalTokens == 100)
    }
}

private final class SaveFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

/// Almacén que no deja escribir.
private struct FailingStore: RepositoryStore {
    struct Failure: Error {}
    func read(key: String) throws -> Data? { nil }
    func readAll() throws -> [Data] { [] }
    func readAllEntries() throws -> StoreReadResult { StoreReadResult(entries: []) }
    func write(key: String, data: Data) throws { throw Failure() }
    func delete(key: String) throws {}
}
