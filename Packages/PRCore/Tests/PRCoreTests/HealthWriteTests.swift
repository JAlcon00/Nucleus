//
//  HealthWriteTests.swift
//  PRCoreTests
//
//  SCRUM-246 (PR-F003): la cola de escritura a Salud. Un entrenamiento llega una vez y sólo
//  una, aunque la app se cierre o Salud falle. Salud va con fake; el disco es real.
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Un repositorio real en un directorio temporal, y lo que se necesita alrededor.
private struct Harness {
    let root: URL
    let persistence: LocalPersistence
    let repository: FileWorkoutRepository
    let health: FakeHealthWorkoutStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum246-\(UUID().uuidString)")
        persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        repository = try persistence.workoutRepository()
        health = FakeHealthWorkoutStore()
    }

    func coordinator(canWrite: Bool = true) -> HealthWriteCoordinator {
        HealthWriteCoordinator(repository: repository, writer: health, canWrite: { canWrite })
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Mira qué hay en disco en el momento en que se llama a Salud.
private final class StatusAtSave: HealthWorkoutWriting, @unchecked Sendable {
    let repository: any WorkoutRepository
    private(set) var seen: HealthWriteStatus?

    init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    func saveFinishedWorkout(_ write: HealthWorkoutWrite) async throws -> HealthWorkoutHandle.ID {
        let id = WorkoutID(rawValue: try #require(UUID(uuidString: write.syncIdentifier)))
        seen = try await repository.session(id: id)?.healthWriteStatus
        return HealthWorkoutHandle.ID()
    }
}

/// Repositorio que deja de poder guardar.
private struct FailingSaveRepository: WorkoutRepository {
    let session: WorkoutSessionRecord
    struct Failure: Error {}
    func allSessions() async throws -> [WorkoutSessionRecord] { [session] }
    func session(id: WorkoutID) async throws -> WorkoutSessionRecord? { session }
    func save(_ session: WorkoutSessionRecord) async throws { throw Failure() }
    func delete(id: WorkoutID) async throws {}
}

@Suite("Cola de escritura a Salud (SCRUM-246)")
struct HealthWriteTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func completed(
        lifecycle: WorkoutLifecycleState = .completed,
        sets: Int = 2,
        status: HealthWriteStatus? = nil
    ) throws -> WorkoutSessionRecord {
        let exercise = ExerciseID()
        var session = WorkoutSessionRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(3600),
            lifecycle: lifecycle,
            sets: try (0..<sets).map { _ in
                try SetRecord(exerciseID: exercise, weight: 80, unit: .kilograms, reps: 8, lifecycle: .completed)
            }
        )
        session.healthWriteStatus = status
        return session
    }

    // Criterio 1
    @Test("Primero queda pendiente en disco y después se llama a Salud")
    func pendingIsSavedBeforeCallingHealth() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)
        let spy = StatusAtSave(repository: harness.repository)
        let coordinator = HealthWriteCoordinator(repository: harness.repository, writer: spy, canWrite: { true })

        try await coordinator.sessionFinished(id: session.id)

        #expect(spy.seen == .pending)
    }

    // Criterio 2
    @Test("Si Salud responde bien queda guardado, con la referencia llena")
    func savedOnSuccess() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        let saved = try #require(try await harness.repository.session(id: session.id))
        #expect(saved.healthWriteStatus == .saved)
        #expect(saved.healthWorkoutReferenceID != nil)
        #expect(await harness.health.savedWorkouts.count == 1)
    }

    // Criterio 3
    @Test("Si Salud falla queda pendiente y el reintento lo guarda")
    func failureStaysPendingAndRetries() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)
        await harness.health.setFailsOnSave(true)
        let coordinator = harness.coordinator()

        try await coordinator.sessionFinished(id: session.id)
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .pending)

        try await coordinator.retryPending()
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .pending)

        await harness.health.setFailsOnSave(false)
        try await coordinator.retryPending()
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .saved)
        #expect(await harness.health.savedWorkouts.count == 1)
    }

    // Criterio 4
    @Test("Si se cierra entre escribir y marcar guardado, el reintento no duplica")
    func crashBetweenWriteAndMarkDoesNotDuplicate() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed(status: .pending)
        try await harness.repository.save(session)
        // Salud ya lo tiene, pero la app se cerró antes de marcarlo.
        let write = try #require(HealthWorkoutWrite(session: session))
        _ = try await harness.health.saveFinishedWorkout(write)

        try await harness.coordinator().retryPending()

        #expect(await harness.health.saveAttempts == 2)
        #expect(await harness.health.savedWorkouts.count == 1)
        #expect(await harness.health.savedWorkouts[session.id.rawValue.uuidString] == write)
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .saved)
    }

    @Test("El identificador es el de la sesión y la versión es la 1")
    func writeIdentifierIsStable() throws {
        let session = try completed()
        let first = try #require(HealthWorkoutWrite(session: session))
        let second = try #require(HealthWorkoutWrite(session: session))

        #expect(first.syncIdentifier == session.id.rawValue.uuidString)
        #expect(first == second)
        #expect(HealthWorkoutWrite.syncVersion == 1)
    }

    // Criterio 5
    @Test("Una sesión abandonada no se escribe")
    func abandonedIsNotWritten() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed(lifecycle: .abandoned)
        try await harness.repository.save(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == nil)
        #expect(await harness.health.saveAttempts == 0)
    }

    @Test("Una sesión completada sin series no se escribe")
    func withoutSetsIsNotWritten() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed(sets: 0)
        try await harness.repository.save(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == nil)
        #expect(await harness.health.saveAttempts == 0)
    }

    // SCRUM-258: el reloj y el iPhone no escriben los dos.
    @Test("Si el reloj registra el entrenamiento, el iPhone no agrega otro", arguments: [
        SessionHealthRecording.State.recording, .saved,
    ])
    func watchOwnsTheWorkout(state: SessionHealthRecording.State) async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        var session = try completed()
        session.healthRecording = SessionHealthRecording(state: state)
        try await harness.repository.save(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        #expect(await harness.health.saveAttempts == 0)
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == nil)
    }

    @Test("Si Salud falló en el reloj, escribe el iPhone con el mismo identificador")
    func watchFailedSoPhoneWrites() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        var session = try completed()
        session.healthRecording = SessionHealthRecording(state: .failed)
        try await harness.repository.save(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        #expect(await harness.health.savedWorkouts.keys.sorted() == [session.id.rawValue.uuidString])
    }

    @Test("Sólo series saltadas no cuentan como series")
    func skippedSetsDoNotCount() throws {
        var session = try completed(sets: 0)
        session.sets = [try SetRecord(exerciseID: ExerciseID(), weight: 80, unit: .kilograms, reps: 8, lifecycle: .skipped)]

        #expect(HealthWorkoutWrite(session: session) == nil)
    }

    // Criterio 6
    @Test("Una sesión anterior a esta historia nunca se escribe")
    func olderSessionsAreNeverWritten() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let older = try completed()
        try await harness.repository.save(older)

        try await harness.coordinator().retryPending()

        #expect(await harness.health.saveAttempts == 0)
        #expect(try await harness.repository.session(id: older.id)?.healthWriteStatus == nil)
    }

    // Criterio 7
    @Test("Con la escritura apagada o el permiso negado no queda nada pendiente")
    func noWriteLeavesNothingPending() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)

        try await harness.coordinator(canWrite: false).sessionFinished(id: session.id)

        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == nil)
        #expect(await harness.health.saveAttempts == 0)
    }

    @Test("Si se niega con algo pendiente, deja de reintentarse sin error y sin perderse")
    func deniedKeepsPendingWithoutError() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed(status: .pending)
        try await harness.repository.save(session)

        try await harness.coordinator(canWrite: false).retryPending()

        #expect(await harness.health.saveAttempts == 0)
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .pending)

        try await harness.coordinator().retryPending()
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .saved)
    }

    // Criterio 8
    @Test("Series, horas y resumen no cambian")
    func sessionDataDoesNotChange() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)
        let summaryBefore = WorkoutSummaryBuilder().summarize(session)

        try await harness.coordinator().sessionFinished(id: session.id)

        let after = try #require(try await harness.repository.session(id: session.id))
        #expect(after.sets == session.sets)
        #expect(after.endedAt == session.endedAt)
        #expect(after.startedAt == session.startedAt)
        #expect(after.lifecycle == session.lifecycle)
        #expect(WorkoutSummaryBuilder().summarize(after) == summaryBefore)
    }

    // Criterio 10
    @Test("Con dos cuentas sólo se procesa lo pendiente de la activa")
    func onlyTheActiveAccountIsProcessed() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let active = try harness.persistence.scoped(toUser: "activa").workoutRepository()
        let other = try harness.persistence.scoped(toUser: "otra").workoutRepository()
        let mine = try completed(status: .pending)
        let theirs = try completed(status: .pending)
        try await active.save(mine)
        try await other.save(theirs)

        let coordinator = HealthWriteCoordinator(repository: active, writer: harness.health, canWrite: { true })
        try await coordinator.retryPending()

        #expect(await harness.health.savedWorkouts.keys.sorted() == [mine.id.rawValue.uuidString])
        #expect(try await other.session(id: theirs.id)?.healthWriteStatus == .pending)
    }

    // Criterio 11
    @Test("A Salud sólo van inicio, fin, tipo e identificador")
    func onlyMinimalDataGoesToHealth() throws {
        let session = try completed()
        let write = try #require(HealthWorkoutWrite(session: session))

        #expect(write.start == session.startedAt)
        #expect(write.end == session.endedAt)
        #expect(write.activityType == .strengthTraining)
        let fields = Set(Mirror(reflecting: write).children.compactMap(\.label))
        #expect(fields == ["syncIdentifier", "start", "end", "activityType"])
    }

    // Casos límite
    @Test("Dos reintentos a la vez dejan un solo entrenamiento")
    func concurrentRetries() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed(status: .pending)
        try await harness.repository.save(session)
        let coordinator = harness.coordinator()

        async let first: Void = coordinator.retryPending()
        async let second: Void = coordinator.retryPending()
        _ = try await (first, second)

        #expect(await harness.health.savedWorkouts.count == 1)
        #expect(try await harness.repository.session(id: session.id)?.healthWriteStatus == .saved)
    }

    @Test("Un error al guardar el estado no se traga")
    func stateSaveErrorIsThrown() async throws {
        let session = try completed()
        let coordinator = HealthWriteCoordinator(
            repository: FailingSaveRepository(session: session),
            writer: FakeHealthWorkoutStore(),
            canWrite: { true }
        )

        await #expect(throws: FailingSaveRepository.Failure.self) {
            try await coordinator.sessionFinished(id: session.id)
        }
    }

    @Test("Una sesión borrada del disco no falla ni se escribe")
    func deletedSessionIsIgnored() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }

        try await harness.coordinator().sessionFinished(id: WorkoutID())

        #expect(await harness.health.saveAttempts == 0)
    }

    @Test("Con el reloj cambiado, sin horas válidas, no hay nada que escribir")
    func invalidClockIsNotWritten() throws {
        var session = try completed()
        session.endedAt = start.addingTimeInterval(-60)

        #expect(HealthWorkoutWrite(session: session) == nil)
    }

    @Test("Terminar dos veces la misma sesión no escribe dos veces")
    func finishingTwiceWritesOnce() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)
        let coordinator = harness.coordinator()

        try await coordinator.sessionFinished(id: session.id)
        try await coordinator.sessionFinished(id: session.id)

        #expect(await harness.health.saveAttempts == 1)
    }

    // Integración con persistencia real
    @Test("Terminar, fallar, reabrir y reintentar deja un solo entrenamiento")
    func finishFailReopenRetry() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let session = try completed()
        try await harness.repository.save(session)
        await harness.health.setFailsOnSave(true)
        try await harness.coordinator().sessionFinished(id: session.id)

        // La app se cierra: otra persistencia y otro coordinador sobre el mismo disco.
        await harness.health.setFailsOnSave(false)
        let reopened = try LocalPersistence(rootURL: harness.root, log: PersistenceLog { _ in }).workoutRepository()
        let coordinator = HealthWriteCoordinator(repository: reopened, writer: harness.health, canWrite: { true })
        try await coordinator.retryPending()

        #expect(await harness.health.savedWorkouts.count == 1)
        let saved = try #require(try await reopened.session(id: session.id))
        #expect(saved.healthWriteStatus == .saved)
        #expect(saved.sets == session.sets)
    }

    // Formato
    @Test("Una sesión sin el campo nuevo se lee igual y no lo agrega al guardar")
    func optionalFieldKeepsTheFormat() throws {
        let session = try completed()
        let encoder = JSONEncoder()
        let text = String(decoding: try encoder.encode(session), as: UTF8.self)

        #expect(!text.contains("healthWriteStatus"))
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: Data(text.utf8))
        #expect(decoded.healthWriteStatus == nil)
    }
}

@Suite("Lo que dice el resumen sobre Salud (SCRUM-247)")
struct HealthSaveDisplayTests {

    private let spanish = Locale(identifier: "es_MX")

    @Test("Guardado dice \"Guardado en Salud\"")
    func saved() {
        let display = HealthSaveDisplay(status: .saved, canWrite: true)
        #expect(display == .saved)
        #expect(display.text(locale: spanish) == "Guardado en Salud")
    }

    @Test("Pendiente dice \"Se guardará en Salud\" y no parece un error")
    func pending() throws {
        let display = HealthSaveDisplay(status: .pending, canWrite: true)
        #expect(display == .pending)
        let text = try #require(display.text(locale: spanish))
        #expect(text == "Se guardará en Salud")
        #expect(!text.localizedCaseInsensitiveContains("error"))
        #expect(!text.localizedCaseInsensitiveContains("falló"))
    }

    @Test("Apagada, negada o sin escritura, el resumen no dice nada", arguments: [
        (HealthWriteStatus?.some(.saved), false),
        (.some(.pending), false),
        (.none, true),
        (.none, false),
    ])
    func hidden(status: HealthWriteStatus?, canWrite: Bool) {
        let display = HealthSaveDisplay(status: status, canWrite: canWrite)
        #expect(display == .hidden)
        #expect(display.text(locale: spanish) == nil)
    }

    @Test("Los textos están traducidos al inglés")
    func english() {
        let english = Locale(identifier: "en_US")
        #expect(HealthSaveDisplay.saved.text(locale: english) == "Saved to Health")
        #expect(HealthSaveDisplay.pending.text(locale: english) == "Will be saved to Health")
    }

    @Test("sessionFinished dice cómo quedó la sesión")
    func finishReturnsStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum247-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).workoutRepository()
        let health = FakeHealthWorkoutStore()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let session = WorkoutSessionRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            lifecycle: .completed,
            sets: [try SetRecord(exerciseID: ExerciseID(), weight: 80, unit: .kilograms, reps: 8, lifecycle: .completed)]
        )
        try await repository.save(session)
        let coordinator = HealthWriteCoordinator(repository: repository, writer: health, canWrite: { true })

        #expect(try await coordinator.sessionFinished(id: session.id) == .saved)
        #expect(try await coordinator.sessionFinished(id: WorkoutID()) == nil)
    }

    @Test("La Salud falsa sólo existe en Debug y con datos temporales")
    func fakeHealthOption() {
        let arguments = ["-PRUITestReset", "-PRUITestFakeHealth", "granted"]

        #expect(UITestLaunchOptions.resolve(arguments: arguments, isDebugBuild: true).fakeHealth == .granted)
        #expect(UITestLaunchOptions.resolve(arguments: arguments, isDebugBuild: false).fakeHealth == nil)
        #expect(UITestLaunchOptions.resolve(arguments: Array(arguments.dropFirst()), isDebugBuild: true).fakeHealth == nil)
        #expect(UITestLaunchOptions.resolve(arguments: ["-PRUITestReset", "-PRUITestFakeHealth", "x"], isDebugBuild: true).fakeHealth == nil)
    }
}
