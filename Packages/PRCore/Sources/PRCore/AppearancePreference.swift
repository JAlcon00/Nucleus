//
//  AppearancePreference.swift
//  PRCore
//
//  SCRUM-208 (FB-1): apariencia elegida en Perfil. Es una preferencia del dispositivo
//  (no del usuario ni de su entrenamiento): vive en `UserDefaults` con esta clave. Por
//  defecto oscuro, la identidad de la marca y lo que la app mostraba hasta ahora.
//

import Foundation

public enum AppearancePreference: String, Sendable, CaseIterable, Hashable {
    /// Sigue al sistema (claro u oscuro según iOS).
    case system
    case light
    case dark

    /// Clave en `UserDefaults` (la usa `@AppStorage` en la app).
    public static let storageKey = "appearance"

    /// Sin elección (o un valor que ya no existe): oscuro.
    public static let fallback = AppearancePreference.dark

    /// Lee lo guardado; un valor desconocido nunca rompe: cae al de por defecto.
    public static func resolve(_ raw: String?) -> AppearancePreference {
        raw.flatMap(AppearancePreference.init(rawValue:)) ?? fallback
    }
}
