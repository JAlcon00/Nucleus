//
//  BlockOverview.swift
//  PRCore
//
//  SCRUM-266 (PR-H004): "Tu bloque" en Plan. Deriva, de forma pura, el objetivo, la fase y
//  en qué semana del bloque va la persona. Las semanas van de lunes a domingo, como "Tu
//  semana" y Progreso: la semana 1 es la del día en que empezó el bloque, aunque haya
//  empezado un jueves. Los días se cuentan con el calendario (nunca sumando 86 400 s), así
//  que el cambio de horario no mueve la semana. Reloj y zona se inyectan. No decide nada
//  del plan: sólo lo presenta.
//

import Foundation
import PRDomain

/// En qué semana del bloque se está.
public enum BlockWeek: Equatable, Sendable {
    /// Semana `week` de `of` (1…`of`).
    case current(week: Int, of: Int)
    /// Ya pasó la última semana planeada: nunca "semana 7 de 6".
    case finished(plannedWeeks: Int)
}

/// Lo que muestra la tarjeta "Tu bloque".
public struct BlockOverview: Equatable, Sendable {
    public let goal: TrainingGoal
    public let phase: BodyCompositionPhase
    public let startDate: Date
    public let week: BlockWeek
}

/// Construye "Tu bloque" (puro).
public struct BlockOverviewBuilder: Sendable {
    public init() {}

    public func overview(block: TrainingBlock, date: Date, timeZone: TimeZone) -> BlockOverview {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents(
            [.day], from: monday(of: block.startDate, calendar: calendar, timeZone: timeZone),
            to: monday(of: date, calendar: calendar, timeZone: timeZone)
        ).day ?? 0
        // Una fecha anterior al inicio (reloj cambiado) cuenta como la semana 1.
        let week = max(0, days) / TrainingWeek.daysInWeek + 1
        let planned = max(1, block.plannedWeeks)
        return BlockOverview(
            goal: block.goal,
            phase: block.phase,
            startDate: block.startDate,
            week: week > planned ? .finished(plannedWeeks: planned) : .current(week: week, of: planned)
        )
    }

    /// Lunes (inicio del día en la zona del usuario) de la semana de `date`.
    private func monday(of date: Date, calendar: Calendar, timeZone: TimeZone) -> Date {
        let index = TrainingWeek.dayIndex(for: date, timeZone: timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -index, to: start) ?? start
    }
}
