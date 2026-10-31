//
//  PRUITestCase.swift
//  PRUITests
//
//  Pruebas de UI de los flujos críticos (promptMaster §32.5), el equivalente a las
//  pruebas end-to-end de Cypress: lanzan la app real en el simulador, la manejan como
//  una persona y comprueban lo que se ve. XCUIAutomation sólo existe en XCTest
//  (AGENTS.md §3.3 lo permite para APIs que lo requieren).
//
//  SCRUM-228: las pruebas van por RECORRIDO, una clase por recorrido (se corre uno solo con
//  `make test-ui-journey RECORRIDO=<Clase>`). Cada paso del recorrido es una actividad con
//  nombre (`step`), así el resultado dice en qué paso falló. Sólo los recorridos del
//  cuestionario lo contestan a mano; los demás arrancan con el perfil ya contestado
//  (`launchWithPlan`, `-PRUITestProfile intermedio-lmv`), que da el mismo plan que
//  `completeOnboarding()` (lo prueba `UITestProfileSeederTests` en `make ci`).
//
//  Cada arranque empieza de cero: `-PRUITestReset` usa un directorio de datos temporal y
//  `-PRFixedDate` fija "hoy" (2026-10-19 es lunes). Con `storeID` el directorio se
//  reutiliza al relanzar (los datos siguen; la pantalla vuelve a empezar en Hoy). Estos
//  modos sólo existen en Debug.
//

import XCTest

extension XCUIElement {
    /// "Aparece en `timeout` segundos", sin pagar la primera evaluación de `waitForExistence`,
    /// que XCTest hace a ~1 s aunque el elemento ya esté (SCRUM-228: en el smoke eran 114
    /// esperas y 118 s de 248). Mira ahora y, si no está, espera como siempre. Sólo para
    /// comprobar que algo aparece; "no aparece en N s" sigue con `waitForExistence`.
    func appears(within timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }
}

@MainActor
class PRUITestCase: XCTestCase {

    static let bundleID = "creadevs.PR"
    // `nonisolated`: son valores por defecto de `launch`, que se evalúan fuera del main actor.
    nonisolated static let monday = "2026-10-19"
    nonisolated static let sunday = "2026-10-25"
    /// El perfil que contesta `completeOnboarding()` con sus valores por defecto
    /// (`UITestSeededProfile.intermediateMondayWednesdayFriday`).
    static let seededProfile = "intermedio-lmv"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Arranque

    func launch(
        date: String = monday, storeID: String? = nil, profile: String? = nil, extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.launchArguments = ["-PRFakeSignIn", "-PRUITestReset", "-PRFixedDate", date] + extraArguments
        if let storeID { app.launchArguments += ["-PRUITestStoreID", storeID] }
        if let profile { app.launchArguments += ["-PRUITestProfile", profile] }
        app.launch()
        return app
    }

    /// Arranca con el cuestionario ya contestado (lo mismo que `completeOnboarding()` con sus
    /// valores por defecto). El plan lo arma la app como al terminar el cuestionario.
    func launchWithPlan(date: String = monday, storeID: String? = nil) -> XCUIApplication {
        launch(date: date, storeID: storeID, profile: Self.seededProfile)
    }

    /// Un directorio de datos propio para relanzar la app y que recuerde lo hecho.
    func newStoreID() -> String {
        "ui-\(UUID().uuidString.prefix(8))"
    }

    /// Un paso del recorrido, con nombre en el resultado de la prueba.
    func step(_ name: String, _ body: () throws -> Void) rethrows {
        try XCTContext.runActivity(named: name) { _ in try body() }
    }

    // MARK: - Elementos

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Desplaza hasta que aparezca `id` (las filas de una lista fuera de pantalla no existen
    /// para la accesibilidad hasta que se ven). Hacia abajo por defecto; `upwards` vuelve al
    /// principio de la lista. `within` desliza sobre esa lista y no en el centro de la
    /// pantalla (p. ej. los ejercicios de Hoy, que se desplazan aparte). En iPhone hace falta
    /// más seguido que en iPad (SCRUM-217).
    func scrollTo(
        _ app: XCUIApplication, _ id: String, within containerID: String? = nil, upwards: Bool = false, maxSwipes: Int = 6
    ) -> XCUIElement {
        let target = element(app, id)
        let surface: XCUIElement = containerID.map { element(app, $0) } ?? app
        var swipes = 0
        while !target.exists && swipes < maxSwipes {
            if upwards { surface.swipeDown() } else { surface.swipeUp() }
            swipes += 1
        }
        return target
    }

    func tap(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(app, id)
        XCTAssertTrue(target.appears(within: 10), "No aparece '\(id)'", file: file, line: line)
        target.tap()
    }

    /// Abre una pestaña por su nombre visible (en español, SCRUM-195). En iPad la barra de
    /// pestañas va arriba y no es un `tabBar`: se busca el botón por su nombre.
    func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.appears(within: 10), "No aparece la pestaña '\(title)'", file: file, line: line)
        tab.tap()
    }

    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// Deja elegidos exactamente estos días (SCRUM-196): toca sólo los chips que no coinciden.
    func selectDays(_ app: XCUIApplication, _ wanted: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        for day in Self.weekdays {
            let chip = element(app, "onboarding.day.\(day)")
            XCTAssertTrue(chip.appears(within: 10), "No aparece el día '\(day)'", file: file, line: line)
            if chip.isSelected != wanted.contains(day) { chip.tap() }
        }
    }

    /// Lleva un Stepper de `from` a `target`. Si ya está en el objetivo no lo toca (la app
    /// debe registrar el valor por defecto igualmente: lo comprueba otra prueba).
    func setStepper(_ app: XCUIApplication, id: String, to target: Int, from current: Int, step: Int = 1) {
        let stepper = app.steppers[id]
        XCTAssertTrue(stepper.appears(within: 10), "No aparece el selector '\(id)'")
        let presses = abs(target - current) / step
        let button = target > current ? stepper.buttons.element(boundBy: 1) : stepper.buttons.element(boundBy: 0)
        for _ in 0..<presses { button.tap() }
    }

    // MARK: - Cuestionario a mano (sólo los recorridos del cuestionario)

    /// "Cuéntanos de ti" (SCRUM-198): edad en la rueda, sexo y peso; luego Continuar.
    func completeAboutYou(_ app: XCUIApplication, age: Int = 30, file: StaticString = #filePath, line: UInt = #line) {
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.appears(within: 10), "No aparece la edad", file: file, line: line)
        wheel.adjust(toPickerWheelValue: "\(age) años")
        tap(app, "aboutYou.sex.male", file: file, line: line)
        let weight = element(app, "aboutYou.weight")
        weight.tap()
        weight.typeText("72")
        tap(app, "aboutYou.continue", file: file, line: line)
    }

    /// Recorre el cuestionario sin cerrar la presentación final (para observar lo que pasa
    /// mientras el plan se genera). Días: los chips elegidos; por defecto L, Mi y V.
    /// Al terminar responde el consentimiento de la IA (SCRUM-202): por defecto "Ahora no".
    func answerQuestionnaire(
        _ app: XCUIApplication,
        days: Set<String> = ["monday", "wednesday", "friday"],
        aiConsent: String = "decline",
        zones: [String] = [],
        note: String? = nil,
        experience: String = "intermediate",
        priority: [String] = []
    ) {
        completeAboutYou(app)
        // SCRUM-210: la experiencia va primero y decide los pasos.
        tap(app, "onboarding.option.\(experience)"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        selectDays(app, days)
        tap(app, "onboarding.next")
        answerMinutesAndTheRest(app, experience: experience, aiConsent: aiConsent, zones: zones, note: note, priority: priority)
    }

    /// Del paso de minutos al consentimiento de la IA (el final de `answerQuestionnaire`).
    func answerMinutesAndTheRest(
        _ app: XCUIApplication,
        experience: String = "intermediate",
        aiConsent: String = "decline",
        zones: [String] = [],
        note: String? = nil,
        priority: [String] = []
    ) {
        // Rodeo del bug "el valor por defecto no se registra": sube y baja un paso. El paso
        // de los días por defecto de `IntermediateQuestionnaireJourney` exige que esto no
        // haga falta.
        let minutes = app.steppers["onboarding.minutesStepper"]
        XCTAssertTrue(minutes.appears(within: 10))
        minutes.buttons.element(boundBy: 1).tap()
        minutes.buttons.element(boundBy: 0).tap()
        tap(app, "onboarding.next")
        let guided = ["novice", "beginner"].contains(experience)
        // Quien empieza no ve "Variedad" (queda estable).
        if !guided { tap(app, "onboarding.option.balanced"); tap(app, "onboarding.next") }
        // Músculos prioritarios (opcional, hasta 2): todos los niveles desde SCRUM-215.
        XCTAssertTrue(element(app, "onboarding.priority.glutes").appears(within: 10), "Paso de prioritarios")
        for muscle in priority { tap(app, "onboarding.priority.\(muscle)") }
        tap(app, "onboarding.next")
        // SCRUM-209: sin paso "Gimnasio"; restricciones opcionales (zonas + nota).
        XCTAssertTrue(element(app, "onboarding.zone.shoulder").appears(within: 10), "Paso de restricciones con zonas")
        for zone in zones { tap(app, "onboarding.zone.\(zone)") }
        if let note {
            let field = element(app, "onboarding.restrictionNote")
            field.tap()
            field.typeText(note)
            tap(app, "onboarding.restrictionNote.done")
        }
        tap(app, "onboarding.next")
        tap(app, "aiConsent.\(aiConsent)")
    }

    /// Desde el paso de experiencia (con "Sobre ti" ya contestado) hasta Hoy.
    func completeOnboardingFromExperience(_ app: XCUIApplication, experience: String) {
        tap(app, "onboarding.option.\(experience)"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        selectDays(app, ["monday", "wednesday", "friday"])
        tap(app, "onboarding.next")
        tap(app, "onboarding.next")
        // SCRUM-215: después de los minutos, prioritarios en palabras simples; se salta con un toque.
        XCTAssertTrue(app.staticTexts["¿Quieres enfocarte en algo?"].appears(within: 10), "Principiante: prioritarios en palabras simples")
        XCTAssertTrue(element(app, "onboarding.priority.glutes").exists)
        XCTAssertTrue(element(app, "onboarding.next").isEnabled, "Se puede saltar sin elegir")
        tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.zone.shoulder").appears(within: 10), "Principiante: de prioritarios a restricciones")
        tap(app, "onboarding.next")
        tap(app, "aiConsent.decline")
        tap(app, "weekIntro.done")
    }

    /// Recorre el cuestionario completo hasta llegar a Hoy (cierra "Tu semana").
    func completeOnboarding(
        _ app: XCUIApplication,
        days: Set<String> = ["monday", "wednesday", "friday"],
        aiConsent: String = "decline",
        zones: [String] = [],
        note: String? = nil,
        experience: String = "intermediate",
        priority: [String] = []
    ) {
        answerQuestionnaire(
            app, days: days, aiConsent: aiConsent, zones: zones, note: note,
            experience: experience, priority: priority
        )
        // SCRUM-197: tras "Armando tu semana" se presenta "Tu semana".
        tap(app, "weekIntro.done")
    }

    // MARK: - Entrenar

    /// Tras empezar: completa una serie, "Terminar" y "Completar sesión" hasta el resumen.
    func finishWorkoutAfterOneSet(_ app: XCUIApplication) {
        tap(app, "workout.completeSet")
        let finish = app.buttons["Terminar"].firstMatch
        XCTAssertTrue(finish.appears(within: 10))
        finish.tap()
        let complete = app.buttons["Completar sesión"].firstMatch
        XCTAssertTrue(complete.appears(within: 5))
        complete.tap()
    }
}
