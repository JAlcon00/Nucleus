//
//  ProgressInsights.swift
//  PRCore
//
//  SCRUM-213 (FB-6): 4 KPIs y las series de la gráfica de Progreso, calculados de forma
//  pura a partir del historial local (nunca en la vista ni con el LLM). Reloj, zona y
//  semanas se inyectan; las semanas van de lunes a domingo.
//
//  KPIs:
//  1. Adherencia: entrenamientos de esta semana contra los planeados.
//  2. Series efectivas de esta semana (series de trabajo completadas).
//  3. Racha: semanas seguidas cumpliendo lo planeado (1 por semana sin plan). La semana
//     en curso suma si ya se cumplió; si todavía no, no rompe la racha.
//  4. Récords personales desde el inicio del bloque (o de todo el historial sin bloque).
//
//  Gráficas: series por semana de las últimas `weeks` semanas (las vacías en 0) y la
//  carga máxima por sesión de cada ejercicio con al menos 2 sesiones (sólo una unidad:
//  nunca se mezclan kilos con libras).
//

import Foundation
import PRDomain

/// Un punto de la gráfica de series por semana.
public struct WeeklySetsPoint: Equatable, Sendable, Identifiable {
    /// Lunes de la semana (inicio del día en la zona del usuario).
    public let weekStart: Date
    public let sets: Int
    public var id: Date { weekStart }
}

/// Un punto de carga máxima de un ejercicio (la serie más pesada de una sesión).
public struct LoadPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let weight: Double
    public var id: Date { date }
}

/// Evolución de la carga máxima de un ejercicio.
public struct ExerciseLoadTrend: Equatable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String?
    public let unit: LoadUnit
    public let points: [LoadPoint]
    public var id: ExerciseID { exerciseID }
}

/// KPIs y gráficas de Progreso.
public struct ProgressInsights: Equatable, Sendable {
    public let completedThisWeek: Int
    public let plannedPerWeek: Int?
    public let setsThisWeek: Int
    /// Semanas seguidas cumpliendo lo planeado.
    public let weekStreak: Int
    public let recordsInBlock: Int
    public let weeklySets: [WeeklySetsPoint]
    public let loadTrends: [ExerciseLoadTrend]

    /// ¿Hay algo que graficar? (al menos una semana con series).
    public var hasWeeklyData: Bool { weeklySets.contains { $0.sets > 0 } }
}

public struct ProgressInsightsBuilder: Sendable {
    /// Semanas de la gráfica de series.
    public static let chartWeeks = 8
    /// Sesiones mínimas para mostrar la tendencia de carga de un ejercicio.
    public static let minimumTrendSessions = 2

    public init() {}

    public func insights(
        entries: [WorkoutLogEntry],
        plannedPerWeek: Int?,
        blockStart: Date?,
        date: Date,
        timeZone: TimeZone,
        weeks: Int = ProgressInsightsBuilder.chartWeeks
    ) -> ProgressInsights {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let thisMonday = monday(of: date, calendar: calendar, timeZone: timeZone)

        func weekStart(_ entry: WorkoutLogEntry) -> Date {
            monday(of: entry.startedAt, calendar: calendar, timeZone: timeZone)
        }
        let byWeek = Dictionary(grouping: entries, by: weekStart)

        let thisWeek = byWeek[thisMonday] ?? []
        let weeklySets: [WeeklySetsPoint] = (0..<max(1, weeks)).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisMonday) else { return nil }
            return WeeklySetsPoint(weekStart: start, sets: (byWeek[start] ?? []).reduce(0) { $0 + $1.workingSets })
        }

        return ProgressInsights(
            completedThisWeek: thisWeek.count,
            plannedPerWeek: plannedPerWeek,
            setsThisWeek: thisWeek.reduce(0) { $0 + $1.workingSets },
            weekStreak: streak(byWeek: byWeek, from: thisMonday, goal: plannedPerWeek ?? 1, calendar: calendar),
            recordsInBlock: entries
                .filter { entry in blockStart.map { entry.startedAt >= $0 } ?? true }
                .reduce(0) { $0 + $1.recordCount },
            weeklySets: weeklySets,
            loadTrends: loadTrends(entries)
        )
    }

    // MARK: - Privado

    private func monday(of date: Date, calendar: Calendar, timeZone: TimeZone) -> Date {
        let index = TrainingWeek.dayIndex(for: date, timeZone: timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -index, to: start) ?? start
    }

    /// Semanas seguidas con al menos `goal` entrenamientos, contando hacia atrás. La
    /// semana en curso suma si ya cumplió; si no, la racha empieza en la anterior.
    private func streak(byWeek: [Date: [WorkoutLogEntry]], from thisMonday: Date, goal: Int, calendar: Calendar) -> Int {
        let needed = max(1, goal)
        var count = (byWeek[thisMonday]?.count ?? 0) >= needed ? 1 : 0
        var week = thisMonday
        while let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week),
              (byWeek[previous]?.count ?? 0) >= needed {
            count += 1
            week = previous
        }
        return count
    }

    /// Carga máxima por sesión de cada ejercicio, en orden cronológico. Sólo ejercicios
    /// con todas sus series en una unidad y al menos `minimumTrendSessions` sesiones.
    private func loadTrends(_ entries: [WorkoutLogEntry]) -> [ExerciseLoadTrend] {
        var points: [ExerciseID: [LoadPoint]] = [:]
        var units: [ExerciseID: Set<LoadUnit>] = [:]
        var names: [ExerciseID: String] = [:]
        var order: [ExerciseID] = []
        for entry in entries.sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in entry.exercises {
                guard let top = exercise.sets.map(\.weight).max(), top > 0 else { continue }
                if points[exercise.exerciseID] == nil { order.append(exercise.exerciseID) }
                points[exercise.exerciseID, default: []].append(LoadPoint(date: entry.startedAt, weight: top))
                units[exercise.exerciseID, default: []].formUnion(exercise.sets.map(\.unit))
                if let name = exercise.name { names[exercise.exerciseID] = name }
            }
        }
        return order.compactMap { id in
            guard let series = points[id], series.count >= Self.minimumTrendSessions,
                  let unitSet = units[id], unitSet.count == 1, let unit = unitSet.first else { return nil }
            return ExerciseLoadTrend(exerciseID: id, name: names[id], unit: unit, points: series)
        }
    }
}
