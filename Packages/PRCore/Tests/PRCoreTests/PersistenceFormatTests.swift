//
//  PersistenceFormatTests.swift
//  PRCoreTests
//
//  SCRUM-40 (ADR-0003): detector en CI de cambios incompatibles en lo que la app guarda.
//  `Fixtures/Persistence/v<N>/<colección>.json` es un registro real escrito por la app
//  en la versión N de su colección.
//  - La muestra de la versión vigente se lee con el modelo actual y, al volver a
//    guardarla, conserva cada campo con su valor (agregar campos opcionales está bien;
//    quitar, renombrar o cambiar el tipo de uno, no).
//  - Las muestras de versiones anteriores se migran con los pasos registrados.
//  Si un cambio de modelo rompe esto: subir la versión de la colección en
//  `PersistenceSchemas`, agregar el paso y guardar la muestra nueva con
//  `PR_WRITE_PERSISTENCE_FIXTURES=1 swift test --filter PersistenceFormatTests`.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

/// Colecciones que la app escribe hoy (las demás existen en el enum pero nadie las abre).
private let writtenCollections: [PersistenceCollection] = [
    .workouts, .pendingOperations, .plans, .blocks, .session, .aiConsent, .checkIns,
]

private func fixture(_ collection: PersistenceCollection, version: SchemaVersion) -> Data? {
    Bundle.module
        .url(forResource: collection.rawValue, withExtension: "json", subdirectory: "Fixtures/Persistence/\(version)")
        .flatMap { try? Data(contentsOf: $0) }
}

/// Decodifica con el modelo vigente de la colección y lo vuelve a codificar como la app.
private func reencode(_ data: Data, as collection: PersistenceCollection) throws -> Data {
    func roundTrip<T: Codable>(_ type: T.Type) throws -> Data {
        try JSONEncoder().encode(JSONDecoder().decode(type, from: data))
    }
    switch collection {
    case .workouts: return try roundTrip(WorkoutSessionRecord.self)
    case .pendingOperations: return try roundTrip(PendingOperationQueue.self)
    case .profile: return try roundTrip(UserTrainingProfile.self)
    case .blocks: return try roundTrip(TrainingBlock.self)
    case .exercises: return try roundTrip(Exercise.self)
    case .gyms: return try roundTrip(GymProfile.self)
    case .restrictions: return try roundTrip(TrainingRestriction.self)
    case .decisions: return try roundTrip(DecisionRecord.self)
    case .agentAudit: return try roundTrip(AgentAuditRecord.self)
    case .plans: return try roundTrip(StoredPlan.self)
    case .session: return try roundTrip(StoredSession.self)
    case .aiConsent: return try roundTrip(StoredAIConsent.self)
    case .checkIns: return try roundTrip(SleepCheckIn.self)
    }
}

@Suite("SCRUM-40 · Muestras del formato guardado")
struct PersistenceFormatTests {

    @Test("Cada colección tiene exactamente un paso por versión", arguments: PersistenceCollection.allCases)
    func registryIsComplete(collection: PersistenceCollection) {
        #expect(PersistenceSchemas.schema(for: collection).isComplete)
    }

    @Test("Hay muestra de la versión vigente de cada colección que la app escribe", arguments: writtenCollections)
    func currentFixtureExists(collection: PersistenceCollection) {
        let current = PersistenceSchemas.schema(for: collection).current
        #expect(fixture(collection, version: current) != nil, "Falta Fixtures/Persistence/\(current)/\(collection.rawValue).json")
    }

    @Test("La muestra vigente se lee completa: ningún campo se pierde ni cambia", arguments: writtenCollections)
    func currentFixtureKeepsEveryField(collection: PersistenceCollection) throws {
        let schema = PersistenceSchemas.schema(for: collection)
        let data = try #require(fixture(collection, version: schema.current))
        #expect(schema.isReadable(data), "El modelo actual ya no lee \(collection.rawValue) \(schema.current)")
        let stored = try JSONDecoder().decode(JSONValue.self, from: data)
        let resaved = try JSONDecoder().decode(JSONValue.self, from: reencode(data, as: collection))
        let difference = stored.firstDifference(in: resaved)
        #expect(difference == nil, "\(collection.rawValue): cambió o se perdió \(difference ?? "")")
    }

    @Test("Las muestras de versiones anteriores migran al formato vigente", arguments: writtenCollections)
    func olderFixturesMigrate(collection: PersistenceCollection) throws {
        let schema = PersistenceSchemas.schema(for: collection)
        var version = SchemaVersion.initial
        while version < schema.current {
            let data = try #require(fixture(collection, version: version), "Falta la muestra \(version) de \(collection.rawValue)")
            let chain = try #require(schema.chain(from: version))
            var migrated = data
            for step in chain {
                migrated = try step.transform(migrated)
            }
            #expect(schema.isReadable(migrated), "\(collection.rawValue) \(version) no llega legible a \(schema.current)")
            version = version.next
        }
    }

    @Test("El detector señala un campo renombrado")
    func detectorCatchesRenamedField() throws {
        let data = try #require(fixture(.checkIns, version: .initial))
        let stored = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(var fields) = stored, let hours = fields.removeValue(forKey: "hours") else {
            Issue.record("La muestra de check-ins debía traer `hours`"); return
        }
        fields["sleptHours"] = hours
        #expect(stored.firstDifference(in: .object(fields)) == "$.hours")
    }

    @Test("El detector acepta un Set en otro orden, pero no un elemento perdido o cambiado")
    func detectorTreatsReorderedSetsAsEqual() {
        let stored = JSONValue.array([.string("monday"), .string("thursday")])
        #expect(stored.firstDifference(in: .array([.string("thursday"), .string("monday")])) == nil)
        #expect(stored.firstDifference(in: .array([.string("monday"), .string("friday")])) == "$[1]")
        #expect(stored.firstDifference(in: .array([.string("monday")])) == "$")
    }

    // MARK: - Generador (opt-in)

    /// Escribe la muestra vigente de cada colección con la app real (datos demo, sin
    /// datos personales). Solo corre con `PR_WRITE_PERSISTENCE_FIXTURES=1`.
    @MainActor
    @Test(
        "Genera las muestras del formato vigente",
        .enabled(if: ProcessInfo.processInfo.environment["PR_WRITE_PERSISTENCE_FIXTURES"] == "1")
    )
    func writeCurrentFixtures() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-fixtures-\(UUID().uuidString)", isDirectory: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        let userID = "fixture-user"

        let seeder = DemoDataSeeder(catalog: try ExerciseCatalogLoader.loadBundled(), timeZone: utc)
        _ = try await seeder.seedIfNeeded(persistence: persistence, userID: userID, now: now)
        try persistence.planStore().saveSession(userID: userID)
        try persistence.aiConsentStore().save(.granted(at: now), userID: userID, at: now)
        try persistence.sleepCheckInStore().save(SleepCheckIn(day: "2026-10-26", hours: 6.5, quality: .poor), userID: userID)
        // El entrenamiento de la muestra trae dolor reportado en dos series (SCRUM-32).
        let firstWorkout = try #require(try persistence.store(for: .workouts).readAllEntries().entries.first)
        var workout = try JSONDecoder().decode(WorkoutSessionRecord.self, from: firstWorkout.data)
        try #require(workout.sets.count >= 2)
        workout.sets[0].painFeedback = PainFeedback(level: .moderate, muscleGroup: .chest)
        workout.sets[1].painFeedback = PainFeedback(level: .mild)
        try persistence.workoutRepository().persist(workout)
        // El demo ya encoló esa serie sin dolor: se cambia por la versión con dolor.
        let queue = try persistence.pendingOperationQueue()
        let key = workout.sets[0].id.rawValue.persistenceKey
        if let queued = try queue.load().operations.first(where: { $0.idempotencyKey == key }) {
            try queue.remove(id: queued.id)
        }
        try #require(try SetPersistenceGuard().enqueueSetSave(workout.sets[0], in: workout.id, queue: queue, now: now))

        // Cada colección se guarda en la carpeta de su versión vigente.
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Persistence", isDirectory: true)
        for collection in writtenCollections {
            let output = fixtures.appendingPathComponent("\(PersistenceSchemas.schema(for: collection).current)", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let entry = try #require(try persistence.store(for: collection).readAllEntries().entries.first)
            try entry.data.write(to: output.appendingPathComponent("\(collection.rawValue).json"), options: .atomic)
        }
    }
}

// MARK: - JSON sin tipos para comparar campo por campo

/// Valor JSON genérico. Solo para comparar lo guardado con lo que la app vuelve a guardar.
enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Primera ruta de `self` que falta o cambia en `other` (`nil` si todo está). `other`
    /// puede traer campos de más: agregar un campo no rompe lo guardado.
    func firstDifference(in other: JSONValue, path: String = "$") -> String? {
        switch (self, other) {
        case (.object(let mine), .object(let theirs)):
            for key in mine.keys.sorted() {
                guard let value = mine[key], let counterpart = theirs[key] else { return "\(path).\(key)" }
                if let difference = value.firstDifference(in: counterpart, path: "\(path).\(key)") { return difference }
            }
            return nil
        case (.array(let mine), .array(let theirs)):
            guard mine.count == theirs.count else { return path }
            let inOrder = zip(mine, theirs).enumerated().lazy.compactMap { item in
                item.element.0.firstDifference(in: item.element.1, path: "\(path)[\(item.offset)]")
            }.first
            guard let inOrder else { return nil }
            // Un `Set` se guarda en un orden distinto en cada proceso: si los mismos
            // elementos están en otro orden, no es un cambio. Volver a guardar un arreglo
            // con orden nunca lo reordena, así que esto no esconde datos perdidos.
            var remaining = theirs
            for element in mine {
                guard let match = remaining.firstIndex(where: { element.firstDifference(in: $0) == nil }) else { return inOrder }
                remaining.remove(at: match)
            }
            return nil
        default:
            return self == other ? nil : path
        }
    }
}
