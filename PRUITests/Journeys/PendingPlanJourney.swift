//
//  PendingPlanJourney.swift
//  PRUITests
//
//  Recorrido 3 · Plan pendiente (SCRUM-228). "Armando tu semana" sólo aparece al terminar el
//  cuestionario, así que este recorrido lo contesta a mano, una vez: declara el hombro con
//  una nota y demora el plan a propósito (`-PRUITestPlanDelay`, sólo Debug). Mientras carga
//  nunca aparece "Día de descanso" (SCRUM-193); "Tu semana" explica el plan y que cuida el
//  hombro (SCRUM-205, SCRUM-209); el lunes, ya con plan, toca entrenar.
//

import XCTest

final class PendingPlanJourney: PRUITestCase {

    /// Segundos que el plan queda pendiente. Las 3 comprobaciones de abajo tienen que caer
    /// dentro: con la Mac cargada tardaron hasta 6.1 s desde "Ahora no" (con 4 s, el plan
    /// llegó a la mitad y la prueba falló sin que la app hiciera nada mal; 2026-10-30).
    private static let planDelaySeconds = "10"

    func testPendingPlanShowsLoadingThenExplainsTheWeek() {
        let app = launch(extraArguments: ["-PRUITestPlanDelay", Self.planDelaySeconds])

        step("Cuestionario con el hombro y una nota en restricciones (testRestrictionZoneIsExplainedInYourWeek)") {
            answerQuestionnaire(app, zones: ["shoulder"], note: "Molestia al subir el brazo")
        }

        step("Con el plan pendiente se ve la carga y nunca 'Día de descanso' (testPendingPlanNeverShowsRestDay)") {
            XCTAssertTrue(element(app, "plan.building").appears(within: 5), "Mientras carga debe verse la carga")
            for _ in 0..<3 {
                XCTAssertFalse(element(app, "today.restDay").exists, "Nunca 'Día de descanso' mientras el plan está pendiente")
                XCTAssertFalse(element(app, "today.start").exists, "Hoy no se puede tocar mientras carga")
                sleep(1)
            }
        }

        // SCRUM-205: "Tu semana" explica el plan (aquí con el texto local: en pruebas no hay IA).
        step("Tu semana explica el plan y que cuida el hombro (testPendingPlanNeverShowsRestDay, testRestrictionZoneIsExplainedInYourWeek)") {
            let rationale = element(app, "plan.rationale")
            XCTAssertTrue(rationale.appears(within: 15), "Debe verse \"Por qué tu plan es así\"")
            XCTAssertTrue(rationale.label.localizedCaseInsensitiveContains("hombro"), "Explica que cuida el hombro: \(rationale.label)")
            tap(app, "weekIntro.done")
        }

        step("Con el plan listo, el lunes toca entrenar (testPendingPlanNeverShowsRestDay, testRestrictionZoneIsExplainedInYourWeek)") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15), "El lunes, ya con plan, toca entrenar; el plan se armó igual")
            XCTAssertFalse(element(app, "today.restDay").exists)
        }
    }
}
