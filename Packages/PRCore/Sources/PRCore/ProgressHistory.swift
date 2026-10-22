//
//  ProgressHistory.swift
//  PRCore
//
//  SCRUM-186 (F-06): la pestaña Progreso muestra el registro de entrenamientos desde el
//  primero. Deriva, de forma pura, el historial de sesiones completadas (más reciente
//  primero) con su duración, series, volumen y récords, más un resumen corto (total,
//  esta semana frente a lo planeado y récords). Los números salen de
//  `WorkoutSummaryBuilder`, la misma lógica del resumen al terminar: la pantalla nunca
//  cuenta distinto que el resumen. No decide nada del plan; reloj y zona se inyectan.
//

import Foundation
import PRDomain

/// Una serie hecha, tal como se guardó.
public struct WorkoutLogSet: Equatable, Sendable, Identifiable {
    public let id: SetRecordID
    public let weight: Double
    public let unit: LoadUnit
    public let reps: Int
}

/// Un ejercicio de un entrenamiento, con sus series en el orden en que se hicieron.
public struct WorkoutLogExercise: Equatable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    /// Nombre del catálogo; `nil` si el catálogo ya no lo tiene (nunca se inventa).
    public let name: String?
    public let sets: [WorkoutLogSet]
    public var id: ExerciseID { exerciseID }
}

/// Un entrenamiento completado del historial.
public struct WorkoutLogEntry: Equatable, Sendable, Identifiable {
    public let id: WorkoutID
    public let startedAt: Date
    public let durationSeconds: Int
    /// Clave estable de la sesión ("Push", "Legs B"…); `nil` si la plantilla ya no se conoce.
    public let sessionTitle: String?
    /// Series completadas.
    public let workingSets: Int
    public let exercises: [WorkoutLogExercise]
    /// Volumen (peso × reps) sólo si todas las series usan la misma unidad: nunca se suman
    /// kilos con libras.
    public let volume: Double?
    public let volumeUnit: LoadUnit?
    /// Récords logrados en este entrenamiento (frente a los anteriores).
    public let recordCount: Int
}

/// Lo que muestra Progreso.
public struct ProgressOverview: Equatable, Sendable {
    /// Entrenamientos completados, del más reciente al primero.
    public let entries: [WorkoutLogEntry]
    /// Completados en la semana en curso (lunes a domingo).
    public let completedThisWeek: Int
    /// Sesiones planeadas por semana; `nil` sin plan.
    public let plannedPerWeek: Int?
    /// Récords logrados en todo el historial.
    public let totalRecords: Int

    public var totalWorkouts: Int { entries.count }
}

/// Construye el historial de Progreso (puro).
public struct ProgressOverviewBuilder: Sendable {
    public init() {}

    public func overview(
        history: [WorkoutSessionRecord],
        templateTitles: [SessionTemplate.ID: String],
        exerciseNames: [ExerciseID: String],
        plannedPerWeek: Int?,
        date: Date,
        timeZone: TimeZone
    ) -> ProgressOverview {
        let completed = history
            .filter { $0.lifecycle == .completed }
            .sorted { $0.startedAt == $1.startedAt ? $0.id.rawValue.uuidString < $1.id.rawValue.uuidString : $0.startedAt < $1.startedAt }
        let summaries = WorkoutSummaryBuilder()
        var earlier: [WorkoutSessionRecord] = []
        var entries: [WorkoutLogEntry] = []
        for session in completed {
            let summary = summaries.summarize(
                session,
                now: session.endedAt ?? session.startedAt,
                baselines: PersonalRecordBaselineBuilder.baselines(from: earlier)
            )
            let done = session.sets.filter { $0.lifecycle == .completed }
            let units = Set(done.map(\.unit))
            entries.append(WorkoutLogEntry(
                id: session.id,
                startedAt: session.startedAt,
                durationSeconds: summary.durationSeconds,
                sessionTitle: session.templateID.flatMap { templateTitles[$0] },
                workingSets: summary.workingSets,
                exercises: exercises(of: done, names: exerciseNames),
                volume: units.count == 1 ? summary.volume : nil,
                volumeUnit: units.count == 1 ? units.first : nil,
                recordCount: summary.records.count
            ))
            earlier.append(session)
        }
        return ProgressOverview(
            entries: entries.reversed(),
            completedThisWeek: completedInWeek(of: date, timeZone: timeZone, sessions: completed),
            plannedPerWeek: plannedPerWeek,
            totalRecords: entries.reduce(0) { $0 + $1.recordCount }
        )
    }

    // MARK: - Privado

    /// Ejercicios en el orden de su primera serie, con sus series en orden.
    private func exercises(of sets: [SetRecord], names: [ExerciseID: String]) -> [WorkoutLogExercise] {
        var order: [ExerciseID] = []
        var byExercise: [ExerciseID: [WorkoutLogSet]] = [:]
        for set in sets.sorted(by: { $0.performedAt < $1.performedAt }) {
            if byExercise[set.exerciseID] == nil { order.append(set.exerciseID) }
            byExercise[set.exerciseID, default: []].append(
                WorkoutLogSet(id: set.id, weight: set.weight, unit: set.unit, reps: set.reps)
            )
        }
        return order.map { WorkoutLogExercise(exerciseID: $0, name: names[$0], sets: byExercise[$0] ?? []) }
    }

    /// Entrenamientos completados de lunes a domingo de la semana de `date`.
    private func completedInWeek(of date: Date, timeZone: TimeZone, sessions: [WorkoutSessionRecord]) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayIndex = TrainingWeek.dayIndex(for: date, timeZone: timeZone)
        guard let monday = calendar.date(byAdding: .day, value: -todayIndex, to: calendar.startOfDay(for: date)),
              let nextMonday = calendar.date(byAdding: .day, value: TrainingWeek.daysInWeek, to: monday) else {
            return 0
        }
        return sessions.filter { $0.startedAt >= monday && $0.startedAt < nextMonday }.count
    }
}

/// Qué pasó al leer el historial del disco.
public enum HistoryStatus: Equatable, Sendable {
    /// Todavía no se lee.
    case notLoaded
    /// Leído; `unreadable` registros no se pudieron leer y no se incluyen (se avisa).
    case loaded(unreadable: Int)
    /// La colección completa no se pudo leer. Los entrenamientos siguen en el disco.
    case failed
}

/// Lo que la pestaña Progreso puede mostrar.
public enum ProgressScreen: Equatable, Sendable {
    case loading
    /// Sin entrenamientos completados todavía.
    case empty(unreadable: Int)
    case loaded(ProgressOverview, unreadable: Int)
    /// No se pudo leer el historial; se puede reintentar.
    case failed
}
