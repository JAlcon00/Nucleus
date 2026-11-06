//
//  PhoneWatchBridgeTests.swift
//  PRCoreTests
//
//  SCRUM-255 (PR-G004): una serie hecha en el reloj llega al iPhone, se guarda antes de
//  aplicarse y nunca se duplica ni se pierde. Con `LocalPersistence` real en un directorio
//  temporal: la serie sobrevive a que la app esté cerrada.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func press(_ name: String) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: .horizontalPress,
        primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
        equipment: .barbell,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [.primaryCompound],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [.horizontalPress]).id
    )
}

@MainActor
private struct Rig {
    let exercise: Exercise
    let template: SessionTemplate
    let persistence: LocalPersistence
    let link = FakeWorkoutLink()
    let bridge: PhoneWatchBridge

    init(sets: Int = 3) throws {
        exercise = try press("Press")
        let work = try SetPrescription(targetRepRange: 8...10, loadUnit: .kilograms, restSeconds: 60...60)
        let id = exercise.id
        template = SessionTemplate(title: "Pecho", plannedSets: (0..<sets).map { _ in PlannedSet(exerciseID: id, prescription: work) })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        self.persistence = persistence
        bridge = PhoneWatchBridge(link: link, clock: { now }) {
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
    }

    func coordinator(restoring: WorkoutSessionRecord? = nil) async throws -> WorkoutSessionCoordinator {
        try await persistence.makeWorkoutCoordinator(
            template: template, exerciseNames: [exercise.id: exercise.canonicalName],
            catalog: [exercise], clock: { now }, restoring: restoring
        )
    }

    func set(weight: Double = 60, at offset: TimeInterval = 10) throws -> SetRecord {
        try SetRecord(
            exerciseID: exercise.id, performedAt: now.addingTimeInterval(offset),
            weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed
        )
    }

    func message(_ set: SetRecord, slot: Int, session: WorkoutID) -> WatchMessage {
        .event(SetEvent(
            device: WorkoutDevice.watch, emittedAt: set.performedAt,
            slot: SetSlot(exerciseID: exercise.id, slotIndex: slot),
            action: .recorded(set), sessionID: session
        ))
    }

    func stored(_ id: WorkoutID) async throws -> WorkoutSessionRecord? {
        try await persistence.workoutRepository().session(id: id)
    }
}

@MainActor
@Suite("SCRUM-255 · Puente iPhone ⇄ reloj")
struct PhoneWatchBridgeTests {

    @Test("Una serie del reloj se guarda en la cola, aparece en la pantalla y el estado la confirma")
    func setFromWatchShowsUp() async throws {
        let rig = try Rig()
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        let session = try coordinator.snapshot().session.id
        let set = try rig.set()

        #expect(try await rig.bridge.handle(rig.message(set, slot: 1, session: session)) == .appliedLive)

        #expect(try coordinator.snapshot().session.sets.map(\.id) == [set.id])
        #expect(coordinator.currentSet()?.position == 2)
        #expect(try rig.persistence.pendingOperationQueue().load().contains(idempotencyKey: set.id.rawValue.persistenceKey))
        #expect(try await rig.stored(session)?.sets.map(\.id) == [set.id], "Queda guardada en disco.")
        await rig.bridge.flush()
        #expect(rig.link.publishedSnapshots.last?.confirmedSetIDs == [set.id])
    }

    @Test("La misma serie entregada dos veces cuenta una")
    func duplicateDelivery() async throws {
        let rig = try Rig()
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        let session = try coordinator.snapshot().session.id
        let message = rig.message(try rig.set(), slot: 1, session: session)
        try await rig.bridge.handle(message)
        try await rig.bridge.handle(message)
        #expect(try coordinator.snapshot().session.sets.count == 1)
        #expect(try rig.persistence.pendingOperationQueue().load().count == 1)
    }

    @Test("Con la app cerrada la serie se aplica a lo guardado y sigue ahí al abrir")
    func appClosed() async throws {
        let rig = try Rig()
        let first = try await rig.coordinator()
        _ = first.start()
        let record = try first.snapshot().session
        let set = try rig.set()

        #expect(try await rig.bridge.handle(rig.message(set, slot: 1, session: record.id)) == .appliedStored)

        let stored = try #require(try await rig.stored(record.id))
        let reopened = try await rig.coordinator(restoring: stored)
        #expect(try reopened.snapshot().session.sets.map(\.id) == [set.id])
        #expect(reopened.currentSet()?.position == 2)
    }

    @Test("Una serie de una sesión ya terminada se agrega a esa sesión y se confirma al reloj")
    func finishedSession() async throws {
        let rig = try Rig()
        let coordinator = try await rig.coordinator()
        _ = coordinator.start()
        _ = try coordinator.recordEditedSet(weight: 60, reps: 8)
        _ = try coordinator.complete()
        let session = try coordinator.snapshot().session
        let late = try rig.set(at: 500)

        #expect(try await rig.bridge.handle(rig.message(late, slot: 2, session: session.id)) == .appliedStored)

        let stored = try #require(try await rig.stored(session.id))
        #expect(stored.sets.count == 2, "Nunca se tira ni crea otra sesión.")
        #expect(stored.lifecycle == .completed)
        await rig.bridge.flush()
        let confirmation = try #require(rig.link.publishedSnapshots.last)
        #expect(confirmation.stage == .finished)
        #expect(confirmation.confirmedSetIDs.contains(late.id))
    }

    @Test("La misma serie hecha en los dos, sin conexión: quedan las dos")
    func conflictKeepsBoth() async throws {
        let rig = try Rig()
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        _ = try coordinator.recordEditedSet(weight: 60, reps: 8, now: now)
        let session = try coordinator.snapshot().session.id
        let watch = try rig.set(weight: 62.5, at: 30)

        try await rig.bridge.handle(rig.message(watch, slot: 1, session: session))

        let record = try coordinator.snapshot().session
        #expect(record.sets.map(\.weight) == [62.5], "Queda la más reciente.")
        #expect(record.setConflicts?.map(\.set.weight) == [60], "Y la otra no se pierde.")
        #expect(coordinator.currentSet()?.position == 2, "No se cuenta una serie de más.")
        #expect(try await rig.stored(session)?.setConflicts?.count == 1)
    }

    @Test("La última serie hecha en el reloj cierra la sesión del iPhone")
    func lastSetClosesSession() async throws {
        let rig = try Rig(sets: 1)
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        let session = try coordinator.snapshot().session.id
        try await rig.bridge.handle(rig.message(try rig.set(), slot: 1, session: session))
        guard case .finished = coordinator.phase else {
            Issue.record("La sesión debía terminar")
            return
        }
        await rig.bridge.flush()
        #expect(rig.link.publishedSnapshots.last?.stage == .finished)
    }

    @Test("Los estados salen en orden: el último publicado es el que queda")
    func publishesInOrder() async throws {
        let rig = try Rig(sets: 20)
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        for _ in 0..<19 { _ = try coordinator.recordEditedSet(weight: 60, reps: 8) }
        await rig.bridge.flush()
        let counts = rig.link.publishedSnapshots.map(\.confirmedSetIDs.count)
        #expect(counts == counts.sorted())
        #expect(counts.last == 19)
    }

    @Test("Un cambio en el iPhone se publica; lo que no cambia no se reenvía")
    func publishesOnlyChanges() async throws {
        let rig = try Rig()
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        await rig.bridge.flush()
        let afterStart = rig.link.publishedSnapshots.count
        #expect(afterStart == 1)
        coordinator.skipRest()
        await rig.bridge.flush()
        #expect(rig.link.publishedSnapshots.count == afterStart, "Nada cambió para el reloj.")
        _ = try coordinator.recordEditedSet(weight: 60, reps: 8)
        await rig.bridge.flush()
        #expect(rig.link.publishedSnapshots.count > afterStart)
    }

    @Test("Sin sesión con ese id la serie se queda en la cola, sin perderse")
    func unknownSessionStaysQueued() async throws {
        let rig = try Rig()
        let set = try rig.set()
        #expect(try await rig.bridge.handle(rig.message(set, slot: 1, session: WorkoutID())) == .noChange)
        #expect(try rig.persistence.pendingOperationQueue().load().count == 1)
    }

    @Test("Sin almacén todavía, falla para que el reloj la conserve")
    func noStorageThrows() async throws {
        let rig = try Rig()
        let bridge = PhoneWatchBridge(link: rig.link, clock: { now }) { nil }
        await #expect(throws: WatchBridgeError.storageUnavailable) {
            try await bridge.handle(rig.message(try rig.set(), slot: 1, session: WorkoutID()))
        }
    }

    @Test("50 series acumuladas llegan todas y una sola vez")
    func manySets() async throws {
        let rig = try Rig(sets: 50)
        let coordinator = try await rig.coordinator()
        rig.bridge.attach(coordinator)
        _ = coordinator.start()
        let session = try coordinator.snapshot().session.id
        var messages: [WatchMessage] = []
        for index in 1...50 {
            messages.append(rig.message(try rig.set(at: TimeInterval(index)), slot: index, session: session))
        }
        for message in messages + messages { try await rig.bridge.handle(message) }
        #expect(try coordinator.snapshot().session.sets.count == 50)
        guard case .finished = coordinator.phase else {
            Issue.record("La sesión debía terminar")
            return
        }
    }

    @Test("Lo que viaja se lee igual del otro lado")
    func messageRoundTrip() throws {
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed)
        let message = WatchMessage.event(SetEvent(device: WorkoutDevice.watch, action: .recorded(set), sessionID: WorkoutID()))
        #expect(try WatchWireCodec.decode(WatchMessage.self, from: WatchWireCodec.encode(message)) == message)
    }

    @Test("Una serie pendiente guardada antes de esta historia se lee igual")
    func oldPendingOperationDecodes() throws {
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed)
        let old = try JSONEncoder().encode(OldSetSave(sessionID: WorkoutID(), set: set))
        let read = try JSONDecoder().decode(StoredSetSave.self, from: old)
        #expect(read.slot == nil)
        #expect(read.device == nil)
        #expect(read.set == set)
    }
}

/// La forma de `StoredSetSave` antes de SCRUM-255.
private struct OldSetSave: Encodable {
    let sessionID: WorkoutID
    let set: SetRecord
}
