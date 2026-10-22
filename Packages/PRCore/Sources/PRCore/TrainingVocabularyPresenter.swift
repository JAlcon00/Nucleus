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

    /// Inicial de un día para los chips de la semana (SCRUM-196). Martes "M" y miércoles
    /// "Mi" para que no se repitan.
    public func weekdayInitial(_ day: WeekDay) -> String {
        switch day {
        case .monday: return resource("L", "Inicial de lunes en los chips de la semana")
        case .tuesday: return resource("M", "Inicial de martes en los chips de la semana")
        case .wednesday: return resource("Mi", "Inicial de miércoles en los chips de la semana")
        case .thursday: return resource("J", "Inicial de jueves en los chips de la semana")
        case .friday: return resource("V", "Inicial de viernes en los chips de la semana")
        case .saturday: return resource("S", "Inicial de sábado en los chips de la semana")
        case .sunday: return resource("D", "Inicial de domingo en los chips de la semana")
        }
    }

    /// Nombre completo de un día (VoiceOver y encabezados de la semana).
    public func weekdayName(_ day: WeekDay) -> String {
        switch day {
        case .monday: return resource("Lunes", "Día de la semana")
        case .tuesday: return resource("Martes", "Día de la semana")
        case .wednesday: return resource("Miércoles", "Día de la semana")
        case .thursday: return resource("Jueves", "Día de la semana")
        case .friday: return resource("Viernes", "Día de la semana")
        case .saturday: return resource("Sábado", "Día de la semana")
        case .sunday: return resource("Domingo", "Día de la semana")
        }
    }

    /// Series de trabajo × rango de repeticiones (M1): "3 × 8–12", "3 × 10" o "2 series".
    public func setsAndReps(sets: Int, repRange: ClosedRange<Int>?) -> String {
        guard let repRange else {
            return String(localized: LocalizedStringResource(
                "\(sets) series", locale: locale, bundle: Self.bundle,
                comment: "Número de series de un ejercicio sin rango de repeticiones"
            ))
        }
        if repRange.lowerBound == repRange.upperBound {
            return String(localized: LocalizedStringResource(
                "\(sets) × \(repRange.lowerBound)", locale: locale, bundle: Self.bundle,
                comment: "Series × repeticiones. Ej.: 3 × 10"
            ))
        }
        return String(localized: LocalizedStringResource(
            "\(sets) × \(repRange.lowerBound)–\(repRange.upperBound)", locale: locale, bundle: Self.bundle,
            comment: "Series × rango de repeticiones. Ej.: 3 × 8–12"
        ))
    }

    /// Tipo de ejercicio para su etiqueta: "Compuesto" (multiarticular) o "Aislado".
    public func exerciseKind(_ jointClass: JointClass) -> String {
        switch jointClass {
        case .multiJoint: return resource("Compuesto", "Ejercicio multiarticular (varias articulaciones)")
        case .singleJoint: return resource("Aislado", "Ejercicio monoarticular (una articulación)")
        }
    }

    /// Series de trabajo con su palabra: "1 serie", "3 series".
    public func workSets(_ sets: Int) -> String {
        if sets == 1 {
            return resource("1 serie", "Una sola serie de trabajo")
        }
        return String(localized: LocalizedStringResource(
            "\(sets) series", locale: locale, bundle: Self.bundle,
            comment: "Número de series de un ejercicio sin rango de repeticiones"
        ))
    }

    /// Repeticiones por serie con su palabra: "10 reps", "8–12 reps".
    public func reps(_ range: ClosedRange<Int>) -> String {
        if range.lowerBound == range.upperBound {
            return String(localized: LocalizedStringResource(
                "\(range.lowerBound) reps", locale: locale, bundle: Self.bundle,
                comment: "Repeticiones por serie. Ej.: 10 reps"
            ))
        }
        return String(localized: LocalizedStringResource(
            "\(range.lowerBound)–\(range.upperBound) reps", locale: locale, bundle: Self.bundle,
            comment: "Rango de repeticiones por serie. Ej.: 8–12 reps"
        ))
    }

    /// "Última vez: 60 kg × 10" (M1).
    public func lastTime(_ performance: LastPerformance) -> String {
        let load = self.load(performance.weight, unit: performance.unit)
        return String(localized: LocalizedStringResource(
            "Última vez: \(load) × \(performance.reps)", locale: locale, bundle: Self.bundle,
            comment: "Mejor serie de la última sesión de un ejercicio. Ej.: Última vez: 60 kg × 10"
        ))
    }

    /// Una serie hecha: "60 kg × 10" (Progreso, SCRUM-186).
    public func setText(weight: Double, unit: LoadUnit, reps: Int) -> String {
        let load = self.load(weight, unit: unit)
        return String(localized: LocalizedStringResource(
            "\(load) × \(reps)", locale: locale, bundle: Self.bundle,
            comment: "Carga del récord: peso con unidad × repeticiones. Ej.: 85 kg × 8"
        ))
    }

    /// Peso con unidad y como mucho un decimal: "1,580 kg", "82.5 kg".
    public func load(_ weight: Double, unit: LoadUnit) -> String {
        let mass: UnitMass
        switch unit {
        case .kilograms: mass = .kilograms
        case .pounds: mass = .pounds
        }
        return Measurement(value: weight, unit: mass).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale)
        )
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
