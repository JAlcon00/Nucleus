//
//  CoachingDetail.swift
//  PRDomain
//
//  Created by PR.
//
//  Nivel de detalle del coaching (promptMaster §17.1, RF-, PR-0403). Mapeo inicial
//  determinista por experiencia (novice/beginner → guided, intermediate → balanced,
//  advanced/competitive → advanced) y SIEMPRE reemplazable por el usuario manualmente.
//  INVARIANTE: determinista; un override manual manda sobre el default mientras dure.
//

import Foundation

/// Mapeo inicial de `ExperienceLevel` → `CoachingDetailLevel` (promptMaster §17.1).
///
/// El usuario SIEMPRE puede reemplazarlo manualmente (PR-0403). Este mapeo es el
/// "default" inicial, no una imposición.
public struct CoachingDetailMapper: Sendable {

    public init() {}

    /// Nivel de detalle sugerido por el nivel de experiencia declarado.
    public func initialDefault(for experience: ExperienceLevel) -> CoachingDetailLevel {
        switch experience {
        case .novice, .beginner:
            // guided: lenguaje simple, más educación contextual (§17.1).
            return .guided
        case .intermediate:
            // balanced: mezcla.
            return .balanced
        case .advanced, .competitive:
            // advanced: valores técnicos y mínima explicación salvo anomalía.
            return .advanced
        }
    }
}

/// Estado del nivel de coaching: el nivel efectivo y si viene de un override manual.
///
/// - `levelSource` distingue si el nivel actual es el "default por experiencia" o un
///   "override manual" del usuario (auditable, sin reglas en Views).
/// - El override, una vez aplicado, manda sobre el default mientras no se resetee.
public struct CoachingDetailPrefs: Equatable, Sendable {
    /// Origen del nivel actual.
    public enum LevelSource: String, Codable, Sendable, Equatable {
        /// Nivel derivado por defecto del `ExperienceLevel`.
        case defaultByExperience
        /// Nivel elegido manualmente por el usuario (manda sobre el default).
        case manualOverride
    }

    /// Nivel actualmente activo.
    public private(set) var level: CoachingDetailLevel
    /// Origen del nivel actual.
    public private(set) var source: LevelSource

    public init(level: CoachingDetailLevel, source: LevelSource = .defaultByExperience) {
        self.level = level
        self.source = source
    }

    /// Construye el estado con el default por experiencia (source = defaultByExperience).
    public static func defaulted(for experience: ExperienceLevel, mapper: CoachingDetailMapper = CoachingDetailMapper()) -> CoachingDetailPrefs {
        CoachingDetailPrefs(level: mapper.initialDefault(for: experience), source: .defaultByExperience)
    }

    /// Aplica una elección manual del usuario. El override manda sobre el default y
    /// queda registrado como `manualOverride`, incluso si coincide con el valor por
    /// defecto (el usuario lo eligió explícitamente).
    public mutating func applyManualOverride(_ newLevel: CoachingDetailLevel) {
        if newLevel != level {
            level = newLevel
        }
        source = .manualOverride
    }

    /// Versión inmutable de `applyManualOverride`.
    public func applyingManualOverride(_ newLevel: CoachingDetailLevel) -> CoachingDetailPrefs {
        var copy = self
        copy.applyManualOverride(newLevel)
        return copy
    }

    /// ¿El usuario eligió manualmente este nivel (aunque coincida con el default)?
    public var isUserChosen: Bool { source == .manualOverride }

    /// Restablece a un default por la experiencia dada (source vuelve a default).
    public func resetting(toDefaultFor experience: ExperienceLevel, mapper: CoachingDetailMapper = CoachingDetailMapper()) -> CoachingDetailPrefs {
        CoachingDetailPrefs.defaulted(for: experience, mapper: mapper)
    }
}