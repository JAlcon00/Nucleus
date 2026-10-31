//
//  SupersetPresenter.swift
//  PRCore
//
//  SCRUM-224: la frase de Hoy sobre los ejercicios que van en superset y por qué. Sólo
//  traduce los pares de la plantilla de hoy (los decide el motor o "Ajustar a mi tiempo");
//  no decide nada. Textos en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

public struct SupersetPresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// `nil` si hoy nada va en superset. `name` da el nombre visible de cada ejercicio.
    public func todayNote(for template: SessionTemplate?, name: (ExerciseID) -> String?) -> String? {
        let pairs = template?.supersetPairs ?? []
        guard !pairs.isEmpty else { return nil }
        let names = pairs.map { pair in
            resource("\(displayName(pair.first, name)) con \(displayName(pair.second, name))", "Superset: un ejercicio con su pareja")
        }
        let list = names.formatted(.list(type: .and).locale(locale))
        return resource(
            "Hoy va en superset \(list): una serie de cada uno y luego descansas, para que tu sesión quepa en tu tiempo.",
            "Hoy: ejercicios en superset y por qué"
        )
    }

    private func displayName(_ id: ExerciseID, _ name: (ExerciseID) -> String?) -> String {
        name(id) ?? resource("un ejercicio", "Ajuste de tiempo: ejercicio sin nombre en el catálogo")
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
