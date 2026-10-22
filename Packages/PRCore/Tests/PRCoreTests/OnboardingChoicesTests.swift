//
//  OnboardingChoicesTests.swift
//  PRCoreTests
//
//  Cuestionario: opciones en español (no el nombre interno del enum), cada opción con
//  su respuesta tipada, la respuesta actual visible para marcarla y los valores por
//  defecto de días y minutos registrados al llegar al paso.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Cuestionario · opciones y valores por defecto")
struct OnboardingChoicesTests {

    private let spanish = OnboardingChoicePresenter(locale: Locale(identifier: "es_MX"))
    private let english = OnboardingChoicePresenter(locale: Locale(identifier: "en_US"))

    @Test("Objetivo: textos en español, ninguno es el nombre interno")
    func goalLabelsAreSpanish() {
        let choices = spanish.choices(for: .goal)
        #expect(choices.map(\.label) == ["Salud general", "Hipertrofia", "Fuerza", "Powerbuilding", "Recomposición", "Culturismo"])
        for choice in choices {
            #expect(choice.label.lowercased() != choice.id.lowercased() || choice.id == "powerbuilding")
        }
    }

    @Test("Cada opción lleva su respuesta tipada y un id estable")
    func answersMatchIDs() {
        let goals = spanish.choices(for: .goal)
        #expect(goals.first { $0.id == "hypertrophy" }?.answer == .goal(.hypertrophy))
        #expect(goals.first { $0.id == "generalHealth" }?.answer == .goal(.generalHealth))
        #expect(spanish.choices(for: .phase).map(\.answer).contains(.phase(.deficit)))
        #expect(spanish.choices(for: .experience).map(\.answer).contains(.experience(.competitive)))
        #expect(spanish.choices(for: .variety).map(\.answer) == [.variety(.stable), .variety(.balanced), .variety(.varied)])
    }

    @Test("Fase, experiencia y variedad también en español")
    func otherStepsAreSpanish() {
        #expect(spanish.choices(for: .phase).map(\.label) == ["Volumen (superávit)", "Definición (déficit)", "Mantenimiento", "Prefiero no decirlo"])
        #expect(spanish.choices(for: .experience).map(\.label) == ["Novato", "Principiante", "Intermedio", "Avanzado", "Competitivo"])
        #expect(spanish.choices(for: .variety).map(\.label) == ["Estable (pocos cambios)", "Equilibrada", "Variada"])
    }

    @Test("El mismo catálogo da inglés")
    func englishComesFromTheSameCatalog() {
        #expect(english.choices(for: .goal).map(\.label).prefix(3) == ["General health", "Hypertrophy", "Strength"])
    }

    @Test("Pasos que no son de elección no tienen opciones")
    func nonChoiceStepsAreEmpty() {
        for step in [OnboardingStep.daysPerWeek, .sessionMinutes, .gym, .restrictions] {
            #expect(spanish.choices(for: step).isEmpty)
        }
    }

    // MARK: - Coordinador

    @MainActor
    private func coordinatorAtDays() async -> OnboardingCoordinator {
        let coordinator = OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider())
        await coordinator.signIn()
        for answer in [OnboardingAnswer.goal(.hypertrophy), .phase(.maintenance), .experience(.intermediate)] {
            coordinator.select(answer)
            coordinator.advance()
        }
        return coordinator
    }

    @MainActor
    @Test("La opción elegida queda visible como respuesta actual")
    func currentAnswerIsExposed() async {
        let coordinator = OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider())
        await coordinator.signIn()
        #expect(coordinator.currentAnswer == nil)
        coordinator.select(.goal(.strength))
        #expect(coordinator.currentAnswer == .goal(.strength))
    }

    @MainActor
    @Test("Al llegar a días y minutos, el valor por defecto ya está registrado y se puede avanzar")
    func defaultsAreSeeded() async {
        let coordinator = await coordinatorAtDays()
        #expect(coordinator.currentAnswer == .daysPerWeek(OnboardingDefaults.trainingDaysPerWeek))
        guard case .onboarding(let step, _, _, let canAdvance, _) = coordinator.phase else {
            Issue.record("Debía estar en el cuestionario, fase \(coordinator.phase)")
            return
        }
        #expect(step == .daysPerWeek)
        #expect(canAdvance)

        coordinator.advance()
        #expect(coordinator.currentAnswer == .sessionMinutes(OnboardingDefaults.sessionMinutes))
        guard case .onboarding(_, _, _, let canAdvanceMinutes, _) = coordinator.phase else { return }
        #expect(canAdvanceMinutes)
    }

    @MainActor
    @Test("El valor por defecto no pisa una respuesta ya dada al volver atrás")
    func defaultDoesNotOverwriteAnswer() async {
        let coordinator = await coordinatorAtDays()
        coordinator.select(.daysPerWeek(3))
        coordinator.advance()
        coordinator.goBack()
        #expect(coordinator.currentAnswer == .daysPerWeek(3))
    }

    @Test("Sólo días y minutos tienen valor por defecto; el resto exige elegir")
    func onlyNumericStepsHaveDefaults() {
        #expect(OnboardingDefaults.answer(for: .daysPerWeek) == .daysPerWeek(4))
        #expect(OnboardingDefaults.answer(for: .sessionMinutes) == .sessionMinutes(60))
        for step in [OnboardingStep.goal, .phase, .experience, .variety, .gym, .restrictions] {
            #expect(OnboardingDefaults.answer(for: step) == nil)
        }
    }
}
