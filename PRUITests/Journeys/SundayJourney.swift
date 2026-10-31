//
//  SundayJourney.swift
//  PRUITests
//
//  Recorrido 8 · Domingo (SCRUM-228). Con el perfil ya contestado (lunes, miércoles y
//  viernes) y "hoy" en domingo, Hoy es día de descanso y no ofrece empezar.
//

import XCTest

final class SundayJourney: PRUITestCase {

    func testSundayIsRestDayWithoutStartButton() {
        step("El domingo es día de descanso, sin Empezar (testSundayIsRestDayWithoutStartButton)") {
            let app = launchWithPlan(date: Self.sunday)
            XCTAssertTrue(element(app, "today.restDay").appears(within: 15), "El domingo debe ser día de descanso")
            XCTAssertFalse(element(app, "today.start").exists)
        }
    }
}
