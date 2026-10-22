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

    private func launch(date: String = monday, storeID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.launchArguments = ["-PRFakeSignIn", "-PRUITestReset", "-PRFixedDate", date]
        if let storeID { app.launchArguments += ["-PRUITestStoreID", storeID] }
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

    /// "Cuéntanos de ti" (SCRUM-198): edad en la rueda, sexo y peso; luego Continuar.
    private func completeAboutYou(_ app: XCUIApplication, age: Int = 30, file: StaticString = #filePath, line: UInt = #line) {
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10), "No aparece la edad", file: file, line: line)
        wheel.adjust(toPickerWheelValue: "\(age) años")
        tap(app, "aboutYou.sex.male", file: file, line: line)
        let weight = element(app, "aboutYou.weight")
        weight.tap()
        weight.typeText("72")
        tap(app, "aboutYou.continue", file: file, line: line)
    }

    /// Recorre el cuestionario completo hasta llegar a Hoy (días: los chips elegidos;
    /// por defecto lunes, miércoles y viernes).
    private func completeOnboarding(_ app: XCUIApplication, days: Set<String> = ["monday", "wednesday", "friday"]) {
        completeAboutYou(app)
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        selectDays(app, days)
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
        // SCRUM-197: tras "Armando tu semana" se presenta "Tu semana".
        tap(app, "weekIntro.done")
    }

    /// Abre una pestaña por su nombre visible (en español, SCRUM-195). En iPad la barra de
    /// pestañas va arriba y no es un `tabBar`: se busca el botón por su nombre.
    private func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No aparece la pestaña '\(title)'", file: file, line: line)
        tab.tap()
    }

    private static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// Deja elegidos exactamente estos días (SCRUM-196): toca sólo los chips que no coinciden.
    private func selectDays(_ app: XCUIApplication, _ wanted: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        for day in Self.weekdays {
            let chip = element(app, "onboarding.day.\(day)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "No aparece el día '\(day)'", file: file, line: line)
            if chip.isSelected != wanted.contains(day) { chip.tap() }
        }
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

    // MARK: - Sobre ti (SCRUM-198)

    /// Lo primero tras iniciar sesión es "Cuéntanos de ti"; con menos de 18 años se explica
    /// y no se puede continuar.
    func testAboutYouComesFirstAndNeedsAnAdult() {
        let app = launch()
        XCTAssertTrue(element(app, "aboutYou.title").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "aboutYou.continue").isEnabled, "Sin datos no se continúa")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10))
        wheel.adjust(toPickerWheelValue: "17 años")
        tap(app, "aboutYou.sex.female")
        let weight = element(app, "aboutYou.weight")
        weight.tap()
        weight.typeText("60")
        XCTAssertTrue(element(app, "aboutYou.underage").waitForExistence(timeout: 5), "Debe explicar el mínimo de 18")
        XCTAssertFalse(element(app, "aboutYou.continue").isEnabled, "Con 17 años no se arma plan")
        wheel.adjust(toPickerWheelValue: "18 años")
        XCTAssertTrue(element(app, "aboutYou.continue").isEnabled)
    }

    // MARK: - Cuestionario

    func testOnboardingOptionsAreInSpanish() {
        let app = launch()
        completeAboutYou(app)
        XCTAssertTrue(element(app, "onboarding.option.hypertrophy").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Hipertrofia")
        XCTAssertEqual(element(app, "onboarding.option.generalHealth").label, "Salud general")
        XCTAssertEqual(element(app, "onboarding.option.strength").label, "Fuerza")
        XCTAssertEqual(element(app, "onboarding.option.recomposition").label, "Recomposición")
    }

    func testSelectedOptionIsMarked() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.strength")
        XCTAssertTrue(element(app, "onboarding.option.strength").isSelected, "La opción elegida no se ve marcada")
        XCTAssertFalse(element(app, "onboarding.option.hypertrophy").isSelected)
    }

    func testOneTapOnAnOptionDoesNotSkipSteps() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.hypertrophy")
        XCTAssertTrue(app.staticTexts["Paso 1 de 8"].exists, "Un toque no debe cambiar de paso")
    }

    func testDefaultDaysAndMinutesCanAdvanceWithoutTouchingTheSteppers() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.day.monday").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "onboarding.next").isEnabled, "Con los días por defecto se debe poder avanzar")
    }

    /// SCRUM-196: los días se eligen con chips; con uno solo no se puede avanzar.
    func testChoosingDaysNeedsAtLeastTwo() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        // Por defecto: lunes, martes, jueves y viernes (descanso intercalado).
        for day in Self.weekdays {
            let expected = ["monday", "tuesday", "thursday", "friday"].contains(day)
            XCTAssertEqual(element(app, "onboarding.day.\(day)").isSelected, expected, "Día por defecto '\(day)'")
        }
        selectDays(app, ["sunday"])
        XCTAssertFalse(element(app, "onboarding.next").isEnabled, "Con un solo día no se debe poder avanzar")
        selectDays(app, ["monday", "sunday"])
        XCTAssertTrue(element(app, "onboarding.next").isEnabled)
    }

    func testOnboardingReachesToday() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "Tras el cuestionario debe verse Hoy con sesión (lunes)")
    }

    // MARK: - Recordar perfil y plan (SCRUM-26)

    func testReopeningTheAppGoesStraightToToday() {
        let storeID = "ui-\(UUID().uuidString.prefix(8))"
        let app = launch(storeID: storeID)
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        let firstSummary = element(app, "today.sessionSummary").label

        app.terminate()
        let reopened = launch(storeID: storeID)
        XCTAssertTrue(element(reopened, "today.start").waitForExistence(timeout: 20),
                      "Al reabrir debe verse Hoy directo, sin login ni cuestionario")
        XCTAssertFalse(element(reopened, "onboarding.next").exists, "No debe repetir el cuestionario")
        XCTAssertEqual(element(reopened, "today.sessionSummary").label, firstSummary, "Debe ser el mismo plan")
    }

    /// SCRUM-24: cierre forzado a mitad del entrenamiento ⇒ al reabrir ofrece continuar y
    /// sigue en la serie siguiente (no vuelve a empezar).
    func testForceQuitMidWorkoutOffersToContinue() {
        let storeID = "ui-\(UUID().uuidString.prefix(8))"
        let app = launch(storeID: storeID)
        completeOnboarding(app)
        tap(app, "today.start")
        for _ in 1...3 {
            tap(app, "workout.completeSet")
            let skip = app.buttons["Saltar"].firstMatch
            if skip.waitForExistence(timeout: 2) { skip.tap() }
        }
        let thirdDone = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Serie 4 de'")
        ).firstMatch
        XCTAssertTrue(thirdDone.waitForExistence(timeout: 10), "Tras 3 series debe tocar la 4")

        app.terminate()   // cierre forzado
        let reopened = launch(storeID: storeID)
        XCTAssertTrue(element(reopened, "today.activeBanner").waitForExistence(timeout: 20),
                      "Debe decir 'Tienes un entrenamiento en curso'")
        tap(reopened, "today.resume")
        let resumed = reopened.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Serie 4 de'")
        ).firstMatch
        XCTAssertTrue(resumed.waitForExistence(timeout: 10), "Al continuar debe seguir la serie 4, con las 3 anteriores guardadas")
    }

    func testRedoQuestionnaireFromProfileOpensTheQuestionnaire() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Perfil")
        tap(app, "profile.redo")
        let confirm = app.buttons["Sí, rehacer"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element(app, "onboarding.option.hypertrophy").waitForExistence(timeout: 10),
                      "Rehacer debe abrir el cuestionario")
    }

    // MARK: - Hoy

    /// SCRUM-195: Hoy tiene una sola acción; lo terciario vive en Perfil. Pestañas en español.
    func testTodayHasASingleActionAndSpanishTabs() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        for title in ["Hoy", "Progreso", "Plan", "Perfil"] {
            XCTAssertTrue(app.buttons[title].firstMatch.exists, "Falta la pestaña '\(title)'")
        }
        XCTAssertFalse(app.buttons["Exportar"].exists, "Exportar ya no va en Hoy")
        XCTAssertFalse(app.buttons["Restricciones"].exists, "Restricciones ya no va en Hoy")
        XCTAssertFalse(app.buttons["Rehacer cuestionario"].exists, "Rehacer ya no va en Hoy")
    }

    // MARK: - Tu semana (SCRUM-197)

    /// Lunes, miércoles y viernes (hoy es lunes): la semana alterna sesión y descanso, el
    /// CTA sólo está en hoy y el detalle de otro día no deja empezar.
    func testPlanShowsTheWeekWithRestBetweenSessions() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Plan")
        for day in Self.weekdays {
            XCTAssertTrue(element(app, "week.day.\(day)").waitForExistence(timeout: 10), "Falta el día '\(day)'")
        }
        XCTAssertTrue(element(app, "week.start").exists, "Hoy (lunes) debe tener Empezar")
        tap(app, "week.day.wednesday")
        XCTAssertTrue(element(app, "day.detail").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "day.exercise.0").exists, "El detalle lista los ejercicios")
        XCTAssertFalse(element(app, "day.start").exists, "Sólo se empieza el día de hoy")
    }

    /// La tira de la semana en Hoy abre el detalle del día tocado.
    func testTodayWeekStripOpensTheDay() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, "week.strip.monday").exists)
        tap(app, "week.strip.friday")
        XCTAssertTrue(element(app, "day.detail").waitForExistence(timeout: 10))
    }

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
        completeOnboarding(app, days: ["monday", "wednesday", "friday"])
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
        openTab(app, "Perfil")
        tap(app, "profile.export")
        XCTAssertTrue(app.staticTexts["Aún no tienes entrenamientos"].waitForExistence(timeout: 10))
    }
}
