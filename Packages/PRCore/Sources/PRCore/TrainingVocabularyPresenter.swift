//
//  TrainingVocabularyPresenter.swift
//  PRCore
//
//  SCRUM-195 (U6): vocabulario de gimnasio visible en la app. El planificador guarda los
//  títulos de sesión como claves estables en inglés ("Push", "Legs B", "Upper A",
//  "Full Body"); aquí se traducen al nombre que ve la persona (Push, Pull, Pierna, Torso,
//  Cuerpo completo) y los grupos musculares a español. Los bloques guardados NO cambian:
//  la traducción es sólo de presentación. Textos en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

public struct TrainingVocabularyPresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Nombre visible de una sesión. Conserva la letra de rotación ("Legs B" → "Pierna B").
    /// Un título que no es del planificador se muestra tal cual (nunca se inventa otro).
    public func sessionName(_ title: String) -> String {
        if let name = baseName(title) { return name }
        guard let space = title.lastIndex(of: " ") else { return title }
        let suffix = title[title.index(after: space)...]
        guard suffix.count == 1, let letter = suffix.first, letter.isUppercase,
              let name = baseName(String(title[..<space])) else {
            return title
        }
        return "\(name) \(letter)"
    }

    /// Nombre visible de un grupo muscular (chips de la semana).
    public func muscleName(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return resource("Pecho", "Grupo muscular")
        case .back: return resource("Espalda", "Grupo muscular")
        case .shoulders: return resource("Hombro", "Grupo muscular")
        case .biceps: return resource("Bíceps", "Grupo muscular")
        case .triceps: return resource("Tríceps", "Grupo muscular")
        case .forearms: return resource("Antebrazo", "Grupo muscular")
        case .quadriceps: return resource("Cuádriceps", "Grupo muscular")
        case .hamstrings: return resource("Femoral", "Grupo muscular: isquiotibiales")
        case .glutes: return resource("Glúteo", "Grupo muscular")
        case .calves: return resource("Pantorrilla", "Grupo muscular")
        case .spinalErectors: return resource("Espalda baja", "Grupo muscular: erectores espinales")
        case .core: return resource("Abdomen", "Grupo muscular: core")
        }
    }

    // MARK: - Privado

    /// Clave estable del planificador → nombre visible; `nil` si no es una clave conocida.
    private func baseName(_ key: String) -> String? {
        switch key {
        case "Push": return resource("Push", "Sesión de empuje: pecho, hombro y tríceps")
        case "Pull": return resource("Pull", "Sesión de jalón: espalda y bíceps")
        case "Legs", "Lower": return resource("Pierna", "Sesión de tren inferior")
        case "Upper": return resource("Torso", "Sesión de tren superior")
        case "Full Body": return resource("Cuerpo completo", "Sesión de cuerpo completo")
        default: return nil
        }
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
