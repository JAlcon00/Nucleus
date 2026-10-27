//
//  PainRecommendationPresenter.swift
//  PRCore
//
//  SCRUM-32: la frase que ve la persona después de reportar dolor. La decisión
//  (continuar, bajar la intensidad, parar) la toma `PainFeedbackEngine`; aquí sólo se dice
//  en palabras simples. Nunca nombra una lesión ni promete recuperación (RN-015).
//

import Foundation
import PRDomain

public struct PainRecommendationPresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// La frase de la recomendación, o `nil` si no hace falta decir nada.
    public func message(for recommendation: PainRecommendation) -> String? {
        switch recommendation {
        case .continueNormal:
            return nil
        case .reduceIntensityAndMonitor:
            return resource("Baja la intensidad y observa cómo te sientes en las próximas series.", "Dolor moderado: recomendación")
        case .stopAndRest:
            return resource("Detén este ejercicio o cámbialo por otro. Si el dolor sigue, consulta a un profesional de la salud.", "Dolor alto: recomendación")
        }
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
