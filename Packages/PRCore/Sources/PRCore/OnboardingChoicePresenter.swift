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

    public init(locale: Locale = .current) {
        self.locale = locale
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
        case .daysPerWeek, .sessionMinutes, .restrictions:
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
        switch variety {
        case .stable: return resource("Estable (pocos cambios)", "Preferencia de variedad de ejercicios")
        case .balanced: return resource("Equilibrada", "Preferencia de variedad de ejercicios")
        case .varied: return resource("Variada", "Preferencia de variedad de ejercicios")
        }
    }
}
