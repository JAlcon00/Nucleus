//
//  ExerciseKindTests.swift
//  PRCoreTests
//
//  Hoy y el detalle del día dicen si cada ejercicio es compuesto o aislado (según el
//  catálogo, nunca adivinado) y escriben series y repeticiones con su palabra.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Tipo de ejercicio y series × reps explícitas")
struct ExerciseKindTests {

    @MainActor
    @Test("Cada ejercicio de Hoy trae su tipo del catálogo y la sesión mezcla compuestos y aislados")
    func todayLinesCarryCatalogJointClass() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let coordinator = TodayPlanCoordinator(catalog: catalog, clock: { monday }, timeZone: { timeZone })
        let profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced,
            defaultGymID: nil, restrictions: []
        )
        #expect(coordinator.load(profile: profile))
        let lines = try #require(coordinator.plan?.todayExercises)
        #expect(!lines.isEmpty)

        let byID = Dictionary(catalog.exercises.map { ($0.id, $0.jointClass) }, uniquingKeysWith: { first, _ in first })
        for line in lines {
            #expect(line.jointClass == byID[line.exerciseID], "El tipo sale del catálogo")
        }
        #expect(lines.contains { $0.jointClass == .multiJoint }, "Una sesión real trae al menos un compuesto")
    }

    @Test("Un ejercicio que ya no está en el catálogo queda sin tipo (no se inventa)")
    func unknownExerciseHasNoKind() {
        let line = TodayExerciseLine(exerciseID: ExerciseID(), name: nil, setCount: 3)
        #expect(line.jointClass == nil)
    }

    @Test("Textos: compuesto o aislado, series y repeticiones con su palabra")
    func texts() {
        let spanish = TrainingVocabularyPresenter(locale: Locale(identifier: "es_MX"))
        #expect(spanish.exerciseKind(.multiJoint) == "Compuesto")
        #expect(spanish.exerciseKind(.singleJoint) == "Aislado")
        #expect(spanish.workSets(1) == "1 serie")
        #expect(spanish.workSets(3) == "3 series")
        #expect(spanish.reps(8...12) == "8–12 reps")
        #expect(spanish.reps(10...10) == "10 reps")
    }
}
