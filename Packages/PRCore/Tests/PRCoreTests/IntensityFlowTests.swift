//
//  IntensityFlowTests.swift
//  PRCoreTests
//
//  SCRUM-200: el RIR de cada ejercicio lo pone el planificador según su tipo, y Hoy y el
//  entrenamiento muestran ese RIR y si conviene dropset (sólo en la última serie).
//

import Foundation
import Testing
import PRCore
import PRDomain

@MainActor
private func mondayPlan(experience: ExperienceLevel) throws -> (TodayPlan, ExerciseCatalog) {
    let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    let catalog = try ExerciseCatalogLoader.loadBundled()
    let coordinator = TodayPlanCoordinator(catalog: catalog, clock: { monday }, timeZone: { timeZone })
    let profile = OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: experience,
        trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced,
        defaultGymID: nil, restrictions: []
    )
    #expect(coordinator.load(profile: profile))
    return (try #require(coordinator.plan), catalog)
}

@Suite("Intensidad en el plan, en Hoy y en el entrenamiento (SCRUM-200)")
struct IntensityFlowTests {
    private let advisor = IntensityAdvisor()

    @MainActor
    @Test("El planificador pone a cada serie de trabajo el RIR del tipo de su ejercicio")
    func plannerUsesRIRByExercise() throws {
        let (plan, catalog) = try mondayPlan(experience: .intermediate)
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let template = try #require(plan.todayTemplate)
        let workSets = template.plannedSets.filter { !$0.prescription.isWarmup }
        #expect(!workSets.isEmpty)
        for planned in workSets {
            let exercise = try #require(byID[planned.exerciseID])
            #expect(planned.prescription.targetRIR == advisor.targetRIR(for: exercise))
        }
    }

    @MainActor
    @Test("Hoy muestra el RIR del motor y el consejo de dropset para la persona")
    func todayLinesCarryIntensity() throws {
        let (plan, catalog) = try mondayPlan(experience: .intermediate)
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(!plan.todayExercises.isEmpty)
        for line in plan.todayExercises {
            let exercise = try #require(byID[line.exerciseID])
            #expect(line.targetRIR == advisor.targetRIR(for: exercise))
            #expect(line.dropset == advisor.advice(for: exercise, experience: .intermediate).dropset)
        }
    }

    @MainActor
    @Test("Para un principiante ningún ejercicio sugiere dropset")
    func beginnerNeverGetsDropset() throws {
        let (plan, _) = try mondayPlan(experience: .beginner)
        #expect(!plan.todayExercises.isEmpty)
        #expect(plan.todayExercises.allSatisfy { $0.dropset == .notRecommended(.experience) })
    }

    @MainActor
    @Test("En el entrenamiento: RIR en las series de trabajo y dropset sólo en la última de cada ejercicio")
    func activeSetShowsDropsetOnlyOnLastWorkSet() throws {
        let curl = ExerciseID()
        let press = ExerciseID()
        let warmup = try SetPrescription(targetRepRange: 10...12, restSeconds: 60...60, isWarmup: true)
        let work = try SetPrescription(targetRepRange: 8...12, targetRIR: 0...1, restSeconds: 60...90)
        let template = SessionTemplate(title: "Pull", plannedSets: [
            PlannedSet(exerciseID: curl, prescription: warmup),
            PlannedSet(exerciseID: curl, prescription: work),
            PlannedSet(exerciseID: curl, prescription: work),
            PlannedSet(exerciseID: press, prescription: work),
        ])
        let coordinator = WorkoutSessionCoordinator(
            template: template,
            dropsetAdvice: [curl: .recommendedOnLastSet, press: .notRecommended(.heavyFreeBarbell)]
        )
        _ = coordinator.start()

        var seen: [(rir: ClosedRange<Int>?, dropset: DropsetAdvice?)] = []
        while let set = coordinator.currentSet() {
            seen.append((set.targetRIR, set.dropset))
            _ = try coordinator.completeCurrentSet()
        }
        #expect(seen.count == 4)
        #expect(seen[0].rir == nil && seen[0].dropset == nil, "Calentamiento: sin RIR ni dropset")
        #expect(seen[1].rir == 0...1 && seen[1].dropset == nil, "Primera de trabajo: RIR, aún sin dropset")
        #expect(seen[2].dropset == .recommendedOnLastSet, "Última serie de trabajo del curl")
        #expect(seen[3].dropset == .notRecommended(.heavyFreeBarbell), "Única serie del press: es la última")
    }

    @Test("Textos: RIR y consejo de dropset con su motivo")
    func texts() {
        let spanish = TrainingVocabularyPresenter(locale: Locale(identifier: "es_MX"))
        #expect(spanish.rir(2...2) == "RIR 2")
        #expect(spanish.rir(1...2) == "RIR 1–2")
        #expect(spanish.dropsetTitle(.recommendedOnLastSet) == "Ideal para dropset")
        #expect(spanish.dropsetDetail(.recommendedOnLastSet) == "Sólo en la última serie")
        #expect(spanish.dropsetTitle(.notRecommended(.heavyFreeBarbell)) == "Sin dropset")
        #expect(spanish.dropsetDetail(.notRecommended(.heavyFreeBarbell)) == "Barra libre pesada")
        for blocker in DropsetBlocker.allCases {
            #expect(!spanish.dropsetDetail(.notRecommended(blocker)).isEmpty)
        }
    }
}
