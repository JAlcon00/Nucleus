//
//  ProgressInsightsTests.swift
//  PRCoreTests
//
//  SCRUM-213 (FB-6): los 4 KPIs (adherencia, series de la semana, racha y récords del
//  bloque) y las gráficas (series por semana y carga máxima) salen del historial con
//  fechas y zona inyectadas; semanas sin datos cuentan 0 y sin historial todo es 0.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .gmt

/// Día relativo al lunes 19 oct 2026 (0 = ese lunes; -7 = el lunes anterior), en UTC.
private func day(_ offset: Int, hour: Int = 9) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour)))
    return try #require(calendar.date(byAdding: .day, value: offset, to: monday))
}

private let squat = ExerciseID()
private let curl = ExerciseID()

/// Un entrenamiento completado con `sets` series de sentadilla al peso dado.
private func workout(on date: Date, sets: Int = 3, squatWeight: Double = 100, curlInPounds: Bool = false) throws -> WorkoutSessionRecord {
    var records = try (0..<sets).map { index in
        try SetRecord(exerciseID: squat, performedAt: date.addingTimeInterval(Double(index * 120)),
                      weight: squatWeight, unit: .kilograms, reps: 5, lifecycle: .completed)
    }
    if curlInPounds {
        records.append(try SetRecord(exerciseID: curl, performedAt: date.addingTimeInterval(900),
                                     weight: 30, unit: .pounds, reps: 10, lifecycle: .completed))
    }
    return WorkoutSessionRecord(
        templateID: UUID(), startedAt: date, endedAt: date.addingTimeInterval(2_700),
        lifecycle: .completed, sets: records
    )
}

private func insights(_ history: [WorkoutSessionRecord], on date: Date, planned: Int? = 3, blockStart: Date? = nil) -> ProgressInsights {
    ProgressOverviewBuilder().overview(
        history: history, templateTitles: [:], exerciseNames: [squat: "Sentadilla", curl: "Curl"],
        plannedPerWeek: planned, blockStart: blockStart, date: date, timeZone: utc
    ).insights
}

@Suite("Progreso: KPIs y gráfica (SCRUM-213)")
struct ProgressInsightsTests {

    @Test("Adherencia y series de la semana en curso (lunes a domingo)")
    func thisWeek() throws {
        let history = [
            try workout(on: try day(-3), sets: 4),   // viernes anterior: no cuenta
            try workout(on: try day(0), sets: 3),    // lunes
            try workout(on: try day(2), sets: 5),    // miércoles
        ]
        let result = insights(history, on: try day(3, hour: 20))
        #expect(result.completedThisWeek == 2)
        #expect(result.plannedPerWeek == 3)
        #expect(result.setsThisWeek == 8)
    }

    @Test("Racha: semanas seguidas cumpliendo; la semana en curso no la rompe si aún no se cumple")
    func streak() throws {
        // Tres semanas anteriores con 3, 3 y 3; una de 1 antes (rompe).
        var history: [WorkoutSessionRecord] = []
        for week in 1...3 {
            for dayOffset in [0, 2, 4] { history.append(try workout(on: try day(-7 * week + dayOffset))) }
        }
        history.append(try workout(on: try day(-28)))
        history.append(try workout(on: try day(0)))   // esta semana: 1 de 3 (aún no cumple)
        #expect(insights(history, on: try day(1)).weekStreak == 3)

        // Al cumplir esta semana suma.
        history.append(try workout(on: try day(2)))
        history.append(try workout(on: try day(4)))
        #expect(insights(history, on: try day(5)).weekStreak == 4)

        // Sin plan, basta 1 por semana.
        #expect(insights([try workout(on: try day(-7)), try workout(on: try day(0))], on: try day(1), planned: nil).weekStreak == 2)
    }

    @Test("Récords del bloque: sólo desde su inicio")
    func recordsInBlock() throws {
        let history = [
            try workout(on: try day(-14), squatWeight: 100),
            try workout(on: try day(-7), squatWeight: 105),  // récord (antes del bloque)
            try workout(on: try day(0), squatWeight: 110),   // récord (en el bloque)
        ]
        let all = insights(history, on: try day(1))
        let block = insights(history, on: try day(1), blockStart: try day(-1))
        #expect(all.recordsInBlock >= block.recordsInBlock)
        #expect(block.recordsInBlock >= 1)
        #expect(insights([try workout(on: try day(0))], on: try day(1), blockStart: try day(1)).recordsInBlock == 0)
    }

    @Test("Series por semana: 8 semanas, las vacías en 0 y en orden cronológico")
    func weeklySets() throws {
        let history = [try workout(on: try day(-14), sets: 4), try workout(on: try day(0), sets: 3)]
        let points = insights(history, on: try day(2)).weeklySets
        #expect(points.count == ProgressInsightsBuilder.chartWeeks)
        #expect(points.map(\.sets) == [0, 0, 0, 0, 0, 4, 0, 3])
        #expect(points.last?.weekStart == (try day(0, hour: 0)), "La última es el lunes de esta semana")
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.weekStart < $1.weekStart })
    }

    @Test("Carga máxima por ejercicio: ≥2 sesiones, una sola unidad, en orden")
    func loadTrends() throws {
        let history = [
            try workout(on: try day(-7), squatWeight: 100, curlInPounds: true),
            try workout(on: try day(0), squatWeight: 110, curlInPounds: true),
            try workout(on: try day(2), squatWeight: 105),
        ]
        let trends = insights(history, on: try day(3)).loadTrends
        let squatTrend = try #require(trends.first { $0.exerciseID == squat })
        #expect(squatTrend.points.map(\.weight) == [100, 110, 105])
        #expect(squatTrend.unit == .kilograms)
        #expect(squatTrend.name == "Sentadilla")
        let curlTrend = try #require(trends.first { $0.exerciseID == curl })
        #expect(curlTrend.unit == .pounds)
        #expect(insights([try workout(on: try day(0))], on: try day(1)).loadTrends.isEmpty, "Con una sola sesión no hay tendencia")
    }

    @Test("Sin historial: todo en 0 y sin datos que graficar")
    func emptyHistory() throws {
        let result = insights([], on: try day(1))
        #expect(result.completedThisWeek == 0)
        #expect(result.setsThisWeek == 0)
        #expect(result.weekStreak == 0)
        #expect(result.recordsInBlock == 0)
        #expect(result.hasWeeklyData == false)
        #expect(result.loadTrends.isEmpty)
    }

    @Test("La semana depende de la zona horaria inyectada")
    func timeZoneMatters() throws {
        // Domingo 25 oct a las 23:30 en Ciudad de México = lunes 26 en UTC.
        let mexico = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mexico
        let sundayNight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 30)))
        let history = [try workout(on: sundayNight)]
        let wednesday = try day(2, hour: 18)
        let inMexico = ProgressOverviewBuilder().overview(
            history: history, templateTitles: [:], exerciseNames: [:], plannedPerWeek: 3,
            date: wednesday, timeZone: mexico
        ).insights
        #expect(inMexico.completedThisWeek == 1, "En México el domingo 25 es de la semana del lunes 19")
        let inUTC = insights(history, on: wednesday)
        #expect(inUTC.completedThisWeek == 0, "En UTC ya es lunes 26: otra semana")
    }
}
