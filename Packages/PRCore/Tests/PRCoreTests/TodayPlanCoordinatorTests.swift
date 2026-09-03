//
//  TodayPlanCoordinatorTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del cableado de "Hoy" con un plan REAL (PR-0601): a partir de un
//  `OnboardingProfile` se genera un `TrainingBlock` vía `BlockPlanner`, se elige la
//  plantilla del día por rotación determinista y `TodayScreenDriver.derive` produce
//  `readyToStart` en días de entrenamiento y `restDay` en días libres. Offline y
//  determinista; no inventa valores.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Today plan (PR-0601 wiring)")
struct TodayPlanCoordinatorTests {

    private func makeCatalog() throws -> ExerciseCatalog {
        try ExerciseCatalogLoader.loadBundled()
    }

    private func makeProfile(
        goal: TrainingGoal = .hypertrophy,
        phase: BodyCompositionPhase = .maintenance,
        experience: ExperienceLevel = .intermediate,
        days: Int = 3,
        minutes: Int = 60,
        variety: VarietyPreference = .balanced
    ) -> OnboardingProfile {
        OnboardingProfile(
            goal: goal,
            phase: phase,
            experience: experience,
            trainingDaysPerWeek: days,
            usualSessionMinutes: minutes,
            varietyPreference: variety,
            defaultGymID: nil,
            restrictions: []
        )
    }

    /// Fecha de un día concreto de la semana actual (lun=0...dom=6), tomando el lunes
    /// de esta semana y sumando el desplazamiento. Reproducible entre entornos.
    private func date(trainingWeekday: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // calendar.weekday con firstWeekday del gregoriano (1=dom...7=sáb): días desde lunes.
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: now)!
        return calendar.date(byAdding: .day, value: trainingWeekday, to: monday)!
    }

    @Test("En un día de entrenamiento genera readyToStart con plantilla real")
    func trainingDayYieldsReadyToStart() throws {
        let builder = TodayPlanBuilder()
        let plan = try builder.plan(
            profile: makeProfile(days: 3),
            catalog: try makeCatalog(),
            planner: TodayPlanBuilder.defaultPlanner(),
            driver: TodayScreenDriver(),
            date: date(trainingWeekday: 0) // lunes, dentro de los 3 días de entrenamiento
        )
        guard case .readyToStart(let presentation) = plan.todayState else {
            Issue.record("Un día de entrenamiento debía estar readyToStart, estado \(plan.todayState)")
            return
        }
        #expect(presentation.title == plan.todayTemplate?.title)
        #expect(presentation.workSetCount > 0)
        // El bloque generado es persistible y tiene sesiones.
        #expect(!plan.block.sessions.isEmpty)
        #expect((4...8).contains(plan.block.plannedWeeks))
        // Duración estimada usada del perfil (estimación del usuario).
        #expect(plan.estimatedMinutes == 60)
        #expect(presentation.estimatedMinutes == 60)
    }

    @Test("En un día libre (>= trainingDaysPerWeek) es resto")
    func restDayYieldsRestDay() throws {
        let builder = TodayPlanBuilder()
        // 3 días de entrenamiento → jueves (índice 3) es descanso.
        let plan = try builder.plan(
            profile: makeProfile(days: 3),
            catalog: try makeCatalog(),
            planner: TodayPlanBuilder.defaultPlanner(),
            driver: TodayScreenDriver(),
            date: date(trainingWeekday: 3)
        )
        #expect(plan.todayState == .restDay)
        #expect(plan.todayTemplate == nil)
    }

    @Test("El mismo perfil produce el mismo resultado (determinista)")
    func deterministic() throws {
        let builder = TodayPlanBuilder()
        let catalog = try makeCatalog()
        let planner = TodayPlanBuilder.defaultPlanner()
        let driver = TodayScreenDriver()
        let profile = makeProfile(days: 3)
        let a = try builder.plan(profile: profile, catalog: catalog, planner: planner, driver: driver, date: date(trainingWeekday: 1))
        let b = try builder.plan(profile: profile, catalog: catalog, planner: planner, driver: driver, date: date(trainingWeekday: 1))
        // Mismo resultado estructural (el id de template/block es nuevo por diseño).
        #expect(a.todayTemplate?.title == b.todayTemplate?.title)
        #expect(a.todayTemplate?.plannedSets.count == b.todayTemplate?.plannedSets.count)
        #expect(a.block.sessions.count == b.block.sessions.count)
        #expect(a.estimatedMinutes == b.estimatedMinutes)
    }

    @MainActor
    @Test("El coordinador observable expone el plan derivado")
    func observableCoordinator() throws {
        let coordinator = TodayPlanCoordinator(catalog: try makeCatalog())
        let loaded = coordinator.load(profile: makeProfile(days: 3))
        #expect(loaded)
        #expect(coordinator.plan != nil)
    }
}