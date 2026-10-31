//
//  FirstWorkoutJourney.swift
//  PRUITests
//
//  Recorrido 5 · Primer entrenamiento → Progreso → Exportar (smoke, SCRUM-228). Arranca con el
//  perfil ya contestado. Antes de entrenar, Exportar y Progreso están vacíos; el primer
//  entrenamiento queda en Progreso con sus KPIs, la gráfica y el detalle (SCRUM-186, 213); y
//  Exportar lo cuenta una sola vez y ofrece JSON y CSV (SCRUM-190, flujo 4). Los datos viven
//  en un directorio propio: al relanzar siguen ahí y Perfil vuelve a su pantalla principal.
//

import XCTest

final class FirstWorkoutJourney: PRUITestCase {

    func testFirstWorkoutReachesProgressAndExport() {
        let storeID = newStoreID()
        let app = launchWithPlan(storeID: storeID)

        step("Antes de entrenar, Exportar muestra el estado vacío (testExportShowsEmptyStateBeforeAnyWorkout)") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Perfil")
            // En iPhone "Exportar" queda abajo de "Sobre ti" y la IA: hay que bajar, como la persona.
            XCTAssertTrue(scrollTo(app, "profile.export").appears(within: 5), "Perfil ofrece exportar")
            tap(app, "profile.export")
            XCTAssertTrue(app.staticTexts["Aún no tienes entrenamientos"].appears(within: 10))
        }

        // Antes de entrenar Progreso está vacío; tras completar el primer entrenamiento queda
        // en el registro y se puede abrir su detalle.
        step("Progreso registra el primer entrenamiento (testProgressLogsTheFirstWorkout)") {
            openTab(app, "Progreso")
            XCTAssertTrue(element(app, "progress.empty").appears(within: 10), "Sin entrenamientos debe estar vacío")

            openTab(app, "Hoy")
            tap(app, "today.start")
            finishWorkoutAfterOneSet(app)
            tap(app, "summary.done")

            openTab(app, "Progreso")
            XCTAssertTrue(element(app, "progress.entry.0").appears(within: 10), "El primer entrenamiento debe quedar registrado")
            XCTAssertTrue(element(app, "progress.summary").exists)
            // SCRUM-213: 4 KPIs y la gráfica de progreso.
            for kpi in 0..<4 {
                XCTAssertTrue(element(app, "progress.kpi.\(kpi)").exists, "Falta el KPI \(kpi)")
            }
            XCTAssertTrue(element(app, "progress.chart").exists, "Debe verse la gráfica de progreso")
            tap(app, "progress.entry.0")
            XCTAssertTrue(element(app, "progress.detail").appears(within: 10))
        }

        // SCRUM-190 (flujo 4): tras el primer entrenamiento, Exportar cuenta exactamente esa
        // sesión y ofrece los dos archivos (JSON y CSV). Se relanza para que Perfil vuelva a su
        // pantalla principal (Exportar quedó abierto arriba); el entrenamiento sigue guardado.
        step("Exportar cuenta ese entrenamiento una sola vez y ofrece JSON y CSV (testExportCountsTheFirstWorkout)") {
            let reopened = launch(storeID: storeID)
            XCTAssertTrue(element(reopened, "today.start").appears(within: 15))
            openTab(reopened, "Perfil")
            // En iPhone "Exportar" queda abajo de "Sobre ti" y la IA: hay que bajar, como la persona.
            XCTAssertTrue(scrollTo(reopened, "profile.export").appears(within: 5), "Perfil ofrece exportar")
            tap(reopened, "profile.export")
            XCTAssertTrue(reopened.staticTexts["1 sesión"].appears(within: 10), "Exportar debe contar el entrenamiento una sola vez")
            XCTAssertTrue(reopened.buttons["JSON completo"].appears(within: 10), "Debe ofrecer el JSON")
            XCTAssertTrue(reopened.buttons["Series (CSV)"].exists, "Debe ofrecer el CSV")
        }
    }
}
