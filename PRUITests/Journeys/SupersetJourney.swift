//
//  SupersetJourney.swift
//  PRUITests
//
//  Recorrido 9 · Superset (SCRUM-224). Con 30 min por sesión y bíceps y tríceps como
//  prioritarios, lo protegido no cabe y el motor junta pares compatibles (perfil sembrado
//  `intermedio-lmv-brazos-30`; `UITestProfileSeederTests` comprueba que el lunes trae
//  supersets). Hoy dice qué va en superset y por qué, "Por qué tu plan es así" también, y en
//  el entrenamiento se alterna A1 → A2 con un toque y el descanso va después de la ronda.
//

import XCTest

final class SupersetJourney: PRUITestCase {

    private static let armsProfile = "intermedio-lmv-brazos-30"

    /// La serie en pantalla va en superset de ese lado (el encabezado lo dice).
    private func supersetHeader(_ app: XCUIApplication, _ side: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "SUPERSET · \(side)")).firstMatch
    }

    func testSupersetFromTodayThroughTheRound() {
        let app = launch(profile: Self.armsProfile)

        step("Hoy dice qué va en superset y por qué") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            let note = scrollTo(app, "today.superset", within: "today.content")
            XCTAssertTrue(note.appears(within: 5), "Hoy debe decir qué va en superset")
            XCTAssertTrue(note.label.contains("superset") && note.label.contains("quepa en tu tiempo"), "Nota: '\(note.label)'")
        }

        step("\"Por qué tu plan es así\" explica el superset") {
            openTab(app, "Plan")
            let rationale = scrollTo(app, "plan.rationale", upwards: true)
            XCTAssertTrue(rationale.appears(within: 15), "Debe verse \"Por qué tu plan es así\"")
            XCTAssertTrue(rationale.label.contains("superset"), "Explica el superset: \(rationale.label)")
        }

        step("En el entrenamiento se alterna A1 → A2 sin descanso y se descansa después de la ronda") {
            openTab(app, "Hoy")
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))
            // Hasta la primera serie en superset (antes puede haber un calentamiento o un ejercicio solo).
            for _ in 1...12 where !supersetHeader(app, "A1").exists {
                tap(app, "workout.completeSet")
                let skip = app.buttons["Saltar"].firstMatch
                if skip.appears(within: 2) { skip.tap() }
            }
            XCTAssertTrue(supersetHeader(app, "A1").appears(within: 5), "Debe llegar al primero del par (A1)")

            tap(app, "workout.completeSet")
            XCTAssertTrue(supersetHeader(app, "A2").appears(within: 5), "Tras A1 sigue la pareja (A2)")
            XCTAssertFalse(app.buttons["Saltar"].exists, "A mitad de la ronda no hay descanso")

            tap(app, "workout.completeSet")
            XCTAssertTrue(app.buttons["Saltar"].firstMatch.appears(within: 5), "Después de la ronda, descanso")
            app.buttons["Saltar"].firstMatch.tap()
            XCTAssertTrue(supersetHeader(app, "A1").appears(within: 5), "La siguiente ronda empieza otra vez por A1")
        }
    }
}
