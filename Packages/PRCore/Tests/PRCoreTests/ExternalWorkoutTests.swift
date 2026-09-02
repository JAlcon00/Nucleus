//
//  ExternalWorkoutTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de consulta de workouts externos (PR-1104): importa metadata autorizada,
//  NO inventa set data (promptMaster §14.1) y permite vincular el workout del día al
//  plan por sugerencia o manualmente. HealthKit real queda detrás del protocolo.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("External workouts query (PR-1104)")
struct ExternalWorkoutTests {

    private func makeExternal(start: Date, end: Date, kcal: Double? = 120) -> ExternalWorkout {
        ExternalWorkout(
            referenceID: HealthWorkoutHandle.ID(),
            start: start,
            end: end,
            activityType: .strengthTraining,
            activeKilocalories: kcal,
            sourceName: "Apple Watch",
            deviceName: "Watch"
        )
    }

    private func template(_ title: String) -> SessionTemplate {
        SessionTemplate(id: UUID(), title: title, plannedSets: [], estimatedMinutes: nil)
    }

    // 1. Importa metadata autorizada: devuelve workouts dentro de la consulta.
    @Test("Importa metadata autorizada del intervalo consultado")
    func importsAuthorizedMetadata() async {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(initialStatus: [.workout: .granted]),
            externalWorkouts: [
                makeExternal(start: t, end: t.addingTimeInterval(3600)),
                makeExternal(start: t.addingTimeInterval(7200), end: t.addingTimeInterval(10800)),
            ]
        )
        // Consulta sólo la primera hora.
        let query = ExternalWorkoutQuery(since: t, until: t.addingTimeInterval(4000))
        let workouts = try! await store.recentWorkouts(in: query)
        #expect(workouts.count == 1)
        #expect(workouts[0].sourceName == "Apple Watch")
    }

    // 1b. Sin permiso .workout, no se importa metadata.
    @Test("Sin permiso .workout no se importa metadata")
    func noPermissionNoImport() async {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(),
            externalWorkouts: [makeExternal(start: t, end: t.addingTimeInterval(3600))]
        )
        // El provider por defecto tiene .notDetermined, así que no se importa.
        let query = ExternalWorkoutQuery(since: t.addingTimeInterval(-1000), until: t.addingTimeInterval(7200))
        let workouts = try! await store.recentWorkouts(in: query)
        #expect(workouts.isEmpty)
    }

    // 2. No inventa set data: el modelo de workout externo es sólo metadata (sin sets).
    @Test("El workout externo no inventa set data (sólo metadata autorizada)")
    func noSetDataInExternal() {
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600), kcal: 90)
        // Expone únicamente metadata autorizada: fecha, tipo, energía, fuente.
        #expect(workout.activityType == .strengthTraining)
        #expect(workout.activeKilocalories == 90)
        #expect(workout.energyOrigin == .measured)
        #expect(workout.sourceName == "Apple Watch")
    }

    // 3. Puede vincular el workout del día al plan por sugerencia.
    @Test("Sugiere vincular el workout del día a una plantilla candidata")
    func suggestsLinkToPlan() {
        let linker = WorkoutPlanLinker()
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let day = DayInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        let workout = makeExternal(start: dayStart.addingTimeInterval(3600), end: dayStart.addingTimeInterval(7200))
        let candidates = [template("Push Day"), template("Pull Day")]

        let suggestion = linker.suggestTemplate(for: workout, candidates: candidates, day: day)
        // Sugerencia determinista: primera candidata del día.
        #expect(suggestion == candidates[0].id)
    }

    // 3b. Fuera del día no hay sugerencia; nunca se inventa un vínculo forzado.
    @Test("Fuera del día no sugiere ninguna plantilla")
    func noSuggestionOutsideDay() {
        let linker = WorkoutPlanLinker()
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let day = DayInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        // Workout en otro día (antes del día considerado).
        let workout = makeExternal(start: dayStart.addingTimeInterval(-86_400), end: dayStart.addingTimeInterval(-82_800))

        let suggestion = linker.suggestTemplate(for: workout, candidates: [template("Push")], day: day)
        #expect(suggestion == nil)
    }

    // 3c. El vínculo manual prevalece y permite desvincular.
    @Test("El vínculo manual prevalece sobre la sugerencia y permite desvincular")
    func manualLinkOverrides() {
        let linker = WorkoutPlanLinker()
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600))
        let push = template("Push Day")

        let manual = linker.manualLink(workout, to: push.id)
        #expect(manual.templateID == push.id)
        #expect(manual.decision == .manual)

        let unlinked = linker.manualLink(workout, to: nil)
        #expect(unlinked.decision == .manual)
        #expect(unlinked.templateID == nil)
    }

    // 3d. Una sugerencia nunca se aplica sola: queda marcada como .suggestion.
    @Test("Una sugerencia nunca se aplica sola (queda marcada como suggestion)")
    func suggestionIsNotSelfApplied() {
        let linker = WorkoutPlanLinker()
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600))
        let link = linker.link(workout, to: template("Push").id, manual: false)
        #expect(link.decision == .suggestion)
    }
}