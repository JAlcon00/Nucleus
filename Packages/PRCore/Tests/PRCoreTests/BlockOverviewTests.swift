//
//  BlockOverviewTests.swift
//  PRCoreTests
//
//  SCRUM-266 (PR-H004): "Tu bloque" en Plan. Objetivo, fase y en qué semana va el bloque,
//  con semanas de lunes a domingo (como "Tu semana" y Progreso). Pasada la última semana
//  se dice que terminó, nunca "semana 7 de 6". El cambio de horario no mueve la semana.
//  Cambiar objetivo o fase abre un bloque nuevo en la semana 1 y conserva el anterior.
//

import Foundation
import Testing
import PRCore
import PRDomain

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, in timeZone: TimeZone) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
}

private func block(start: Date, weeks: Int = 6, goal: TrainingGoal = .hypertrophy, phase: BodyCompositionPhase = .maintenance) throws -> TrainingBlock {
    try TrainingBlock(
        name: "Bloque", goal: goal, phase: phase, startDate: start, plannedWeeks: weeks,
        progressionPolicy: .doubleProgression, deloadPolicy: .afterSixWeeks,
        varietyPolicy: try VarietyPolicy(percentStable: 0.65)
    )
}

private let mexico = TimeZone(identifier: "America/Mexico_City") ?? .current
private let newYork = TimeZone(identifier: "America/New_York") ?? .current

private func week(_ block: TrainingBlock, on day: Date, in timeZone: TimeZone = mexico) -> BlockWeek {
    BlockOverviewBuilder().overview(block: block, date: day, timeZone: timeZone).week
}

@Suite("Fase H · Tu bloque en Plan (SCRUM-266)")
struct BlockOverviewTests {

    @Test("Un bloque de 6 semanas que empezó el lunes 19 de octubre va en la semana 2 el miércoles 28")
    func secondWeek() throws {
        let start = try date(2026, 10, 19, in: mexico)
        let overview = BlockOverviewBuilder().overview(
            block: try block(start: start, goal: .strength, phase: .deficit), date: try date(2026, 10, 28, in: mexico), timeZone: mexico
        )
        #expect(overview.week == .current(week: 2, of: 6))
        #expect(overview.goal == .strength)
        #expect(overview.phase == .deficit)
        #expect(overview.startDate == start)
    }

    @Test("El día que empieza es la semana 1")
    func firstWeek() throws {
        let start = try date(2026, 10, 19, hour: 9, in: mexico)
        #expect(week(try block(start: start), on: start) == .current(week: 1, of: 6))
        #expect(week(try block(start: start), on: try date(2026, 10, 25, hour: 23, in: mexico)) == .current(week: 1, of: 6))
    }

    @Test("Semanas de lunes a domingo: si empezó un jueves, el lunes siguiente ya es la semana 2")
    func startedOnThursday() throws {
        let thursday = try date(2026, 10, 22, in: mexico)
        let b = try block(start: thursday)
        #expect(week(b, on: try date(2026, 10, 25, hour: 22, in: mexico)) == .current(week: 1, of: 6), "domingo")
        #expect(week(b, on: try date(2026, 10, 26, hour: 6, in: mexico)) == .current(week: 2, of: 6), "lunes")
    }

    @Test("La última semana se nombra; después, el bloque terminó (nunca 'semana 7 de 6')")
    func lastWeekAndFinished() throws {
        let b = try block(start: try date(2026, 10, 19, in: mexico))
        #expect(week(b, on: try date(2026, 11, 29, hour: 20, in: mexico)) == .current(week: 6, of: 6))
        #expect(week(b, on: try date(2026, 11, 30, hour: 8, in: mexico)) == .finished(plannedWeeks: 6))
        #expect(week(b, on: try date(2027, 2, 1, in: mexico)) == .finished(plannedWeeks: 6))
    }

    @Test("Una fecha anterior al inicio (reloj cambiado) cuenta como la semana 1")
    func dateBeforeStart() throws {
        let b = try block(start: try date(2026, 10, 19, in: mexico), weeks: 4)
        #expect(week(b, on: try date(2026, 10, 5, in: mexico)) == .current(week: 1, of: 4))
    }

    @Test("El cambio de horario no mueve la semana")
    func daylightSavingTime() throws {
        // Nueva York adelanta el reloj el domingo 8 de marzo de 2026: esa semana dura 167 h.
        let start = try date(2026, 3, 2, hour: 0, minute: 30, in: newYork)
        let b = try block(start: start)
        #expect(week(b, on: try date(2026, 3, 9, hour: 0, minute: 10, in: newYork), in: newYork) == .current(week: 2, of: 6))
        #expect(week(b, on: try date(2026, 3, 8, hour: 23, minute: 50, in: newYork), in: newYork) == .current(week: 1, of: 6))
        // Y lo atrasa el domingo 1 de noviembre de 2026: esa semana dura 169 h.
        let fall = try block(start: try date(2026, 10, 26, hour: 0, minute: 10, in: newYork))
        #expect(week(fall, on: try date(2026, 11, 1, hour: 23, minute: 55, in: newYork), in: newYork) == .current(week: 1, of: 6))
        #expect(week(fall, on: try date(2026, 11, 2, hour: 0, minute: 5, in: newYork), in: newYork) == .current(week: 2, of: 6))
    }

    // MARK: - Integración

    @MainActor
    @Test("Integración: cambiar el objetivo abre un bloque nuevo en la semana 1 y conserva el anterior")
    func changingTheGoalStartsAtWeekOne() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-block-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let planStore = try persistence.planStore()
        let catalog = try ExerciseCatalogLoader.loadBundled()
        var now = try date(2026, 10, 19, in: mexico)
        let coordinator = TodayPlanCoordinator(catalog: catalog, planStore: planStore, clock: { now }, timeZone: { mexico })
        func profile(_ goal: TrainingGoal) -> OnboardingProfile {
            OnboardingProfile(
                goal: goal, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: 3,
                usualSessionMinutes: 60, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
            )
        }

        await coordinator.activate(profile: profile(.hypertrophy), userID: "ana")
        let first = try #require(coordinator.blockOverview)
        #expect(first.goal == .hypertrophy)
        guard case .current(1, let planned) = first.week else {
            Issue.record("Debía ir en la semana 1: \(first.week)"); return
        }

        // Dos semanas después cambia el objetivo.
        now = try date(2026, 11, 4, in: mexico)
        #expect(coordinator.blockOverview?.week == .current(week: 3, of: planned))
        let oldID = try #require(coordinator.plan?.block.id)
        await coordinator.activate(profile: profile(.strength), userID: "ana")
        let changed = try #require(coordinator.blockOverview)
        #expect(changed.goal == .strength)
        #expect(changed.startDate == now)
        guard case .current(1, _) = changed.week else {
            Issue.record("El bloque nuevo debía empezar en la semana 1: \(changed.week)"); return
        }

        guard case .loaded(let stored, let active) = await planStore.loadPlan(userID: "ana") else {
            Issue.record("No hay plan guardado"); return
        }
        #expect(active.id != oldID)
        let history = await planStore.blockHistory(of: stored)
        #expect(history.first?.id == oldID, "El bloque anterior se conserva")
        #expect(history.first?.status == .completed)
        #expect(history.first?.goal == .hypertrophy)
    }
}
