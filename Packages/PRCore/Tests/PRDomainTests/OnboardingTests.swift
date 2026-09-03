import Testing
import Foundation
@testable import PRDomain

@Suite("Onboarding profile flow (PR-0402)")
struct OnboardingTests {

    // MARK: - Fixtures

    /// Borrador completo y válido (novice hypertrophy, definición, 3 días, 60 min).
    private func completeDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft = draft.settingAnswer(.goal(.hypertrophy), for: .goal)
        draft = draft.settingAnswer(.phase(.deficit), for: .phase)
        draft = draft.settingAnswer(.experience(.novice), for: .experience)
        draft = draft.settingAnswer(.daysPerWeek(3), for: .daysPerWeek)
        draft = draft.settingAnswer(.sessionMinutes(60), for: .sessionMinutes)
        draft = draft.settingAnswer(.variety(.balanced), for: .variety)
        return draft
    }

    // MARK: - Builder / validación

    @Test("borrador completo produce un OnboardingProfile válido con todos los campos")
    func completeDraftBuildsProfile() throws {
        let draft = completeDraft()
        let profile = try OnboardingProfileBuilder().build(from: draft)

        #expect(profile.goal == .hypertrophy)
        #expect(profile.phase == .deficit)
        #expect(profile.experience == .novice)
        #expect(profile.trainingDaysPerWeek == 3)
        #expect(profile.usualSessionMinutes == 60)
        #expect(profile.varietyPreference == .balanced)
        // gym y restrictions opcionales quedan vacíos por defecto.
        #expect(profile.defaultGymID == nil)
        #expect(profile.restrictions.isEmpty)
    }

    @Test("validación 2...7 días: 1 y 8 lanzan error")
    func daysOutOfRangeThrows() throws {
        for invalidDays in [1, 8] {
            var draft = completeDraft()
            draft = draft.settingAnswer(.daysPerWeek(invalidDays), for: .daysPerWeek)
            #expect(throws: OnboardingProfileBuilder.BuildError.invalidTrainingDays(invalidDays)) {
                _ = try OnboardingProfileBuilder().build(from: draft)
            }
        }
    }

    @Test("validación 20...240 minutos: 10 y 300 lanzan error")
    func minutesOutOfRangeThrows() throws {
        for invalidMinutes in [10, 300] {
            var draft = completeDraft()
            draft = draft.settingAnswer(.sessionMinutes(invalidMinutes), for: .sessionMinutes)
            #expect(throws: OnboardingProfileBuilder.BuildError.invalidSessionMinutes(invalidMinutes)) {
                _ = try OnboardingProfileBuilder().build(from: draft)
            }
        }
    }

    @Test("días límite válidos (2 y 7) aceptados; minutos límite (20 y 240) aceptados")
    func boundaryValuesAccepted() throws {
        for days in [2, 7] {
            var draft = completeDraft()
            draft = draft.settingAnswer(.daysPerWeek(days), for: .daysPerWeek)
            let profile = try OnboardingProfileBuilder().build(from: draft)
            #expect(profile.trainingDaysPerWeek == days)
        }
        for minutes in [20, 240] {
            var draft = completeDraft()
            draft = draft.settingAnswer(.sessionMinutes(minutes), for: .sessionMinutes)
            let profile = try OnboardingProfileBuilder().build(from: draft)
            #expect(profile.usualSessionMinutes == minutes)
        }
    }

    @Test("paso obligatorio faltante: el builder NO finaliza (no inventa objetivos)")
    func missingRequiredStepThrows() {
        // Borrador sin el paso goal.
        let draft = completeDraft().settingAnswer(nilRemoving: .goal)
        #expect(throws: OnboardingProfileBuilder.BuildError.missingAnswer(.goal)) {
            _ = try OnboardingProfileBuilder().build(from: draft)
        }
    }

    @Test("gym y restricciones opcionales se propagan al perfil cuando se definen")
    func optionalGymAndRestrictionsPropagate() throws {
        let gymID = GymID()
        let restriction = TrainingRestriction(bodyRegion: .shoulder, side: .left)
        var draft = completeDraft()
        draft = draft.settingAnswer(.gym(gymID), for: .gym)
        draft = draft.settingAnswer(.restrictions([restriction]), for: .restrictions)

        let profile = try OnboardingProfileBuilder().build(from: draft)
        #expect(profile.defaultGymID == gymID)
        #expect(profile.restrictions == [restriction])
    }

    // MARK: - Draft / back-navigation

    @Test("volver atrás NO pierde las respuestas ya dadas")
    func backNavigationPreservesAnswers() throws {
        var flow = OnboardingFlowController()
        // Avanza hasta gym respondiendo cada paso obligatorio.
        flow = flow.answering(.goal(.strength)).advance()      // → phase
        flow = flow.answering(.phase(.surplus)).advance()       // → experience
        flow = flow.answering(.experience(.advanced)).advance() // → days
        flow = flow.answering(.daysPerWeek(4)).advance()        // → session
        flow = flow.answering(.sessionMinutes(90)).advance()    // → gym
        #expect(flow.currentStep == .gym)
        #expect(flow.draft.isCompleted == false)

        // Navega atrás hasta el inicio.
        while !flow.isAtStart {
            flow = flow.goBack()
        }
        #expect(flow.currentStep == .goal)

        // Todas las respuestas sobreviven.
        #expect(flow.draft.answer(for: .goal) == .goal(.strength))
        #expect(flow.draft.answer(for: .phase) == .phase(.surplus))
        #expect(flow.draft.answer(for: .experience) == .experience(.advanced))
        #expect(flow.draft.answer(for: .daysPerWeek) == .daysPerWeek(4))
        #expect(flow.draft.answer(for: .sessionMinutes) == .sessionMinutes(90))
    }

    @Test("advance no avanza hasta que el paso obligatorio tiene respuesta")
    func advanceBlockedUntilAnswered() {
        let flow = OnboardingFlowController() // en .goal, sin respuesta
        #expect(flow.canAdvance == false)
        let advanced = flow.advance()
        #expect(advanced.currentStep == .goal) // no avanza
    }

    @Test("pasos opcionales (gym/restrictions) permiten avanzar sin respuesta")
    func optionalStepsAdvanceWithoutAnswer() throws {
        var flow = OnboardingFlowController()
        // Llega hasta gym (paso opcional) con respuestas en los obligatorios previos.
        flow = flow.answering(.goal(.generalHealth)).advance()
        flow = flow.answering(.phase(.maintenance)).advance()
        flow = flow.answering(.experience(.beginner)).advance()
        flow = flow.answering(.daysPerWeek(5)).advance()
        flow = flow.answering(.sessionMinutes(45)).advance()
        // gym permite avanzar sin responder (opcional).
        #expect(flow.currentStep == .gym)
        #expect(flow.canAdvance == true)
        let advanced = flow.advance()
        #expect(advanced.currentStep == .variety)
    }

    @Test("el flujo se completa sólo en el último paso con los obligatorios respondidos")
    func flowCompleteOnlyAtEnd() throws {
        var flow = OnboardingFlowController()
        // Responde todo (gym/restrictions opcionales → se avanza sin responderlos).
        flow = flow.answering(.goal(.bodybuilding)).advance()   // → phase
        flow = flow.answering(.phase(.surplus)).advance()        // → experience
        flow = flow.answering(.experience(.intermediate)).advance() // → days
        flow = flow.answering(.daysPerWeek(6)).advance()         // → session
        flow = flow.answering(.sessionMinutes(120)).advance()    // → gym
        flow = flow.advance()                                    // gym opcional → variety
        flow = flow.answering(.variety(.varied)).advance()       // → restrictions
        #expect(flow.currentStep == .restrictions)
        #expect(flow.isAtEnd == true)
        #expect(flow.isFlowComplete == true)

        let profile = try OnboardingProfileBuilder().build(from: flow.draft)
        #expect(profile.goal == .bodybuilding)
        #expect(profile.trainingDaysPerWeek == 6)
        #expect(profile.usualSessionMinutes == 120)
    }

    @Test("goBack en el primer paso no hace nada; advance en el último no hace nada")
    func boundsRespected() throws {
        let first = OnboardingFlowController()
        #expect(first.goBack().currentStep == .goal) // sin cambio

        var end = OnboardingFlowController()
        // Llena hasta el último paso con respuestas.
        end = end.answering(.goal(.recomposition)).advance()      // → phase
        end = end.answering(.phase(.maintenance)).advance()       // → experience
        end = end.answering(.experience(.competitive)).advance()  // → days
        end = end.answering(.daysPerWeek(2)).advance()            // → session
        end = end.answering(.sessionMinutes(30)).advance()        // → gym
        end = end.advance()                                       // gym opcional → variety
        end = end.answering(.variety(.stable)).advance()          // → restrictions
        #expect(end.currentStep == .restrictions)
        let same = end.advance()
        #expect(same.currentStep == .restrictions) // no sale del rango
    }
}

// MARK: - Helper (borra una respuesta; sólo para simular el caso faltante)

private extension OnboardingDraft {
    func settingAnswer(nilRemoving step: OnboardingStep) -> OnboardingDraft {
        OnboardingDraft(answers: answers.filter { $0.key != step })
    }
}