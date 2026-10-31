//
//  IntermediateQuestionnaireJourney.swift
//  PRUITests
//
//  Recorrido 1 · Cuestionario intermedio (smoke, SCRUM-228). Contesta el cuestionario a mano
//  una sola vez y comprueba en el camino lo que antes eran 9 pruebas, cada una con su
//  cuestionario: "Sobre ti" pide un adulto; las opciones van en español, se marca la elegida
//  y un toque no cambia de paso; los días y minutos por defecto dejan avanzar y hacen falta
//  al menos 2 días; llega a Hoy; el consentimiento de la IA se pide al final y se retira en
//  Perfil; al reabrir entra directo a Hoy con el mismo plan.
//

import XCTest

final class IntermediateQuestionnaireJourney: PRUITestCase {

    func testIntermediateQuestionnaireFromAboutYouToReopening() {
        // SCRUM-198: lo primero tras iniciar sesión es "Cuéntanos de ti"; con menos de 18 años
        // se explica y no se puede continuar. Arranque aparte: aquí se elige 17 años y mujer.
        step("Sobre ti va primero y pide un adulto (testAboutYouComesFirstAndNeedsAnAdult)") {
            let app = launch()
            XCTAssertTrue(element(app, "aboutYou.title").appears(within: 10))
            XCTAssertFalse(element(app, "aboutYou.continue").isEnabled, "Sin datos no se continúa")
            let wheel = app.pickerWheels.firstMatch
            XCTAssertTrue(wheel.appears(within: 10))
            wheel.adjust(toPickerWheelValue: "17 años")
            tap(app, "aboutYou.sex.female")
            let weight = element(app, "aboutYou.weight")
            weight.tap()
            weight.typeText("60")
            XCTAssertTrue(element(app, "aboutYou.underage").appears(within: 5), "Debe explicar el mínimo de 18")
            XCTAssertFalse(element(app, "aboutYou.continue").isEnabled, "Con 17 años no se arma plan")
            wheel.adjust(toPickerWheelValue: "18 años")
            XCTAssertTrue(element(app, "aboutYou.continue").isEnabled)
        }

        // El cuestionario de `completeOnboarding()` (30 años, intermedio, L-Mi-V), paso a paso.
        let storeID = newStoreID()
        let app = launch(storeID: storeID)

        step("Un toque en una opción no cambia de paso (testOneTapOnAnOptionDoesNotSkipSteps)") {
            completeAboutYou(app)
            tap(app, "onboarding.option.intermediate")
            XCTAssertTrue(app.staticTexts["Paso 1 de 8"].exists, "Un toque no debe cambiar de paso (intermedio: 8 pasos desde SCRUM-215)")
            tap(app, "onboarding.next")
        }

        step("Las opciones del objetivo están en español (testOnboardingOptionsAreInSpanish)") {
            XCTAssertTrue(element(app, "onboarding.option.hypertrophy").appears(within: 10))
            XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Hipertrofia")
            XCTAssertEqual(element(app, "onboarding.option.generalHealth").label, "Salud general")
            XCTAssertEqual(element(app, "onboarding.option.strength").label, "Fuerza")
            XCTAssertEqual(element(app, "onboarding.option.recomposition").label, "Recomposición")
        }

        step("La opción elegida se ve marcada (testSelectedOptionIsMarked)") {
            tap(app, "onboarding.option.strength")
            XCTAssertTrue(element(app, "onboarding.option.strength").isSelected, "La opción elegida no se ve marcada")
            XCTAssertFalse(element(app, "onboarding.option.hypertrophy").isSelected)
            // El cuestionario sigue con hipertrofia, como `completeOnboarding()`.
            tap(app, "onboarding.option.hypertrophy"); tap(app, "onboarding.next")
            tap(app, "onboarding.option.maintenance"); tap(app, "onboarding.next")
        }

        step("Con los días por defecto se puede avanzar (testDefaultDaysAndMinutesCanAdvanceWithoutTouchingTheSteppers)") {
            XCTAssertTrue(element(app, "onboarding.day.monday").appears(within: 10))
            XCTAssertTrue(element(app, "onboarding.next").isEnabled, "Con los días por defecto se debe poder avanzar")
        }

        // SCRUM-196: los días se eligen con chips; con uno solo no se puede avanzar.
        step("Elegir días pide al menos dos (testChoosingDaysNeedsAtLeastTwo)") {
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

        var firstSummary = ""
        step("El cuestionario llega a Hoy (testOnboardingReachesToday)") {
            selectDays(app, ["monday", "wednesday", "friday"])
            tap(app, "onboarding.next")
            // SCRUM-202: tras el formulario se pide el consentimiento de la IA: aquí se acepta.
            answerMinutesAndTheRest(app, aiConsent: "accept")
            tap(app, "weekIntro.done")
            XCTAssertTrue(element(app, "today.start").appears(within: 15), "Tras el cuestionario debe verse Hoy con sesión (lunes)")
            firstSummary = element(app, "today.sessionSummary").label
        }

        // SCRUM-202: se pidió una sola vez, tras el formulario; en Perfil se ve aceptado y se
        // puede retirar.
        step("El consentimiento de la IA se ve en Perfil y se retira (testAIConsentIsAskedAfterTheFormAndCanBeRevokedInProfile)") {
            openTab(app, "Perfil")
            let toggle = app.switches["profile.aiConsent"].firstMatch
            XCTAssertTrue(toggle.appears(within: 10), "Perfil debe mostrar el consentimiento de la IA")
            XCTAssertEqual(toggle.value as? String, "1", "Aceptado en el formulario")
            toggle.switches.firstMatch.tap()
            XCTAssertEqual(toggle.value as? String, "0", "Retirar aplica al instante")
        }

        // SCRUM-26: el cuestionario se contesta una sola vez.
        step("Al reabrir se entra directo a Hoy con el mismo plan (testReopeningTheAppGoesStraightToToday)") {
            app.terminate()
            let reopened = launch(storeID: storeID)
            XCTAssertTrue(element(reopened, "today.start").appears(within: 20),
                          "Al reabrir debe verse Hoy directo, sin login ni cuestionario")
            XCTAssertFalse(element(reopened, "onboarding.next").exists, "No debe repetir el cuestionario")
            XCTAssertEqual(element(reopened, "today.sessionSummary").label, firstSummary, "Debe ser el mismo plan")
        }
    }
}
