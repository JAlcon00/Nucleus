//
//  OnboardingCoordinator.swift
//  PRCore
//
//  Created by PR.
//
//  Coordinador de app del onboarding (EPIC-04, PR-0401 + PR-0402 wiring).
//  Orquesta `AppleIDAuthCoordinator` (Sign in with Apple) y el motor de dominio
//  `OnboardingFlowController`/`OnboardingProfileBuilder` (PRDomain) detrás de un
//  único estado observable que la UI renderiza. No contiene reglas de negocio:
//  delega en los engines; sólo conserva el paso de navegación y las respuestas.
//  No persiste el credential token de forma insegura (RF-0401) y el flujo no
//  requiere HealthKit. Este tipo es app-core y por tanto testeable en `PRCoreTests`
//  con el `FakeAppleIDAuthProvider` (nunca AuthenticationServices real).
//

import Foundation
import Observation
import PRDomain

/// Fase observable del flujo onboarding (auth-gate + pasos + perfil final).
public enum OnboardingPhase: Equatable {
    /// El usuario aún no ha iniciado sesión (mostrar Sign in with Apple).
    case signedOut
    /// Flujo de Sign in with Apple en curso.
    case signingIn
    /// El usuario está completando el onboarding. Expone el paso actual y la
    /// navegación posible; `canAdvance` refleja si el paso obligatorio está respondido.
    case onboarding(step: OnboardingStep, index: Int, canGoBack: Bool, canAdvance: Bool, isAtEnd: Bool)
    /// Onboarding completado con el perfil mínimo construido.
    case completed(OnboardingProfile)
    /// Último intento fallido (error de auth o de finalización del perfil).
    case failed(String)
}

/// Coordinador de app del onboarding.
///
/// Composición: posee un `AppleIDAuthCoordinator` (proveedor inyectado; el caller de
/// la app elige el provider real o un fake) y el `OnboardingFlowController` de dominio.
/// La UI envía intents (`signIn`, `select`, `advance`, `goBack`, `complete`) y este
/// tipo de app-core actualiza `phase`; nunca hay reglas de negocio en las Views.
@MainActor
@Observable
public final class OnboardingCoordinator {
    /// Coordinador de auth subyacente (Sign in with Apple).
    public let auth: AppleIDAuthCoordinator
    /// Motor de dominio de navegación/respuestas del onboarding (value semántico).
    public private(set) var flowController: OnboardingFlowController
    /// Builder que convierte el borrador completo en `OnboardingProfile` (PR-0402).
    public let builder: OnboardingProfileBuilder

    /// Fase actual visible por la UI.
    public private(set) var phase: OnboardingPhase = .signedOut

    public init(
        authProvider: (any AppleIDAuthProviding)? = nil,
        auth: AppleIDAuthCoordinator? = nil,
        flowController: OnboardingFlowController = OnboardingFlowController(),
        builder: OnboardingProfileBuilder = OnboardingProfileBuilder()
    ) {
        if let auth {
            self.auth = auth
        } else {
            self.auth = AppleIDAuthCoordinator(provider: authProvider ?? FakeAppleIDAuthProvider())
        }
        self.flowController = flowController
        self.builder = builder
    }

    // MARK: - Intents

    /// Inicia el flujo de Sign in with Apple. En éxito entra al primer paso del
    /// onboarding; cancelado vuelve a `.signedOut`; fallo expone `.failed`.
    public func signIn() async {
        phase = .signingIn
        await auth.signIn()

        switch auth.flowState {
        case .signedIn:
            phase = onboardingPhase(for: flowController)
        case .idle:
            // Auth cancelada por el usuario: no es un error, volvemos al gate.
            phase = .signedOut
        case .failed(let message):
            phase = .failed(message)
        case .authenticating:
            phase = .signingIn
        }
    }

    /// Registra la respuesta del paso actual en el flow controller de dominio.
    public func select(_ answer: OnboardingAnswer) {
        flowController = flowController.answering(answer)
        phase = onboardingPhase(for: flowController)
    }

    /// Avanza al siguiente paso si el actual está válidamente respondido.
    public func advance() {
        flowController = flowController.advance()
        phase = onboardingPhase(for: flowController)
    }

    /// Retrocede un paso conservando todas las respuestas ya dadas.
    public func goBack() {
        flowController = flowController.goBack()
        phase = onboardingPhase(for: flowController)
    }

    /// Finaliza el onboarding construyendo el perfil mínimo. Falla si quedan pasos
    /// obligatorios sin responder o los valores son inválidos (no inventa respuestas).
    public func complete() {
        do {
            let profile = try builder.build(from: flowController.draft)
            phase = .completed(profile)
        } catch {
            phase = .failed("No se pudo completar el perfil: \(localizedDescription(of: error))")
        }
    }

    /// Restablece el error mostrado y devuelve la UI a su estado coherente.
    public func dismissFailure() {
        // Según de dónde venga el fallo, regresamos al gate o al paso actual.
        if case .failed = phase, auth.profile == nil {
            phase = .signedOut
        } else {
            phase = onboardingPhase(for: flowController)
        }
    }

    // MARK: - Projection

    /// Deriva `OnboardingPhase.onboarding` desde el flow controller de dominio.
    private func onboardingPhase(for controller: OnboardingFlowController) -> OnboardingPhase {
        .onboarding(
            step: controller.currentStep,
            index: controller.currentIndex,
            canGoBack: !controller.isAtStart,
            canAdvance: controller.canAdvance,
            isAtEnd: controller.isAtEnd
        )
    }

    /// Mensaje legible del error de build de dominio (map infra → uso, sin filtrar
    /// detalles internos a la UI).
    private func localizedDescription(of error: Error) -> String {
        guard let buildError = error as? OnboardingProfileBuilder.BuildError else {
            return "Hubo un problema al completar el perfil."
        }
        switch buildError {
        case .missingAnswer(let step):
            return "Falta responder \(step.rawValue)."
        case .invalidTrainingDays(let days):
            return "\(days) días no está en el rango permitido (2...7)."
        case .invalidSessionMinutes(let minutes):
            return "\(minutes) minutos no están en el rango permitido (20...240)."
        }
    }
}