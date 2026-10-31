//
//  BeginnerQuestionnaireJourney.swift
//  PRUITests
//
//  Recorrido 2 · Cuestionario por experiencia (SCRUM-228): el principiante ve menos pasos,
//  lenguaje simple y, en Hoy, el RIR en palabras; el avanzado tiene el paso de músculos
//  prioritarios. Cada uno contesta su cuestionario a mano, en su propio arranque. El
//  avanzado vive aquí (y no en el recorrido intermedio) para que el smoke quepa en 4 min.
//

import XCTest

final class BeginnerQuestionnaireJourney: PRUITestCase {

    func testBeginnerAndAdvancedQuestionnaires() {
        // SCRUM-210: un principiante ve 7 pasos (sin "Variedad"; con prioritarios opcionales
        // desde SCRUM-215), lenguaje simple y, en Hoy, el RIR explicado en palabras.
        step("Principiante: 7 pasos, lenguaje simple y el RIR en palabras (testBeginnerFlowIsSimplerAndExplainsRIR)") {
            let app = launch()
            completeAboutYou(app)
            tap(app, "onboarding.option.beginner")
            XCTAssertTrue(app.staticTexts["Paso 1 de 7"].appears(within: 5), "Principiante: 7 pasos")
            tap(app, "onboarding.next")
            XCTAssertTrue(element(app, "onboarding.option.hypertrophy").appears(within: 10))
            XCTAssertEqual(element(app, "onboarding.option.hypertrophy").label, "Ganar músculo", "Lenguaje simple")
            tap(app, "onboarding.back")
            completeOnboardingFromExperience(app, experience: "beginner")
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            let plainRIR = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "en reserva")).firstMatch
            XCTAssertTrue(plainRIR.appears(within: 5), "El RIR se explica en palabras")
        }

        // SCRUM-210: un avanzado tiene el paso de músculos prioritarios (como mucho 2).
        step("Avanzado: el plan se arma con dos músculos prioritarios (testAdvancedFlowAsksPriorityMuscles)") {
            let app = launch()
            completeOnboarding(app, experience: "advanced", priority: ["glutes", "back"])
            XCTAssertTrue(element(app, "today.start").appears(within: 15), "El plan se armó con los prioritarios")
        }
    }
}
