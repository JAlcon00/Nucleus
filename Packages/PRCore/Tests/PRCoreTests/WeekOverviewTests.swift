//
//  WeekOverviewTests.swift
//  PRCoreTests
//
//  SCRUM-197 (U4): "Tu semana". Cada día de lunes a domingo dice qué toca (sesión con
//  músculos, ejercicios, series y minutos) y en qué estado está: descanso, pendiente,
//  hecho o no realizado (nunca como error). M1: "3 × 8–12" y "última vez: 60 kg × 10".
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

/// Día de la semana del 19 de octubre de 2026 (lunes = 0) a la hora indicada, en UTC.
private func day(_ mondayIndex: Int, hour: Int = 12) throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 19 + mondayIndex
    components.hour = hour
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private func profile(_ days: Set<WeekDay> = [.monday, .wednesday, .friday]) throws -> OnboardingProfile {
    try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: days, usualSessionMinutes: 60, varietyPreference: .balanced
    )
}

private struct WeekFixture {
    let profile: OnboardingProfile
    let result: BlockPlanningResult
    let catalog: ExerciseCatalog

    init(_ profile: OnboardingProfile) throws {
        self.profile = profile
        catalog = try ExerciseCatalogLoader.loadBundled()
        result = try TodayPlanBuilder().generate(profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner())
    }

    func week(on date: Date, history: [WorkoutSessionRecord] = []) throws -> WeekOverview {
        try #require(WeekOverviewBuilder().overview(
            profile: profile, block: result.block, explanation: result.explanation,
            catalog: catalog, history: history, date: date, timeZone: utc
        ))
    }
}

private func completedSession(on date: Date, sets: [SetRecord] = []) -> WorkoutSessionRecord {
    WorkoutSessionRecord(startedAt: date, endedAt: date.addingTimeInterval(3600), lifecycle: .completed, sets: sets)
}

@Suite("Tu semana (SCRUM-197)")
struct WeekOverviewTests {

    @Test("Lunes, miércoles y viernes: siete días en orden con descanso intercalado")
    func daysInOrderWithInterleavedRest() throws {
        let week = try WeekFixture(try profile()).week(on: try day(2))
        #expect(week.days.map(\.day) == WeekDay.allCases)
        #expect(week.days.map { $0.session != nil } == [true, false, true, false, true, false, false])
        #expect(week.today?.day == .wednesday)
        #expect(week.days.filter(\.isToday).count == 1)
    }

    @Test("Estados: pasado sin hacer es 'no realizado'; hoy y lo que viene, pendiente; descanso")
    func statusesWithoutHistory() throws {
        let week = try WeekFixture(try profile()).week(on: try day(2))
        #expect(week.days.map(\.status) == [.missed, .rest, .pending, .rest, .pending, .rest, .rest])
    }

    @Test("Un entrenamiento completado ese día lo marca como hecho")
    func completedWorkoutMarksTheDay() throws {
        let history = [
            completedSession(on: try day(0, hour: 7)),
            // Abandonado: no cuenta.
            WorkoutSessionRecord(startedAt: try day(2, hour: 7), lifecycle: .abandoned),
        ]
        let week = try WeekFixture(try profile()).week(on: try day(2, hour: 20), history: history)
        #expect(week.days[0].status == .completed)
        #expect(week.days[2].status == .pending)
    }

    @Test("Un entrenamiento de la semana anterior no marca esta semana")
    func previousWeekDoesNotCount() throws {
        let lastMonday = try day(-7)
        let week = try WeekFixture(try profile()).week(on: try day(2), history: [completedSession(on: lastMonday)])
        #expect(week.days[0].status == .missed)
    }

    @Test("Cada sesión trae sus músculos principales (máx. 3), ejercicios, series y minutos")
    func sessionSummary() throws {
        let fixture = try WeekFixture(try profile([.monday, .tuesday, .thursday, .friday, .saturday]))
        let week = try fixture.week(on: try day(0))
        let sessions = week.days.compactMap(\.session)
        #expect(sessions.count == 5)
        for session in sessions {
            #expect(!session.muscles.isEmpty)
            #expect(session.muscles.count <= WeekOverviewBuilder.maxMuscles)
            #expect(!session.exercises.isEmpty)
            #expect(session.workSetCount == session.exercises.map(\.workSetCount).reduce(0, +))
            #expect(session.estimatedMinutes == 60)
        }
        // Con 5 días el split es Push/Pull/Legs: el Pull tiene espalda primero.
        let pull = try #require(sessions.first { $0.title.hasPrefix("Pull") })
        #expect(pull.muscles.first == .back)
    }

    @Test("Los ejercicios traen series de trabajo y rango de repeticiones (3 × 8–12)")
    func exerciseLinesHaveRepRange() throws {
        let week = try WeekFixture(try profile()).week(on: try day(0))
        let line = try #require(week.days[0].session?.exercises.first)
        #expect(line.workSetCount > 0)
        #expect(line.repRange == 8...12)
    }

    @Test("Cada sesión trae su '¿Por qué este orden?'")
    func sessionsCarryOrderExplanation() throws {
        let week = try WeekFixture(try profile()).week(on: try day(0))
        for session in week.days.compactMap(\.session) {
            #expect(session.order.count == session.exercises.count)
        }
    }

    @Test("Perfil con una semana inválida: no hay semana (no se inventa)")
    func invalidProfileHasNoWeek() throws {
        let valid = try WeekFixture(try profile())
        let invalid = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 9, usualSessionMinutes: 60, varietyPreference: .balanced
        )
        #expect(WeekOverviewBuilder().overview(
            profile: invalid, block: valid.result.block, explanation: valid.result.explanation,
            catalog: valid.catalog, history: [], date: try day(0), timeZone: utc
        ) == nil)
    }

    // MARK: - Última vez (M1)

    @Test("Última vez: la mejor serie de la sesión completada más reciente")
    func lastPerformanceUsesMostRecentBestSet() throws {
        let squat = ExerciseID()
        let old = completedSession(on: try day(-7), sets: [
            try SetRecord(exerciseID: squat, weight: 100, unit: .kilograms, reps: 5, lifecycle: .completed),
        ])
        let recent = completedSession(on: try day(0), sets: [
            try SetRecord(exerciseID: squat, weight: 40, unit: .kilograms, reps: 10, lifecycle: .completed),
            try SetRecord(exerciseID: squat, weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed),
            try SetRecord(exerciseID: squat, weight: 60, unit: .kilograms, reps: 10, lifecycle: .completed),
            try SetRecord(exerciseID: squat, weight: 80, unit: .kilograms, reps: 1, lifecycle: .skipped),
        ])
        let index = LastPerformanceIndex.build(from: [old, recent])
        let last = try #require(index[squat])
        #expect(last.weight == 60)
        #expect(last.reps == 10)
        #expect(last.unit == .kilograms)
    }

    @Test("Última vez ignora sesiones abandonadas o sin terminar")
    func lastPerformanceIgnoresUnfinishedSessions() throws {
        let press = ExerciseID()
        let abandoned = WorkoutSessionRecord(startedAt: try day(1), lifecycle: .abandoned, sets: [
            try SetRecord(exerciseID: press, weight: 50, unit: .kilograms, reps: 8, lifecycle: .completed),
        ])
        #expect(LastPerformanceIndex.build(from: [abandoned]).isEmpty)
    }

    // MARK: - Coordinador

    @MainActor
    @Test("El coordinador expone la semana y la última vez tras leer el historial")
    func coordinatorExposesWeek() async throws {
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(),
            clock: { (try? day(2)) ?? Date() },
            timeZone: { utc }
        )
        #expect(coordinator.week == nil, "Sin plan no hay semana")
        #expect(coordinator.load(profile: try profile()))
        let week = try #require(coordinator.week)
        #expect(week.today?.day == .wednesday)

        let exerciseID = try #require(week.days[0].session?.exercises.first?.exerciseID)
        coordinator.updateHistory([
            completedSession(on: try day(0), sets: [
                try SetRecord(exerciseID: exerciseID, weight: 60, unit: .kilograms, reps: 10, lifecycle: .completed),
            ]),
        ])
        #expect(coordinator.week?.days[0].status == .completed)
        #expect(coordinator.lastPerformance[exerciseID]?.weight == 60)
    }

    // MARK: - Textos

    @Test("Textos: series × rango y última vez")
    func texts() {
        let spanish = TrainingVocabularyPresenter(locale: Locale(identifier: "es_MX"))
        #expect(spanish.setsAndReps(sets: 3, repRange: 8...12) == "3 × 8–12")
        #expect(spanish.setsAndReps(sets: 3, repRange: 10...10) == "3 × 10")
        #expect(spanish.setsAndReps(sets: 2, repRange: nil) == "2 series")
        let last = LastPerformance(weight: 60, unit: .kilograms, reps: 10, performedAt: Date())
        #expect(spanish.lastTime(last) == "Última vez: 60 kg × 10")
        let decimal = LastPerformance(weight: 82.5, unit: .kilograms, reps: 8, performedAt: Date())
        #expect(spanish.lastTime(decimal) == "Última vez: 82.5 kg × 8")
    }
}
