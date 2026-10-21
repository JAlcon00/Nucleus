//
//  TrainingWeekTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  SCRUM-27: días correctos de la semana. Índice lunes = 0 … domingo = 6 desde el
//  `weekday` gregoriano, exactamente N días de entrenamiento con slots distintos, e
//  independencia del `firstWeekday` del sistema y de la zona horaria (día local).
//

import Foundation
import Testing
import PRDomain

@Suite("SCRUM-27 · Semana de entrenamiento")
struct TrainingWeekTests {

    /// Fecha local (mediodía) en `timeZone`, construida por componentes (sin sumar segundos).
    private func localDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier))
    }

    // MARK: - weekday → índice

    @Test("weekday gregoriano 1…7 (dom…sáb) → lunes = 0 … domingo = 6",
          arguments: [(1, 6), (2, 0), (3, 1), (4, 2), (5, 3), (6, 4), (7, 5)])
    func weekdayTable(weekday: Int, expected: Int) throws {
        #expect(try TrainingWeek.dayIndex(gregorianWeekday: weekday) == expected)
    }

    @Test("weekday fuera de 1…7 se rechaza", arguments: [0, 8, -1])
    func invalidWeekday(weekday: Int) {
        #expect(throws: TrainingWeekError.invalidGregorianWeekday(weekday)) {
            try TrainingWeek.dayIndex(gregorianWeekday: weekday)
        }
    }

    @Test("Lunes da 0 y domingo da 6 en una fecha real")
    func mondayAndSunday() throws {
        let utc = try zone("UTC")
        #expect(TrainingWeek.dayIndex(for: try localDate(year: 2026, month: 10, day: 19, timeZone: utc), timeZone: utc) == 0)
        #expect(TrainingWeek.dayIndex(for: try localDate(year: 2026, month: 10, day: 25, timeZone: utc), timeZone: utc) == 6)
    }

    // MARK: - Días de entrenamiento

    @Test("Para N = 2…7, exactamente N de los 7 días proponen entrenar", arguments: Array(2...7))
    func exactTrainingDayCount(days: Int) throws {
        let week = try TrainingWeek(trainingDaysPerWeek: days)
        let trainingDays = (0..<7).filter { week.isTrainingDay(dayIndex: $0) }
        #expect(trainingDays.count == days)
    }

    @Test("Ningún día repite el slot de sesión de otro", arguments: Array(2...7))
    func uniqueSlots(days: Int) throws {
        let week = try TrainingWeek(trainingDaysPerWeek: days)
        let slots = (0..<7).compactMap { week.sessionSlot(dayIndex: $0) }
        #expect(slots == Array(0..<days))
        #expect(Set(slots).count == slots.count)
    }

    @Test("Con 7 días, sábado y domingo tienen slots distintos (antes repetían)")
    func saturdayAndSundayDiffer() throws {
        let week = try TrainingWeek(trainingDaysPerWeek: 7)
        #expect(week.sessionSlot(dayIndex: 5) == 5)
        #expect(week.sessionSlot(dayIndex: 6) == 6)
    }

    @Test("Con 3 días, lunes a miércoles entrenan y jueves a domingo descansan")
    func threeDays() throws {
        let week = try TrainingWeek(trainingDaysPerWeek: 3)
        #expect((0..<7).map { week.isTrainingDay(dayIndex: $0) }
            == [true, true, true, false, false, false, false])
    }

    @Test("Días por semana fuera de 2…7 se rechazan", arguments: [0, 1, 8])
    func invalidTrainingDays(days: Int) {
        #expect(throws: TrainingWeekError.invalidTrainingDays(days)) {
            try TrainingWeek(trainingDaysPerWeek: days)
        }
    }

    @Test("Un índice de día inválido no tiene sesión", arguments: [-1, 7, 100])
    func invalidDayIndex(index: Int) throws {
        #expect(try TrainingWeek(trainingDaysPerWeek: 7).sessionSlot(dayIndex: index) == nil)
    }

    // MARK: - Independencia del sistema

    @Test("El firstWeekday del calendario del usuario no cambia el índice", arguments: [1, 2, 7])
    func independentOfFirstWeekday(firstWeekday: Int) throws {
        let utc = try zone("UTC")
        var userCalendar = Calendar(identifier: .gregorian)
        userCalendar.timeZone = utc
        userCalendar.firstWeekday = firstWeekday
        let monday = try localDate(year: 2026, month: 10, day: 19, timeZone: utc)
        let weekday = userCalendar.component(.weekday, from: monday)
        #expect(try TrainingWeek.dayIndex(gregorianWeekday: weekday) == 0)
        #expect(TrainingWeek.dayIndex(for: monday, timeZone: utc) == 0)
    }

    @Test("El mismo día local da el mismo índice en cualquier zona horaria",
          arguments: ["UTC", "Asia/Tokyo", "America/Mexico_City", "Pacific/Kiritimati", "Pacific/Pago_Pago"])
    func independentOfTimeZone(identifier: String) throws {
        let tz = try zone(identifier)
        for (day, expected) in [(19, 0), (22, 3), (25, 6)] {
            let local = try localDate(year: 2026, month: 10, day: day, timeZone: tz)
            #expect(TrainingWeek.dayIndex(for: local, timeZone: tz) == expected, "\(identifier) día \(day)")
        }
    }

    @Test("Cerca de medianoche cuenta el día local del usuario, no el de UTC")
    func usesLocalDayNearMidnight() throws {
        let mexico = try zone("America/Mexico_City")
        // Lunes 23:30 en Ciudad de México = martes en UTC.
        let lateMonday = try localDate(year: 2026, month: 10, day: 19, hour: 23, minute: 30, timeZone: mexico)
        #expect(TrainingWeek.dayIndex(for: lateMonday, timeZone: mexico) == 0)
        #expect(TrainingWeek.dayIndex(for: lateMonday, timeZone: try zone("UTC")) == 1)
    }
}
