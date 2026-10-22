//
//  WeekOverview.swift
//  PRCore
//
//  SCRUM-197 (U4): "Tu semana". Deriva, de forma pura y determinista, qué toca cada día de
//  la semana en curso (lunes a domingo) a partir del plan guardado, los días elegidos
//  (`TrainingWeek`) y el historial: sesión con sus músculos principales, ejercicios,
//  series y minutos, y el estado del día (descanso, pendiente, hecho o no realizado).
//  También "última vez" por ejercicio (M1). Sin reloj ni zona propios: se inyectan.
//  No decide nada del plan: sólo lo presenta.
//

import Foundation
import PRDomain

/// Estado de un día en "Tu semana".
public enum WeekDayStatus: Equatable, Sendable {
    /// Sin sesión ese día.
    case rest
    /// Día de entrenamiento de hoy o por venir, sin hacer todavía.
    case pending
    /// Hubo un entrenamiento completado ese día.
    case completed
    /// Día de entrenamiento que ya pasó sin hacerse. No es un error: sólo se informa.
    case missed
}

/// La mejor serie de la última vez que se hizo un ejercicio (M1: "última vez: 60 kg × 10").
public struct LastPerformance: Equatable, Sendable {
    public let weight: Double
    public let unit: LoadUnit
    public let reps: Int
    public let performedAt: Date

    public init(weight: Double, unit: LoadUnit, reps: Int, performedAt: Date) {
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.performedAt = performedAt
    }
}

/// Una sesión de la semana tal como se lista en "Tu semana".
public struct WeekSession: Equatable, Sendable {
    public let templateID: SessionTemplate.ID
    /// Clave estable del planificador ("Push", "Legs"…): la vista la traduce.
    public let title: String
    /// Músculos principales, de más a menos series (máximo `WeekOverviewBuilder.maxMuscles`).
    public let muscles: [MuscleGroup]
    /// Ejercicios en orden, con series de trabajo y rango de repeticiones.
    public let exercises: [TodayExerciseLine]
    /// Series de trabajo (sin calentamiento).
    public let workSetCount: Int
    public let estimatedMinutes: Int?
    /// "¿Por qué este orden?" de esta sesión.
    public let order: [TodayOrderLine]
    public let orderReorderedByFatigue: Bool
}

/// Un día de la semana en curso.
public struct WeekDayEntry: Equatable, Sendable, Identifiable {
    public let day: WeekDay
    public let isToday: Bool
    public let status: WeekDayStatus
    /// Sesión planeada ese día; `nil` en descanso.
    public let session: WeekSession?
    public var id: WeekDay { day }
}

/// La semana en curso, de lunes a domingo.
public struct WeekOverview: Equatable, Sendable {
    public let days: [WeekDayEntry]

    /// El día de hoy.
    public var today: WeekDayEntry? { days.first(where: \.isToday) }
}

/// Construye "Tu semana" (puro: reloj, zona e historial se inyectan).
public struct WeekOverviewBuilder: Sendable {
    /// Músculos que se muestran como chips por sesión.
    public static let maxMuscles = 3

    public init() {}

    /// Semana en curso para el perfil y su bloque. `nil` si la semana del perfil no es
    /// válida (nunca se inventa un reparto).
    public func overview(
        profile: OnboardingProfile,
        block: TrainingBlock,
        explanation: BlockExplanation,
        catalog: ExerciseCatalog,
        history: [WorkoutSessionRecord],
        date: Date,
        timeZone: TimeZone
    ) -> WeekOverview? {
        guard let week = try? profile.trainingWeek() else { return nil }
        let todayIndex = TrainingWeek.dayIndex(for: date, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: date)
        let completedDays = completedDayIndexes(
            history: history, startOfToday: startOfToday, todayIndex: todayIndex, calendar: calendar
        )
        let lineBuilder = TodayPlanBuilder()
        let days = WeekDay.allCases.map { day -> WeekDayEntry in
            let index = day.mondayBasedIndex
            let template = week.sessionSlot(dayIndex: index).flatMap { slot in
                block.sessions.isEmpty ? nil : block.sessions[slot % block.sessions.count]
            }
            let session = template.map {
                weekSession($0, profile: profile, explanation: explanation, catalog: catalog, lineBuilder: lineBuilder)
            }
            let status: WeekDayStatus
            if completedDays.contains(index) {
                status = .completed
            } else if session == nil {
                status = .rest
            } else if index < todayIndex {
                status = .missed
            } else {
                status = .pending
            }
            return WeekDayEntry(day: day, isToday: index == todayIndex, status: status, session: session)
        }
        return WeekOverview(days: days)
    }

    // MARK: - Privado

    private func weekSession(
        _ template: SessionTemplate,
        profile: OnboardingProfile,
        explanation: BlockExplanation,
        catalog: ExerciseCatalog,
        lineBuilder: TodayPlanBuilder
    ) -> WeekSession {
        let orderExplanation = explanation.sessionOrder.first { $0.sessionTitle == template.title }
        return WeekSession(
            templateID: template.id,
            title: template.title,
            muscles: mainMuscles(of: template, catalog: catalog),
            exercises: lineBuilder.exerciseLines(for: template, catalog: catalog, profile: profile),
            workSetCount: template.plannedSets.filter { !$0.prescription.isWarmup }.count,
            estimatedMinutes: profile.usualSessionMinutes,
            order: lineBuilder.orderLines(for: orderExplanation, catalog: catalog),
            orderReorderedByFatigue: orderExplanation?.reorderedByFatigue ?? false
        )
    }

    /// Músculos principales: cada serie de trabajo suma a los músculos primarios de su
    /// ejercicio; se ordenan por series (empate: el que aparece antes).
    private func mainMuscles(of template: SessionTemplate, catalog: ExerciseCatalog) -> [MuscleGroup] {
        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sets: [MuscleGroup: Int] = [:]
        var firstSeen: [MuscleGroup] = []
        for planned in template.plannedSets where !planned.prescription.isWarmup {
            for contribution in exercises[planned.exerciseID]?.primaryMuscles ?? [] {
                let muscle = contribution.muscleGroupID
                if sets[muscle] == nil { firstSeen.append(muscle) }
                sets[muscle, default: 0] += 1
            }
        }
        let ranked = firstSeen.enumerated().sorted { lhs, rhs in
            let left = sets[lhs.element] ?? 0
            let right = sets[rhs.element] ?? 0
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        return ranked.prefix(Self.maxMuscles).map(\.element)
    }

    /// Días de esta semana (lunes = 0) con un entrenamiento completado.
    private func completedDayIndexes(
        history: [WorkoutSessionRecord],
        startOfToday: Date,
        todayIndex: Int,
        calendar: Calendar
    ) -> Set<Int> {
        var result: Set<Int> = []
        for index in 0..<TrainingWeek.daysInWeek {
            guard let start = calendar.date(byAdding: .day, value: index - todayIndex, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let done = history.contains { session in
                session.lifecycle == .completed && session.startedAt >= start && session.startedAt < end
            }
            if done { result.insert(index) }
        }
        return result
    }
}

/// "Última vez" por ejercicio (M1): de la sesión completada más reciente que lo incluye, su
/// mejor serie completada (más peso; a igual peso, más repeticiones).
public enum LastPerformanceIndex {
    public static func build(from history: [WorkoutSessionRecord]) -> [ExerciseID: LastPerformance] {
        var result: [ExerciseID: LastPerformance] = [:]
        let completed = history
            .filter { $0.lifecycle == .completed }
            .sorted { $0.startedAt > $1.startedAt }
        for session in completed {
            var best: [ExerciseID: SetRecord] = [:]
            for set in session.sets where set.lifecycle == .completed && result[set.exerciseID] == nil {
                if let current = best[set.exerciseID] {
                    if set.weight > current.weight || (set.weight == current.weight && set.reps > current.reps) {
                        best[set.exerciseID] = set
                    }
                } else {
                    best[set.exerciseID] = set
                }
            }
            for (exerciseID, set) in best {
                result[exerciseID] = LastPerformance(
                    weight: set.weight, unit: set.unit, reps: set.reps, performedAt: set.performedAt
                )
            }
        }
        return result
    }
}
