//
//  ExperienceFlowTests.swift
//  PRCoreTests
//
//  SCRUM-210 (FB-3): la experiencia va primero y decide el formulario:
//  - novato/principiante: lenguaje simple, sin "Variedad" (queda estable);
//  - intermedio: el flujo de siempre;
//  - avanzado/competitivo: lenguaje técnico y hasta 2 músculos prioritarios que el
//    motor usa como `.emphasize`.
//  Los textos cambian por nivel y el RIR se explica en palabras a quien empieza.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let spanish = Locale(identifier: "es_MX")

private func draft(_ experience: ExperienceLevel, variety: VarietyPreference? = .varied, priority: Set<MuscleGroup>? = nil) -> OnboardingDraft {
    var draft = OnboardingDraft()
    var answers: [(OnboardingStep, OnboardingAnswer)] = [
        (.experience, .experience(experience)),
        (.goal, .goal(.hypertrophy)),
        (.phase, .phase(.maintenance)),
        (.daysPerWeek, .trainingDays([.monday, .tuesday, .thursday, .friday])),
        (.sessionMinutes, .sessionMinutes(75)),
    ]
    if let variety { answers.append((.variety, .variety(variety))) }
    if let priority { answers.append((.priorityMuscles, .priorityMuscles(priority))) }
    for (step, answer) in answers { draft = draft.settingAnswer(answer, for: step) }
    return draft
}

@Suite("Formulario según la experiencia (SCRUM-210)")
struct ExperienceFlowTests {

    @Test("Pasos por nivel: guiado sin variedad, estándar igual, experto con prioritarios")
    func stepsPerLevel() {
        let guided: [OnboardingStep] = [.experience, .goal, .phase, .daysPerWeek, .sessionMinutes, .restrictions]
        let standard: [OnboardingStep] = [.experience, .goal, .phase, .daysPerWeek, .sessionMinutes, .variety, .restrictions]
        let expert: [OnboardingStep] = [.experience, .goal, .phase, .daysPerWeek, .sessionMinutes, .variety, .priorityMuscles, .restrictions]
        #expect(OnboardingFlowPolicy.steps(for: .novice) == guided)
        #expect(OnboardingFlowPolicy.steps(for: .beginner) == guided)
        #expect(OnboardingFlowPolicy.steps(for: .intermediate) == standard)
        #expect(OnboardingFlowPolicy.steps(for: .advanced) == expert)
        #expect(OnboardingFlowPolicy.steps(for: .competitive) == expert)
        #expect(OnboardingFlowPolicy.steps(for: nil) == standard, "Antes de elegir: el flujo estándar")
    }

    @Test("Elegir la experiencia cambia los pasos que siguen (y se puede volver a cambiar)")
    func choosingExperienceUpdatesFlow() {
        var flow = OnboardingFlowController()
        #expect(flow.currentStep == .experience)
        flow = flow.answering(.experience(.beginner))
        #expect(flow.stepCount == 6)
        #expect(flow.audience == .guided)
        flow = flow.answering(.experience(.advanced))
        #expect(flow.stepCount == 8)
        #expect(flow.audience == .expert)
        #expect(flow.currentStep == .experience, "Cambiar de nivel no mueve el paso actual")
    }

    @Test("Novato: no se pregunta variedad y queda estable aunque el borrador traiga otra")
    func guidedDefaults() throws {
        let profile = try OnboardingProfileBuilder().build(from: draft(.novice, variety: .varied, priority: [.chest]))
        #expect(profile.varietyPreference == .stable)
        #expect(profile.priorityMuscles.isEmpty, "Los prioritarios son sólo para avanzados")
        let noVariety = try OnboardingProfileBuilder().build(from: draft(.beginner, variety: nil))
        #expect(noVariety.varietyPreference == OnboardingFlowPolicy.guidedVariety)
    }

    @Test("Intermedio: la variedad es obligatoria como siempre")
    func standardNeedsVariety() {
        #expect(throws: OnboardingProfileBuilder.BuildError.missingAnswer(.variety)) {
            _ = try OnboardingProfileBuilder().build(from: draft(.intermediate, variety: nil))
        }
    }

    @Test("Avanzado: hasta 2 prioritarios; 3 no deja continuar ni construir")
    func expertPriorityLimit() throws {
        let profile = try OnboardingProfileBuilder().build(from: draft(.advanced, priority: [.glutes, .back]))
        #expect(profile.priorityMuscles == [.back, .glutes], "Orden estable")
        let three = OnboardingAnswer.priorityMuscles([.chest, .back, .glutes])
        #expect(three.isValid == false)
        #expect(throws: OnboardingProfileBuilder.BuildError.tooManyPriorityMuscles(2)) {
            _ = try OnboardingProfileBuilder().build(from: draft(.advanced, priority: [.chest, .back, .glutes]))
        }
    }

    @Test("Los prioritarios del avanzado llegan al motor como énfasis")
    func priorityReachesEngine() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let planner = TodayPlanBuilder.defaultPlanner()
        let profile = try OnboardingProfileBuilder().build(from: draft(.advanced, priority: [.glutes]))
        let block = try TodayPlanBuilder().generate(profile: profile, catalog: catalog, planner: planner).block
        #expect(block.priorities.first { $0.muscleGroupID == .glutes }?.priority == .emphasize)
        #expect(block.priorities.first { $0.muscleGroupID == .chest }?.priority == .normal)
        #expect(profile.trainingFields.priorityMuscles == [.glutes], "Cambiar prioritarios cambia el plan")
    }

    @Test("Un perfil anterior (sin prioritarios) se lee igual y se guarda igual")
    func legacyProfileWithoutPriority() throws {
        let old = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .advanced,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        let data = try JSONEncoder().encode(old)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["priorityMuscles"] == nil, "Vacío no se escribe")
        #expect(try JSONDecoder().decode(OnboardingProfile.self, from: data).priorityMuscles.isEmpty)
    }

    @Test("Los textos cambian por nivel: simple para quien empieza, técnico para el avanzado")
    func copyChangesByLevel() {
        let guided = OnboardingCopy(locale: spanish, audience: .guided)
        let standard = OnboardingCopy(locale: spanish, audience: .standard)
        let expert = OnboardingCopy(locale: spanish, audience: .expert)
        #expect(guided.title(for: .goal) != expert.title(for: .goal))
        #expect(guided.subtitle(for: .phase) != expert.subtitle(for: .phase))
        #expect(standard.title(for: .phase) == "Fase")
        #expect(expert.title(for: .priorityMuscles) == "Músculos prioritarios")

        let guidedPhase = OnboardingChoicePresenter(locale: spanish, audience: .guided).choices(for: .phase).map(\.label)
        let expertPhase = OnboardingChoicePresenter(locale: spanish, audience: .expert).choices(for: .phase).map(\.label)
        #expect(guidedPhase.contains("Como normal"))
        #expect(expertPhase.contains("Déficit calórico (definición)"))
        #expect(!guidedPhase.contains { $0.contains("calórico") }, "Sin jerga para quien empieza")
    }

    @Test("El RIR se explica en palabras a quien empieza; técnico para el resto")
    func rirByAudience() {
        #expect(TrainingVocabularyPresenter(locale: spanish, audience: .guided).rir(1...2) == "Deja 1–2 reps en reserva")
        #expect(TrainingVocabularyPresenter(locale: spanish, audience: .guided).rir(2...2) == "Deja 2 reps en reserva")
        #expect(TrainingVocabularyPresenter(locale: spanish, audience: .expert).rir(1...2) == "RIR 1–2")
        #expect(TrainingVocabularyPresenter(locale: spanish).rir(2...2) == "RIR 2")
    }
}
