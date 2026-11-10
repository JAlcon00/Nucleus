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

    // SCRUM-259: una serie hecha en el iPhone y en el reloj sin conexión. El resumen muestra
    // las dos y nada se borra hasta que la persona elige.
    func testSetConflictIsResolvedInTheSummary() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestSetConflict"])

        step("El resumen muestra la serie en conflicto y se elige") {
            tap(app, "today.start")
            let finish = app.buttons["Terminar"].firstMatch
            XCTAssertTrue(finish.appears(within: 10))
            finish.tap()
            let complete = app.buttons["Completar sesión"].firstMatch
            XCTAssertTrue(complete.appears(within: 5))
            complete.tap()

            XCTAssertTrue(element(app, "summary.conflict").appears(within: 10), "Debe avisar del conflicto")
            tap(app, "summary.conflict.both")
            XCTAssertFalse(element(app, "summary.conflict").waitForExistence(timeout: 2), "Al elegir, ya no hay conflicto")
            XCTAssertTrue(element(app, "summary.done").exists)
        }
    }

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

            // SCRUM-238: con el entrenamiento en curso no se cambia de gimnasio y dice por qué.
            openTab(reopened, "Perfil")
            tap(reopened, "profile.gym")
            XCTAssertTrue(element(reopened, "gym.locked").appears(within: 5), "Dice por qué")
            XCTAssertFalse(element(reopened, "gym.row.0").isEnabled, "La opción está desactivada")
            openTab(reopened, "Hoy")

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

        // SCRUM-237: la segunda serie aparece precargada con el peso de la primera.
        step("La segunda serie dice que trae tu último peso (SCRUM-237)") {
            let app = launchWithPlan()
            tap(app, "today.start")
            tap(app, "workout.completeSet")
            let skip = app.buttons["Saltar"].firstMatch
            if skip.appears(within: 5) { skip.tap() }
            XCTAssertTrue(element(app, "workout.lastWeight").appears(within: 5), "Precarga el peso de la serie anterior")

            // SCRUM-274: "¿Por qué este peso?" explica de dónde salió y se cierra; la serie
            // sigue lista para completarse.
            tap(app, "workout.weight.why")
            XCTAssertTrue(element(app, "why.sheet").appears(within: 5), "Abre la explicación del peso")
            XCTAssertTrue(element(app, "why.reason.0").appears(within: 5), "Dice de dónde salió el peso")
            tap(app, "why.done")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 5), "\"Completar serie\" sigue a la mano")
        }

        // SCRUM-234: con todo ocupado se ofrece un sustituto; al elegirlo se sigue con él.
        step("Máquina ocupada ofrece un sustituto equivalente y se sigue con él (SCRUM-234)") {
            let app = launchWithPlan()
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))
            var option = element(app, "occupied.option.0")
            for _ in 0..<12 where !option.exists {
                tap(app, "workout.occupied")
                option = element(app, "occupied.option.0")
                _ = option.appears(within: 2)
            }
            XCTAssertTrue(option.exists, "Sin nada que adelantar ofrece un sustituto")
            option.tap()
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 5), "Sigue con el sustituto")
            tap(app, "workout.completeSet")
        }

        // SCRUM-236: "No hay esta máquina aquí" se recuerda, Semana lo dice y se puede quitar.
        step("No hay esta máquina: se recuerda y se quita desde Perfil (SCRUM-236)") {
            let storeID = newStoreID()
            let app = launchWithPlan(storeID: storeID)
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))
            let sheet = element(app, "occupied.option.0")
            for _ in 0..<12 where !sheet.exists {
                tap(app, "workout.occupied")
                _ = sheet.appears(within: 2)
            }
            let missing = scrollTo(app, "occupied.missing")
            XCTAssertTrue(missing.appears(within: 5), "La hoja ofrece decir que no hay la máquina")
            missing.tap()
            tap(app, "occupied.option.0")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 5), "Sigue con el sustituto")

            app.terminate()
            let reopened = launch(storeID: storeID)
            XCTAssertTrue(element(reopened, "today.activeBanner").appears(within: 20))
            openTab(reopened, "Plan")
            XCTAssertTrue(element(reopened, "plan.gymNote").appears(within: 10), "La semana dice qué cambió")
            openTab(reopened, "Perfil")
            tap(reopened, "profile.gym")
            tap(reopened, "gym.missing.remove.0")
            XCTAssertFalse(element(reopened, "gym.missing.0").waitForExistence(timeout: 3), "La marca se quitó")
        }

        // SCRUM-276: el entrenador del entrenamiento, junto a "Terminar": "Está ocupada" hace
        // lo mismo que el botón "Máquina ocupada", sin IA, y la serie sigue a la mano.
        step("El entrenador marca la máquina ocupada desde el entrenamiento (SCRUM-276)") {
            let app = launchWithPlan()
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))
            tap(app, "workout.coach")
            XCTAssertTrue(element(app, "coach.intro").appears(within: 5), "Abre el entrenador")
            tap(app, "coach.suggestion.0")   // "Está ocupada"
            // Si nada se puede adelantar, la hoja se cierra y se abren las opciones de siempre.
            if element(app, "occupied.wait").appears(within: 5) {
                tap(app, "occupied.wait")
            } else {
                XCTAssertTrue(element(app, "coach.message.1").appears(within: 10), "El entrenador responde")
                tap(app, "coach.done")
            }
            XCTAssertTrue(element(app, "workout.occupied.notice").appears(within: 5), "Dice dónde quedó el ejercicio, como el botón")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 5), "\"Completar serie\" sigue a la mano")
        }

        // SCRUM-212 y SCRUM-233: "Máquina ocupada" dice qué sigue, se salta (con confirmación),
        // se retoma, y al terminar el resumen dice qué se saltó.
        step("Dejar para después, saltar y retomar; el resumen dice qué se saltó (testDeferSkipAndResumeInWorkout)") {
            let app = launchWithPlan()
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))

            tap(app, "workout.occupied")
            // Sin nada que adelantar pregunta (SCRUM-234): "Esperar" lo manda al final.
            if element(app, "occupied.wait").appears(within: 3) { tap(app, "occupied.wait") }
            XCTAssertTrue(element(app, "workout.occupied.notice").appears(within: 5), "Dice dónde quedó el ejercicio")
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
