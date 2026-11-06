//
//  WatchOutboxTests.swift
//  PRCoreTests
//
//  SCRUM-256 (PR-G005): el reloj guarda primero en el reloj. Con `AtomicFileRepositoryStore`
//  real en un directorio temporal: la serie sobrevive a cerrar la app y se reenvía sin
//  duplicar hasta que el iPhone la confirma.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let start = Date(timeIntervalSince1970: 1_792_670_400)

/// Reloj de prueba que se puede adelantar.
@MainActor
private final class Ticker {
    var now = start
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Un almacén cuya escritura se puede romper a propósito.
private final class BreakableStore: RepositoryStore, @unchecked Sendable {
    let backing = MemoryRepositoryStore()
    var failsWrites = false
    func read(key: String) throws -> Data? { try backing.read(key: key) }
    func readAll() throws -> [Data] { try backing.readAll() }
    func readAllEntries() throws -> StoreReadResult { try backing.readAllEntries() }
    func write(key: String, data: Data) throws {
        if failsWrites { throw CocoaError(.fileWriteOutOfSpace) }
        try backing.write(key: key, data: data)
    }
    func delete(key: String) throws { try backing.delete(key: key) }
}

private struct Plan {
    let session = WorkoutID()
    let bench = ExerciseID()
    let row = ExerciseID()

    func set(_ exercise: ExerciseID, number: Int, weight: Double? = 60, rest: Int? = 90) -> WatchPlannedSet {
        WatchPlannedSet(
            slot: SetSlot(exerciseID: exercise, slotIndex: number),
            exerciseName: exercise == bench ? "Press" : "Remo",
            totalInExercise: 2, targetRepRange: 8...12, targetReps: 8, weight: weight,
            unit: .kilograms, isWarmup: false, restSecondsAfter: rest, supersetPartner: nil
        )
    }

    func snapshot(
        revision: Int = 1,
        stage: WatchSessionStage = .active,
        confirmed: [SetRecordID] = [],
        remaining: [WatchPlannedSet]? = nil,
        session: WorkoutID? = nil
    ) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: session ?? self.session, revision: revision, title: "Torso", stage: stage,
            confirmedSetIDs: confirmed, restEndsAt: nil,
            remaining: remaining ?? [set(bench, number: 1), set(bench, number: 2), set(row, number: 1, rest: nil)]
        )
    }
}

@MainActor
private func controller(
    store: any RepositoryStore,
    link: FakeWorkoutLink = FakeWorkoutLink(),
    ticker: Ticker = Ticker()
) -> WatchSessionController {
    WatchSessionController(store: WatchLocalStore(store: store), link: link, clock: { ticker.now })
}

private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-watch-box-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func recordedSet(_ message: WatchMessage?) throws -> SetRecord {
    guard case .event(let event)? = message, case .recorded(let set) = event.action else {
        throw WatchSessionError.noSession
    }
    return set
}

@MainActor
@Suite("SCRUM-256 · El reloj guarda primero en el reloj")
struct WatchOutboxTests {

    @Test("La serie queda en disco antes de confirmar, y se manda después")
    func savesBeforeConfirming() async throws {
        let plan = Plan()
        let store = try AtomicFileRepositoryStore(directory: directory())
        let link = FakeWorkoutLink()
        let watch = controller(store: store, link: link)
        await watch.receive(plan.snapshot())

        await watch.completeCurrentSet()

        #expect(watch.confirmedTaps == 1)
        let saved = try WatchLocalStore(store: store).load()
        #expect(saved.done.count == 1)
        #expect(saved.outbox.count == 1)
        #expect(link.sentMessages.count == 1)
        let set = try recordedSet(link.sentMessages.first)
        #expect(set.weight == 60)
        #expect(set.reps == 8)
        #expect(set.lifecycle == .completed)
        #expect(set.performedAt == start)
    }

    @Test("Al cerrar y abrir la app sigue en la misma serie, con lo hecho")
    func survivesRelaunch() async throws {
        let plan = Plan()
        let store = try AtomicFileRepositoryStore(directory: directory())
        let first = controller(store: store)
        await first.receive(plan.snapshot())
        await first.completeCurrentSet()

        let reopened = controller(store: store)
        #expect(reopened.state.currentSet?.slot.slotIndex == 2)
        #expect(reopened.state.done.count == 1)
        #expect(reopened.draftWeight == 60)
    }

    @Test("Lo que falta confirmar se reenvía sin cambiar: el iPhone lo cuenta una vez")
    func resendsPending() async throws {
        let plan = Plan()
        let store = MemoryRepositoryStore()
        let first = controller(store: store)
        await first.receive(plan.snapshot())
        await first.completeCurrentSet()

        let link = FakeWorkoutLink()
        let reopened = controller(store: store, link: link)
        await reopened.phoneReachabilityChanged(true)
        #expect(reopened.isPhoneReachable)
        let resent = try recordedSet(link.sentMessages.first)
        #expect(resent.id == (try recordedSet(reopened.state.outbox.first)).id)
    }

    @Test("Sólo un estado con la serie confirmada la quita del buzón")
    func onlyConfirmationPrunes() async throws {
        let plan = Plan()
        let watch = controller(store: MemoryRepositoryStore())
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        let set = try recordedSet(watch.state.outbox.first)

        await watch.receive(plan.snapshot(revision: 2))
        #expect(watch.state.pendingCount == 1, "Sin confirmación se queda.")

        await watch.receive(plan.snapshot(revision: 3, confirmed: [set.id], remaining: [plan.set(plan.bench, number: 2)]))
        #expect(watch.state.pendingCount == 0)
    }

    @Test("Si no se pudo escribir, la serie no cuenta y lo dice")
    func writeFailureDoesNotConfirm() async throws {
        let plan = Plan()
        let store = BreakableStore()
        let link = FakeWorkoutLink()
        let watch = controller(store: store, link: link)
        await watch.receive(plan.snapshot())
        store.failsWrites = true

        await watch.completeCurrentSet()

        #expect(watch.saveFailed)
        #expect(watch.confirmedTaps == 0)
        #expect(watch.state.done.isEmpty)
        #expect(link.sentMessages.isEmpty)
        #expect(watch.state.currentSet?.slot.slotIndex == 1, "Sigue en la misma serie.")
    }

    @Test("Sin iPhone se hace toda la sesión con lo que ya se recibió")
    func wholeSessionOffline() async throws {
        let plan = Plan()
        let ticker = Ticker()
        let watch = controller(store: MemoryRepositoryStore(), ticker: ticker)
        await watch.receive(plan.snapshot())
        for _ in 0..<3 {
            await watch.completeCurrentSet()
            ticker.advance(120)
        }
        #expect(watch.state.done.count == 3)
        #expect(watch.state.pendingCount == 3)
        #expect(watch.screen == .allDone)
    }

    @Test("Terminada y confirmada, el reloj se limpia")
    func cleansAfterConfirmation() async throws {
        let plan = Plan()
        let store = try AtomicFileRepositoryStore(directory: directory())
        let watch = controller(store: store)
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        let set = try recordedSet(watch.state.outbox.first)

        await watch.receive(plan.snapshot(revision: 2, stage: .finished, confirmed: [set.id], remaining: []))

        #expect(watch.screen == .finished)
        #expect(try store.read(key: "session") == nil, "En disco no queda nada.")
    }

    @Test("Terminada pero sin confirmar, se conserva")
    func keepsUnconfirmedFinished() async throws {
        let plan = Plan()
        let store = MemoryRepositoryStore()
        let watch = controller(store: store)
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        await watch.receive(plan.snapshot(revision: 2, stage: .finished, remaining: []))
        #expect(try WatchLocalStore(store: store).load().pendingCount == 1)
    }

    @Test("Una sesión de ayer sin confirmar se conserva al empezar otra, y se reenvía")
    func yesterdaySessionStaysQueued() async throws {
        let plan = Plan()
        let link = FakeWorkoutLink()
        let watch = controller(store: MemoryRepositoryStore(), link: link)
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        let sentBefore = link.sentMessages.count

        let today = Plan()
        await watch.receive(today.snapshot())

        #expect(watch.state.snapshot?.sessionID == today.session)
        #expect(watch.state.done.isEmpty)
        #expect(watch.state.pendingCount == 1)
        #expect(link.sentMessages.count > sentBefore, "Se vuelve a mandar.")
    }

    @Test("La confirmación de una sesión vieja no reemplaza a la de hoy")
    func oldFinishedOnlyConfirms() async throws {
        let plan = Plan()
        let watch = controller(store: MemoryRepositoryStore())
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        let set = try recordedSet(watch.state.outbox.first)
        let today = Plan()
        await watch.receive(today.snapshot())

        await watch.receive(plan.snapshot(revision: 9, stage: .finished, confirmed: [set.id], remaining: []))

        #expect(watch.state.snapshot?.sessionID == today.session)
        #expect(watch.state.pendingCount == 0)
    }

    @Test("Un estado viejo no reemplaza a uno nuevo, pero sí confirma")
    func staleSnapshotIsIgnored() async throws {
        let plan = Plan()
        let watch = controller(store: MemoryRepositoryStore())
        await watch.receive(plan.snapshot(revision: 5))
        await watch.receive(plan.snapshot(revision: 4, stage: .paused))
        #expect(watch.state.snapshot?.revision == 5)
        #expect(watch.state.snapshot?.stage == .active)
    }

    @Test("Con series sin confirmar, las locales mandan sobre un estado que aún no las trae")
    func localSetsWin() async throws {
        let plan = Plan()
        let watch = controller(store: MemoryRepositoryStore())
        await watch.receive(plan.snapshot())
        await watch.completeCurrentSet()
        await watch.receive(plan.snapshot(revision: 2))
        #expect(watch.state.currentSet?.slot.slotIndex == 2)
    }

    @Test("Un archivo ilegible no se borra y la pantalla lo dice")
    func unreadableFile() throws {
        let store = MemoryRepositoryStore()
        try store.write(key: "session", data: Data("no es json".utf8))
        let watch = controller(store: store)
        #expect(watch.screen == .failed)
        #expect(try store.read(key: "session") != nil)
    }
}
