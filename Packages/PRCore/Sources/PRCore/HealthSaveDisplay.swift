//
//  HealthSaveDisplay.swift
//  PRCore
//
//  SCRUM-247 (PR-F004): qué dice el resumen sobre Salud. La decisión y el texto viven aquí;
//  la pantalla sólo los pinta. "Se guardará" no es un error: Salud falló o tardó y la cola lo
//  reintenta. Sin escritura activa no se dice nada.
//

import Foundation
import PRDomain

public enum HealthSaveDisplay: Sendable, Hashable {
    case hidden
    case pending
    case saved

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    /// `canWrite`: si la escritura sigue activa. Apagada o negada, el resumen no dice nada.
    public init(status: HealthWriteStatus?, canWrite: Bool) {
        guard canWrite, let status else {
            self = .hidden
            return
        }
        switch status {
        case .pending: self = .pending
        case .saved: self = .saved
        }
    }

    /// Texto para el resumen; `nil` si no hay nada que decir.
    public func text(locale: Locale) -> String? {
        switch self {
        case .hidden:
            return nil
        case .pending:
            return String(localized: LocalizedStringResource(
                "Se guardará en Salud", locale: locale, bundle: Self.bundle,
                comment: "Resumen: el entrenamiento aún no llega a Salud; no es un error"
            ))
        case .saved:
            return String(localized: LocalizedStringResource(
                "Guardado en Salud", locale: locale, bundle: Self.bundle,
                comment: "Resumen: el entrenamiento ya está en Salud"
            ))
        }
    }
}
