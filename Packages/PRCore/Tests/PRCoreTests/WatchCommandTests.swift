//
//  WatchCommandTests.swift
//  PRCoreTests
//
//  SCRUM-259 (PR-G008): pausar y terminar desde el reloj, también sin iPhone. Con
//  `LocalPersistence` real en un directorio temporal: terminar en el reloj sin conexión deja
//  la sesión completa al reconectar, con un solo cierre y un solo resumen.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func press() throws -> Exercise {
    Exercise(
        canonicalName: "Press",
        movementPattern: .horizontalPress,
        primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
        equipment: .barbell,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [.primaryCompound],
        substitutionFamilyID: ExerciseFamily(name: "Press", movementPatterns: [.horizontalPress]).id
    )
}

/// Cuenta los cierres que avisa el coordinador.
@MainActor
private final class Closures {
    var count = 0
}

@MainActor
private final class Rig {
    let link = FakeWorkoutLink()
    let exercise: Exercise
    let template: SessionTemplate
    let persistence: LocalPersistence
    let bridge: PhoneWatchBridge
    let phone: WorkoutSessionCoordinator
    let watch: WatchSessionController
    let session: WorkoutID
    var clockNow = now

    init() async throws {
        exercise = try press()
        let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...60)
        let id = exercise.id
        template = SessionTemplate(title: "Pecho", plannedSets: (0..<3).map { _ in PlannedSet(exerciseID: id, prescription: work) })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-watch-cmd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        self.persistence = persistence
        let link = self.link
        bridge = PhoneWatchBridge(link: link, clock: { now }) {
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
        phone = try await persistence.makeWorkoutCoordinator(
            template: template, exerciseNames: [exercise.id: "Press"], catalog: [exercise], clock: { now }
        )
        bridge.attach(phone)
        _ = phone.start()
        session = try phone.snapshot().session.id
        var tick = now
        watch = WatchSessionController(store: WatchLocalStore(store: MemoryRepositoryStore()), link: link, clock: {
            tick = tick.addingTimeInterval(30)
            return tick
        })
        await sync()
    }

    func sync() async {
        await bridge.flush()
        if let latest = link.publishedSnapshots.last { await watch.receive(latest) }
    }

    func deliver() async throws {
        for message in watch.state.outbox { try await bridge.handle(message) }
        await sync()
    }

    func stored() async throws -> WorkoutSessionRecord? {
        try await persistence.workoutRepository().session(id: session)
    }

    func command(_ kind: WatchSessionCommandKind, at offset: TimeInterval = 10) -> WatchSessionCommand {
        WatchSessionCommand(sessionID: session, kind: kind, issuedAt: now.addingTimeInterval(offset))
    }
}

@MainActor
@Suite("SCRUM-259 · Pausar y terminar desde el reloj")
struct WatchCommandTests {

    @Test("Pausar en el reloj pausa el iPhone, y reanudar lo reanuda")
    func pauseFromWatch() async throws {
        let rig = try await Rig()
        await rig.watch.pause()
        #expect(!rig.watch.canComplete, "No se completan series en pausa.")
        try await rig.deliver()
        guard case .paused = rig.phone.phase else {
            Issue.record("El iPhone debía quedar en pausa")
            return
        }
        #expect(rig.watch.state.pendingCount == 0)

        await rig.watch.resume()
        try await rig.deliver()
        guard case .active = rig.phone.phase else {
            Issue.record("El iPhone debía reanudar")
            return
        }
        #expect(rig.watch.canComplete)
    }

    @Test("Pausar en el iPhone pausa el reloj")
    func pauseFromPhone() async throws {
        let rig = try await Rig()
        _ = try rig.phone.pause()
        await rig.sync()
        guard case .paused = rig.watch.screen else {
            Issue.record("El reloj debía quedar en pausa")
            return
        }
    }

    @Test("Terminar sin conexión: al reconectar la sesión se completa con la hora real del reloj")
    func finishOffline() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        await rig.watch.finish()
        #expect(rig.watch.screen == .finished)
        #expect(rig.watch.finishedSummary?.isSaved == false, "Todavía no está guardado.")
        #expect(rig.watch.finishedSummary?.sets == 1)
        let endedOnWatch = try #require(rig.watch.state.finishedAt)

        try await rig.deliver()

        guard case .finished = rig.phone.phase else {
            Issue.record("La sesión del iPhone debía cerrarse")
            return
        }
        let stored = try #require(try await rig.stored())
        #expect(stored.lifecycle == .completed)
        #expect(stored.endedAt == endedOnWatch)
        #expect(stored.sets.count == 1)
        #expect(rig.watch.finishedSummary?.isSaved == true)
        #expect(rig.watch.state.pendingCount == 0)
    }

    @Test("Con la app del iPhone cerrada también se cierra, sobre lo guardado")
    func finishWithAppClosed() async throws {
        let rig = try await Rig()
        let closed = PhoneWatchBridge(link: rig.link, clock: { now }) { [persistence = rig.persistence] in
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
        let set = try SetRecord(exerciseID: rig.exercise.id, performedAt: now, weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed)
        try await closed.handle(.event(SetEvent(
            device: WorkoutDevice.watch, slot: SetSlot(exerciseID: rig.exercise.id, slotIndex: 1),
            action: .recorded(set), sessionID: rig.session
        )))
        let finish = rig.command(.finish, at: 300)

        #expect(try await closed.handle(.command(finish)) == .appliedStored)

        let stored = try #require(try await rig.stored())
        #expect(stored.lifecycle == .completed)
        #expect(stored.endedAt == finish.issuedAt)
        #expect(stored.appliedCommandIDs == [finish.id])
        await closed.flush()
        #expect(rig.link.publishedSnapshots.last?.confirmedCommandIDs == [finish.id])
    }

    @Test("Sin series, terminar abandona: no hay entrenamiento que cerrar")
    func finishWithoutSets() async throws {
        let rig = try await Rig()
        rig.phone.applyRemoteCommand(rig.command(.finish))
        #expect(try rig.phone.snapshot().session.lifecycle == .abandoned)
    }

    @Test("Si los dos terminan queda un solo cierre y un solo resumen")
    func bothFinish() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        _ = try rig.phone.complete(now: now.addingTimeInterval(100))
        let ended = try rig.phone.snapshot().session.endedAt
        let phase = rig.phone.phase

        rig.phone.applyRemoteCommand(rig.command(.finish, at: 200))

        #expect(try rig.phone.snapshot().session.endedAt == ended, "Gana el primer cierre.")
        #expect(rig.phone.phase == phase)
    }

    @Test("Un comando repetido no hace nada", arguments: [WatchSessionCommandKind.pause, .finish])
    func repeatedCommand(kind: WatchSessionCommandKind) async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        let command = rig.command(kind)
        #expect(rig.phone.applyRemoteCommand(command))
        let first = try rig.phone.snapshot().session
        #expect(!rig.phone.applyRemoteCommand(command))
        #expect(try rig.phone.snapshot().session == first)
    }

    @Test("Una pausa vieja no deshace una reanudación nueva")
    func outOfOrder() async throws {
        let rig = try await Rig()
        let pause = rig.command(.pause, at: 10)
        let resume = rig.command(.resume, at: 20)
        rig.phone.applyRemoteCommand(resume)
        rig.phone.applyRemoteCommand(pause)
        guard case .active = rig.phone.phase else {
            Issue.record("Debe quedar lo más reciente")
            return
        }
        #expect(try rig.phone.snapshot().session.appliedCommandIDs?.count == 2, "Los dos quedan confirmados.")
    }

    @Test("Una pausa después de terminar no reabre nada")
    func pauseAfterFinish() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        rig.phone.applyRemoteCommand(rig.command(.finish, at: 10))
        rig.phone.applyRemoteCommand(rig.command(.pause, at: 5))
        #expect(try rig.phone.snapshot().session.lifecycle == .completed)
    }

    @Test("Terminar en pausa también cierra")
    func finishWhilePaused() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        _ = try rig.phone.pause()
        rig.phone.applyRemoteCommand(rig.command(.finish))
        #expect(try rig.phone.snapshot().session.lifecycle == .completed)
    }

    @Test("Terminar en el iPhone con el reloj apagado: al volver, el reloj se entera")
    func finishOnPhone() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        _ = try rig.phone.complete()
        await rig.sync()
        #expect(rig.watch.screen == .finished)
        #expect(rig.watch.finishedSummary?.sets == 1)
    }

    @Test("Sin sesión con ese id, falla para que el reloj conserve el comando")
    func unknownSession() async throws {
        let rig = try await Rig()
        let other = WatchSessionCommand(sessionID: WorkoutID(), kind: .finish, issuedAt: now)
        await #expect(throws: WatchBridgeError.sessionNotFound) {
            try await rig.bridge.handle(.command(other))
        }
    }

    // MARK: - Series en conflicto

    private func conflicted() async throws -> Rig {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8, now: now)
        let set = try SetRecord(
            exerciseID: rig.exercise.id, performedAt: now.addingTimeInterval(30),
            weight: 62.5, unit: .kilograms, reps: 8, lifecycle: .completed
        )
        rig.phone.applyRemoteSet(set, slot: SetSlot(exerciseID: rig.exercise.id, slotIndex: 1), device: WorkoutDevice.watch)
        _ = try rig.phone.complete()
        return rig
    }

    @Test("El resumen muestra las dos series; si no eligen, nada se borra")
    func conflictIsShown() async throws {
        let rig = try await conflicted()
        let conflict = try #require(rig.phone.setConflicts.first)
        #expect(conflict.exerciseName == "Press")
        #expect(conflict.setNumber == 1)
        #expect(conflict.current.weight == 62.5)
        #expect(conflict.other.weight == 60)
        let stored = try #require(try await rig.stored())
        #expect(stored.sets.count + (stored.setConflicts?.count ?? 0) == 2)
    }

    @Test("Elegir la otra la pone en su lugar y rehace el resumen")
    func keepOther() async throws {
        let rig = try await conflicted()
        let conflict = try #require(rig.phone.setConflicts.first)
        rig.phone.resolveSetConflict(conflict.id, choice: .keepOther)
        let session = try rig.phone.snapshot().session
        #expect(session.sets.map(\.weight) == [60])
        #expect(session.setConflicts == nil)
        guard case .finished(let summary) = rig.phone.phase else {
            Issue.record("Sigue en el resumen")
            return
        }
        #expect(summary.volume == 480)
    }

    @Test("Conservar la actual descarta sólo la otra")
    func keepCurrent() async throws {
        let rig = try await conflicted()
        let conflict = try #require(rig.phone.setConflicts.first)
        rig.phone.resolveSetConflict(conflict.id, choice: .keepCurrent)
        #expect(try rig.phone.snapshot().session.sets.map(\.weight) == [62.5])
        #expect(rig.phone.setConflicts.isEmpty)
    }

    @Test("Conservar las dos deja dos series, en orden, y queda en disco")
    func keepBoth() async throws {
        let rig = try await conflicted()
        let conflict = try #require(rig.phone.setConflicts.first)
        rig.phone.resolveSetConflict(conflict.id, choice: .keepBoth)
        #expect(try rig.phone.snapshot().session.sets.map(\.weight) == [60, 62.5])
        #expect(try await rig.stored()?.sets.count == 2)
        #expect(try await rig.stored()?.setConflicts == nil)
    }

    @Test("Una sesión guardada antes de esta historia se lee igual")
    func oldSessionDecodes() throws {
        let session = WorkoutSessionRecord(lifecycle: .completed)
        let data = try JSONEncoder().encode(session)
        let read = try JSONDecoder().decode(WorkoutSessionRecord.self, from: data)
        #expect(read.appliedCommandIDs == nil)
        #expect(read.lastRemoteCommandAt == nil)
        #expect(read.setConflicts == nil)
    }
}
