//
//  SchemaMigrationTests.swift
//  PRCoreTests
//
//  SCRUM-40: migraciones seguras de datos guardados. Las pruebas del migrador usan un
//  formato de prueba ("levantamiento": v1 → v2 → v3) sobre directorios temporales; la de
//  integración usa entrenamientos reales del demo con `LocalPersistence` y Exportar.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

// MARK: - Formato de prueba

private struct LiftV1: Codable, Equatable {
    let name: String
    let kg: Double
}

private struct LiftV2: Codable, Equatable {
    struct Load: Codable, Equatable {
        let value: Double
        let unit: String
    }
    let title: String
    let load: Load
}

private struct LiftV3: Codable, Equatable {
    let title: String
    let load: LiftV2.Load
    let notes: String
}

private let v2 = SchemaVersion.initial.next
private let v3 = v2.next

/// v1 → v2: `name`/`kg` pasan a `title`/`load`. Falla con un registro que no es v1.
private let liftStep1 = SchemaMigrationStep(from: .initial) { data in
    let old = try JSONDecoder().decode(LiftV1.self, from: data)
    return try JSONEncoder().encode(LiftV2(title: old.name, load: .init(value: old.kg, unit: "kg")))
}

/// v2 → v3: agrega `notes` vacío.
private let liftStep2 = SchemaMigrationStep(from: v2) { data in
    let old = try JSONDecoder().decode(LiftV2.self, from: data)
    return try JSONEncoder().encode(LiftV3(title: old.title, load: old.load, notes: ""))
}

private let liftSchemaV2 = CollectionSchema(current: v2, steps: [liftStep1]) {
    (try? JSONDecoder().decode(LiftV2.self, from: $0)) != nil
}

private let liftSchemaV3 = CollectionSchema(current: v3, steps: [liftStep1, liftStep2]) {
    (try? JSONDecoder().decode(LiftV3.self, from: $0)) != nil
}

// MARK: - Ayudantes

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-schema-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Carpeta de colección con registros v1 (`squat`, `bench`) y, si se pide, uno que no
/// es v1 (`broken`).
private func liftsV1(in root: URL, withBroken: Bool = false) throws -> URL {
    let directory = root.appendingPathComponent("lifts", isDirectory: true)
    let store = try AtomicFileRepositoryStore(directory: directory)
    try store.write(key: "squat", data: JSONEncoder().encode(LiftV1(name: "Sentadilla", kg: 100)))
    try store.write(key: "bench", data: JSONEncoder().encode(LiftV1(name: "Press", kg: 80)))
    if withBroken {
        try store.write(key: "broken", data: Data(#"{"name":"Sin carga"}"#.utf8))
    }
    return directory
}

private func records(in directory: URL) throws -> [String: Data] {
    let entries = try AtomicFileRepositoryStore(directory: directory).readActiveEntries().entries
    return Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.data) })
}

/// Todo lo que hay en una carpeta (incluidos ocultos), para comprobar que nada cambió.
private func snapshot(of directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
        let url = directory.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            result[path] = try Data(contentsOf: url)
        }
    }
    return result
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

@Suite("SCRUM-40 · Migraciones seguras de datos guardados")
struct SchemaMigrationTests {

    // MARK: Versión, orden y una sola vez

    @Test("Sin marca es la versión 1: migra a la 2, marca la carpeta y deja el original como respaldo")
    func unmarkedIsVersionOneAndMigrates() throws {
        let directory = try liftsV1(in: try makeRoot())
        let original = try records(in: directory)

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .migrated(from: .initial, to: v2, records: 2, quarantined: 0))
        #expect(CollectionLayout.readMarker(in: directory) == .version(v2))
        let squat = try #require(try records(in: directory)["squat"])
        #expect(try JSONDecoder().decode(LiftV2.self, from: squat) == LiftV2(title: "Sentadilla", load: .init(value: 100, unit: "kg")))
        #expect(try records(in: CollectionLayout.backupURL(for: directory)) == original, "El original queda como respaldo")
        #expect(!exists(CollectionLayout.stagingURL(for: directory)))
    }

    @Test("Varias versiones de golpe: 1 → 2 → 3 en orden")
    func migratesThroughEveryStepInOrder() throws {
        let directory = try liftsV1(in: try makeRoot())

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV3)

        #expect(outcome == .migrated(from: .initial, to: v3, records: 2, quarantined: 0))
        let bench = try #require(try records(in: directory)["bench"])
        #expect(try JSONDecoder().decode(LiftV3.self, from: bench) == LiftV3(title: "Press", load: .init(value: 80, unit: "kg"), notes: ""))
    }

    @Test("Correr otra vez no hace nada")
    func secondRunDoesNothing() throws {
        let directory = try liftsV1(in: try makeRoot())
        _ = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)
        let afterFirst = try snapshot(of: directory)
        let backup = try snapshot(of: CollectionLayout.backupURL(for: directory))

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .upToDate(v2))
        #expect(try snapshot(of: directory) == afterFirst)
        #expect(try snapshot(of: CollectionLayout.backupURL(for: directory)) == backup)
    }

    @Test("Carpeta inexistente: nada que migrar")
    func absentCollection() throws {
        let directory = try makeRoot().appendingPathComponent("lifts", isDirectory: true)
        #expect(try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2) == .absent)
        #expect(!exists(directory))
    }

    // MARK: Nunca se pierde el original

    @Test("Un registro que no se puede migrar queda intacto en cuarentena, el resto migra y se cuenta como ilegible")
    func unconvertibleRecordGoesToQuarantine() throws {
        let directory = try liftsV1(in: try makeRoot(), withBroken: true)
        let brokenBytes = try #require(try records(in: directory)["broken"])

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .migrated(from: .initial, to: v2, records: 2, quarantined: 1))
        let quarantined = CollectionLayout.quarantineURL(in: directory).appendingPathComponent("v1/broken.json")
        #expect(try Data(contentsOf: quarantined) == brokenBytes, "El original, byte por byte")
        let read = try AtomicFileRepositoryStore(directory: directory).readAllEntries()
        #expect(read.entries.map(\.key) == ["bench", "squat"])
        #expect(read.unreadableKeys == ["broken"])
    }

    @Test("La cuarentena de una migración anterior se conserva en la siguiente")
    func previousQuarantineSurvivesNextMigration() throws {
        let directory = try liftsV1(in: try makeRoot(), withBroken: true)
        _ = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV3)

        #expect(outcome == .migrated(from: v2, to: v3, records: 2, quarantined: 0))
        #expect(exists(CollectionLayout.quarantineURL(in: directory).appendingPathComponent("v1/broken.json")))
        #expect(try AtomicFileRepositoryStore(directory: directory).readAllEntries().unreadableKeys == ["broken"])
    }

    @Test("Un archivo que no se puede leer detiene la migración y deja todo intacto para reintentar")
    func unreadableFileStopsTheMigration() throws {
        let directory = try liftsV1(in: try makeRoot())
        // Un directorio con nombre de registro: existe pero no se puede leer como archivo.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("locked.json"), withIntermediateDirectories: false)
        let before = try snapshot(of: directory)

        #expect(throws: SchemaMigrationError.unreadableRecords(count: 1)) {
            try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)
        }
        #expect(try snapshot(of: directory) == before)
        #expect(CollectionLayout.readMarker(in: directory) == .absent)
        #expect(!exists(CollectionLayout.stagingURL(for: directory)))
        #expect(!exists(CollectionLayout.backupURL(for: directory)))
    }

    // MARK: Cortes a la mitad

    @Test("Corte antes del cambio: lo que quedó a medias se descarta y se migra completo")
    func cutBeforeSwapIsRedone() throws {
        let directory = try liftsV1(in: try makeRoot())
        let staging = CollectionLayout.stagingURL(for: directory)
        try AtomicFileRepositoryStore(directory: staging).write(key: "squat", data: Data("a medias".utf8))

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .migrated(from: .initial, to: v2, records: 2, quarantined: 0))
        #expect(try records(in: directory).count == 2)
        #expect(!exists(staging))
    }

    @Test("Corte entre los dos movimientos: queda la migrada, sin migrar dos veces ni duplicar")
    func cutBetweenMovesKeepsTheMigratedCollection() throws {
        let directory = try liftsV1(in: try makeRoot())
        _ = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)
        let migrated = try snapshot(of: directory)
        // Estado tras el primer movimiento: el original ya es respaldo y la migrada sigue aparte.
        try FileManager.default.moveItem(at: directory, to: CollectionLayout.stagingURL(for: directory))

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .upToDate(v2))
        #expect(try snapshot(of: directory) == migrated)
        #expect(!exists(CollectionLayout.stagingURL(for: directory)))
    }

    @Test("Abrir una colección tras un corte la regresa a su lugar en vez de crear una vacía encima")
    func openingAfterCutRestoresTheCollection() throws {
        let root = try makeRoot()
        let directory = root.appendingPathComponent(PersistenceCollection.checkIns.rawValue, isDirectory: true)
        let staging = CollectionLayout.stagingURL(for: directory)
        let checkIn = try JSONEncoder().encode(SleepCheckIn(day: "2026-10-26", hours: 7, quality: .good))
        try AtomicFileRepositoryStore(directory: staging).write(key: "u1-2026-10-26", data: checkIn)
        try CollectionLayout.writeMarker(.initial, in: staging)

        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let read = try persistence.store(for: .checkIns).readAllEntries()

        #expect(read.entries.map(\.data) == [checkIn])
        #expect(!exists(staging))
    }

    // MARK: No se toca

    @Test("Datos de una versión más nueva: no se tocan")
    func newerVersionIsLeftUntouched() throws {
        let directory = try liftsV1(in: try makeRoot())
        try CollectionLayout.writeMarker(v3, in: directory)
        let before = try snapshot(of: directory)

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .newerThanKnown(found: v3, known: v2))
        #expect(try snapshot(of: directory) == before)
        #expect(!exists(CollectionLayout.backupURL(for: directory)))
    }

    @Test("Falta un paso: no se toca nada y se dice cuál falta")
    func missingStepLeavesEverythingUntouched() throws {
        let directory = try liftsV1(in: try makeRoot())
        let before = try snapshot(of: directory)
        let incomplete = CollectionSchema(current: v3, steps: [liftStep1]) { _ in true }

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: incomplete)

        #expect(outcome == .untouched(.missingStep(from: v2)))
        #expect(!incomplete.isComplete)
        #expect(try snapshot(of: directory) == before)
    }

    @Test("Marca ilegible: no se adivina la versión")
    func unreadableMarkerLeavesEverythingUntouched() throws {
        let directory = try liftsV1(in: try makeRoot())
        try Data("dos".utf8).write(to: directory.appendingPathComponent(CollectionLayout.markerFileName))
        let before = try snapshot(of: directory)

        let outcome = try CollectionSchemaMigrator().migrate(collectionAt: directory, schema: liftSchemaV2)

        #expect(outcome == .untouched(.unreadableMarker))
        #expect(try snapshot(of: directory) == before)
    }

    // MARK: Con la persistencia real

    @Test("Una colección nueva se marca con su formato vigente")
    func newCollectionIsMarkedWithCurrentVersion() throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        for collection in PersistenceCollection.allCases {
            _ = try persistence.store(for: collection)
            let directory = root.appendingPathComponent(collection.rawValue, isDirectory: true)
            #expect(CollectionLayout.readMarker(in: directory) == .version(PersistenceSchemas.schema(for: collection).current))
        }
    }

    @Test("Al arrancar, una colección de antes de SCRUM-40 queda marcada como versión 1 sin cambiar sus datos")
    func legacyCollectionIsMarkedAtLaunch() throws {
        let root = try makeRoot()
        let directory = root.appendingPathComponent(PersistenceCollection.session.rawValue, isDirectory: true)
        let session = try JSONEncoder().encode(StoredSession(userID: "u1"))
        try AtomicFileRepositoryStore(directory: directory).write(key: "current", data: session)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })

        let outcomes = persistence.migrateSchemas()

        #expect(outcomes[.session] == .upToDate(.initial))
        #expect(CollectionLayout.readMarker(in: directory) == .version(.initial))
        #expect(try records(in: directory) == ["current": session])
    }

    @Test("Por usuario: sus colecciones migran al entrar y las de la raíz no se tocan")
    func userScopedCollectionsMigrateOnSignIn() throws {
        let root = try makeRoot()
        let userDirectory = root.appendingPathComponent("users/\(PlanStore.key(forUser: "u1"))/workouts", isDirectory: true)
        try AtomicFileRepositoryStore(directory: userDirectory)
            .write(key: "lift", data: JSONEncoder().encode(LiftV1(name: "Remo", kg: 60)))
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })

        let scoped = try persistence.scoped(toUser: "u1")
        #expect(CollectionLayout.readMarker(in: userDirectory) == .version(.initial), "Entrar marca las colecciones del usuario")

        let outcomes = scoped.migrateSchemas(of: [.workouts]) { _ in liftSchemaV2 }

        #expect(outcomes[.workouts] == .migrated(from: .initial, to: v2, records: 1, quarantined: 0))
        let lift = try #require(try records(in: userDirectory)["lift"])
        #expect(try JSONDecoder().decode(LiftV2.self, from: lift).title == "Remo")
        let rootWorkouts = root.appendingPathComponent("workouts", isDirectory: true)
        #expect(!exists(CollectionLayout.backupURL(for: rootWorkouts)), "La colección sin dueño de la raíz no se migró")
    }

    @Test("Un plan en cuarentena se avisa como ilegible, no como primer arranque")
    func quarantinedPlanIsUnreadable() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let planStore = try persistence.planStore()
        #expect(await planStore.loadPlan(userID: "u1") == .none)

        let quarantine = CollectionLayout.quarantineURL(in: root.appendingPathComponent("plans", isDirectory: true))
            .appendingPathComponent("v1", isDirectory: true)
        try AtomicFileRepositoryStore(directory: quarantine).write(key: PlanStore.key(forUser: "u1"), data: Data("{}".utf8))

        #expect(await planStore.loadPlan(userID: "u1") == .unreadable)
        #expect(await planStore.loadPlan(userID: "u2") == .none, "Otro usuario sigue en primer arranque")
    }

    @MainActor
    @Test("Layout antiguo → carpetas → versiones: Exportar cuenta lo mismo; con un paso nuevo, avisa lo que quedó en cuarentena")
    func legacyLayoutToVersionsKeepsExportCounts() async throws {
        // Historial real: 8 entrenamientos del demo.
        let source = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        _ = try await DemoDataSeeder(catalog: try ExerciseCatalogLoader.loadBundled(), timeZone: utc)
            .seedIfNeeded(persistence: source, userID: "demo", now: now)
        let before = try await DataExportCoordinator().loadHistory(from: try source.workoutRepository())
        #expect(before.sessions.count == 8)
        #expect(before.unreadableCount == 0)

        // Como antes de SCRUM-23: los archivos sueltos en la raíz.
        let root = try makeRoot()
        for entry in try source.store(for: .workouts).readAllEntries().entries {
            try entry.data.write(to: root.appendingPathComponent("\(entry.key).json"))
        }
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        #expect(try persistence.migrateLegacyLayout().moved == 8)
        #expect(persistence.migrateSchemas()[.workouts] == .upToDate(.initial))
        let afterLaunch = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())
        #expect(afterLaunch == before)

        // Un paso nuevo (v1 → v2) que no puede convertir el primer entrenamiento.
        let firstID = try #require(before.sessions.first?.id)
        let rejectFirst = SchemaMigrationStep(from: .initial) { data in
            let record = try JSONDecoder().decode(WorkoutSessionRecord.self, from: data)
            guard record.id != firstID else { throw CocoaError(.coderInvalidValue) }
            return data
        }
        let workoutsV2 = CollectionSchema(current: v2, steps: [rejectFirst]) { PersistenceCollection.workouts.decodes($0) }

        let outcomes = persistence.migrateSchemas(of: [.workouts]) { _ in workoutsV2 }

        #expect(outcomes[.workouts] == .migrated(from: .initial, to: v2, records: 7, quarantined: 1))
        let afterStep = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())
        #expect(afterStep.sessions.map(\.id) == before.sessions.dropFirst().map(\.id))
        #expect(afterStep.unreadableCount == 1, "Exportar avisa del que quedó en cuarentena")
        let backup = CollectionLayout.backupURL(for: root.appendingPathComponent("workouts", isDirectory: true))
        #expect(try records(in: backup).count == 8, "Los 8 originales siguen en el respaldo")
    }
}
