//
//  UnreadablePlanTests.swift
//  PRCoreTests
//
//  SCRUM-223: con un plan ilegible, "Rehacer cuestionario" guardaba el plan nuevo encima
//  del anterior. Ahora el anterior se guarda intacto en la cuarentena de `plans/` antes de
//  escribir; si eso no se puede, no se escribe nada. Todo sobre `LocalPersistence` real
//  en un directorio temporal y el catálogo real.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-unreadable-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Lunes 19 de octubre de 2026 a mediodía (UTC).
private func monday() throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
}

private func profile() -> OnboardingProfile {
    OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced
    )
}

@MainActor
private func coordinator(_ planStore: PlanStore) throws -> TodayPlanCoordinator {
    let date = try monday()
    return TodayPlanCoordinator(
        catalog: try ExerciseCatalogLoader.loadBundled(), planStore: planStore, clock: { date }, timeZone: { utc }
    )
}

private func planURL(in root: URL, user: String) -> URL {
    root.appendingPathComponent("plans/\(PlanStore.key(forUser: user)).json")
}

/// Copias guardadas de planes dañados, por nombre de archivo.
private func damagedCopies(in root: URL) throws -> [String: Data] {
    let directory = CollectionLayout.quarantineURL(in: root.appendingPathComponent("plans", isDirectory: true))
        .appendingPathComponent("damaged", isDirectory: true)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
    var copies: [String: Data] = [:]
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasSuffix(".json") {
        copies[name] = try Data(contentsOf: directory.appendingPathComponent(name))
    }
    return copies
}

@MainActor
@Suite("SCRUM-223 · Un plan ilegible no se sobrescribe al rehacer el cuestionario")
struct UnreadablePlanTests {

    @Test("Plan con JSON roto → rehacer: se guarda el plan nuevo y el original queda en cuarentena, byte por byte")
    func brokenRecordIsPreservedBeforeOverwrite() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        #expect(try await coordinator(try persistence.planStore()).activate(profile: profile(), userID: "u1"))
        let broken = Data("{roto".utf8)
        try broken.write(to: planURL(in: root, user: "u1"))

        let reopened = try coordinator(try persistence.planStore())
        #expect(await reopened.restore(userID: "u1") == .unreadable)
        #expect(await reopened.activate(profile: profile(), userID: "u1"))

        #expect(try damagedCopies(in: root).values.map { $0 } == [broken])
        guard case .loaded(let stored, let block) = try await persistence.planStore().loadPlan(userID: "u1") else {
            Issue.record("El plan nuevo debía quedar guardado"); return
        }
        #expect(stored.blockHistory == [block.id], "Del registro roto no hay historial que rescatar")
    }

    @Test("Plan sano con bloque activo ilegible → rehacer: conserva el historial y el bloque sigue en disco")
    func readableRecordKeepsBlockHistory() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let first = try coordinator(try persistence.planStore())
        #expect(await first.activate(profile: profile(), userID: "u1"))
        let firstBlock = try #require(first.plan?.block.id)
        let record = try Data(contentsOf: planURL(in: root, user: "u1"))
        let blockURL = root.appendingPathComponent("blocks/\(firstBlock.rawValue.persistenceKey).json")
        let brokenBlock = Data("{bloque roto".utf8)
        try brokenBlock.write(to: blockURL)

        let reopened = try coordinator(try persistence.planStore())
        #expect(await reopened.restore(userID: "u1") == .unreadable)
        #expect(await reopened.activate(profile: profile(), userID: "u1"))

        guard case .loaded(let stored, let block) = try await persistence.planStore().loadPlan(userID: "u1") else {
            Issue.record("El plan nuevo debía quedar guardado"); return
        }
        #expect(stored.blockHistory == [firstBlock, block.id])
        #expect(try Data(contentsOf: blockURL) == brokenBlock, "El bloque ilegible no se toca")
        #expect(try damagedCopies(in: root).values.map { $0 } == [record], "El registro sano también se guarda")
    }

    @Test("Si la copia a cuarentena falla, no se escribe el plan nuevo y el anterior queda intacto")
    func failedCopyWritesNothing() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        #expect(try await coordinator(try persistence.planStore()).activate(profile: profile(), userID: "u1"))
        let broken = Data("{roto".utf8)
        try broken.write(to: planURL(in: root, user: "u1"))
        let blocksBefore = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("blocks").path).sorted()
        let failing = PlanStore(
            plans: try persistence.store(for: .plans),
            sessions: try persistence.store(for: .session),
            blocks: try persistence.store(for: .blocks),
            damagedPlans: UnwritableStore()
        )

        let reopened = try coordinator(failing)
        #expect(await reopened.activate(profile: profile(), userID: "u1") == false)

        #expect(try Data(contentsOf: planURL(in: root, user: "u1")) == broken)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("blocks").path).sorted() == blocksBefore,
                "Tampoco se escribe un bloque nuevo")
        #expect(reopened.generation == .failed)
    }

    @Test("Rehacer dos veces: cada versión dañada queda guardada una vez, sin pisarse")
    func twoRedosKeepBothDamagedVersions() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        #expect(try await coordinator(try persistence.planStore()).activate(profile: profile(), userID: "u1"))

        let firstBroken = Data("{roto 1".utf8)
        try firstBroken.write(to: planURL(in: root, user: "u1"))
        #expect(try await coordinator(try persistence.planStore()).activate(profile: profile(), userID: "u1"))
        let secondBroken = Data("{roto 2".utf8)
        try secondBroken.write(to: planURL(in: root, user: "u1"))
        #expect(try await coordinator(try persistence.planStore()).activate(profile: profile(), userID: "u1"))

        let key = PlanStore.key(forUser: "u1")
        #expect(try damagedCopies(in: root) == ["\(key)-1.json": firstBroken, "\(key)-2.json": secondBroken])
    }

    @Test("Guardar la misma versión dañada otra vez no la duplica")
    func samePlanIsNotCopiedTwice() throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let planStore = try persistence.planStore()
        try Data("{roto".utf8).write(to: planURL(in: root, user: "u1"))

        _ = try planStore.preserveUnreadablePlan(userID: "u1")
        _ = try planStore.preserveUnreadablePlan(userID: "u1")

        #expect(try damagedCopies(in: root).count == 1)
    }

    @Test("Plan que quedó en cuarentena al migrar (SCRUM-40) → rehacer: nada que copiar y el plan nuevo se guarda")
    func migrationQuarantinedPlanNeedsNoCopy() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let migrationQuarantine = CollectionLayout.quarantineURL(in: root.appendingPathComponent("plans", isDirectory: true))
            .appendingPathComponent("v1", isDirectory: true)
        try AtomicFileRepositoryStore(directory: migrationQuarantine).write(key: PlanStore.key(forUser: "u1"), data: Data("{}".utf8))

        let reopened = try coordinator(try persistence.planStore())
        #expect(await reopened.restore(userID: "u1") == .unreadable)
        #expect(await reopened.activate(profile: profile(), userID: "u1"))

        #expect(try damagedCopies(in: root).isEmpty)
        guard case .loaded = try await persistence.planStore().loadPlan(userID: "u1") else {
            Issue.record("El plan nuevo debía quedar guardado"); return
        }
    }

    @Test("El registro anota la copia sin datos personales")
    func preservationIsLoggedWithoutPersonalData() throws {
        let root = try makeRoot()
        let messages = LockedMessages()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { messages.append($0) })
        let planStore = try persistence.planStore()
        try Data("{roto".utf8).write(to: planURL(in: root, user: "apple-user-1"))

        _ = try planStore.preserveUnreadablePlan(userID: "apple-user-1")

        #expect(messages.all == ["persistence.quarantine damaged collection=plans count=1"])
    }
}

/// Almacén donde no se puede escribir (disco lleno o bloqueado).
private struct UnwritableStore: RepositoryStore {
    struct WriteFailed: Error {}
    func read(key: String) throws -> Data? { nil }
    func readAll() throws -> [Data] { [] }
    func readAllEntries() throws -> StoreReadResult { StoreReadResult(entries: []) }
    func write(key: String, data: Data) throws { throw WriteFailed() }
    func delete(key: String) throws {}
}

private final class LockedMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    var all: [String] { lock.withLock { messages } }
    func append(_ message: String) { lock.withLock { messages.append(message) } }
}
