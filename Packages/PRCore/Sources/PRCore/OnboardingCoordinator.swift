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
    /// El perfil o el bloque guardados no se pueden leer (SCRUM-26): se ofrece rehacer el
    /// cuestionario. No se borra nada del historial.
    case planUnreadable
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

    /// "Sobre ti" (SCRUM-198): respuesta en curso. Va antes del primer paso.
    public private(set) var aboutYouAnswer = AboutYouAnswer()
    /// `true` mientras falta confirmar "Sobre ti" (la UI lo muestra antes del primer paso).
    public private(set) var needsAboutYou = false

    private let clock: () -> Date
    private let timeZone: () -> TimeZone

    public init(
        authProvider: (any AppleIDAuthProviding)? = nil,
        auth: AppleIDAuthCoordinator? = nil,
        flowController: OnboardingFlowController = OnboardingFlowController(),
        builder: OnboardingProfileBuilder = OnboardingProfileBuilder(),
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.clock = clock
        self.timeZone = timeZone
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
            needsAboutYou = true
            // Apple entrega el nombre sólo la primera vez: prellena "Sobre ti" (SCRUM-198).
            if aboutYouAnswer.name.isEmpty, let name = auth.profile?.displayName {
                aboutYouAnswer.name = name
            }
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

    // MARK: - SCRUM-26: sesión y plan recordados

    /// Entra con una sesión recordada, sin pasar por Apple. Quién es el usuario lo decide
    /// quien llama (la sesión guardada); aquí sólo se refleja en el estado.
    public func resumeSession(userIdentifier: String) {
        auth.restoreSession(userIdentifier: userIdentifier)
    }

    /// Hay un plan guardado: directo a "Hoy".
    public func showCompleted(_ profile: OnboardingProfile) {
        phase = .completed(profile)
    }

    /// No hay plan guardado: empieza el cuestionario (primero "Sobre ti").
    public func beginOnboarding() {
        needsAboutYou = true
        phase = onboardingPhase(for: flowController)
    }

    // MARK: - SCRUM-198: "Sobre ti"

    /// Registra lo que la persona va llenando en "Sobre ti".
    public func updateAboutYou(_ answer: AboutYouAnswer) {
        aboutYouAnswer = answer
    }

    /// "Continuar" en "Sobre ti": sólo avanza con edad (≥ 18), sexo y peso válidos.
    @discardableResult
    public func confirmAboutYou() -> Bool {
        guard aboutYouAnswer.isComplete else { return false }
        needsAboutYou = false
        return true
    }

    /// Vuelve al login sin tocar datos locales (credencial revocada, SCRUM-26).
    public func returnToSignIn() {
        auth.signOut()
        flowController = OnboardingFlowController()
        aboutYouAnswer = AboutYouAnswer()
        needsAboutYou = false
        phase = .signedOut
    }

    /// El plan guardado no se pudo leer.
    public func showPlanUnreadable() {
        phase = .planUnreadable
    }

    /// "Rehacer cuestionario": vuelve al primer paso. Conserva las respuestas de la sesión
    /// o, si se pasa el perfil guardado, parte de sus valores para no empezar de cero.
    public func redo(from profile: OnboardingProfile? = nil) {
        var draft = flowController.draft
        if let profile {
            let answers: [(OnboardingStep, OnboardingAnswer)] = [
                (.goal, .goal(profile.goal)),
                (.phase, .phase(profile.phase)),
                (.experience, .experience(profile.experience)),
                (.daysPerWeek, .trainingDays(profile.trainingWeekdays ?? [])),
                (.sessionMinutes, .sessionMinutes(profile.usualSessionMinutes)),
                (.variety, .variety(profile.varietyPreference)),
                (.restrictions, .restrictions(RestrictionsAnswer(
                    zones: Set(profile.restrictions
                        .filter { BodyRegionRestrictionRule.selectableRegions.contains($0.bodyRegion) }
                        .map(\.bodyRegion)),
                    note: profile.restrictionNote ?? "",
                    previous: profile.restrictions
                ))),
            ]
            for (step, answer) in answers { draft = draft.settingAnswer(answer, for: step) }
        }
        // "Sobre ti" ya contestado se edita en Perfil; un perfil anterior sin él lo pide.
        if let aboutYou = profile?.aboutYou {
            aboutYouAnswer = AboutYouAnswer(aboutYou, on: clock(), timeZone: timeZone())
            needsAboutYou = false
        } else {
            needsAboutYou = true
        }
        flowController = OnboardingFlowController(draft: draft)
        phase = onboardingPhase(for: flowController)
    }

    /// Respuesta guardada del paso actual (la UI marca la opción elegida con ella).
    public var currentAnswer: OnboardingAnswer? {
        flowController.draft.answer(for: flowController.currentStep)
    }

    /// Registra la respuesta del paso actual en el flow controller de dominio.
    public func select(_ answer: OnboardingAnswer) {
        flowController = flowController.answering(answer)
        phase = onboardingPhase(for: flowController)
    }

    /// Avanza al siguiente paso si el actual está válidamente respondido.
    public func advance() {
        flowController = flowController.advance()
        seedDefaultForCurrentStep()
        phase = onboardingPhase(for: flowController)
    }

    /// Retrocede un paso conservando todas las respuestas ya dadas.
    public func goBack() {
        flowController = flowController.goBack()
        seedDefaultForCurrentStep()
        phase = onboardingPhase(for: flowController)
    }

    /// En pasos con selector numérico, lo que se muestra por defecto se registra al
    /// llegar (sin pisar una respuesta ya dada): así "Siguiente" no exige mover el selector.
    private func seedDefaultForCurrentStep() {
        let step = flowController.currentStep
        guard !flowController.draft.hasAnswer(for: step),
              let answer = OnboardingDefaults.answer(for: step) else { return }
        flowController = flowController.answering(answer)
    }

    /// Finaliza el onboarding construyendo el perfil mínimo. Falla si quedan pasos
    /// obligatorios sin responder o los valores son inválidos (no inventa respuestas).
    public func complete() {
        do {
            var profile = try builder.build(from: flowController.draft)
            if !needsAboutYou, aboutYouAnswer.isComplete {
                profile.aboutYou = try aboutYouAnswer.aboutYou(on: clock(), timeZone: timeZone())
            }
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
        case .invalidTrainingDays:
            return "Elige al menos 2 días para entrenar."
        case .invalidSessionMinutes(let minutes):
            return "\(minutes) minutos no están en el rango permitido (30...240)."
        case .restrictionNoteTooLong(let maximum):
            return "La nota de restricciones puede tener hasta \(maximum) caracteres."
        }
    }
}