//
//  CollectionPersistenceTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  SCRUM-23: historial y export correctos. Cada colección en su subdirectorio,
//  lectura tolerante a archivos dañados (sin ocultar los válidos ni devolver 0 en
//  silencio), migración única e idempotente desde el layout compartido antiguo, y
//  export con el conteo real. Todo sobre `AtomicFileRepositoryStore` real en un
//  directorio temporal.
//

import Foundation
import Testing
import PRCore
import PRDomain

// MARK: - Helpers

/// Directorio temporal propio de cada test.
private struct TempRoot {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-scrum23-\(UUID().uuidString)", isDirectory: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func collectionFile(_ collection: PersistenceCollection, _ key: String) -> URL {
        url.appendingPathComponent(collection.rawValue, isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Recolecta los mensajes del `PersistenceLog` para verificar que no llevan datos.
private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var log: PersistenceLog {
        PersistenceLog { [self] message in
            lock.lock(); defer { lock.unlock() }
            storage.append(message)
        }
    }
}

enum Fixture {
    static func completedSession(sets: Int, startedAt: Date) throws -> WorkoutSessionRecord {
        var session = WorkoutSessionRecord(startedAt: startedAt, endedAt: startedAt.addingTimeInterval(3600), lifecycle: .completed)
        for index in 0..<sets {
            session = session.performedSet(try SetRecord(
                exerciseID: ExerciseID(),
                performedAt: startedAt.addingTimeInterval(Double(index) * 60),
                weight: 60,
                unit: .kilograms,
                reps: 8,
                lifecycle: .completed
            ))
        }
        return session
    }

    static func pendingOperation() -> PendingOperation {
        PendingOperation(idempotencyKey: UUID().uuidString, kind: .saveSet, payload: Data("{}".utf8))
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

// MARK: - Colecciones separadas y lectura tolerante

@Suite("SCRUM-23 · Colecciones separadas y lectura tolerante")
struct CollectionPersistenceTests {

    @Test("Cada colección vive en su subdirectorio: la cola no contamina los workouts")
    func collectionsAreIsolated() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let session = try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 1_000))
        try await persistence.workoutRepository().save(session)
        _ = try persistence.pendingOperationQueue().enqueue(Fixture.pendingOperation())

        #expect(root.exists(root.collectionFile(.workouts, session.id.rawValue.persistenceKey)))
        #expect(root.exists(root.collectionFile(.pendingOperations, PendingOperationQueueStore.storageKey)))

        let result = try await persistence.workoutRepository().loadAllSessions()
        #expect(result.items == [session])
        #expect(result.unreadableCount == 0)
        #expect(try persistence.pendingOperationQueue().load().count == 1)
    }

    @Test("1 archivo corrupto entre 3 válidos: devuelve los 3 y cuenta 1 ilegible")
    func toleratesCorruptFile() async throws {
        let root = TempRoot(); defer { root.remove() }
        let recorder = LogRecorder()
        let persistence = try LocalPersistence(rootURL: root.url, log: recorder.log)
        let repo = try persistence.workoutRepository()
        for offset in 0..<3 {
            try await repo.save(try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: Double(offset))))
        }
        let corruptKey = "corrupt-\(UUID().uuidString.lowercased())"
        try Data("{ no es json".utf8).write(to: root.collectionFile(.workouts, corruptKey))

        let result = try await repo.loadAllSessions()

        #expect(result.items.count == 3)
        #expect(result.unreadableCount == 1)
        #expect(try await repo.allSessions().count == 3)
    }

    @Test("El error de lectura se registra sin claves, rutas ni contenido")
    func logsWithoutPersonalData() async throws {
        let root = TempRoot(); defer { root.remove() }
        let recorder = LogRecorder()
        let persistence = try LocalPersistence(rootURL: root.url, log: recorder.log)
        let corruptKey = "user-\(UUID().uuidString.lowercased())"
        try FileManager.default.createDirectory(
            at: root.url.appendingPathComponent(PersistenceCollection.workouts.rawValue),
            withIntermediateDirectories: true
        )
        try Data("{ \"secreto\": \"juan@example.com\"".utf8).write(to: root.collectionFile(.workouts, corruptKey))

        _ = try await persistence.workoutRepository().loadAllSessions()

        #expect(recorder.messages == ["persistence.read unreadable collection=workouts count=1"])
        let joined = recorder.messages.joined()
        #expect(!joined.contains(corruptKey))
        #expect(!joined.contains("juan@example.com"))
        #expect(!joined.contains(root.url.path))
    }

    @Test("Los .json.tmp de una escritura interrumpida no se leen como registros")
    func ignoresTemporaryFiles() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let repo = try persistence.workoutRepository()
        try await repo.save(try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: 0)))
        try Data("parcial".utf8).write(
            to: root.url.appendingPathComponent("workouts").appendingPathComponent("x.json.tmp")
        )

        let result = try await repo.loadAllSessions()
        #expect(result.items.count == 1)
        #expect(result.unreadableCount == 0)
    }
}

// MARK: - Migración desde el layout compartido

@Suite("SCRUM-23 · Migración del directorio compartido")
struct LegacyPersistenceMigrationTests {

    @Test("Clasifica cada tipo persistido en su colección, sin ambigüedad")
    func classifiesEveryCollection() throws {
        let samples: [(PersistenceCollection, Data)] = [
            (.workouts, try Fixture.encoded(try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: 0)))),
            (.pendingOperations, try Fixture.encoded(PendingOperationQueue(operations: [Fixture.pendingOperation()]))),
            (.profile, try Fixture.encoded(RepoFixtures.profile())),
            (.blocks, try Fixture.encoded(RepoFixtures.block())),
            (.exercises, try Fixture.encoded(RepoFixtures.exercise())),
            (.gyms, try Fixture.encoded(RepoFixtures.gym())),
            (.restrictions, try Fixture.encoded(RepoFixtures.restriction())),
            (.decisions, try Fixture.encoded(RepoFixtures.decision())),
            (.agentAudit, try Fixture.encoded(AgentAuditRecord(stage: .inboundIntent))),
            (.plans, try Fixture.encoded(StoredPlan(
                userID: "u",
                profile: OnboardingProfile(
                    goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
                    trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced
                ),
                activeBlockID: TrainingBlockID(),
                blockHistory: [],
                explanation: BlockExplanation(facts: [], ruleReferences: []),
                updatedAt: Date(timeIntervalSince1970: 0)
            ))),
            (.session, try Fixture.encoded(StoredSession(userID: "u"))),
        ]
        #expect(samples.map(\.0).sorted { $0.rawValue < $1.rawValue }
            == PersistenceCollection.allCases.sorted { $0.rawValue < $1.rawValue })
        for (expected, data) in samples {
            #expect(LegacyPersistenceMigration.classify(data) == expected, "collection \(expected.rawValue)")
        }
        #expect(LegacyPersistenceMigration.classify(Data("{ roto".utf8)) == nil)
        #expect(LegacyPersistenceMigration.classify(Data("{}".utf8)) == nil)
    }

    @Test("Mueve workouts y cola a su colección por contenido; la segunda vez no hace nada")
    func migratesAndIsIdempotent() async throws {
        let root = TempRoot(); defer { root.remove() }
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        let first = try Fixture.completedSession(sets: 3, startedAt: Date(timeIntervalSince1970: 0))
        let second = try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 100))
        // Layout antiguo: todo en la raíz. Un nombre engañoso no cambia la clasificación.
        try Fixture.encoded(first).write(to: root.file(first.id.rawValue.persistenceKey + ".json"))
        try Fixture.encoded(second).write(to: root.file(second.id.rawValue.persistenceKey + ".json"))
        try Fixture.encoded(PendingOperationQueue(operations: [Fixture.pendingOperation()]))
            .write(to: root.file("pending-operations.json"))

        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let report = try persistence.migrateLegacyLayout()

        #expect(report.moved == 3)
        #expect(report.unclassified == 0)
        #expect(!root.exists(root.file("pending-operations.json")))
        let sessions = try await persistence.workoutRepository().loadAllSessions()
        #expect(Set(sessions.items) == [first, second])
        #expect(sessions.unreadableCount == 0)
        #expect(try persistence.pendingOperationQueue().load().count == 1)

        let again = try persistence.migrateLegacyLayout()
        #expect(again == LegacyPersistenceMigration.Report())
        #expect(!again.didWork)
    }

    @Test("Migración interrumpida: destino ya escrito e igual ⇒ sólo se quita el origen")
    func completesInterruptedMigration() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let session = try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: 0))
        let key = session.id.rawValue.persistenceKey
        let data = try Fixture.encoded(session)
        try persistence.store(for: .workouts).write(key: key, data: data)
        try data.write(to: root.file(key + ".json"))

        let report = try persistence.migrateLegacyLayout()

        #expect(report.alreadyMigrated == 1)
        #expect(!root.exists(root.file(key + ".json")))
        #expect(try await persistence.workoutRepository().allSessions() == [session])
    }

    @Test("Conflicto (destino distinto): no se borra nada")
    func keepsBothOnConflict() throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let original = try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: 0))
        var edited = original
        edited.endedAt = Date(timeIntervalSince1970: 9_999)
        let key = original.id.rawValue.persistenceKey
        let editedData = try Fixture.encoded(edited)
        let originalData = try Fixture.encoded(original)
        try persistence.store(for: .workouts).write(key: key, data: editedData)
        try originalData.write(to: root.file(key + ".json"))

        let report = try persistence.migrateLegacyLayout()

        #expect(report.conflicts == 1)
        #expect(try Data(contentsOf: root.file(key + ".json")) == originalData)
        let destination = try persistence.store(for: .workouts).read(key: key)
        #expect(destination == editedData)
    }

    @Test("Un archivo no clasificable se queda intacto en la raíz")
    func leavesUnclassifiedFiles() throws {
        let root = TempRoot(); defer { root.remove() }
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        let garbage = Data("{ roto".utf8)
        try garbage.write(to: root.file("desconocido.json"))
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)

        let report = try persistence.migrateLegacyLayout()

        #expect(report.unclassified == 1)
        #expect(try Data(contentsOf: root.file("desconocido.json")) == garbage)
    }
}

// MARK: - Export

@Suite("SCRUM-23 · Export del historial")
struct ExportHistoryTests {

    @Test("2 sesiones completadas + 1 operación en cola ⇒ Export ve 2 sesiones con todas sus series")
    func exportsRealHistory() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let first = try Fixture.completedSession(sets: 3, startedAt: Date(timeIntervalSince1970: 0))
        let second = try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 7_200))
        try await persistence.workoutRepository().save(first)
        try await persistence.workoutRepository().save(second)
        _ = try persistence.pendingOperationQueue().enqueue(Fixture.pendingOperation())

        let coordinator = DataExportCoordinator()
        let history = try await coordinator.loadHistory(from: try persistence.workoutRepository())

        #expect(history == .loaded(sessions: [first, second], unreadableCount: 0))

        let json = try coordinator.exportJSON(
            sessions: history.sessions, exercises: [], blocks: [], gyms: [], restrictions: [], profile: nil,
            exportedAt: Date(timeIntervalSince1970: 0)
        )
        let bundle = try JSONDecoder.iso8601.decode(ExportBundle.self, from: json.data)
        #expect(bundle.sessions.count == 2)
        #expect(bundle.sessions.map(\.sets.count).reduce(0, +) == 5)

        let csv = String(decoding: coordinator.exportSetsCSV(sessions: history.sessions).data, as: UTF8.self)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 1 + 5) // cabecera + una fila por serie
    }

    @Test("Sin sesiones ⇒ estado vacío explícito, no una lista vacía cualquiera")
    func emptyHistory() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        _ = try persistence.pendingOperationQueue().enqueue(Fixture.pendingOperation())

        let history = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())

        #expect(history == .empty(unreadableCount: 0))
    }

    @Test("Sólo registros ilegibles ⇒ vacío pero avisando cuántos no se pudieron leer")
    func emptyButWarns() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        _ = try persistence.store(for: .workouts)
        try Data("{ roto".utf8).write(to: root.collectionFile(.workouts, "x"))

        let history = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())

        #expect(history == .empty(unreadableCount: 1))
    }

    @Test("Con un archivo corrupto entre 3 válidos, Export ve 3 y avisa de 1")
    func exportWarnsAboutUnreadable() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        for offset in 0..<3 {
            try await persistence.workoutRepository()
                .save(try Fixture.completedSession(sets: 1, startedAt: Date(timeIntervalSince1970: Double(offset))))
        }
        try Data("{ roto".utf8).write(to: root.collectionFile(.workouts, "x"))

        let history = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())

        #expect(history.sessions.count == 3)
        #expect(history.unreadableCount == 1)
    }

    @Test("El export no incluye tokens, identificadores de Apple ni claves")
    func exportHasNoSecrets() async throws {
        let session = try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 0))
        let json = try DataExportCoordinator().exportJSON(
            sessions: [session], exercises: [], blocks: [], gyms: [], restrictions: [], profile: RepoFixtures.profile()
        )
        let text = String(decoding: json.data, as: UTF8.self).lowercased()
        #expect(!ExportEngine.containsForbiddenSecretFields(inJSON: json.data))
        for forbidden in ["token", "useridentifier", "appleid", "apikey", "authorizationcode", "email"] {
            #expect(!text.contains(forbidden), "contiene \(forbidden)")
        }
    }
}

// MARK: - Integración con el coordinador real

@Suite("SCRUM-23 · Integración workout → historial → export")
struct WorkoutHistoryIntegrationTests {

    private func template() throws -> SessionTemplate {
        let prescription = try SetPrescription(
            targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...90, isWarmup: false
        )
        let exerciseID = ExerciseID()
        return SessionTemplate(
            title: "Press banca",
            plannedSets: [PlannedSet(exerciseID: exerciseID, prescription: prescription),
                          PlannedSet(exerciseID: exerciseID, prescription: prescription)]
        )
    }

    @MainActor
    @Test("Entrenar y terminar ⇒ 1 sesión en disco y Export cuenta 1 (otra instancia, mismo directorio)",
          .timeLimit(.minutes(1)))
    func workoutAppearsInExport() async throws {
        let root = TempRoot(); defer { root.remove() }
        let persistence = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let (persisted, continuation) = AsyncStream<Result<WorkoutID, any Error>>.makeStream()
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinator = try await persistence.makeWorkoutCoordinator(
            template: try template(),
            clock: { now },
            onPersisted: { result in continuation.yield(result) }
        )

        _ = coordinator.start(now: now)
        _ = try coordinator.completeCurrentSet(now: now)
        let phase = try coordinator.completeCurrentSet(now: now)
        guard case .finished = phase else {
            Issue.record("Tras la última serie la sesión debía terminar, fase \(phase)")
            return
        }
        var firstResult: Result<WorkoutID, any Error>?
        for await result in persisted {
            firstResult = result
            break
        }
        let savedID = try #require(firstResult).get()

        // Instancia nueva sobre el mismo directorio: lo que vería la app al reabrir.
        let reopened = try LocalPersistence(rootURL: root.url, log: LogRecorder().log)
        let sessions = try await reopened.workoutRepository().allSessions()
        #expect(sessions.map(\.id) == [savedID])
        #expect(sessions.first?.sets.count == 2)

        let history = try await DataExportCoordinator().loadHistory(from: try reopened.workoutRepository())
        #expect(history.sessions.count == 1)
        #expect(history.unreadableCount == 0)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
