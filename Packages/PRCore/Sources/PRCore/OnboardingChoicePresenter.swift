//
//  OnboardingChoicePresenter.swift
//  PRCore
//
//  Created by PR.
//
//  Opciones de los pasos de elección del cuestionario (objetivo, fase, experiencia,
//  variedad) con su texto localizado. Antes la vista mostraba el nombre interno del
//  enum ("Generalhealth", "Hypertrophy") y convertía la selección con un fallback que
//  podía registrar otra respuesta. Aquí cada opción ya trae su `OnboardingAnswer`
//  tipada: la vista sólo la pinta y la reenvía. Textos en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

/// Una opción visible de un paso de elección.
public struct OnboardingChoice: Equatable, Sendable, Identifiable {
    /// Estable (nombre interno de la opción): sirve de identificador de accesibilidad.
    public let id: String
    public let label: String
    public let answer: OnboardingAnswer
}

public struct OnboardingChoicePresenter: Sendable {
    private let locale: Locale
    /// A quién le habla (SCRUM-210): simple para quien empieza, técnico para el avanzado.
    private let audience: OnboardingAudience

    public init(locale: Locale = .current, audience: OnboardingAudience = .standard) {
        self.locale = locale
        self.audience = audience
    }

    /// Opciones del paso, en orden; vacío para pasos que no son de elección.
    public func choices(for step: OnboardingStep) -> [OnboardingChoice] {
        switch step {
        case .goal:
            return TrainingGoal.allCases.map {
                OnboardingChoice(id: $0.rawValue, label: label($0), answer: .goal($0))
            }
        case .phase:
            return BodyCompositionPhase.allCases.map {
                OnboardingChoice(id: $0.rawValue, label: label($0), answer: .phase($0))
            }
        case .experience:
            return ExperienceLevel.allCases.map {
                OnboardingChoice(id: $0.rawValue, label: label($0), answer: .experience($0))
            }
        case .variety:
            return VarietyPreference.allCases.map {
                OnboardingChoice(id: $0.rawValue, label: label($0), answer: .variety($0))
            }
        case .daysPerWeek, .sessionMinutes, .priorityMuscles, .restrictions:
            return []
        }
    }

    // MARK: - Textos (clave = español; el catálogo trae es/en)

    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        text(LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }

    private func label(_ goal: TrainingGoal) -> String {
        if audience == .guided {
            switch goal {
            case .generalHealth: return resource("Estar más sano y con energía", "Objetivo (principiante): salud general")
            case .hypertrophy: return resource("Ganar músculo", "Objetivo (principiante): hipertrofia")
            case .strength: return resource("Ser más fuerte", "Objetivo (principiante): fuerza")
            case .powerbuilding: return resource("Fuerza y músculo a la vez", "Objetivo (principiante): powerbuilding")
            case .recomposition: return resource("Bajar grasa y ganar músculo", "Objetivo (principiante): recomposición")
            case .bodybuilding: return resource("Culturismo (competir)", "Objetivo (principiante): culturismo")
            }
        }
        switch goal {
        case .generalHealth: return resource("Salud general", "Objetivo de entrenamiento")
        case .hypertrophy: return resource("Hipertrofia", "Objetivo de entrenamiento: ganar músculo")
        case .strength: return resource("Fuerza", "Objetivo de entrenamiento")
        case .powerbuilding: return resource("Powerbuilding", "Objetivo: fuerza e hipertrofia combinadas")
        case .recomposition: return resource("Recomposición", "Objetivo: perder grasa y ganar músculo a la vez")
        case .bodybuilding: return resource("Culturismo", "Objetivo de entrenamiento")
        }
    }

    private func label(_ phase: BodyCompositionPhase) -> String {
        switch audience {
        case .guided:
            switch phase {
            case .surplus: return resource("Como de más para subir de peso", "Fase (principiante): superávit")
            case .deficit: return resource("Como de menos para bajar grasa", "Fase (principiante): déficit")
            case .maintenance: return resource("Como normal", "Fase (principiante): mantenimiento")
            case .unspecified: return resource("No sé", "Fase (principiante): sin especificar")
            }
        case .expert:
            switch phase {
            case .surplus: return resource("Superávit calórico (volumen)", "Fase (avanzado)")
            case .deficit: return resource("Déficit calórico (definición)", "Fase (avanzado)")
            case .maintenance: return resource("Normocalórica (mantenimiento)", "Fase (avanzado)")
            case .unspecified: return resource("Sin especificar", "Fase (avanzado)")
            }
        case .standard:
            break
        }
        switch phase {
        case .surplus: return resource("Volumen (superávit)", "Fase: comer por encima del mantenimiento")
        case .deficit: return resource("Definición (déficit)", "Fase: comer por debajo del mantenimiento")
        case .maintenance: return resource("Mantenimiento", "Fase: peso estable")
        case .unspecified: return resource("Prefiero no decirlo", "Fase sin especificar")
        }
    }

    private func label(_ level: ExperienceLevel) -> String {
        switch level {
        case .novice: return resource("Novato", "Nivel de experiencia")
        case .beginner: return resource("Principiante", "Nivel de experiencia")
        case .intermediate: return resource("Intermedio", "Nivel de experiencia")
        case .advanced: return resource("Avanzado", "Nivel de experiencia")
        case .competitive: return resource("Competitivo", "Nivel de experiencia")
        }
    }

    private func label(_ variety: VarietyPreference) -> String {
        if audience == .expert {
            switch variety {
            case .stable: return resource("Estable (mismos ejercicios ancla)", "Variedad (avanzado)")
            case .balanced: return resource("Equilibrada (rota accesorios)", "Variedad (avanzado)")
            case .varied: return resource("Variada (rota más ejercicios)", "Variedad (avanzado)")
            }
        }
        switch variety {
        case .stable: return resource("Estable (pocos cambios)", "Preferencia de variedad de ejercicios")
        case .balanced: return resource("Equilibrada", "Preferencia de variedad de ejercicios")
        case .varied: return resource("Variada", "Preferencia de variedad de ejercicios")
        }
    }
}
