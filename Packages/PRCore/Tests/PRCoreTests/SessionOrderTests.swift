//
//  SessionOrderTests.swift
//  PRCoreTests
//
//  SCRUM-211 (FB-4): la persona reordena los ejercicios de una sesión; el orden propio se
//  guarda, sobrevive a reabrir la app y se puede restablecer; la prescripción (series,
//  reps, RIR, carga, descanso) queda idéntica; un orden que agrega o quita ejercicios se
//  rechaza.
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Lunes 19 oct 2026 a mediodía en Ciudad de México (día de entrenamiento).
private func monday() throws -> (date: Date, timeZone: TimeZone) {
    let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    return (date, timeZone)
}

private func profile() throws -> OnboardingProfile {
    try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 75, varietyPreference: .balanced
    )
}

@MainActor
private func coordinator(_ store: PlanStore) throws -> TodayPlanCoordinator {
    let today = try monday()
    return TodayPlanCoordinator(
        catalog: try ExerciseCatalogLoader.loadBundled(),
        planStore: store,
        clock: { today.date },
        timeZone: { today.timeZone }
    )
}

private func prescriptions(_ template: SessionTemplate) -> [ExerciseID: [SetPrescription]] {
    Dictionary(grouping: template.plannedSets, by: \.exerciseID).mapValues { $0.map(\.prescription) }
}

@Suite("Orden propio de los ejercicios (SCRUM-211)")
struct SessionOrderTests {

    @Test("Reordenar mueve cada ejercicio con todas sus series y no cambia la prescripción")
    func applyKeepsPrescription() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let block = try TodayPlanBuilder().generate(
            profile: try profile(), catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()
        ).block
        let template = try #require(block.sessions.first)
        let original = SessionOrderOverride.exerciseOrder(of: template)
        let reversed = Array(original.reversed())

        let moved = SessionOrderOverride.apply(reversed, to: template)
        #expect(SessionOrderOverride.exerciseOrder(of: moved) == reversed)
        #expect(moved.plannedSets.count == template.plannedSets.count)
        #expect(prescriptions(moved) == prescriptions(template), "Series, reps, RIR y descanso idénticos")
        #expect(moved.id == template.id && moved.title == template.title)
    }

    @Test("Un orden que agrega, quita o repite ejercicios se ignora")
    func invalidOrderIsIgnored() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let template = try #require(try TodayPlanBuilder().generate(
            profile: try profile(), catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()
        ).block.sessions.first)
        let original = SessionOrderOverride.exerciseOrder(of: template)
        let missing = Array(original.dropLast())
        let extra = original + [ExerciseID()]
        let repeated = Array(original.dropLast()) + [original[0]]
        for order in [missing, extra, repeated] {
            #expect(!SessionOrderOverride.isPermutation(order, of: template))
            #expect(SessionOrderOverride.apply(order, to: template) == template)
        }
    }

    @MainActor
    @Test("El orden propio se guarda, sobrevive a reabrir la app y se puede restablecer")
    func customOrderPersistsAndResets() async throws {
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let first = try coordinator(store)
        #expect(await first.activate(profile: try profile(), userID: "u1"))
        let today = try #require(first.plan?.todayTemplate)
        let recommended = SessionOrderOverride.exerciseOrder(of: today)
        let mine = Array(recommended.reversed())
        #expect(first.plan?.todayOrderIsCustom == false)

        #expect(await first.reorderSession(today.id, to: mine))
        #expect(first.plan?.todayExercises.map(\.exerciseID) == mine, "Hoy muestra el orden propio")
        #expect(first.plan?.todayOrderIsCustom == true)
        #expect(first.hasCustomOrder(today.id))
        let reordered = try #require(first.plan?.todayTemplate)
        #expect(prescriptions(reordered) == prescriptions(today), "La prescripción no cambia")

        // El bloque guardado conserva el orden del motor; el propio va aparte.
        guard case .loaded(let stored, let block) = await store.loadPlan(userID: "u1") else {
            Issue.record("Debía haber plan guardado"); return
        }
        #expect(stored.sessionOrders[today.id] == mine)
        #expect(SessionOrderOverride.exerciseOrder(of: try #require(block.sessions.first { $0.id == today.id })) == recommended)

        // Reabrir la app.
        let reopened = try coordinator(store)
        #expect(await reopened.restore(userID: "u1") == .restored(try profile()))
        #expect(reopened.plan?.todayExercises.map(\.exerciseID) == mine)
        #expect(reopened.plan?.todayOrderIsCustom == true)

        // Restablecer.
        #expect(await reopened.resetSessionOrder(today.id))
        #expect(reopened.plan?.todayExercises.map(\.exerciseID) == recommended)
        #expect(reopened.plan?.todayOrderIsCustom == false)
        guard case .loaded(let afterReset, _) = await store.loadPlan(userID: "u1") else { return }
        #expect(afterReset.customOrders == nil)
    }

    @MainActor
    @Test("Un orden inválido no se guarda y Hoy no cambia")
    func invalidReorderIsRejected() async throws {
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let coordinator = try coordinator(store)
        #expect(await coordinator.activate(profile: try profile(), userID: "u1"))
        let today = try #require(coordinator.plan?.todayTemplate)
        let before = coordinator.plan?.todayExercises.map(\.exerciseID)
        #expect(await coordinator.reorderSession(today.id, to: [ExerciseID()]) == false)
        #expect(coordinator.plan?.todayExercises.map(\.exerciseID) == before)
        guard case .loaded(let stored, _) = await store.loadPlan(userID: "u1") else { return }
        #expect(stored.customOrders == nil)
    }

    @MainActor
    @Test("Un plan nuevo (otros días) olvida los órdenes de las sesiones anteriores")
    func newBlockDropsOldOrders() async throws {
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let coordinator = try coordinator(store)
        #expect(await coordinator.activate(profile: try profile(), userID: "u1"))
        let today = try #require(coordinator.plan?.todayTemplate)
        #expect(await coordinator.reorderSession(today.id, to: SessionOrderOverride.exerciseOrder(of: today).reversed()))

        var changed = try profile()
        changed = try OnboardingProfile(
            goal: changed.goal, phase: changed.phase, experience: changed.experience,
            trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 75, varietyPreference: .balanced
        )
        #expect(await coordinator.activate(profile: changed, userID: "u1"))
        #expect(coordinator.plan?.todayOrderIsCustom == false)
        guard case .loaded(let stored, _) = await store.loadPlan(userID: "u1") else { return }
        #expect(stored.customOrders == nil)
    }
}
