//
//  TodayWeekIntegrationTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  SCRUM-27 (integración parcial): el coordinador real de "Hoy", con el catálogo
//  real y reloj/zona inyectados, recorre la semana del 19 al 25 de octubre de 2026
//  (lunes a domingo). Para cada opción de 2 a 7 días, exactamente N días están listos
//  para entrenar y el resto muestra descanso sin plantilla. La parte con
//  `AppEnvironment` y plan persistido se completa en SCRUM-26 (bloque 6).
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-27 · Hoy recorre la semana correcta")
struct TodayWeekIntegrationTests {

    private func profile(days: Int) -> OnboardingProfile {
        OnboardingProfile(
            goal: .hypertrophy,
            phase: .maintenance,
            experience: .intermediate,
            trainingDaysPerWeek: days,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            defaultGymID: nil,
            restrictions: []
        )
    }

    /// Mediodía local de cada día de la semana 19–25 oct 2026 (lunes…domingo).
    private func week(in timeZone: TimeZone) throws -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try (19...25).map { day in
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
        }
    }

    @MainActor
    @Test("Para N = 2…7, Hoy propone entrenar exactamente N días y descansa el resto",
          arguments: Array(2...7))
    func todayAcrossWeek(days: Int) throws {
        let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
        let catalog = try ExerciseCatalogLoader.loadBundled()
        var states: [TodayScreenState] = []
        for date in try week(in: timeZone) {
            let coordinator = TodayPlanCoordinator(catalog: catalog, clock: { date }, timeZone: { timeZone })
            #expect(coordinator.load(profile: profile(days: days)))
            let plan = try #require(coordinator.plan)
            states.append(plan.todayState)
            if plan.todayState == .restDay {
                #expect(plan.todayTemplate == nil)
            }
        }
        let trainingDays = states.filter {
            if case .readyToStart = $0 { return true }
            return false
        }
        #expect(trainingDays.count == days)
        #expect(states.prefix(days).allSatisfy { $0 != .restDay })
        #expect(states.dropFirst(days).allSatisfy { $0 == .restDay })
    }
}

@Suite("Hoy lista los ejercicios de la sesión")
struct TodayExerciseListTests {

    @MainActor
    @Test("En un día de entrenamiento Hoy trae los ejercicios con nombre y series, en el orden de la plantilla")
    func listsExercisesInTemplateOrder() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let coordinator = TodayPlanCoordinator(catalog: catalog, clock: { monday }, timeZone: { timeZone })
        let profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced,
            defaultGymID: nil, restrictions: []
        )
        #expect(coordinator.load(profile: profile))
        let plan = try #require(coordinator.plan)
        let template = try #require(plan.todayTemplate)

        #expect(!plan.todayExercises.isEmpty)
        #expect(plan.todayExercises.allSatisfy { $0.name != nil })
        #expect(plan.todayExercises.map(\.setCount).reduce(0, +) == template.plannedSets.count)
        var seen: [ExerciseID] = []
        for planned in template.plannedSets where !seen.contains(planned.exerciseID) { seen.append(planned.exerciseID) }
        #expect(plan.todayExercises.map(\.exerciseID) == seen)
    }

    @MainActor
    @Test("En día de descanso no hay ejercicios")
    func restDayHasNoExercises() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), clock: { sunday }, timeZone: { timeZone }
        )
        let profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced,
            defaultGymID: nil, restrictions: []
        )
        #expect(coordinator.load(profile: profile))
        #expect(coordinator.plan?.todayExercises.isEmpty == true)
    }
}
