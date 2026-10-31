//
//  WorkoutRecoveryJourney.swift
//  PRUITests
//
//  Recorrido 4 · Entrenamiento con cierre forzado y dolor (smoke, SCRUM-228). Arranca con el
//  perfil ya contestado. Empezar muestra la primera serie; un cierre forzado a la mitad ofrece
//  continuar en la serie siguiente (SCRUM-24); el dolor reportado en el descanso sigue
//  guardado al reabrir (SCRUM-226); dejar para después, saltar y retomar llega al resumen
//  (SCRUM-212). Cada tramo usa su propio entrenamiento nuevo, como las pruebas de antes.
//

import XCTest

final class WorkoutRecoveryJourney: PRUITestCase {

    func testWorkoutSurvivesForceQuitAndKeepsPain() {
        let forceQuitStore = newStoreID()
        let app = launchWithPlan(storeID: forceQuitStore)

        step("Empezar muestra la primera serie, no una pantalla negra (testStartShowsTheFirstSetNotABlackScreen)") {
            tap(app, "today.start")
            let shown = element(app, "workout.completeSet").appears(within: 10)
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

        // SCRUM-24: cierre forzado a mitad del entrenamiento ⇒ al reabrir ofrece continuar y
        // sigue en la serie siguiente (no vuelve a empezar).
        step("Un cierre forzado a la mitad ofrece continuar en la serie 4 (testForceQuitMidWorkoutOffersToContinue)") {
            for _ in 1...3 {
                tap(app, "workout.completeSet")
                let skip = app.buttons["Saltar"].firstMatch
                if skip.appears(within: 2) { skip.tap() }
            }
            let thirdDone = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Serie 4 de'")
            ).firstMatch
            XCTAssertTrue(thirdDone.appears(within: 10), "Tras 3 series debe tocar la 4")

            app.terminate()   // cierre forzado
            let reopened = launch(storeID: forceQuitStore)
            XCTAssertTrue(element(reopened, "today.activeBanner").appears(within: 20),
                          "Debe decir 'Tienes un entrenamiento en curso'")
            tap(reopened, "today.resume")
            let resumed = reopened.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Serie 4 de'")
            ).firstMatch
            XCTAssertTrue(resumed.appears(within: 10), "Al continuar debe seguir la serie 4, con las 3 anteriores guardadas")
        }

        // SCRUM-226: en el descanso se reporta el dolor de la serie. Moderado da la
        // recomendación y se puede decir dónde; al reabrir la app sigue guardado. Alto ofrece
        // saltar el ejercicio, que queda para retomar.
        step("El dolor se reporta en el descanso y sigue al reabrir (testPainIsReportedDuringRestAndKeptAfterReopening)") {
            let painStore = newStoreID()
            let app = launchWithPlan(storeID: painStore)
            tap(app, "today.start")
            // Hasta el primer descanso (el calentamiento puede no tenerlo).
            let pain = element(app, "workout.pain")
            for _ in 1...4 where !pain.exists {
                tap(app, "workout.completeSet")
                _ = pain.appears(within: 3)
            }
            XCTAssertTrue(pain.exists, "En el descanso se puede reportar el dolor")
            XCTAssertTrue(pain.label.contains("Reportar dolor"), "Antes de reportar: '\(pain.label)'")

            pain.tap()
            tap(app, "pain.level.moderate")
            let advice = element(app, "pain.recommendation")
            XCTAssertTrue(advice.appears(within: 5), "Moderado muestra la recomendación")
            XCTAssertTrue(advice.label.contains("Baja la intensidad"), "Recomendación: '\(advice.label)'")
            XCTAssertFalse(element(app, "pain.skip").exists, "Moderado no ofrece saltar")
            let muscle = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'pain.muscle.'")).firstMatch
            XCTAssertTrue(muscle.exists, "Se puede decir dónde (opcional)")
            muscle.tap()
            tap(app, "pain.done")
            XCTAssertTrue(pain.appears(within: 5))
            XCTAssertTrue(pain.label.contains("Moderado"), "El botón dice lo reportado: '\(pain.label)'")

            app.terminate()   // cierre forzado: el dolor ya está en la serie guardada
            let reopened = launch(storeID: painStore)
            XCTAssertTrue(element(reopened, "today.activeBanner").appears(within: 20))
            tap(reopened, "today.resume")
            let painAfter = element(reopened, "workout.pain")
            XCTAssertTrue(painAfter.appears(within: 10), "Al reabrir sigue el descanso")
            XCTAssertTrue(painAfter.label.contains("Moderado"), "El dolor sigue en la serie: '\(painAfter.label)'")

            painAfter.tap()
            tap(reopened, "pain.level.high")
            let stop = element(reopened, "pain.recommendation")
            XCTAssertTrue(stop.appears(within: 5))
            XCTAssertTrue(stop.label.contains("Detén este ejercicio"), "Recomendación: '\(stop.label)'")
            tap(reopened, "pain.skip")
            XCTAssertTrue(element(reopened, "workout.resume.0").appears(within: 5),
                          "El ejercicio que dolió queda saltado y se puede retomar")
        }

        // SCRUM-212: en el entrenamiento se deja un ejercicio para después, se salta (con
        // confirmación), se retoma, y al terminar el resumen dice qué se saltó.
        step("Dejar para después, saltar y retomar; el resumen dice qué se saltó (testDeferSkipAndResumeInWorkout)") {
            let app = launchWithPlan()
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))

            tap(app, "workout.defer")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 5), "Sigue con el siguiente ejercicio")

            tap(app, "workout.skip")
            let confirm = app.buttons["Sí, saltar"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5), "Saltar pide confirmación")
            confirm.tap()
            XCTAssertTrue(element(app, "workout.resume.0").appears(within: 5), "El saltado se puede retomar")

            tap(app, "workout.resume.0")
            XCTAssertFalse(element(app, "workout.resume.0").waitForExistence(timeout: 2), "Retomado: ya no está saltado")

            tap(app, "workout.skip")
            XCTAssertTrue(app.buttons["Sí, saltar"].firstMatch.appears(within: 5))
            app.buttons["Sí, saltar"].firstMatch.tap()

            app.buttons["Terminar"].firstMatch.tap()
            let complete = app.buttons["Completar sesión"].firstMatch
            XCTAssertTrue(complete.appears(within: 5))
            complete.tap()
            XCTAssertTrue(element(app, "summary.skipped").appears(within: 10), "El resumen muestra lo saltado")
        }
    }
}
