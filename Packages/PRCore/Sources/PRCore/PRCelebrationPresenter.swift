//
//  PRCelebrationPresenter.swift
//  PRCore
//
//  Created by PR.
//
//  Convierte la celebración decidida por el dominio (`PRCelebration`, PR-1004) en
//  textos localizables (RNF-013). Sin reglas: no decide qué se celebra, sólo cómo se
//  dice. Strings en `Resources/Localizable.xcstrings`; números y unidades con
//  `Measurement.FormatStyle` (singular/plural y separador decimal según el locale) y
//  SIN conversión de unidades (`usage: .asProvided`): se muestra lo que el usuario
//  registró.
//

import Foundation
import PRDomain

/// Celebración lista para pintar.
public struct PRCelebrationPresentation: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let id: ExerciseID
        public let exerciseName: String
        /// p. ej. "85 kg × 8".
        public let loadText: String
    }

    public let headline: String
    public let detail: String?
    public let rows: [Row]
    /// Texto para `AccessibilityNotification.Announcement`.
    public let accessibilityAnnouncement: String
}

/// Presentador de `PRCelebration` (PR-1004). `locale` se inyecta para tests deterministas.
public struct PRCelebrationPresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Locale de presentación: idioma = el que resolvió la app (p. ej.
    /// `Bundle.main.preferredLocalizations.first`), formato regional = el del usuario.
    /// Con `Locale.current` a secas, un sistema en inglés mostraría la celebración en
    /// inglés dentro de una app en español. `appLanguage == nil` ⇒ `userLocale` tal cual.
    public static func presentationLocale(appLanguage: String?, userLocale: Locale) -> Locale {
        guard let appLanguage, !appLanguage.isEmpty else { return userLocale }
        var components = Locale.Components(locale: userLocale)
        components.languageComponents = Locale.Language.Components(identifier: appLanguage)
        // Asignar `languageComponents` borra la región: se repone la del usuario.
        components.region = userLocale.region
        return Locale(components: components)
    }

    public func present(_ celebration: PRCelebration) -> PRCelebrationPresentation {
        let headline = headline(count: celebration.items.count)
        let rows = celebration.items.map { item in
            PRCelebrationPresentation.Row(
                id: item.exerciseID,
                exerciseName: name(item),
                loadText: text(LocalizedStringResource(
                    "\(load(item, width: .abbreviated)) × \(item.reps)",
                    locale: locale, bundle: Self.bundle,
                    comment: "Carga del récord: peso con unidad × repeticiones. Ej.: 85 kg × 8"
                ))
            )
        }
        let spokenItems = celebration.items.map { item in
            text(LocalizedStringResource(
                "\(name(item)), \(load(item, width: .wide)) por \(repetitions(item.reps))",
                locale: locale, bundle: Self.bundle,
                comment: "VoiceOver: un récord. Ej.: Press banca, 85 kilogramos por 8 repeticiones"
            ))
        }
        let announcement = text(LocalizedStringResource(
            "\(headline): \(spokenItems.formatted(.list(type: .and).locale(locale))).",
            locale: locale, bundle: Self.bundle,
            comment: "VoiceOver al aparecer la celebración: titular y lista de récords"
        ))
        return PRCelebrationPresentation(
            headline: headline,
            detail: celebration.detail.map(detailText),
            rows: rows,
            accessibilityAnnouncement: announcement
        )
    }

    // MARK: - Strings

    /// Catálogo de PRCore. Con `LocalizedStringResource.locale` el idioma Y el formato
    /// salen del mismo locale (con `String(localized:locale:)` el idioma venía del
    /// proceso y el formato del locale: mezclaba idiomas).
    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func text(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    private func headline(count: Int) -> String {
        if count == 1 {
            return text(LocalizedStringResource("Nuevo récord", locale: locale, bundle: Self.bundle,
                                                comment: "Titular de la celebración con un solo récord"))
        }
        return text(LocalizedStringResource("\(count) nuevos récords", locale: locale, bundle: Self.bundle,
                                            comment: "Titular de la celebración con varios récords (count ≥ 2)"))
    }

    private func detailText(_ detail: PRCelebrationDetail) -> String {
        switch detail {
        case .progressiveOverloadExplained:
            return text(LocalizedStringResource(
                "Levantaste más que tu mejor carga registrada. Así se ve la sobrecarga progresiva: el plan decidirá en la próxima sesión si conviene subir.",
                locale: locale, bundle: Self.bundle,
                comment: "Explicación para nivel guiado tras un récord"
            ))
        case .bestLoadSurpassed:
            return text(LocalizedStringResource("Superaste tu mejor carga registrada.", locale: locale, bundle: Self.bundle,
                                                comment: "Explicación breve para nivel balanceado tras un récord"))
        }
    }

    private func name(_ item: PRCelebrationItem) -> String {
        item.exerciseName ?? text(LocalizedStringResource("Ejercicio", locale: locale, bundle: Self.bundle,
                                                          comment: "Nombre genérico si el ejercicio no está en el catálogo"))
    }

    private func repetitions(_ reps: Int) -> String {
        text(LocalizedStringResource("\(reps) repeticiones", locale: locale, bundle: Self.bundle,
                                     comment: "Número de repeticiones (con variación singular/plural)"))
    }

    // MARK: - Formato

    private func load(_ item: PRCelebrationItem, width: Measurement<UnitMass>.FormatStyle.UnitWidth) -> String {
        let unit: UnitMass
        switch item.unit {
        case .kilograms: unit = .kilograms
        case .pounds: unit = .pounds
        }
        return Measurement(value: item.weight, unit: unit).formatted(
            .measurement(
                width: width,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...1))
            ).locale(locale)
        )
    }
}
