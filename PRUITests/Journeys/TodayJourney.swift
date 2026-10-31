//
//  TodayJourney.swift
//  PRUITests
//
//  Recorrido 7 · Hoy (SCRUM-228). Arranca con el perfil ya contestado, un lunes. Con "¿Cómo
//  dormiste?" a la vista los ejercicios quedan a un deslizamiento (SCRUM-222); Hoy tiene una
//  sola acción y pestañas en español (SCRUM-195), lista la sesión con volumen realista
//  (SCRUM-28); se reordena y se restablece (SCRUM-211); la tira y Plan abren la semana
//  (SCRUM-197); "Dormí mal" aligera el día (SCRUM-203). Los datos viven en un directorio
//  propio; se relanza donde el paso anterior dejó la pantalla desplazada o en otra vista.
//

import XCTest

final class TodayJourney: PRUITestCase {

    func testTodayFromSleepCheckInToTheWeek() throws {
        let storeID = newStoreID()

        // SCRUM-222: en iPhone, con "¿Cómo dormiste?" a la vista, los ejercicios de Hoy quedan a
        // un deslizamiento (antes la lista quedaba de 24 pt de alto) y Empezar sigue a la vista.
        step("Con '¿Cómo dormiste?' a la vista, los ejercicios quedan a un deslizamiento (testTodayExercisesStayReachableWithSleepCheckIn)") {
            let app = launchWithPlan(storeID: storeID)
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            XCTAssertTrue(element(app, "today.sleep").appears(within: 5), "Debe preguntar cómo dormiste")
            XCTAssertTrue(element(app, "today.exercise.0").appears(within: 5))

            // "A la vista" = su centro queda entre el borde de arriba del contenido y las acciones
            // fijas de abajo (isHittable no es confiable con las filas de SwiftUI, que son contenedores).
            let content = element(app, "today.content")
            let second = element(app, "today.exercise.1")
            let footerTop = ["today.whyOrder", "today.reorder", "today.start"]
                .map { element(app, $0) }
                .filter(\.exists)
                .map(\.frame.minY)
                .min() ?? content.frame.maxY
            func secondIsVisible() -> Bool {
                second.exists && second.frame.midY > content.frame.minY && second.frame.midY < footerTop
            }
            if !secondIsVisible() {
                // Un deslizamiento lento (sin inercia) que empieza justo arriba de las acciones fijas
                // (el marco del contenido llega por debajo de ellas), como quien baja un poco.
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let from = origin.withOffset(CGVector(dx: content.frame.midX, dy: footerTop - 24))
                let to = origin.withOffset(CGVector(dx: content.frame.midX, dy: content.frame.minY + 120))
                from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTAssertTrue(
                secondIsVisible(),
                "El segundo ejercicio queda a un deslizamiento: fila \(second.frame), contenido \(content.frame), acciones desde y=\(footerTop)"
            )
            XCTAssertTrue(element(app, "today.start").isHittable, "Empezar sigue a la vista")
        }

        // Se relanza: Hoy vuelve arriba (el paso anterior lo desplazó).
        let app = launch(storeID: storeID)

        // SCRUM-195: Hoy tiene una sola acción; lo terciario vive en Perfil. Pestañas en español.
        step("Hoy tiene una sola acción y pestañas en español (testTodayHasASingleActionAndSpanishTabs)") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            for title in ["Hoy", "Progreso", "Plan", "Perfil"] {
                XCTAssertTrue(app.buttons[title].firstMatch.exists, "Falta la pestaña '\(title)'")
            }
            XCTAssertFalse(app.buttons["Exportar"].exists, "Exportar ya no va en Hoy")
            XCTAssertFalse(app.buttons["Restricciones"].exists, "Restricciones ya no va en Hoy")
            XCTAssertFalse(app.buttons["Rehacer cuestionario"].exists, "Rehacer ya no va en Hoy")
        }

        step("Hoy lista los ejercicios de la sesión (testTodayListsTheExercisesOfTheSession)") {
            let exercises = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'today.exercise.'")
            )
            XCTAssertGreaterThan(exercises.count, 0, "Hoy debe listar los ejercicios de la sesión")
        }

        try step("La sesión de 60 min tiene volumen realista (testTodaySessionHasRealisticVolume)") {
            let summary = element(app, "today.sessionSummary")
            XCTAssertTrue(summary.appears(within: 15))
            let digits = summary.label.prefix { $0.isNumber }
            let sets = try XCTUnwrap(Int(digits), "No se pudo leer el número de series de '\(summary.label)'")
            XCTAssertLessThanOrEqual(sets, 30, "Una sesión de 60 min no puede tener \(sets) series")
        }

        // SCRUM-211: reordenar en Hoy cambia el orden, "¿Por qué este orden?" dice que es
        // tuyo y "Volver al orden recomendado" lo restablece.
        step("Reordenar cambia el orden, dice que es tuyo y se restablece (testReorderTodayExercisesAndReset)") {
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            // En iPhone la segunda fila puede quedar abajo: se desliza Hoy (SCRUM-222: todo se
            // desplaza junto, también con "¿Cómo dormiste?" a la vista).
            let firstName = element(app, "today.exercise.0").label
            let secondName = scrollTo(app, "today.exercise.1", within: "today.content").label
            XCTAssertNotEqual(firstName, secondName)

            tap(app, "today.reorder")
            tap(app, "reorder.down.0")
            tap(app, "reorder.save")
            XCTAssertTrue(element(app, "today.start").appears(within: 10))
            XCTAssertEqual(
                scrollTo(app, "today.exercise.0", within: "today.content", upwards: true).label, secondName,
                "El segundo pasa al primer lugar"
            )
            XCTAssertEqual(scrollTo(app, "today.exercise.1", within: "today.content").label, firstName)

            tap(app, "today.whyOrder")
            XCTAssertTrue(element(app, "order.custom").appears(within: 5), "Dice que el orden es tuyo")
            app.buttons["Listo"].firstMatch.tap()

            tap(app, "today.reorder")
            tap(app, "reorder.reset")
            XCTAssertTrue(element(app, "today.start").appears(within: 10))
            XCTAssertEqual(
                scrollTo(app, "today.exercise.0", within: "today.content", upwards: true).label, firstName,
                "Vuelve al recomendado"
            )
        }

        // La tira de la semana en Hoy abre el detalle del día tocado. Se relanza: Hoy arriba.
        step("La tira de la semana abre el día tocado (testTodayWeekStripOpensTheDay)") {
            let app = launch(storeID: storeID)
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            XCTAssertTrue(element(app, "week.strip.monday").exists)
            tap(app, "week.strip.friday")
            XCTAssertTrue(element(app, "day.detail").appears(within: 10))
        }

        // SCRUM-197: lunes, miércoles y viernes (hoy es lunes): la semana alterna sesión y
        // descanso, el CTA sólo está en hoy y el detalle de otro día no deja empezar. Se
        // relanza: el paso anterior dejó abierto el detalle de un día.
        step("Plan muestra la semana con descanso entre sesiones; sólo se empieza hoy (testPlanShowsTheWeekWithRestBetweenSessions)") {
            let app = launch(storeID: storeID)
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            openTab(app, "Plan")
            for day in Self.weekdays {
                XCTAssertTrue(element(app, "week.day.\(day)").appears(within: 10), "Falta el día '\(day)'")
            }
            XCTAssertTrue(element(app, "week.start").exists, "Hoy (lunes) debe tener Empezar")
            tap(app, "week.day.wednesday")
            XCTAssertTrue(element(app, "day.detail").appears(within: 10))
            XCTAssertTrue(element(app, "day.exercise.0").exists, "El detalle lista los ejercicios")
            XCTAssertFalse(element(app, "day.start").exists, "Sólo se empieza el día de hoy")
        }

        // SCRUM-203: en un día de entrenamiento Hoy pregunta cómo dormiste; "Dormí mal"
        // aligera el día y lo explica; no se vuelve a preguntar. Va al final: cambia el día.
        step("'Dormí mal' aligera el día, lo explica y no se vuelve a preguntar (testSleepCheckInMakesTheDayLighter)") {
            let app = launch(storeID: storeID)
            XCTAssertTrue(element(app, "today.start").appears(within: 15))
            XCTAssertTrue(element(app, "today.sleep").appears(within: 5), "Debe preguntar cómo dormiste")
            tap(app, "today.sleep.poor")
            XCTAssertTrue(element(app, "today.readiness").appears(within: 5), "Debe explicar el ajuste del día")
            XCTAssertFalse(element(app, "today.sleep").exists, "No vuelve a preguntar hoy")
            XCTAssertTrue(element(app, "today.start").exists, "Se puede entrenar igual")
        }
    }
}
