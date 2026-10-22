//
//  TrainingWeek.swift
//  PRDomain
//
//  Created by PR.
//
//  Semana de entrenamiento (SCRUM-27, SCRUM-196). ÚNICO lugar del dominio que traduce un
//  día del calendario a "qué toca hoy":
//  - índice de día con lunes = 0 … domingo = 6, a partir del `weekday` gregoriano
//    (que SIEMPRE es domingo = 1 … sábado = 7, sin importar `firstWeekday`);
//  - la persona elige qué días entrena (2…7, SCRUM-196) y cada día elegido recibe, en
//    orden de lunes a domingo, su propio slot de sesión 0…N-1; el resto es descanso;
//  - una semana de "N días" sin días elegidos (perfiles anteriores a SCRUM-196) son los
//    primeros N días desde el lunes: el comportamiento de antes, para que ningún plan
//    guardado cambie en silencio.
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

    /// Días en que se entrena (2…7).
    public let trainingDays: Set<WeekDay>

    /// Número de días de entrenamiento.
    public var trainingDaysPerWeek: Int { trainingDays.count }

    /// Días de entrenamiento de lunes a domingo: el slot de cada uno es su posición aquí.
    public var orderedDays: [WeekDay] {
        WeekDay.allCases.filter { trainingDays.contains($0) }
    }

    /// Semana con los días elegidos. Falla con menos de 2 días (nunca se inventa otro).
    public init(trainingDays: Set<WeekDay>) throws {
        guard Self.allowedTrainingDays.contains(trainingDays.count) else {
            throw TrainingWeekError.invalidTrainingDays(trainingDays.count)
        }
        self.trainingDays = trainingDays
    }

    /// Semana de "N días" (perfiles anteriores a SCRUM-196): los primeros N desde el lunes.
    public init(trainingDaysPerWeek: Int) throws {
        guard let days = Self.firstDays(trainingDaysPerWeek) else {
            throw TrainingWeekError.invalidTrainingDays(trainingDaysPerWeek)
        }
        self.trainingDays = days
    }

    /// Los primeros `count` días desde el lunes; `nil` fuera de 2…7.
    public static func firstDays(_ count: Int) -> Set<WeekDay>? {
        guard allowedTrainingDays.contains(count) else { return nil }
        return Set(WeekDay.allCases.prefix(count))
    }

    /// Reparto por defecto al elegir cuántos días entrenar: descanso intercalado para
    /// recuperar (docs/ux/auditoria-ui-2026-10-22.md §4.3). Falla fuera de 2…7.
    public static func spacedDays(count: Int) throws -> Set<WeekDay> {
        switch count {
        case 2: return [.monday, .thursday]
        case 3: return [.monday, .wednesday, .friday]
        case 4: return [.monday, .tuesday, .thursday, .friday]
        case 5: return [.monday, .tuesday, .wednesday, .friday, .saturday]
        case 6: return [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        case 7: return Set(WeekDay.allCases)
        default: throw TrainingWeekError.invalidTrainingDays(count)
        }
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
    /// índice no es un día válido. Los slots siguen el orden de los días elegidos.
    public func sessionSlot(dayIndex: Int) -> Int? {
        guard let day = WeekDay(mondayBasedIndex: dayIndex), trainingDays.contains(day) else {
            return nil
        }
        return orderedDays.firstIndex(of: day)
    }
}

extension WeekDay {
    /// Índice lunes = 0 … domingo = 6 (el mismo que `TrainingWeek.dayIndex`).
    public var mondayBasedIndex: Int {
        switch self {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }

    /// Día para un índice lunes = 0 … domingo = 6; `nil` fuera de rango.
    public init?(mondayBasedIndex index: Int) {
        guard WeekDay.allCases.indices.contains(index) else { return nil }
        self = WeekDay.allCases[index]
    }
}
