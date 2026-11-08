//
//  CoachingPreferenceTests.swift
//  PRCoreTests
//
//  SCRUM-267 (PR-H005, RF-026): cuánto le explica la app a cada persona. Sin elección, el
//  nivel de su experiencia; una elección en Perfil manda hasta volver a "según mi
//  experiencia". Se guarda por usuario en su colección, sobrevive a reabrir, no toca el plan
//  y rehacer el cuestionario no la pisa. Un error al guardar se avisa y deja lo guardado.
//  Ningún nivel quita el aviso por molestia.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

/// Almacén cuya escritura falla (disco lleno, sin permisos…).
private final class FailingWriteStore: RepositoryStore, @unchecked Sendable {
    struct WriteFailed: Error {}
    func read(key: String) throws -> Data? { nil }
    func readAll() throws -> [Data] { [] }
    func readAllEntries() throws -> StoreReadResult { StoreReadResult(entries: []) }
    func write(key: String, data: Data) throws { throw WriteFailed() }
    func delete(key: String) throws {}
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-coaching-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func persistence(_ root: URL) throws -> LocalPersistence {
    try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
}

private func profile(experience: ExperienceLevel) -> OnboardingProfile {
    OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: experience, trainingDaysPerWeek: 3,
        usualSessionMinutes: 60, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
    )
}

@MainActor
@Suite("Fase H · Cuánto me explica la app (SCRUM-267)")
struct CoachingPreferenceTests {

    @Test("Sin elección, el nivel es el de la experiencia", arguments: [
        (ExperienceLevel.novice, CoachingDetailLevel.guided),
        (.beginner, .guided),
        (.intermediate, .balanced),
        (.advanced, .advanced),
        (.competitive, .advanced),
    ])
    func defaultByExperience(experience: ExperienceLevel, expected: CoachingDetailLevel) throws {
        let coordinator = CoachingPreferenceCoordinator(store: try persistence(try makeRoot()).coachingPreferenceStore())
        coordinator.load(userID: "ana")
        let prefs = coordinator.prefs(for: experience)
        #expect(coordinator.choice == .byExperience)
        #expect(prefs.level == expected)
        #expect(!prefs.isUserChosen)
    }

    @Test("Elegir un nivel manda sobre el de la experiencia y queda como elegido")
    func manualChoiceWins() throws {
        let coordinator = CoachingPreferenceCoordinator(store: try persistence(try makeRoot()).coachingPreferenceStore())
        coordinator.load(userID: "ana")
        #expect(coordinator.choose(.manual(level: .advanced)))
        let prefs = coordinator.prefs(for: .novice)
        #expect(prefs.level == .advanced)
        #expect(prefs.isUserChosen)
        #expect(!coordinator.saveFailed)
    }

    @Test("Elegir el mismo nivel que la experiencia también cuenta como elegido")
    func sameAsDefaultIsStillChosen() throws {
        let coordinator = CoachingPreferenceCoordinator(store: try persistence(try makeRoot()).coachingPreferenceStore())
        coordinator.load(userID: "ana")
        coordinator.choose(.manual(level: .balanced))
        #expect(coordinator.prefs(for: .intermediate).isUserChosen)
    }

    @Test("'Usar el de mi experiencia' quita la elección")
    func backToExperience() throws {
        let root = try makeRoot()
        let coordinator = CoachingPreferenceCoordinator(store: try persistence(root).coachingPreferenceStore())
        coordinator.load(userID: "ana")
        coordinator.choose(.manual(level: .advanced))
        #expect(coordinator.choose(.byExperience))
        #expect(coordinator.prefs(for: .beginner).level == .guided)
        #expect(try persistence(root).coachingPreferenceStore().load(userID: "ana") == .byExperience)
    }

    @Test("Error al guardar: se avisa y sigue lo que estaba guardado")
    func saveFailureKeepsTheSavedChoice() {
        let coordinator = CoachingPreferenceCoordinator(store: CoachingPreferenceStore(store: FailingWriteStore()))
        coordinator.load(userID: "ana")
        #expect(!coordinator.choose(.manual(level: .advanced)))
        #expect(coordinator.saveFailed)
        #expect(coordinator.choice == .byExperience)
        #expect(coordinator.prefs(for: .intermediate).level == .balanced)
    }

    @Test("Sin almacén no se finge que se guardó")
    func noStoreIsAFailure() {
        let coordinator = CoachingPreferenceCoordinator(store: nil)
        coordinator.load(userID: "ana")
        #expect(!coordinator.choose(.manual(level: .guided)))
        #expect(coordinator.saveFailed)
        #expect(coordinator.choice == .byExperience)
    }

    @Test("Ningún nivel quita el aviso por molestia")
    func painWarningAtEveryLevel() {
        let driver = CoachingCardDriver()
        for level in CoachingDetailLevel.allCases {
            let card = driver.card(for: CoachingContext(level: level, painRecommendation: .stopAndRest))
            #expect(card?.id == CoachingCardDriver.painSafetyCardID, "\(level)")
        }
    }

    // MARK: - Integración con la persistencia real

    @Test("La elección sobrevive a reabrir la app")
    func survivesReopening() throws {
        let root = try makeRoot()
        let first = CoachingPreferenceCoordinator(store: try persistence(root).coachingPreferenceStore())
        first.load(userID: "ana")
        first.choose(.manual(level: .guided))

        let second = CoachingPreferenceCoordinator(store: try persistence(root).coachingPreferenceStore())
        second.load(userID: "ana")
        #expect(second.choice == .manual(level: .guided))
    }

    @Test("Dos cuentas en el mismo iPhone: cada una el suyo")
    func perUser() throws {
        let coordinator = CoachingPreferenceCoordinator(store: try persistence(try makeRoot()).coachingPreferenceStore())
        coordinator.load(userID: "ana")
        coordinator.choose(.manual(level: .advanced))
        coordinator.load(userID: "beto")
        #expect(coordinator.choice == .byExperience)
        coordinator.load(userID: "ana")
        #expect(coordinator.choice == .manual(level: .advanced))
    }

    @Test("Sin registro (datos de antes) o con uno ilegible: según la experiencia, sin borrar nada")
    func missingOrUnreadableIsByExperience() throws {
        let root = try makeRoot()
        let base = try persistence(root)
        #expect(try base.coachingPreferenceStore().load(userID: "ana") == .byExperience)

        let damaged = Data("no es json".utf8)
        try base.store(for: .coachingPreference).write(key: PlanStore.key(forUser: "ana"), data: damaged)
        #expect(try base.coachingPreferenceStore().load(userID: "ana") == .byExperience)
        #expect(try base.store(for: .coachingPreference).read(key: PlanStore.key(forUser: "ana")) == damaged, "No se borra")
    }

    @Test("Elegir no toca el plan, y rehacer el cuestionario con otra experiencia no pisa la elección")
    func independentFromThePlan() async throws {
        let root = try makeRoot()
        let base = try persistence(root)
        let planStore = try base.planStore()
        let todayPlan = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled(), planStore: planStore)
        await todayPlan.activate(profile: profile(experience: .intermediate), userID: "ana")
        guard case .loaded(let before, let block) = await planStore.loadPlan(userID: "ana") else {
            Issue.record("No hay plan guardado"); return
        }

        let coaching = CoachingPreferenceCoordinator(store: try base.coachingPreferenceStore())
        coaching.load(userID: "ana")
        coaching.choose(.manual(level: .advanced))
        guard case .loaded(let after, let sameBlock) = await planStore.loadPlan(userID: "ana") else {
            Issue.record("El plan desapareció"); return
        }
        #expect(after == before, "Elegir el nivel no reescribe el plan")
        #expect(sameBlock.id == block.id)

        // Rehacer el cuestionario como principiante.
        await todayPlan.activate(profile: profile(experience: .beginner), userID: "ana")
        let reopened = CoachingPreferenceCoordinator(store: try persistence(root).coachingPreferenceStore())
        reopened.load(userID: "ana")
        #expect(reopened.choice == .manual(level: .advanced))
        #expect(reopened.prefs(for: .beginner).level == .advanced)
    }
}
