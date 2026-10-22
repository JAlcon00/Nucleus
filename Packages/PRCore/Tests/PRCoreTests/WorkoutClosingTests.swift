//
//  WorkoutClosingTests.swift
//  PRCoreTests
//
//  SCRUM-25: cerrar bien la sesión al terminar. La última serie completa la sesión, el
//  resumen no provoca escrituras, `tick()` nunca escribe, los estados finales rechazan
//  cualquier otra transición y Export cuenta el entrenamiento una sola vez.
//

import Foundation
import Testing
import PRCore
import PRDomain

private final class TickClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 2_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// Almacén espía: cuenta cada escritura (lo que pidió el plan: "store espía").
private final class SpyStore: RepositoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var blobs: [String: Data] = [:]
    private var writes = 0
    var writeCount: Int { lock.withLock { writes } }
    func read(key: String) throws -> Data? { lock.withLock { blobs[key] } }
    func readAll() throws -> [Data] { lock.withLock { Array(blobs.values) } }
    func readAllEntries() throws -> StoreReadResult {
        lock.withLock { StoreReadResult(entries: blobs.map { StoredEntry(key: $0.key, data: $0.value) }) }
    }
    func write(key: String, data: Data) throws { lock.withLock { writes += 1; blobs[key] = data } }
    func delete(key: String) throws { lock.withLock { _ = blobs.removeValue(forKey: key) } }
}

private final class FinishCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func hit() { lock.withLock { value += 1 } }
}

private func template(sets: Int = 3) throws -> SessionTemplate {
    let prescription = try SetPrescription(
        targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false
    )
    let exercise = ExerciseID()
    return SessionTemplate(
        title: "Press banca",
        plannedSets: (0..<sets).map { _ in PlannedSet(exerciseID: exercise, prescription: prescription) }
    )
}

@MainActor
private func makeCoordinator(
    template: SessionTemplate, clock: TickClock, store: SpyStore, finished: FinishCounter = FinishCounter()
) -> WorkoutSessionCoordinator {
    let repository = FileWorkoutRepository(store: store)
    return WorkoutSessionCoordinator(
        template: template,
        clock: { clock.now },
        onSessionFinished: { _ in finished.hit() },
        persistSession: { try repository.persist($0) }
    )
}

@MainActor
@Suite("SCRUM-25 · Cerrar bien la sesión al terminar")
struct WorkoutClosingTests {

    @Test("La última serie pasa la sesión a completed con hora de fin y muestra el resumen")
    func lastSetCompletesTheSession() async throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(), clock: clock, store: store)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet(); clock.advance(30)
        _ = try coordinator.completeCurrentSet(); clock.advance(30)
        let phase = try coordinator.completeCurrentSet()

        guard case .finished(let summary) = phase else { Issue.record("debía mostrar el resumen: \(phase)"); return }
        #expect(summary.workingSets == 3)
        let saved = try #require(try await FileWorkoutRepository(store: store).allSessions().first)
        #expect(saved.lifecycle == .completed)
        #expect(saved.endedAt == clock.now)
        #expect(saved.sets.count == 3)
    }

    @Test("Durante 60 s en el resumen no hay ninguna escritura adicional (tick no escribe)")
    func noWritesWhileOnSummary() async throws {
        let clock = TickClock()
        let store = SpyStore()
        let finished = FinishCounter()
        let coordinator = makeCoordinator(template: try template(), clock: clock, store: store, finished: finished)
        _ = coordinator.start()
        for _ in 1...3 { _ = try coordinator.completeCurrentSet(); clock.advance(10) }
        let writesAtSummary = store.writeCount

        for _ in 1...60 {          // un tick por segundo, durante 60 s
            clock.advance(1)
            coordinator.tick()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.writeCount == writesAtSummary, "tick() escribió en disco")
        #expect(finished.count == 1, "el aviso de cierre debe darse una sola vez, no por tick")
    }

    @Test("tick() durante el entrenamiento tampoco escribe")
    func tickNeverWritesWhileTraining() throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(), clock: clock, store: store)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        let before = store.writeCount
        for _ in 1...120 { clock.advance(1); coordinator.tick() }
        #expect(store.writeCount == before)
    }

    @Test("Cada cambio de estado escribe exactamente una vez: iniciar, serie, pausa, reanudar, fin")
    func onlyStateChangesPersist() throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(sets: 4), clock: clock, store: store)
        _ = coordinator.start();                         #expect(store.writeCount == 1)
        _ = try coordinator.completeCurrentSet();        #expect(store.writeCount == 2)
        _ = try coordinator.pause();                     #expect(store.writeCount == 3)
        _ = try coordinator.resume();                    #expect(store.writeCount == 4)
        _ = try coordinator.abandon();                   #expect(store.writeCount == 5)
        coordinator.tick(); coordinator.tick();          #expect(store.writeCount == 5)
    }

    @Test("La duración del resumen no crece con el reloj: se calcula desde la hora de fin guardada")
    func durationIsFrozenAtEnd() throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(sets: 2), clock: clock, store: store)
        _ = coordinator.start()
        clock.advance(120)
        _ = try coordinator.completeCurrentSet()
        clock.advance(60)
        guard case .finished(let first) = try coordinator.completeCurrentSet() else {
            Issue.record("debía terminar"); return
        }
        clock.advance(3_600)
        coordinator.tick()
        guard case .finished(let later) = coordinator.phase else { Issue.record("sigue terminada"); return }
        #expect(first.durationSeconds == 180)
        #expect(later.durationSeconds == 180)
    }

    @Test("El resumen sale de los datos guardados: series de trabajo, volumen y duración")
    func summaryMatchesSavedData() async throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(), clock: clock, store: store)
        _ = coordinator.start()
        for _ in 1...3 { _ = try coordinator.completeCurrentSet(); clock.advance(20) }
        guard case .finished(let summary) = coordinator.phase else { Issue.record("debía terminar"); return }

        let saved = try #require(try await FileWorkoutRepository(store: store).allSessions().first)
        let rebuilt = WorkoutSummaryBuilder().summarize(saved)
        #expect(summary.workingSets == rebuilt.workingSets)
        #expect(summary.volume == rebuilt.volume)
        #expect(summary.durationSeconds == rebuilt.durationSeconds)
        #expect(summary.volume > 0)
    }

    @Test("Si faltan series, Completar deja completed y Abandonar deja abandoned; ambas conservan las series")
    func completeOrAbandonKeepSets() async throws {
        for finish in ["complete", "abandon"] {
            let clock = TickClock()
            let store = SpyStore()
            let coordinator = makeCoordinator(template: try template(sets: 5), clock: clock, store: store)
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet(); clock.advance(5)
            _ = try coordinator.completeCurrentSet(); clock.advance(5)
            if finish == "complete" { _ = try coordinator.complete() } else { _ = try coordinator.abandon() }

            let saved = try #require(try await FileWorkoutRepository(store: store).allSessions().first)
            #expect(saved.lifecycle == (finish == "complete" ? .completed : .abandoned), "\(finish)")
            #expect(saved.sets.count == 2, "\(finish): las series hechas se conservan")
            #expect(saved.endedAt != nil)
        }
    }

    @Test("Desde un estado final, cualquier otra transición se rechaza")
    func finalStatesRejectTransitions() throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(sets: 3), clock: clock, store: store)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.abandon()
        let writes = store.writeCount

        #expect(throws: WorkoutSessionError.self) { _ = try coordinator.complete() }
        #expect(throws: WorkoutSessionError.self) { _ = try coordinator.abandon() }
        #expect(throws: WorkoutSessionError.self) { _ = try coordinator.pause() }
        #expect(throws: WorkoutSessionError.self) { _ = try coordinator.resume() }
        #expect(throws: WorkoutSessionError.self) { _ = try coordinator.completeCurrentSet() }
        #expect(store.writeCount == writes, "los rechazos no escriben")

        // Completada: abandonar/pausar se rechazan; completar de nuevo es idempotente.
        let other = makeCoordinator(template: try template(sets: 1), clock: clock, store: SpyStore())
        _ = other.start()
        _ = try other.completeCurrentSet()
        #expect(throws: WorkoutSessionError.self) { _ = try other.abandon() }
        #expect(throws: WorkoutSessionError.self) { _ = try other.pause() }
        if case .finished = try other.complete() {} else { Issue.record("completar de nuevo debe seguir mostrando el resumen") }
    }

    @Test("Completar desde pausa funciona (reanuda y cierra)")
    func completeFromPaused() async throws {
        let clock = TickClock()
        let store = SpyStore()
        let coordinator = makeCoordinator(template: try template(sets: 3), clock: clock, store: store)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.pause()
        _ = try coordinator.complete()
        let saved = try #require(try await FileWorkoutRepository(store: store).allSessions().first)
        #expect(saved.lifecycle == .completed)
    }

    @Test("Export cuenta el entrenamiento una sola vez y como completado, aunque haya muchos ticks")
    func exportCountsOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-close-\(UUID().uuidString)", isDirectory: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TickClock()
        let (persisted, continuation) = AsyncStream<Result<WorkoutID, any Error>>.makeStream()
        let coordinator = try await persistence.makeWorkoutCoordinator(
            template: try template(sets: 2), clock: { clock.now },
            onPersisted: { continuation.yield($0) }
        )
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.completeCurrentSet()
        for _ in 1...30 { clock.advance(1); coordinator.tick() }
        for await result in persisted { _ = try result.get(); break }

        let history = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())
        #expect(history.sessions.count == 1)
        #expect(history.sessions.first?.lifecycle == .completed)
    }
}
