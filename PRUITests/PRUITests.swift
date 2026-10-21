//
//  PRUITests.swift
//  PRUITests
//
//  Pruebas de UI de los flujos críticos (promptMaster §32.5), el equivalente a las
//  pruebas end-to-end de Cypress: lanzan la app real en el simulador, la manejan como
//  una persona y comprueban lo que se ve. XCUIAutomation sólo existe en XCTest
//  (AGENTS.md §3.3 lo permite para APIs que lo requieren).
//
//  Cada prueba arranca de cero: `-PRUITestReset` usa un directorio de datos temporal
//  y `-PRFixedDate` fija "hoy" (2026-10-19 es lunes). Estos modos sólo existen en Debug.
//

import XCTest

@MainActor
final class PRUITests: XCTestCase {

    private static let bundleID = "creadevs.PR"
    private static let monday = "2026-10-19"
    private static let sunday = "2026-10-25"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(date: String = monday) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.launchArguments = ["-PRFakeSignIn", "-PRUITestReset", "-PRFixedDate", date]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(app, id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "No aparece '\(id)'", file: file, line: line)
        target.tap()
    }

    /// Recorre el cuestionario completo hasta llegar a Hoy (días: lo que pida el stepper).
    private func completeOnboarding(_ app: XCUIApplication, days: Int = 3) {
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        setStepper(app, id: "onboarding.daysStepper", to: days, from: 4)
        tap(app, "onboarding.next")
        // Rodeo del bug "el valor por defecto no se registra": sube y baja un paso. La
        // prueba `testDefaultDaysAndMinutes...` exige que esto no haga falta.
        let minutes = app.steppers["onboarding.minutesStepper"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 10))
        minutes.buttons.element(boundBy: 1).tap()
        minutes.buttons.element(boundBy: 0).tap()
        tap(app, "onboarding.next")
        tap(app, "onboarding.skipGym"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.balanced"); tap(app, "onboarding.next")
        tap(app, "onboarding.skipRestrictions"); tap(app, "onboarding.next")
    }

    /// Lleva un Stepper de `from` a `target`. Si ya está en el objetivo no lo toca (la app
    /// debe registrar el valor por defecto igualmente: lo comprueba otra prueba).
    private func setStepper(_ app: XCUIApplication, id: String, to target: Int, from current: Int, step: Int = 1) {
        let stepper = app.steppers[id]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "No aparece el selector '\(id)'")
        let presses = abs(target - current) / step
        let button = target > current ? stepper.buttons.element(boundBy: 1) : stepper.buttons.element(boundBy: 0)
        for _ in 0..<presses { button.tap() }
    }

    // MARK: - Cuestionario

    func testOnboardingOptionsAreInSpanish() {
        let app = launch()
        XCTAssertTrue(element(app, "onboarding.option.hypertrophy").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Hipertrofia")
        XCTAssertEqual(element(app, "onboarding.option.generalHealth").label, "Salud general")
        XCTAssertEqual(element(app, "onboarding.option.strength").label, "Fuerza")
        XCTAssertEqual(element(app, "onboarding.option.recomposition").label, "Recomposición")
    }

    func testSelectedOptionIsMarked() {
        let app = launch()
        tap(app, "onboarding.option.strength")
        XCTAssertTrue(element(app, "onboarding.option.strength").isSelected, "La opción elegida no se ve marcada")
        XCTAssertFalse(element(app, "onboarding.option.hypertrophy").isSelected)
    }

    func testOneTapOnAnOptionDoesNotSkipSteps() {
        let app = launch()
        tap(app, "onboarding.option.hypertrophy")
        XCTAssertTrue(app.staticTexts["Paso 1 de 8"].exists, "Un toque no debe cambiar de paso")
    }

    func testDefaultDaysAndMinutesCanAdvanceWithoutTouchingTheSteppers() {
        let app = launch()
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        XCTAssertTrue(app.steppers["onboarding.daysStepper"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "onboarding.next").isEnabled, "Con los días por defecto se debe poder avanzar")
    }

    func testOnboardingReachesToday() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "Tras el cuestionario debe verse Hoy con sesión (lunes)")
    }

    // MARK: - Hoy

    func testTodayListsTheExercisesOfTheSession() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        let exercises = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'today.exercise.'")
        )
        XCTAssertGreaterThan(exercises.count, 0, "Hoy debe listar los ejercicios de la sesión")
    }

    func testTodaySessionHasRealisticVolume() throws {
        let app = launch()
        completeOnboarding(app)
        let summary = element(app, "today.sessionSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let digits = summary.label.prefix { $0.isNumber }
        let sets = try XCTUnwrap(Int(digits), "No se pudo leer el número de series de '\(summary.label)'")
        XCTAssertLessThanOrEqual(sets, 30, "Una sesión de 60 min no puede tener \(sets) series")
    }

    func testSundayIsRestDayWithoutStartButton() {
        let app = launch(date: Self.sunday)
        completeOnboarding(app, days: 3)
        XCTAssertTrue(element(app, "today.restDay").waitForExistence(timeout: 15), "El domingo debe ser día de descanso")
        XCTAssertFalse(element(app, "today.start").exists)
    }

    // MARK: - Entrenar

    func testStartShowsTheFirstSetNotABlackScreen() {
        let app = launch()
        completeOnboarding(app)
        tap(app, "today.start")
        let shown = element(app, "workout.completeSet").waitForExistence(timeout: 10)
        if !shown {
            // Evidencia del estado de la pantalla cuando falla (queda en el reporte).
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "jerarquia-tras-empezar"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("HIERARCHY-AFTER-START:\n\(app.debugDescription)")
        }
        XCTAssertTrue(shown, "Al tocar Empezar debe verse la primera serie (pantalla negra)")
    }

    // MARK: - Exportar

    func testExportShowsEmptyStateBeforeAnyWorkout() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        app.buttons["Exportar"].tap()
        XCTAssertTrue(app.staticTexts["Aún no tienes entrenamientos"].waitForExistence(timeout: 10))
    }
}
