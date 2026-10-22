//
//  UserScopedHistoryTests.swift
//  PRCoreTests
//
//  SCRUM-26: el historial de entrenamientos (y la cola de pendientes) es de cada usuario.
//  Dos cuentas en el mismo dispositivo no comparten sesiones ni Export; el historial
//  anterior a las cuentas (sin dueño) lo adopta el primer usuario, una sola vez y sin
//  perder datos.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-26 · Historial por usuario")
struct UserScopedHistoryTests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func persistence(_ root: URL) throws -> LocalPersistence {
        try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
    }

    @Test("Dos cuentas no comparten historial")
    func twoUsersHaveSeparateHistory() async throws {
        let base = try persistence(try makeRoot())
        let alice = try base.scoped(toUser: "alice")
        let bob = try base.scoped(toUser: "bob")
        try await alice.workoutRepository().save(try Fixture.completedSession(sets: 3, startedAt: Date(timeIntervalSince1970: 0)))

        #expect(try await alice.workoutRepository().loadAllSessions().items.count == 1)
        #expect(try await bob.workoutRepository().loadAllSessions().items.isEmpty)

        try await bob.workoutRepository().save(try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 100)))
        #expect(try await alice.workoutRepository().loadAllSessions().items.count == 1)
        #expect(try await bob.workoutRepository().loadAllSessions().items.count == 1)
    }

    @Test("El mismo usuario ve su historial al reabrir")
    func sameUserSeesHistoryAfterReopen() async throws {
        let root = try makeRoot()
        let first = try persistence(root).scoped(toUser: "alice")
        try await first.workoutRepository().save(try Fixture.completedSession(sets: 3, startedAt: Date(timeIntervalSince1970: 0)))
        let again = try persistence(root).scoped(toUser: "alice")
        #expect(try await again.workoutRepository().loadAllSessions().items.count == 1)
    }

    @Test("El historial anterior a las cuentas lo adopta el primer usuario, una sola vez")
    func firstUserAdoptsUnownedHistory() async throws {
        let root = try makeRoot()
        let base = try persistence(root)
        // Historial sin dueño (como lo dejaba la app antes de las cuentas).
        try await base.workoutRepository().save(try Fixture.completedSession(sets: 3, startedAt: Date(timeIntervalSince1970: 0)))
        try await base.workoutRepository().save(try Fixture.completedSession(sets: 2, startedAt: Date(timeIntervalSince1970: 50)))

        let alice = try base.scoped(toUser: "alice")
        #expect(try await alice.workoutRepository().loadAllSessions().items.count == 2)
        #expect(try await base.workoutRepository().loadAllSessions().items.isEmpty, "el origen quedó vacío: nada duplicado")

        // Un segundo usuario no hereda nada, ni al reabrir ni al repetir la adopción.
        let bob = try base.scoped(toUser: "bob")
        #expect(try await bob.workoutRepository().loadAllSessions().items.isEmpty)
        let aliceAgain = try persistence(root).scoped(toUser: "alice")
        #expect(try await aliceAgain.workoutRepository().loadAllSessions().items.count == 2)
    }

    @Test("La cola de pendientes también es por usuario")
    func pendingQueueIsPerUser() async throws {
        let base = try persistence(try makeRoot())
        let alice = try base.scoped(toUser: "alice")
        let bob = try base.scoped(toUser: "bob")
        let aliceQueue = try alice.pendingOperationQueue()
        _ = try aliceQueue.enqueue(Fixture.pendingOperation())
        #expect(try aliceQueue.load().operations.count == 1)
        #expect(try bob.pendingOperationQueue().load().operations.isEmpty)
    }
}
