//
//  OnboardingCoordinatorTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del coordinador de app del onboarding (EPIC-04 wiring, PR-0401 + PR-0402):
//  auth-gate con fake provider, navegación por pasos preservando respuestas e
//  finalización con `OnboardingProfileBuilder`. No se usa AuthenticationServices real
//  ni HealthKit (el login no lo requiere, RF-0401/PR-0401).
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Onboarding coordinator (EPIC-04)")
@MainActor
struct OnboardingCoordinatorTests {

    private func makeCoordinator(
        authBehavior: FakeAppleIDAuthProvider.FakeAuthBehavior = .success(userIdentifier: "apple-user")
    ) -> OnboardingCoordinator {
        OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider(behavior: authBehavior))
    }

    @Test("Empieza en signedOut hasta que hay login")
    func startsSignedOut() {
        let coordinator = makeCoordinator()
        #expect(coordinator.phase == .signedOut)
    }

    @Test("Login exitoso entra al onboarding en el primer paso")
    func signInEntersOnboardingAtFirstStep() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()
        guard case .onboarding(let step, let index, _, _, _) = coordinator.phase else {
            Issue.record("Debía estar en onboarding, estaba \(coordinator.phase)")
            return
        }
        #expect(step == .goal)
        #expect(index == 0)
    }

    @Test("Cancelación de auth no es un error: vuelve a signedOut")
    func cancelReturnsToSignedOut() async {
        let coordinator = makeCoordinator(authBehavior: .cancel)
        await coordinator.signIn()
        #expect(coordinator.phase == .signedOut)
    }

    @Test("Fallo de auth expone el mensaje a la UI")
    func failureExposesMessage() async {
        let coordinator = makeCoordinator(authBehavior: .fail("Apple no disponible"))
        await coordinator.signIn()
        guard case .failed(let message) = coordinator.phase else {
            Issue.record("Debía fallar, estaba \(coordinator.phase)")
            return
        }
        #expect(message == "Apple no disponible")
    }

    @Test("Responder el paso habilita avanzar")
    func answeringEnablesAdvance() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()

        coordinator.select(.goal(.hypertrophy))
        guard case .onboarding(_, _, let canGoBack, let canAdvance, _) = coordinator.phase else {
            return
        }
        #expect(canAdvance)
        #expect(!canGoBack)
    }

    @Test("Avanzar mueve al siguiente paso y habilita volver atrás")
    func advanceMovesAndEnablesBack() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()

        coordinator.select(.goal(.hypertrophy))
        coordinator.advance()

        guard case .onboarding(let step, _, let canGoBack, let canAdvance, _) = coordinator.phase else {
            return
        }
        #expect(step == .phase)
        #expect(canGoBack)
        #expect(!canAdvance) // phase aún sin responder
    }

    @Test("Volver atrás conserva la respuesta ya dada")
    func goBackPreservesPreviousAnswer() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()

        coordinator.select(.goal(.hypertrophy))
        coordinator.advance()
        coordinator.goBack()

        guard case .onboarding(let step, _, _, let canAdvance, _) = coordinator.phase else {
            return
        }
        #expect(step == .goal)
        #expect(canAdvance) // el goal sigue respondido
    }

    @Test("Completar produce el perfil mínimo con las respuestas dadas")
    func completeBuildsProfile() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()

        // Respondemos cada paso en orden (gym/restrictions opcionales: nil/vacío).
        let answers: [OnboardingAnswer] = [
            .goal(.hypertrophy),
            .phase(.surplus),
            .experience(.intermediate),
            .daysPerWeek(4),
            .sessionMinutes(60),
            .gym(nil),
            .variety(.balanced),
            .restrictions([]),
        ]
        for answer in answers {
            coordinator.select(answer)
            if case .onboarding(_, _, _, _, let isAtEnd) = coordinator.phase, !isAtEnd {
                coordinator.advance()
            }
        }

        coordinator.complete()

        guard case .completed(let profile) = coordinator.phase else {
            Issue.record("Debía completarse, estaba \(coordinator.phase)")
            return
        }
        #expect(profile.goal == .hypertrophy)
        #expect(profile.phase == .surplus)
        #expect(profile.experience == .intermediate)
        #expect(profile.trainingDaysPerWeek == 4)
        #expect(profile.usualSessionMinutes == 60)
        #expect(profile.varietyPreference == .balanced)
    }

    @Test("Completar sin respond pasado obligatorio falla sin inventar respuestas")
    func completeFailsWithoutInventingAnswers() async {
        let coordinator = makeCoordinator()
        await coordinator.signIn()

        // Saltamos el paso de days/session: incomplete → build falla.
        coordinator.complete()

        guard case .failed = coordinator.phase else {
            Issue.record("Un borrador incompleto no debe completar, estaba \(coordinator.phase)")
            return
        }
    }

    @Test("dismissFailure tras fallo de auth vuelve al gate")
    func dismissFailureReturnsToGate() async {
        let coordinator = makeCoordinator(authBehavior: .fail("boom"))
        await coordinator.signIn()
        #expect(coordinator.phase != .signedOut)

        coordinator.dismissFailure()
        #expect(coordinator.phase == .signedOut)
    }

    @Test("El flujo no requiere HealthKit (no referencia tipos Health en el ciclo de vida)")
    func doesNotRequireHealthKit() async {
        // El ciclo de vida del onboarding sólo toca auth + dominio; este test documenta
        // que la composición arranca sin ningún HealthStore.
        let coordinator = makeCoordinator()
        await coordinator.signIn()
        guard case .onboarding = coordinator.phase else {
            Issue.record("Debía iniciar onboarding sin HealthKit")
            return
        }
    }
}