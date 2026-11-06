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
            // Sin escritura a Salud, el resumen no habla de Salud (SCRUM-247).
            XCTAssertFalse(element(app, "summary.health").exists)
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

    /// SCRUM-247: con permiso, el resumen dice que el entrenamiento quedó en Salud (Salud falsa).
    func testSummarySaysItWasSavedInHealth() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestFakeHealth", "granted"])

        step("El resumen dice \"Guardado en Salud\"") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            tap(app, "today.start")
            finishWorkoutAfterOneSet(app)
            let status = element(app, "summary.health")
            XCTAssertTrue(status.appears(within: 10), "El resumen debe decir qué pasó con Salud")
            XCTAssertTrue(status.label.contains("Guardado en Salud"), "Dijo: \(status.label)")
        }
    }

    /// SCRUM-248: al terminar se propone guardar en Salud; aceptar guarda este entrenamiento.
    func testSummaryOffersHealthAndSavesTheWorkout() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestFakeHealth", "undecided"])

        step("La tarjeta no sale antes ni durante, y aceptar guarda en Salud") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            XCTAssertFalse(element(app, "summary.healthOffer").exists)
            tap(app, "today.start")
            XCTAssertTrue(element(app, "workout.completeSet").appears(within: 10))
            XCTAssertFalse(element(app, "summary.healthOffer").exists)
            finishWorkoutAfterOneSet(app)
            XCTAssertTrue(scrollTo(app, "summary.healthOffer.accept").appears(within: 10), "El resumen propone Salud")
            tap(app, "summary.healthOffer.accept")
            let status = scrollTo(app, "summary.health", upwards: true)
            XCTAssertTrue(status.appears(within: 10), "Aceptar guarda el entrenamiento recién terminado")
            XCTAssertFalse(element(app, "summary.healthOffer").exists)
        }
    }

    /// SCRUM-248: si se niega en la hoja, la app no insiste y el resumen sigue normal.
    func testRefusingTheSheetDoesNotInsist() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestFakeHealth", "refuses"])

        step("Negar no bloquea ni deja rastro de Salud") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            tap(app, "today.start")
            finishWorkoutAfterOneSet(app)
            XCTAssertTrue(scrollTo(app, "summary.healthOffer.accept").appears(within: 10))
            tap(app, "summary.healthOffer.accept")
            XCTAssertTrue(element(app, "summary.done").appears(within: 10))
            XCTAssertFalse(element(app, "summary.health").exists)
            XCTAssertFalse(element(app, "summary.healthOffer").exists)
        }
    }

    /// SCRUM-250: la sesión muestra la energía del reloj una vez, y lo de otra app sale aparte.
    func testWatchEnergyShowsOnceAndActivityStaysApart() {
        let app = launch(profile: Self.seededProfile, extraArguments: ["-PRUITestFakeHealth", "watch"])

        step("El resumen muestra la energía con su fuente") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            tap(app, "today.start")
            finishWorkoutAfterOneSet(app)
            let energy = element(app, "health.energy")
            XCTAssertTrue(energy.appears(within: 10), "La sesión debe mostrar la energía del reloj")
            XCTAssertTrue(energy.label.contains("Apple Watch"), "Dijo: \(energy.label)")
            XCTAssertTrue(energy.label.contains("240 kcal"), "Dijo: \(energy.label)")
            tap(app, "summary.done")
        }

        step("Progreso cuenta un entrenamiento y la actividad de otra app va aparte") {
            openTab(app, "Progreso")
            XCTAssertTrue(element(app, "progress.entry.0").appears(within: 10))
            XCTAssertFalse(element(app, "progress.entry.1").exists, "La actividad no es un entrenamiento")
            XCTAssertTrue(scrollTo(app, "progress.activity.0").appears(within: 10), "Debe salir la actividad de Salud")
            XCTAssertFalse(element(app, "progress.activity.1").exists, "El reloj no sale como actividad aparte")
        }
    }
}
