//
//  UITestProfileSeeder.swift
//  PRCore
//
//  SCRUM-228: perfil sembrado para las pruebas de UI. Con `-PRUITestProfile <perfil>` (sólo
//  Debug y con datos temporales, ver `UITestLaunchOptions`) la app contesta sola el
//  cuestionario: así sólo los recorridos del cuestionario lo contestan a mano.
//  No inventa un plan. Llena "Sobre ti" y cada paso con el MISMO `OnboardingCoordinator`
//  que la pantalla (respuesta, "Siguiente" y, al final, "Terminar") y contesta el
//  consentimiento de la IA como su botón. El plan lo arma después la activación de siempre
//  (`AppSessionCoordinator.planCompleted`), igual que al terminar el cuestionario.
//  `UITestProfileSeederTests` comprueba que da el mismo perfil y el mismo plan que contestar
//  el cuestionario como lo hacen las pruebas de UI.
//

import Foundation
import PRDomain

/// Perfiles que las pruebas de UI pueden sembrar con `-PRUITestProfile <valor>`.
public enum UITestSeededProfile: String, CaseIterable, Sendable {
    /// Lo que contesta `completeOnboarding()` de `PRUITests` con sus valores por defecto:
    /// 30 años, hombre y 72 kg; intermedio, hipertrofia y mantenimiento; lunes, miércoles y
    /// viernes; 60 min; variedad balanceada; sin prioritarios ni restricciones; IA "Ahora no".
    case intermediateMondayWednesdayFriday = "intermedio-lmv"

    /// "Sobre ti" como lo llena la prueba (rueda de edad, sexo y peso). El nombre no va
    /// aquí: lo pone el inicio de sesión, igual que en la pantalla.
    var aboutYou: AboutYouAnswer {
        switch self {
        case .intermediateMondayWednesdayFriday:
            return AboutYouAnswer(age: 30, sex: .male, weight: 72, weightUnit: .kilograms)
        }
    }

    /// La respuesta de cada paso. Un paso sin respuesta se pasa con "Siguiente" sin elegir
    /// nada (prioritarios y restricciones son opcionales), como en la prueba.
    var answers: [OnboardingStep: OnboardingAnswer] {
        switch self {
        case .intermediateMondayWednesdayFriday:
            return [
                .experience: .experience(.intermediate),
                .goal: .goal(.hypertrophy),
                .phase: .phase(.maintenance),
                .daysPerWeek: .trainingDays([.monday, .wednesday, .friday]),
                .sessionMinutes: .sessionMinutes(60),
                .variety: .variety(.balanced),
            ]
        }
    }

    /// El botón que toca en el consentimiento de la IA.
    var aiConsent: UITestAIConsentChoice {
        switch self {
        case .intermediateMondayWednesdayFriday: return .decline
        }
    }
}

/// Los dos botones de la pantalla del consentimiento de la IA (SCRUM-202).
public enum UITestAIConsentChoice: Sendable {
    case accept
    case decline
}

/// Qué hizo el perfil sembrado.
public enum UITestSeedOutcome: Equatable, Sendable {
    /// Contestó el cuestionario; la app arma el plan como al terminarlo.
    case answered(OnboardingProfile)
    /// La app no estaba en el cuestionario (p. ej. ya hay un plan guardado al reabrir con el
    /// mismo `-PRUITestStoreID`, o no hay sesión): no tocó nada.
    case notInQuestionnaire
    /// "Sobre ti" no aceptó las respuestas: se queda ahí, a la vista de la prueba.
    case aboutYouRejected
    /// Este paso no avanzó con su respuesta: se queda en él.
    case stepRejected(OnboardingStep)
    /// "Terminar" no armó el perfil (el coordinador muestra el error).
    case profileRejected
}

/// Contesta el cuestionario con las respuestas de un perfil sembrado.
@MainActor
public struct UITestProfileSeeder {
    public let profile: UITestSeededProfile

    public init(profile: UITestSeededProfile) {
        self.profile = profile
    }

    /// Contesta si la app está en el cuestionario (recién iniciada la sesión y sin plan).
    /// Nunca se salta la validación del coordinador: si un paso no avanza, se detiene ahí.
    @discardableResult
    public func answer(onboarding: OnboardingCoordinator, aiConsent: AIConsentCoordinator) -> UITestSeedOutcome {
        guard case .onboarding = onboarding.phase else { return .notInQuestionnaire }
        if onboarding.needsAboutYou {
            var answer = profile.aboutYou
            answer.name = onboarding.aboutYouAnswer.name
            onboarding.updateAboutYou(answer)
            guard onboarding.confirmAboutYou() else { return .aboutYouRejected }
        }
        let answers = profile.answers
        // Como en la pantalla: la respuesta del paso (si la hay) y "Siguiente"; en el último,
        // "Terminar". Los pasos los decide el coordinador (cambian con la experiencia).
        while case .onboarding(let step, let index, _, _, let isAtEnd) = onboarding.phase {
            if let answer = answers[step] { onboarding.select(answer) }
            if isAtEnd {
                onboarding.complete()
                break
            }
            onboarding.advance()
            guard case .onboarding(_, let next, _, _, _) = onboarding.phase, next > index else {
                return .stepRejected(step)
            }
        }
        guard case .completed(let completed) = onboarding.phase else { return .profileRejected }
        if aiConsent.needsDecision {
            switch profile.aiConsent {
            case .accept: aiConsent.grant()
            case .decline: aiConsent.decline()
            }
        }
        return .answered(completed)
    }
}
