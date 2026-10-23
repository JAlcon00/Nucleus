//
//  SessionTimePresenter.swift
//  PRCore
//
//  SCRUM-30 (PR-0108): la frase que "Hoy" muestra al ajustar la sesión al tiempo elegido:
//  qué se quitó y por qué, que no cabe ni recortada o que no se agregan series. Sólo
//  traduce el resultado del dominio (`SessionTimeAdjustment`); no decide nada. Textos en
//  `Localizable.xcstrings`.
//

import Foundation
import PRDomain

public struct SessionTimePresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Una sola frase. `name` da el nombre visible de cada ejercicio.
    public func sentence(for adjustment: SessionTimeAdjustment, name: (ExerciseID) -> String?) -> String {
        let budget = adjustment.budgetMinutes
        switch adjustment.fit {
        case .fits(_, let suggestions):
            let minutes = adjustment.originalMinutes
            guard !suggestions.isEmpty else {
                return resource(
                    "Tu sesión dura unos \(minutes) min y cabe en \(budget); no agregamos series.",
                    "Ajuste de tiempo: la sesión ya cabía y no se le suma volumen"
                )
            }
            let extras = list(suggestions.map(activityName))
            return resource(
                "Tu sesión dura unos \(minutes) min; no agregamos series, pero con el tiempo que sobra puedes sumar \(extras).",
                "Ajuste de tiempo: sobra tiempo; se sugiere movilidad o cardio, nunca más series"
            )
        case .trimmed(let removed, let reduced):
            let removedNames = list(removed.map { displayName($0, name) })
            let reducedNames = list(reduced.map { displayName($0.exerciseID, name) })
            switch (removed.isEmpty, reduced.isEmpty) {
            case (false, false):
                return resource(
                    "Para caber en \(budget) min quitamos \(removedNames) y dejamos menos series de \(reducedNames); los ejercicios principales se quedan.",
                    "Ajuste de tiempo: se quitaron accesorios y se redujeron otros"
                )
            case (false, true):
                return resource(
                    "Para caber en \(budget) min quitamos \(removedNames); los ejercicios principales se quedan.",
                    "Ajuste de tiempo: se quitaron accesorios"
                )
            case (true, false):
                return resource(
                    "Para caber en \(budget) min dejamos menos series de \(reducedNames); los ejercicios principales se quedan.",
                    "Ajuste de tiempo: se redujeron series de accesorios"
                )
            case (true, true):
                return resource(
                    "Ajustamos la sesión para caber en \(budget) min; los ejercicios principales se quedan.",
                    "Ajuste de tiempo: cambio sin ejercicios quitados ni reducidos"
                )
            }
        case .doesNotFit(let needed, _, _):
            return resource(
                "Aun recortada, esta sesión necesita unos \(needed) min y no cabe en \(budget); conservamos los ejercicios principales.",
                "Ajuste de tiempo: la sesión no cabe ni quitando accesorios"
            )
        }
    }

    // MARK: - Privado

    private func displayName(_ id: ExerciseID, _ name: (ExerciseID) -> String?) -> String {
        name(id) ?? resource("un ejercicio", "Ajuste de tiempo: ejercicio sin nombre en el catálogo")
    }

    private func activityName(_ activity: ExtraTimeActivity) -> String {
        switch activity {
        case .mobility: return resource("movilidad", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra")
        case .cardio: return resource("cardio", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra")
        case .posing: return resource("práctica de poses", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra (culturismo)")
        }
    }

    private func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(locale))
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
