//
//  SessionTimeBudgetTests.swift
//  PRCoreTests
//
//  SCRUM-30 (PR-0108): con el plan real del motor, Hoy muestra la duración de la sesión
//  real y la ajusta al tiempo elegido (30, 45, 60, 90 y 180 min) conservando las anclas
//  del motor. Integración con la persistencia real en un directorio temporal: el ajuste
//  se guarda, el entrenamiento empieza con la sesión recortada y tras un cierre forzado se
//  retoma con la misma; con un entrenamiento en curso no se cambia y al día siguiente ya
//  no aplica. La frase dice qué se quitó, que no cabe o que no se agregan series.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt

/// Día de octubre de 2026 a mediodía en Ciudad de México (19 = lunes).
private func october(_ day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
}

/// Cuatro días de torso/pierna: el lunes toca "Upper A", la sesión más larga (20 series).
private func profile() throws -> OnboardingProfile {
    try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
    )
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-time-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private func coordinator(_ store: PlanStore, clock: Clock) throws -> TodayPlanCoordinator {
    TodayPlanCoordinator(
        catalog: try ExerciseCatalogLoader.loadBundled(),
        planStore: store,
        clock: { clock.now },
        timeZone: { zone }
    )
}

private func workSets(_ id: ExerciseID, _ template: SessionTemplate) -> Int {
    template.plannedSets.filter { $0.exerciseID == id && !$0.prescription.isWarmup }.count
}

@Suite("Duración real y ajuste a mi tiempo en Hoy (SCRUM-30)")
struct SessionTimeBudgetTests {

    @Test("La misma sesión real con 30, 45, 60, 90 y 180 min: cabe o lo dice y conserva las anclas del motor")
    func realSessionAllBudgets() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let builder = TodayPlanBuilder()
        let planner = TodayPlanBuilder.defaultPlanner()
        let generated = try builder.generate(profile: try profile(), catalog: catalog, planner: planner)
        func today(_ budget: Int?) throws -> TodayPlan {
            try builder.todayPlan(
                profile: try profile(), block: generated.block, explanation: generated.explanation, catalog: catalog,
                driver: TodayScreenDriver(), date: try october(19), timeZone: zone, timeBudget: budget, planner: planner
            )
        }
        let base = try today(nil)
        let full = try #require(base.todayTemplate)
        #expect(base.timeAdjustment == nil)
        #expect(base.estimatedMinutes == SessionTimeFitter().minutes(of: full))
        let roles = try builder.timeRoles(for: full, profile: try profile(), block: generated.block, catalog: catalog, planner: planner)
        let anchors = roles.anchors.intersection(full.plannedSets.map(\.exerciseID))
        #expect(!anchors.isEmpty, "La sesión trae anclas del motor")

        for budget in [30, 45, 60, 90, 180] {
            let plan = try today(budget)
            let template = try #require(plan.todayTemplate)
            let adjustment = try #require(plan.timeAdjustment)
            #expect(adjustment.budgetMinutes == budget)
            #expect(plan.estimatedMinutes == SessionTimeFitter().minutes(of: template), "\(budget) min: Hoy muestra la sesión que se va a hacer")
            #expect(anchors.allSatisfy { workSets($0, template) == workSets($0, full) }, "\(budget) min: las anclas no se tocan")
            #expect(Set(full.plannedSets.map(\.exerciseID)).allSatisfy { workSets($0, template) <= workSets($0, full) },
                    "\(budget) min: nunca se agregan series")
            switch adjustment.fit {
            case .fits:
                #expect(template == full, "\(budget) min: si ya cabe no se toca")
            case .trimmed:
                #expect((plan.estimatedMinutes ?? .max) <= budget, "\(budget) min: recortada cabe")
            case .doesNotFit(let needed, _, _):
                #expect(needed > budget)
                #expect(plan.estimatedMinutes == needed, "Hoy dice cuánto necesita de verdad")
            }
        }
        #expect(try today(90).todayTemplate == full)
        #expect(try today(180).todayTemplate == full)
        #expect(try today(30).todayTemplate != full, "La sesión de ~40 min no cabe en 30 sin recortar")
    }

    @Test("SCRUM-225: ajustar a 30 o 45 min nunca deja un ejercicio con menos de 2 series de trabajo")
    func adjustmentNeverLeavesSingleSets() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let builder = TodayPlanBuilder()
        let planner = TodayPlanBuilder.defaultPlanner()
        let fitter = SessionTimeFitter()
        var adjusted = 0
        for goal in [TrainingGoal.hypertrophy, .strength] {
            for days in [2, 3, 4, 6] {
                for usual in [60, 90] {
                    let profile = OnboardingProfile(
                        goal: goal, phase: .maintenance, experience: .intermediate,
                        trainingDaysPerWeek: days, usualSessionMinutes: usual, varietyPreference: .balanced
                    )
                    let block = try builder.generate(profile: profile, catalog: catalog, planner: planner).block
                    for session in block.sessions {
                        let roles = try builder.timeRoles(for: session, profile: profile, block: block, catalog: catalog, planner: planner)
                        for budget in [30, 45] {
                            let (template, adjustment) = fitter.fit(session, budgetMinutes: budget, roles: roles, goal: goal, phase: .maintenance)
                            if case .fits = adjustment.fit { continue }
                            adjusted += 1
                            let exercises = Set(template.plannedSets.map(\.exerciseID))
                            let single = exercises.filter { workSets($0, template) < 2 }
                            #expect(single.isEmpty, "\(goal.rawValue) \(days)d \(usual)min → \(budget)min, \(session.title): \(single.count) ejercicio(s) con 1 serie")
                        }
                    }
                }
            }
        }
        #expect(adjusted > 0, "Alguna sesión tenía que recortarse")
    }

    @MainActor
    @Test("Desde Hoy: 30 min recorta, el entrenamiento empieza recortado y tras un cierre se retoma igual")
    func coordinatorToWorkoutAndRecovery() async throws {
        let root = try makeRoot()
        let clock = Clock(try october(19))
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let first = try coordinator(try persistence.planStore(), clock: clock)
        #expect(await first.activate(profile: try profile(), userID: "u1"))
        let full = try #require(first.plan?.todayTemplate)

        #expect(await first.setTimeBudget(30))
        let trimmed = try #require(first.plan?.todayTemplate)
        #expect(first.plan?.timeAdjustment?.budgetMinutes == 30)
        #expect(trimmed.id == full.id)
        #expect(trimmed.plannedSets.count < full.plannedSets.count)
        #expect(first.plan?.todayExercises.map(\.setCount).reduce(0, +) == trimmed.plannedSets.count,
                "La lista de Hoy es la sesión recortada")
        let todayInWeek = try #require(first.week?.days.first(where: \.isToday)?.session)
        #expect(todayInWeek.exercises == first.plan?.todayExercises, "Tu semana muestra la sesión que se va a entrenar")
        #expect(todayInWeek.estimatedMinutes == first.plan?.estimatedMinutes)

        // Empezar: el entrenamiento usa la sesión recortada.
        let workout = try await persistence.makeWorkoutCoordinator(template: trimmed, clock: { clock.now })
        _ = workout.start()
        #expect(workout.currentSet()?.total == trimmed.plannedSets.count)
        _ = try workout.completeCurrentSet()

        // Con el entrenamiento en curso el ajuste no cambia.
        first.refreshState(activeSession: try workout.snapshot().session)
        #expect(await first.setTimeBudget(nil) == false)
        #expect(first.plan?.todayTemplate == trimmed)

        // Cierre forzado: el plan guardado trae el ajuste y el entrenamiento se retoma igual.
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let second = try coordinator(try reopened.planStore(), clock: clock)
        #expect(await second.restore(userID: "u1") == .restored(try profile()))
        #expect(second.plan?.todayTemplate == trimmed)
        let templates = await second.allKnownTemplates()
        guard case .restored(let resumed) = try await reopened.recoverWorkout(templates: templates, clock: { clock.now }) else {
            Issue.record("El entrenamiento debía retomarse")
            return
        }
        #expect(resumed.currentSet()?.total == trimmed.plannedSets.count, "Ningún ejercicio quitado vuelve a aparecer")
    }

    @MainActor
    @Test("Quitar el ajuste vuelve a la sesión completa; al día siguiente el ajuste ya no aplica")
    func clearAndNextDay() async throws {
        let clock = Clock(try october(19))
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let first = try coordinator(store, clock: clock)
        #expect(await first.activate(profile: try profile(), userID: "u1"))
        let full = try #require(first.plan?.todayTemplate)

        #expect(await first.setTimeBudget(30))
        #expect(first.plan?.todayTemplate != full)
        #expect(await first.setTimeBudget(nil))
        #expect(first.plan?.todayTemplate == full)
        #expect(first.plan?.timeAdjustment == nil)
        #expect(await first.setTimeBudget(20) == false, "Fuera de 30–240 min no se acepta")

        #expect(await first.setTimeBudget(30))
        clock.now = try october(20)  // martes, también de entrenamiento
        let nextDay = try coordinator(store, clock: clock)
        #expect(await nextDay.restore(userID: "u1") == .restored(try profile()))
        #expect(nextDay.plan?.timeAdjustment == nil, "El tiempo elegido era para el lunes")
    }

    @Test("La frase dice qué se quitó y por qué, que no cabe o que no se agregan series")
    func sentences() {
        let presenter = SessionTimePresenter(locale: Locale(identifier: "es_MX"))
        let curl = ExerciseID(), lateral = ExerciseID()
        let names = [curl: "Curl martillo", lateral: "Elevaciones laterales"]
        func say(_ fit: SessionTimeFit, budget: Int = 30, original: Int = 40) -> String {
            presenter.sentence(for: SessionTimeAdjustment(budgetMinutes: budget, originalMinutes: original, fit: fit)) { names[$0] }
        }

        #expect(say(.trimmed(removed: [curl], reduced: [SetReduction(exerciseID: lateral, from: 3, to: 1)]))
                == "Para caber en 30 min quitamos Curl martillo y dejamos menos series de Elevaciones laterales; los ejercicios principales se quedan.")
        #expect(say(.trimmed(removed: [curl, lateral], reduced: []))
                == "Para caber en 30 min quitamos Curl martillo y Elevaciones laterales; los ejercicios principales se quedan.")
        #expect(say(.doesNotFit(neededMinutes: 36, removed: [curl], reduced: []))
                == "Aun recortada, esta sesión necesita unos 36 min y no cabe en 30; conservamos los ejercicios principales.")
        #expect(say(.fits(spareMinutes: 50, suggestions: [.mobility, .cardio]), budget: 90)
                == "Tu sesión dura unos 40 min; no agregamos series, pero con el tiempo que sobra puedes sumar movilidad y cardio.")
        #expect(say(.fits(spareMinutes: 5, suggestions: []), budget: 45)
                == "Tu sesión dura unos 40 min y cabe en 45; no agregamos series.")
        #expect(say(.trimmed(removed: [ExerciseID()], reduced: [])).contains("un ejercicio"), "Sin nombre en el catálogo no se inventa uno")
    }
}
