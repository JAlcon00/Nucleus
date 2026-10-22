//
//  TrainingWeek.swift
//  PRDomain
//
//  Created by PR.
//
//  Semana de entrenamiento (SCRUM-27). ÚNICO lugar del dominio que traduce un día del
//  calendario a "qué toca hoy":
//  - índice de día con lunes = 0 … domingo = 6, a partir del `weekday` gregoriano
//    (que SIEMPRE es domingo = 1 … sábado = 7, sin importar `firstWeekday`);
//  - los primeros N días desde el lunes son de entrenamiento (N = 2…7) y cada uno
//    recibe su propio slot de sesión 0…N-1; el resto es descanso.
//  Puro y determinista: la zona horaria se inyecta; el calendario del sistema
//  (`firstWeekday`, identificador, locale) no influye.
//

import Foundation

public enum TrainingWeekError: Error, Equatable, Sendable {
    case invalidTrainingDays(Int)
    case invalidGregorianWeekday(Int)
}

public struct TrainingWeek: Equatable, Sendable {
    /// Días de una semana.
    public static let daysInWeek = 7
    /// Rango permitido de días de entrenamiento por semana (§4.2).
    public static let allowedTrainingDays: ClosedRange<Int> = 2...7
    /// Rango permitido de minutos por sesión: mínimo 30 (una sesión más corta no alcanza
    /// para calentar y completar series de trabajo útiles) y máximo 240.
    public static let allowedSessionMinutes: ClosedRange<Int> = 30...240

    public let trainingDaysPerWeek: Int

    public init(trainingDaysPerWeek: Int) throws {
        guard Self.allowedTrainingDays.contains(trainingDaysPerWeek) else {
            throw TrainingWeekError.invalidTrainingDays(trainingDaysPerWeek)
        }
        self.trainingDaysPerWeek = trainingDaysPerWeek
    }

    /// Índice lunes = 0 … domingo = 6 desde el `weekday` gregoriano (domingo = 1 … sábado = 7).
    public static func dayIndex(gregorianWeekday weekday: Int) throws -> Int {
        guard (1...daysInWeek).contains(weekday) else {
            throw TrainingWeekError.invalidGregorianWeekday(weekday)
        }
        return (weekday + 5) % daysInWeek
    }

    /// Índice del día local de `date` en `timeZone` (la zona del usuario). Usa un
    /// calendario gregoriano propio: el `firstWeekday` del sistema no cambia el resultado.
    public static func dayIndex(for date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // `component(.weekday)` siempre está en 1...7 para un calendario gregoriano.
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % daysInWeek
    }

    /// ¿Se entrena el día `dayIndex` (0 = lunes)?
    public func isTrainingDay(dayIndex: Int) -> Bool {
        sessionSlot(dayIndex: dayIndex) != nil
    }

    /// Slot de sesión (0…N-1) para un día de entrenamiento; `nil` si es descanso o el
    /// índice no es un día válido. Cada día de entrenamiento tiene un slot distinto.
    public func sessionSlot(dayIndex: Int) -> Int? {
        guard (0..<Self.daysInWeek).contains(dayIndex), dayIndex < trainingDaysPerWeek else {
            return nil
        }
        return dayIndex
    }
}
