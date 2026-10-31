//
//  ProfileJourney.swift
//  PRUITests
//
//  Recorrido 6 · Perfil (SCRUM-228). Arranca con el perfil ya contestado. Una restricción se
//  agrega y se resuelve desde Perfil y el plan la cuida mientras está vigente (SCRUM-36);
//  "Cerrar sesión" pide confirmación y la misma cuenta recupera su plan (SCRUM-208); "Rehacer
//  cuestionario" lo abre (SCRUM-26). Cada tramo arranca con un perfil recién sembrado, como
//  las pruebas de antes arrancaban con el cuestionario recién contestado.
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
            tap(app, "profile.redo")
            let confirm = app.buttons["Sí, rehacer"].firstMatch
            XCTAssertTrue(confirm.appears(within: 5))
            confirm.tap()
            // SCRUM-210: el cuestionario empieza por la experiencia.
            XCTAssertTrue(element(app, "onboarding.option.intermediate").appears(within: 10),
                          "Rehacer debe abrir el cuestionario")
        }
    }
}
