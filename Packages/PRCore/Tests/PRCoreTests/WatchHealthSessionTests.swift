//
//  WatchHealthSessionTests.swift
//  PRCoreTests
//
//  SCRUM-258 (PR-G007): la sesión de Salud en el reloj, con un builder falso (nunca HealthKit
//  real). Un fallo de Salud no bloquea el entrenamiento, y el iPhone sabe quién escribe para
//  que en Salud quede un solo entrenamiento.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private actor FakeBuilder: LiveWorkoutBuilder {
    private(set) var starts = 0
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var ends = 0
    private(set) var tagged: String?
    private let failsStart: Bool
    private let failsEnd: Bool
    private let recovers: Bool

    init(failsStart: Bool = false, failsEnd: Bool = false, recovers: Bool = false) {
        self.failsStart = failsStart
        self.failsEnd = failsEnd
        self.recovers = recovers
    }

    func start() async throws {
        if failsStart { throw CocoaError(.featureUnsupported) }
        starts += 1
    }
    func pause() async throws { pauses += 1 }
    func resume() async throws { resumes += 1 }
    func end() async throws -> HealthLiveMetrics {
        if failsEnd { throw CocoaError(.featureUnsupported) }
        ends += 1
        return HealthLiveMetrics(activeKilocalories: 300, heartRateBPM: 120)
    }
    func recover() async throws -> Bool { recovers }
    func tag(syncIdentifier: String) async { tagged = syncIdentifier }
    func averageHeartRate() async -> Double? { 120 }
}

@MainActor
private final class Rig {
    let link = FakeWorkoutLink()
    let builder: FakeBuilder
    let exercise: Exercise
    let persistence: LocalPersistence
    let bridge: PhoneWatchBridge
    let phone: WorkoutSessionCoordinator
    let watch: WatchSessionController
    let session: WorkoutID

    init(builder: FakeBuilder = FakeBuilder(), recordsHealth: Bool = true) async throws {
        self.builder = builder
        exercise = Exercise(
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
        let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...60)
        let id = exercise.id
        let template = SessionTemplate(title: "Pecho", plannedSets: (0..<3).map { _ in PlannedSet(exerciseID: id, prescription: work) })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-watch-health-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        self.persistence = persistence
        bridge = PhoneWatchBridge(link: link, clock: { now }, recordsHealth: recordsHealth) {
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
        phone = try await persistence.makeWorkoutCoordinator(
            template: template, exerciseNames: [exercise.id: "Press"], catalog: [exercise], clock: { now }
        )
        bridge.attach(phone)
        _ = phone.start()
        session = try phone.snapshot().session.id
        var tick = now
        watch = WatchSessionController(
            store: WatchLocalStore(store: MemoryRepositoryStore()), link: link,
            health: HealthLiveWorkoutCoordinator(builder: builder),
            clock: {
                tick = tick.addingTimeInterval(30)
                return tick
            }
        )
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

    var recording: SessionHealthRecording? {
        get throws { try phone.snapshot().session.healthRecording }
    }
}

@MainActor
@Suite("SCRUM-258 · Sesión de Salud en el reloj")
struct WatchHealthSessionTests {

    @Test("Con sesión activa el reloj abre Salud, liga el id y le avisa al iPhone")
    func startsAndNotifies() async throws {
        let rig = try await Rig()
        #expect(await rig.builder.starts == 1)
        #expect(await rig.builder.tagged == HealthWorkoutWrite.syncIdentifier(for: rig.session))
        #expect(rig.watch.state.healthSession == .running)
        try await rig.deliver()
        let recording = try #require(try rig.recording)
        #expect(recording.state == .recording)
        #expect(recording.watchOwnsHealthWorkout, "El iPhone no escribe otro.")
    }

    @Test("Apagado desde el iPhone, el reloj no abre nada")
    func flagOff() async throws {
        let rig = try await Rig(recordsHealth: false)
        #expect(await rig.builder.starts == 0)
        #expect(rig.watch.state.pendingCount == 0)
    }

    @Test("No abre dos sesiones aunque lleguen más estados")
    func startsOnce() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        await rig.sync()
        await rig.watch.syncHealth()
        #expect(await rig.builder.starts == 1)
    }

    @Test("Si Salud no arranca, se entrena igual y el iPhone sabe que le toca escribir")
    func startFailure() async throws {
        let rig = try await Rig(builder: FakeBuilder(failsStart: true))
        #expect(rig.watch.state.healthSession == .failed)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.confirmedTaps == 1, "Las series siguen.")
        try await rig.deliver()
        let recording = try #require(try rig.recording)
        #expect(recording.state == .failed)
        #expect(!recording.watchOwnsHealthWorkout)
    }

    @Test("No reintenta una sesión que ya falló")
    func noRetryAfterFailure() async throws {
        let rig = try await Rig(builder: FakeBuilder(failsStart: true))
        await rig.watch.syncHealth()
        #expect(rig.watch.state.pendingCount == 1, "Un solo aviso de fallo.")
    }

    @Test("Un fallo al iniciar llega con su causa real, no como sesión terminada")
    func startErrorKeepsCause() async {
        let coordinator = HealthLiveWorkoutCoordinator(builder: FakeBuilder(failsStart: true))
        do {
            _ = try await coordinator.start(stateMachine: HealthLiveWorkoutStateMachine())
            Issue.record("Debía fallar")
        } catch let error as HealthLiveWorkoutError {
            guard case .infrastructure = error else {
                Issue.record("Debe ser la causa real, no \(error)")
                return
            }
        } catch {
            Issue.record("Error inesperado")
        }
    }

    @Test("Tras reiniciar el reloj se recupera la sesión, sin abrir otra")
    func recovers() async throws {
        let rig = try await Rig(builder: FakeBuilder(recovers: true))
        #expect(await rig.builder.starts == 0)
        #expect(rig.watch.state.healthSession == .running)
    }

    @Test("Pausar y reanudar siguen a la sesión de entrenamiento")
    func pauseAndResume() async throws {
        let rig = try await Rig()
        await rig.watch.pause()
        #expect(await rig.builder.pauses == 1)
        await rig.watch.resume()
        #expect(await rig.builder.resumes == 1)
    }

    @Test("Una pausa desde el iPhone también pausa Salud")
    func pauseFromPhone() async throws {
        let rig = try await Rig()
        _ = try rig.phone.pause()
        await rig.sync()
        #expect(await rig.builder.pauses == 1)
    }

    @Test("Al terminar se cierra Salud y la energía y el ritmo cardiaco llegan como medidos")
    func finishSavesMetrics() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        await rig.watch.finish()
        #expect(await rig.builder.ends == 1)
        try await rig.deliver()
        let recording = try #require(try rig.recording)
        #expect(recording.state == .saved)
        #expect(recording.activeKilocalories == 300)
        #expect(recording.averageHeartRateBPM == 120)
        #expect(recording.watchOwnsHealthWorkout)
        #expect(rig.watch.state.pendingCount == 0)
    }

    @Test("Terminar en el iPhone también cierra Salud en el reloj")
    func finishFromPhone() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8)
        _ = try rig.phone.complete()
        await rig.sync()
        #expect(await rig.builder.ends == 1)
        try await rig.deliver()
        #expect(try rig.recording?.state == .saved)
    }

    @Test("Si el cierre de Salud falla, el iPhone escribe y las series quedan")
    func endFailure() async throws {
        let rig = try await Rig(builder: FakeBuilder(failsEnd: true))
        await rig.watch.completeCurrentSet()
        await rig.watch.finish()
        try await rig.deliver()
        let session = try rig.phone.snapshot().session
        #expect(session.healthRecording?.watchOwnsHealthWorkout == false)
        #expect(session.sets.count == 1)
    }

    @Test("El reloj marca el entrenamiento con el texto exacto que escribe el iPhone")
    func sameSyncIdentifierAsPhone() async throws {
        let rig = try await Rig(builder: FakeBuilder(failsEnd: true))
        await rig.watch.completeCurrentSet()
        await rig.watch.finish()
        try await rig.deliver()
        let write = try #require(HealthWorkoutWrite(session: try rig.phone.snapshot().session))
        #expect(await rig.builder.tagged == write.syncIdentifier)
    }

    @Test("Lo que escribió el reloj cuenta como propio en el iPhone, aunque venga de otra app")
    func watchWorkoutIsOwn() async throws {
        let rig = try await Rig()
        let sample = HealthWorkoutSample(
            uuid: UUID(),
            start: now,
            end: now.addingTimeInterval(3_600),
            activityType: .strengthTraining,
            activeKilocalories: 300,
            sourceBundleIdentifier: "creadevs.PR.watch",
            sourceName: "PR",
            syncIdentifier: await rig.builder.tagged
        )
        #expect(HealthWorkoutClassifier.isOwn(
            sample, ownBundleIdentifier: "creadevs.PR", ownSyncIdentifiers: [rig.session.rawValue.uuidString]
        ))
    }

    @Test("Un aviso repetido o que llega tarde no deshace que ya esté guardado")
    func saveWinsOverLateNotice() async throws {
        let rig = try await Rig()
        let saved = WatchHealthNotice(sessionID: rig.session, recording: SessionHealthRecording(state: .saved, activeKilocalories: 300))
        let late = WatchHealthNotice(sessionID: rig.session, recording: SessionHealthRecording(state: .recording))
        rig.phone.applyHealthNotice(saved)
        rig.phone.applyHealthNotice(late)
        rig.phone.applyHealthNotice(saved)
        #expect(try rig.recording?.state == .saved)
        #expect(try rig.recording?.activeKilocalories == 300)
    }

    @Test("Con la app del iPhone cerrada el aviso se guarda en la sesión")
    func noticeOnStoredSession() async throws {
        let rig = try await Rig()
        let closed = PhoneWatchBridge(link: rig.link, clock: { now }) { [persistence = rig.persistence] in
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
        let notice = WatchHealthNotice(sessionID: rig.session, recording: SessionHealthRecording(state: .saved))
        #expect(try await closed.handle(.health(notice)) == .appliedStored)
        let stored = try await rig.persistence.workoutRepository().session(id: rig.session)
        #expect(stored?.healthRecording?.state == .saved)
    }

    @Test("La flag del reloj viene apagada")
    func flagIsOffByDefault() {
        #expect(!FeatureFlags().isEnabled(.watchHealthSessionEnabled))
        #expect(!FeatureFlags.shipped.contains(.watchHealthSessionEnabled))
    }
}
