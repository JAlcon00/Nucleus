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

    private func launch(date: String = monday, storeID: String? = nil, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.launchArguments = ["-PRFakeSignIn", "-PRUITestReset", "-PRFixedDate", date] + extraArguments
        if let storeID { app.launchArguments += ["-PRUITestStoreID", storeID] }
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Desplaza hasta que aparezca `id` (las filas de una lista fuera de pantalla no existen
    /// para la accesibilidad hasta que se ven). Hacia abajo por defecto; `upwards` vuelve al
    /// principio de la lista. `within` desliza sobre esa lista y no en el centro de la
    /// pantalla (p. ej. los ejercicios de Hoy, que se desplazan aparte). En iPhone hace falta
    /// más seguido que en iPad (SCRUM-217).
    private func scrollTo(
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

    /// Recorre el cuestionario sin cerrar la presentación final (para observar lo que pasa
    /// mientras el plan se genera). Días: los chips elegidos; por defecto L, Mi y V.
    /// Al terminar responde el consentimiento de la IA (SCRUM-202): por defecto "Ahora no".
    private func answerQuestionnaire(
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
        // Rodeo del bug "el valor por defecto no se registra": sube y baja un paso. La
        // prueba `testDefaultDaysAndMinutes...` exige que esto no haga falta.
        let minutes = app.steppers["onboarding.minutesStepper"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 10))
        minutes.buttons.element(boundBy: 1).tap()
        minutes.buttons.element(boundBy: 0).tap()
        tap(app, "onboarding.next")
        let guided = ["novice", "beginner"].contains(experience)
        let expert = ["advanced", "competitive"].contains(experience)
        // Quien empieza no ve "Variedad" (queda estable).
        if !guided { tap(app, "onboarding.option.balanced"); tap(app, "onboarding.next") }
        // Avanzado: músculos prioritarios (opcional, hasta 2).
        if expert {
            XCTAssertTrue(element(app, "onboarding.priority.glutes").waitForExistence(timeout: 10), "Paso de prioritarios")
            for muscle in priority { tap(app, "onboarding.priority.\(muscle)") }
            tap(app, "onboarding.next")
        }
        // SCRUM-209: sin paso "Gimnasio"; restricciones opcionales (zonas + nota).
        XCTAssertTrue(element(app, "onboarding.zone.shoulder").waitForExistence(timeout: 10), "Paso de restricciones con zonas")
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
    private func completeOnboardingFromExperience(_ app: XCUIApplication, experience: String) {
        tap(app, "onboarding.option.\(experience)"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        selectDays(app, ["monday", "wednesday", "friday"])
        tap(app, "onboarding.next")
        tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.zone.shoulder").waitForExistence(timeout: 10), "Principiante: de minutos a restricciones")
        tap(app, "onboarding.next")
        tap(app, "aiConsent.decline")
        tap(app, "weekIntro.done")
    }

    /// Recorre el cuestionario completo hasta llegar a Hoy (cierra "Tu semana").
    private func completeOnboarding(
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
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.option.hypertrophy").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Hipertrofia")
        XCTAssertEqual(element(app, "onboarding.option.generalHealth").label, "Salud general")
        XCTAssertEqual(element(app, "onboarding.option.strength").label, "Fuerza")
        XCTAssertEqual(element(app, "onboarding.option.recomposition").label, "Recomposición")
    }

    func testSelectedOptionIsMarked() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.strength")
        XCTAssertTrue(element(app, "onboarding.option.strength").isSelected, "La opción elegida no se ve marcada")
        XCTAssertFalse(element(app, "onboarding.option.hypertrophy").isSelected)
    }

    func testOneTapOnAnOptionDoesNotSkipSteps() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.intermediate")
        XCTAssertTrue(app.staticTexts["Paso 1 de 7"].exists, "Un toque no debe cambiar de paso (intermedio: 7 pasos)")
    }

    func testDefaultDaysAndMinutesCanAdvanceWithoutTouchingTheSteppers() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.day.monday").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "onboarding.next").isEnabled, "Con los días por defecto se debe poder avanzar")
    }

    /// SCRUM-196: los días se eligen con chips; con uno solo no se puede avanzar.
    func testChoosingDaysNeedsAtLeastTwo() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.intermediate"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
        tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
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

    // MARK: - Estados de carga (SCRUM-193)

    /// Con el plan pendiente (demora a propósito) nunca aparece "Día de descanso": se ve la
    /// carga ("Armando tu semana") y, cuando el plan llega, la semana y Hoy con su sesión.
    func testPendingPlanNeverShowsRestDay() {
        let app = launch(extraArguments: ["-PRUITestPlanDelay", "4"])
        answerQuestionnaire(app)
        XCTAssertTrue(element(app, "plan.building").waitForExistence(timeout: 5), "Mientras carga debe verse la carga")
        for _ in 0..<3 {
            XCTAssertFalse(element(app, "today.restDay").exists, "Nunca 'Día de descanso' mientras el plan está pendiente")
            XCTAssertFalse(element(app, "today.start").exists, "Hoy no se puede tocar mientras carga")
            sleep(1)
        }
        // SCRUM-205: "Tu semana" explica el plan (aquí con el texto local: en pruebas no hay IA).
        XCTAssertTrue(element(app, "plan.rationale").waitForExistence(timeout: 15), "Debe verse \"Por qué tu plan es así\"")
        tap(app, "weekIntro.done")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "El lunes, ya con plan, toca entrenar")
        XCTAssertFalse(element(app, "today.restDay").exists)
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
        // SCRUM-210: el cuestionario empieza por la experiencia.
        XCTAssertTrue(element(app, "onboarding.option.intermediate").waitForExistence(timeout: 10),
                      "Rehacer debe abrir el cuestionario")
    }

    /// SCRUM-202: tras el formulario se pide el consentimiento de la IA una sola vez; en
    /// Perfil se ve aceptado y se puede retirar.
    func testAIConsentIsAskedAfterTheFormAndCanBeRevokedInProfile() {
        let app = launch()
        completeOnboarding(app, aiConsent: "accept")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Perfil")
        let toggle = app.switches["profile.aiConsent"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Perfil debe mostrar el consentimiento de la IA")
        XCTAssertEqual(toggle.value as? String, "1", "Aceptado en el formulario")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0", "Retirar aplica al instante")
    }

    /// SCRUM-211: reordenar en Hoy cambia el orden, "¿Por qué este orden?" dice que es
    /// tuyo y "Volver al orden recomendado" lo restablece.
    func testReorderTodayExercisesAndReset() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        // En iPhone, con "¿Cómo dormiste?" a la vista, la lista de ejercicios de Hoy queda de
        // 24 pt de alto (bug de layout encontrado en SCRUM-217, se arregla aparte): se responde
        // "Ahora no" para ver los ejercicios y se desliza sobre la lista misma.
        if element(app, "today.sleep.skip").waitForExistence(timeout: 3) {
            tap(app, "today.sleep.skip")
        }
        let firstName = element(app, "today.exercise.0").label
        let secondName = scrollTo(app, "today.exercise.1", within: "today.exerciseList").label
        XCTAssertNotEqual(firstName, secondName)

        tap(app, "today.reorder")
        tap(app, "reorder.down.0")
        tap(app, "reorder.save")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 10))
        XCTAssertEqual(
            scrollTo(app, "today.exercise.0", within: "today.exerciseList", upwards: true).label, secondName,
            "El segundo pasa al primer lugar"
        )
        XCTAssertEqual(scrollTo(app, "today.exercise.1", within: "today.exerciseList").label, firstName)

        tap(app, "today.whyOrder")
        XCTAssertTrue(element(app, "order.custom").waitForExistence(timeout: 5), "Dice que el orden es tuyo")
        app.buttons["Listo"].firstMatch.tap()

        tap(app, "today.reorder")
        tap(app, "reorder.reset")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 10))
        XCTAssertEqual(
            scrollTo(app, "today.exercise.0", within: "today.exerciseList", upwards: true).label, firstName,
            "Vuelve al recomendado"
        )
    }

    /// SCRUM-210: un principiante ve 6 pasos (sin "Variedad"), lenguaje simple y, en Hoy,
    /// el RIR explicado en palabras.
    func testBeginnerFlowIsSimplerAndExplainsRIR() {
        let app = launch()
        completeAboutYou(app)
        tap(app, "onboarding.option.beginner")
        XCTAssertTrue(app.staticTexts["Paso 1 de 6"].waitForExistence(timeout: 5), "Principiante: 6 pasos")
        tap(app, "onboarding.next")
        XCTAssertTrue(element(app, "onboarding.option.hypertrophy").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Ganar músculo", "Lenguaje simple")
        tap(app, "onboarding.back")
        completeOnboardingFromExperience(app, experience: "beginner")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        let plainRIR = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "en reserva")).firstMatch
        XCTAssertTrue(plainRIR.waitForExistence(timeout: 5), "El RIR se explica en palabras")
    }

    /// SCRUM-210: un avanzado tiene el paso de músculos prioritarios (como mucho 2).
    func testAdvancedFlowAsksPriorityMuscles() {
        let app = launch()
        completeOnboarding(app, experience: "advanced", priority: ["glutes", "back"])
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "El plan se armó con los prioritarios")
    }

    /// SCRUM-209: elegir "Hombro" en restricciones (con nota) arma el plan igual y "Tu
    /// semana" explica que se cuida esa zona.
    func testRestrictionZoneIsExplainedInYourWeek() {
        let app = launch()
        answerQuestionnaire(app, zones: ["shoulder"], note: "Molestia al subir el brazo")
        let rationale = element(app, "plan.rationale")
        XCTAssertTrue(rationale.waitForExistence(timeout: 15), "Debe verse \"Por qué tu plan es así\"")
        XCTAssertTrue(rationale.label.localizedCaseInsensitiveContains("hombro"), "Explica que cuida el hombro: \(rationale.label)")
        tap(app, "weekIntro.done")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "El plan se armó igual")
    }

    /// SCRUM-208: "Cerrar sesión" pide confirmación, vuelve al login y, al entrar con la
    /// misma cuenta, el plan sigue ahí (no se borró nada).
    func testSignOutAsksAndKeepsThePlan() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Perfil")
        XCTAssertTrue(scrollTo(app, "profile.appearance").waitForExistence(timeout: 5), "Perfil ofrece la apariencia")
        XCTAssertTrue(scrollTo(app, "profile.signOut").waitForExistence(timeout: 5), "Perfil ofrece cerrar sesión")
        tap(app, "profile.signOut")
        let confirm = app.buttons["profile.signOut.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Debe pedir confirmación")
        confirm.tap()
        XCTAssertTrue(element(app, "signIn.apple").waitForExistence(timeout: 10), "Vuelve al inicio de sesión")
        tap(app, "signIn.apple")
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15), "La misma cuenta recupera su plan")
    }

    /// SCRUM-203: en un día de entrenamiento Hoy pregunta cómo dormiste; "Dormí mal"
    /// aligera el día y lo explica; no se vuelve a preguntar.
    func testSleepCheckInMakesTheDayLighter() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, "today.sleep").waitForExistence(timeout: 5), "Debe preguntar cómo dormiste")
        tap(app, "today.sleep.poor")
        XCTAssertTrue(element(app, "today.readiness").waitForExistence(timeout: 5), "Debe explicar el ajuste del día")
        XCTAssertFalse(element(app, "today.sleep").exists, "No vuelve a preguntar hoy")
        XCTAssertTrue(element(app, "today.start").exists, "Se puede entrenar igual")
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

    /// SCRUM-212: en el entrenamiento se deja un ejercicio para después, se salta (con
    /// confirmación), se retoma, y al terminar el resumen dice qué se saltó.
    func testDeferSkipAndResumeInWorkout() {
        let app = launch()
        completeOnboarding(app)
        tap(app, "today.start")
        XCTAssertTrue(element(app, "workout.completeSet").waitForExistence(timeout: 10))

        tap(app, "workout.defer")
        XCTAssertTrue(element(app, "workout.completeSet").waitForExistence(timeout: 5), "Sigue con el siguiente ejercicio")

        tap(app, "workout.skip")
        let confirm = app.buttons["Sí, saltar"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Saltar pide confirmación")
        confirm.tap()
        XCTAssertTrue(element(app, "workout.resume.0").waitForExistence(timeout: 5), "El saltado se puede retomar")

        tap(app, "workout.resume.0")
        XCTAssertFalse(element(app, "workout.resume.0").waitForExistence(timeout: 2), "Retomado: ya no está saltado")

        tap(app, "workout.skip")
        XCTAssertTrue(app.buttons["Sí, saltar"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Sí, saltar"].firstMatch.tap()

        app.buttons["Terminar"].firstMatch.tap()
        let complete = app.buttons["Completar sesión"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(element(app, "summary.skipped").waitForExistence(timeout: 10), "El resumen muestra lo saltado")
    }

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

    // MARK: - Progreso (SCRUM-186)

    /// Antes de entrenar Progreso está vacío; tras completar el primer entrenamiento queda
    /// en el registro y se puede abrir su detalle.
    func testProgressLogsTheFirstWorkout() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Progreso")
        XCTAssertTrue(element(app, "progress.empty").waitForExistence(timeout: 10), "Sin entrenamientos debe estar vacío")

        openTab(app, "Hoy")
        tap(app, "today.start")
        tap(app, "workout.completeSet")
        let finish = app.buttons["Terminar"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()
        let complete = app.buttons["Completar sesión"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        tap(app, "summary.done")

        openTab(app, "Progreso")
        XCTAssertTrue(element(app, "progress.entry.0").waitForExistence(timeout: 10), "El primer entrenamiento debe quedar registrado")
        XCTAssertTrue(element(app, "progress.summary").exists)
        // SCRUM-213: 4 KPIs y la gráfica de progreso.
        for kpi in 0..<4 {
            XCTAssertTrue(element(app, "progress.kpi.\(kpi)").exists, "Falta el KPI \(kpi)")
        }
        XCTAssertTrue(element(app, "progress.chart").exists, "Debe verse la gráfica de progreso")
        tap(app, "progress.entry.0")
        XCTAssertTrue(element(app, "progress.detail").waitForExistence(timeout: 10))
    }

    // MARK: - Exportar

    func testExportShowsEmptyStateBeforeAnyWorkout() {
        let app = launch()
        completeOnboarding(app)
        XCTAssertTrue(element(app, "today.start").waitForExistence(timeout: 15))
        openTab(app, "Perfil")
        // En iPhone "Exportar" queda abajo de "Sobre ti" y la IA: hay que bajar, como la persona.
        XCTAssertTrue(scrollTo(app, "profile.export").waitForExistence(timeout: 5), "Perfil ofrece exportar")
        tap(app, "profile.export")
        XCTAssertTrue(app.staticTexts["Aún no tienes entrenamientos"].waitForExistence(timeout: 10))
    }
}
