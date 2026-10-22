//
//  AIConsentTests.swift
//  PRCoreTests
//
//  SCRUM-202 (IA-1): el consentimiento se guarda por usuario, se puede retirar al
//  instante y un fallo de disco nunca hace que se compartan datos.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

/// Almacén cuya escritura falla (disco lleno, sin permisos…).
private final class FailingWriteStore: RepositoryStore, @unchecked Sendable {
    struct WriteFailed: Error {}
    func read(key: String) throws -> Data? { nil }
    func readAll() throws -> [Data] { [] }
    func readAllEntries() throws -> StoreReadResult { StoreReadResult(entries: []) }
    func write(key: String, data: Data) throws { throw WriteFailed() }
    func delete(key: String) throws {}
}

private func profileWithAboutYou() throws -> OnboardingProfile {
    var profile = try OnboardingProfile(
        goal: .strength, phase: .maintenance, experience: .advanced,
        trainingDays: [.monday, .thursday], usualSessionMinutes: 75, varietyPreference: .stable
    )
    profile.aboutYou = try AboutYou(name: nil, birthYear: 1990, sex: .male, heightCentimeters: 180, weight: 82, weightUnit: .kilograms)
    return profile
}

@MainActor
@Suite("Consentimiento para la IA (SCRUM-202)")
struct AIConsentTests {

    @Test("Sin registro es \"sin preguntar\"; lo guardado se lee igual; un archivo dañado no comparte")
    func storeRoundTrip() throws {
        let memory = MemoryRepositoryStore()
        let store = AIConsentStore(store: memory)
        #expect(try store.load(userID: "u1") == .notAsked)
        try store.save(.granted(at: now), userID: "u1", at: now)
        #expect(try store.load(userID: "u1") == .granted(at: now))
        #expect(try store.load(userID: "u2") == .notAsked, "Cada usuario tiene su propia decisión")
        try memory.write(key: try #require(memory.readAllEntries().entries.first?.key), data: Data("{ roto".utf8))
        #expect(try store.load(userID: "u1") == .notAsked)
    }

    @Test("Aceptar guarda y habilita el contexto; retirar lo corta al instante")
    func grantAndRevoke() throws {
        let store = AIConsentStore(store: MemoryRepositoryStore())
        let coordinator = AIConsentCoordinator(store: store, clock: { now })
        coordinator.load(userID: "u1")
        #expect(coordinator.needsDecision)
        let profile = try profileWithAboutYou()
        #expect(coordinator.context(for: profile) == nil)

        #expect(coordinator.grant())
        #expect(coordinator.context(for: profile) != nil)
        #expect(try store.load(userID: "u1") == .granted(at: now))

        #expect(coordinator.decline())
        #expect(coordinator.context(for: profile) == nil)
        #expect(try store.load(userID: "u1") == .declined(at: now))
    }

    @Test("Si no se puede guardar el \"sí\", no se comparte; un \"no\" aplica aunque falle el disco")
    func saveFailures() throws {
        let coordinator = AIConsentCoordinator(store: AIConsentStore(store: FailingWriteStore()), clock: { now })
        coordinator.load(userID: "u1")
        #expect(!coordinator.grant())
        #expect(coordinator.saveFailed)
        #expect(coordinator.consent == .notAsked)
        #expect(coordinator.context(for: try profileWithAboutYou()) == nil)

        #expect(!coordinator.decline())
        #expect(coordinator.consent == .declined(at: now), "Retirar nunca se queda a medias")
    }

    @Test("Cada usuario carga su decisión; cerrar sesión la olvida en memoria")
    func perUser() throws {
        let store = AIConsentStore(store: MemoryRepositoryStore())
        try store.save(.granted(at: now), userID: "ana", at: now)
        let coordinator = AIConsentCoordinator(store: store, clock: { now })
        coordinator.load(userID: "ana")
        #expect(coordinator.consent == .granted(at: now))
        coordinator.load(userID: "luis")
        #expect(coordinator.needsDecision)
        coordinator.load(userID: nil)
        #expect(coordinator.consent == .notAsked)
    }
}
