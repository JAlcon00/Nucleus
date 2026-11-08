//
//  ProfileJourney.swift
//  PRUITests
//
//  Recorrido 6 · Perfil (SCRUM-228). Arranca con el perfil ya contestado. Una restricción se
//  agrega y se resuelve desde Perfil y el plan la cuida mientras está vigente (SCRUM-36);
//  "Cerrar sesión" pide confirmación y la misma cuenta recupera su plan (SCRUM-208); "Rehacer
//  cuestionario" lo abre (SCRUM-26), también desde "Tu bloque" en Plan (SCRUM-266). Cada tramo
//  arranca con un perfil recién sembrado, como las pruebas de antes arrancaban con el
//  cuestionario recién contestado.
//

import XCTest

final class ProfileJourney: PRUITestCase {

    func testProfileRestrictionsSignOutAndRedo() {
        // SCRUM-36: una restricción se agrega desde Perfil sin rehacer el cuestionario y el plan
        // la cuida desde ese momento ("Por qué tu plan" lo dice y Hoy no trae curls ni tríceps).
        // "Ya no me molesta" pide confirmación, la deja en el historial y el plan deja de cuidarla.
        step("Una restricción se agrega y se resuelve desde Perfil (testRestrictionIsAddedAndResolvedFromProfile)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))

            openTab(app, "Perfil")
            tap(app, "profile.restrictions")
            XCTAssertTrue(element(app, "restrictions.empty").appears(within: 10), "Sin restricciones al empezar")
            tap(app, "restrictions.add")
            tap(app, "restrictions.zone.elbow")
            tap(app, "restrictions.form.save")
            XCTAssertTrue(element(app, "restrictions.row").appears(within: 15), "La restricción aparece en la lista")

            openTab(app, "Plan")
            let rationale = scrollTo(app, "plan.rationale", upwards: true)
            XCTAssertTrue(rationale.appears(within: 15), "Debe verse \"Por qué tu plan es así\"")
            XCTAssertTrue(rationale.label.localizedCaseInsensitiveContains("codo"), "El plan cuida el codo: \(rationale.label)")

            openTab(app, "Hoy")
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            let exercises = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'today.exercise.'"))
            for index in 0..<exercises.count {
                let label = exercises.element(boundBy: index).label.lowercased()
                XCTAssertFalse(label.contains("curl") || label.contains("tríceps"), "Hoy no carga el codo: \(label)")
            }

            openTab(app, "Perfil")
            tap(app, "restrictions.row")
            XCTAssertTrue(element(app, "restrictions.detail").appears(within: 10), "Abre el detalle de la restricción")
            XCTAssertTrue(scrollTo(app, "restrictions.resolve").appears(within: 5), "El detalle ofrece \"Ya no me molesta\"")
            tap(app, "restrictions.resolve")
            let confirm = app.alerts.buttons["Ya no me molesta"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5), "Resolver pide confirmación")
            confirm.tap()
            XCTAssertTrue(element(app, "restrictions.history.row").appears(within: 15), "Queda en el historial")

            openTab(app, "Plan")
            let updated = scrollTo(app, "plan.rationale", upwards: true)
            XCTAssertTrue(updated.appears(within: 15))
            XCTAssertFalse(updated.label.localizedCaseInsensitiveContains("codo"), "Resuelta: el plan ya no la cuida: \(updated.label)")
        }

        // SCRUM-235: "Mi gimnasio" existe sin pasos nuevos y se puede renombrar.
        step("Perfil muestra Mi gimnasio y se puede renombrar (SCRUM-235)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            let row = element(app, "profile.gym")
            XCTAssertTrue(row.appears(within: 10), "Perfil muestra el gimnasio")
            XCTAssertTrue(row.label.contains("Mi gimnasio"), "Se llama Mi gimnasio: \(row.label)")
            tap(app, "profile.gym")
            tap(app, "gym.rename")
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.appears(within: 5), "Pide el nombre")
            field.tap()
            field.typeText("Oficina")
            app.alerts.buttons["Guardar"].firstMatch.tap()
            let renamed = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Oficina' OR value CONTAINS 'Oficina'")).firstMatch
            XCTAssertTrue(renamed.appears(within: 10), "El nombre nuevo se ve")
        }

        // SCRUM-238: agregar un gimnasio y elegirlo. Lo que dice Hoy está en TodayJourney.
        step("Agregar un gimnasio y elegirlo (SCRUM-238)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            tap(app, "profile.gym")
            tap(app, "gym.add")
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.appears(within: 5), "Pide el nombre")
            field.tap()
            field.typeText("Casa")
            app.alerts.buttons["Agregar"].firstMatch.tap()
            let row = element(app, "gym.row.0")
            XCTAssertTrue(row.appears(within: 5), "Aparece en la lista")
            row.tap()       // "Casa" va primero por orden alfabético
            let chosen = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == 'Gimnasio activo: Casa'")
            ).firstMatch
            XCTAssertTrue(chosen.appears(within: 5), "VoiceOver dice cuál es el activo")
        }

        // SCRUM-208: "Cerrar sesión" pide confirmación, vuelve al login y, al entrar con la
        // misma cuenta, el plan sigue ahí (no se borró nada).
        step("Cerrar sesión pide confirmación y la misma cuenta recupera su plan (testSignOutAsksAndKeepsThePlan)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            XCTAssertTrue(scrollTo(app, "profile.appearance").appears(within: 5), "Perfil ofrece la apariencia")
            XCTAssertTrue(scrollTo(app, "profile.signOut").appears(within: 5), "Perfil ofrece cerrar sesión")
            tap(app, "profile.signOut")
            let confirm = app.buttons["profile.signOut.confirm"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5), "Debe pedir confirmación")
            confirm.tap()
            XCTAssertTrue(element(app, "signIn.apple").appears(within: 10), "Vuelve al inicio de sesión")
            tap(app, "signIn.apple")
            XCTAssertTrue(element(app, "today.start").appears(within: 15), "La misma cuenta recupera su plan")
        }

        step("Rehacer el cuestionario desde Perfil lo abre (testRedoQuestionnaireFromProfileOpensTheQuestionnaire)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            XCTAssertTrue(scrollTo(app, "profile.redo").appears(within: 5), "Perfil ofrece rehacer el cuestionario")
            tap(app, "profile.redo")
            let confirm = app.buttons["Sí, rehacer"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5))
            confirm.tap()
            // SCRUM-210: el cuestionario empieza por la experiencia.
            XCTAssertTrue(element(app, "onboarding.option.intermediate").appears(within: 10),
                          "Rehacer debe abrir el cuestionario")
        }

        // SCRUM-266: Plan muestra "Tu bloque" en la semana 1 y "Cambiar objetivo o fase" pide la
        // misma confirmación que Perfil y abre el cuestionario.
        step("Plan muestra tu bloque y ofrece cambiar objetivo o fase (SCRUM-266)") {
            let app = launchWithPlan()
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Plan")
            let block = scrollTo(app, "plan.block", upwards: true)
            XCTAssertTrue(block.appears(within: 15), "Plan muestra tu bloque")
            XCTAssertTrue(block.label.contains("Semana 1 de"), "El bloque recién creado va en la semana 1: \(block.label)")
            tap(app, "plan.block.change")
            let confirm = app.buttons["Sí, rehacer"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5), "Pide la misma confirmación que Perfil")
            confirm.tap()
            XCTAssertTrue(element(app, "onboarding.option.intermediate").appears(within: 10),
                          "Cambiar objetivo o fase abre el cuestionario")
        }

        // SCRUM-39: con la flag de la IA apagada, la IA no aparece: no se pide el consentimiento
        // tras el cuestionario, el plan se arma con el motor local y Perfil no tiene la sección.
        step("Con la IA apagada por flag no se pide el consentimiento ni hay Perfil › IA (SCRUM-39)") {
            let app = launch(extraArguments: ["-PRFeatureFlag", "agent.nvidia.enabled=0"])
            answerQuestionnaire(app, aiConsent: nil)
            XCTAssertTrue(element(app, "weekIntro.done").appears(within: 20), "El plan se arma sin preguntar por la IA")
            XCTAssertFalse(element(app, "aiConsent.decline").exists, "Sin la IA no hay consentimiento")
            tap(app, "weekIntro.done")
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            XCTAssertTrue(scrollTo(app, "profile.redo").appears(within: 10))
            XCTAssertFalse(app.switches["profile.aiConsent"].exists, "Perfil no muestra la IA")
            XCTAssertFalse(element(app, "profile.aiStatus").exists)
            XCTAssertFalse(app.switches["profile.healthWrites"].exists, "Con el flag apagado no hay Salud")
        }
    }

    /// SCRUM-248: "Ahora no" no vuelve a salir y Perfil sigue ofreciendo la opción.
    func testHealthSwitchInProfile() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestFakeHealth", "undecided"])

        step("\"Ahora no\" deja el interruptor apagado y se puede encender en Perfil") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            tap(app, "today.start")
            finishWorkoutAfterOneSet(app)
            XCTAssertTrue(scrollTo(app, "summary.healthOffer.decline").appears(within: 10))
            tap(app, "summary.healthOffer.decline")
            XCTAssertFalse(element(app, "summary.healthOffer").exists)
            tap(app, "summary.done")

            openTab(app, "Perfil")
            let toggle = app.switches["profile.healthWrites"]
            XCTAssertTrue(scrollTo(app, "profile.healthWrites").appears(within: 10), "Perfil ofrece Salud")
            XCTAssertEqual(toggle.value as? String, "0")
            toggle.switches.firstMatch.tap()
            XCTAssertTrue(NSPredicate(format: "value == '1'").evaluate(with: toggle) || toggle.waitForValue("1"))
        }
    }
}

private extension XCUIElement {
    func waitForValue(_ expected: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
}
