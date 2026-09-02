//
//  BodybuildingPhase.swift
//  PRDomain
//
//  Created by PR.
//
//  Bodybuilding phase domain (promptMaster §18.1, PR-1801). Representa la fase de
//  competición del usuario (offSeason/cut/contestPrep/recovery) como una DIMENSIÓN
//  INDEPENDIENTE del objetivo de entrenamiento (`TrainingGoal.bodybuilding` sigue siendo
//  un valor de `TrainingGoal`; cambiarla NO toca el goal). El módulo de competición se
//  limita a entrenamiento/organización (promptMaster §18.3): nunca entrena cosas médicas.
//
//  INVARIANTE: determinista; un cambio de fase es un valor de tipo `BodybuildingPhase`
//  que conmuta sólo la fase y deja `TrainingGoal` intacto. No se inventan reglas: el ciclo
//  y los nombres vienen de promptMaster §18.1.
//

import Foundation

/// Fase de competición de bodybuilding (promptMaster §18.1).
public enum BodybuildingPhase: String, Codable, Sendable, CaseIterable, Hashable {
    case offSeason
    case cut
    case contestPrep
    case recovery

    /// Nombre legible para UI (sin reglas de negocio en Views).
    public var displayName: String {
        switch self {
        case .offSeason: return "Fuera de temporada"
        case .cut: return "Definición"
        case .contestPrep: return "Preparación de competición"
        case .recovery: return "Recuperación"
        }
    }

    /// Fase siguiente en el ciclo estándar de competición (§18.1).
    public var next: BodybuildingPhase {
        switch self {
        case .offSeason: return .cut
        case .cut: return .contestPrep
        case .contestPrep: return .recovery
        case .recovery: return .offSeason
        }
    }

    /// ¿La fase implica competición activa/periodización hacia un stage?
    public var isCompetitionActive: Bool { self == .contestPrep }
}

/// Perfil de fase de competición, INDEPENDIENTE del objetivo de entrenamiento (PR-1801).
///
/// `TrainingGoal.bodybuilding` sigue siendo un valor de `TrainingGoal` (PR-0104); esta
/// estructura sólo describe en qué fase de competición está el usuario. Cambiar la fase
/// jamás modifica el `goal`.
public struct BodybuildingPhaseProfile: Codable, Sendable, Hashable {
    public var phase: BodybuildingPhase

    public init(phase: BodybuildingPhase) {
        self.phase = phase
    }
}

/// Regla determinista para cambiar de fase de competición (PR-1801).
///
/// Un cambio de fase valida que siga el ciclo estándar (`offSeason → cut → contestPrep →
/// recovery → offSeason`) y produce la NUEVA fase sin tocar `TrainingGoal` (la API ni
/// siquiera recibe el goal → independencia estructural).
public struct BodybuildingPhaseController: Sendable {

    public init() {}

    /// Avanza la fase siguiendo el ciclo de competición.
    /// - Returns: la fase resultante tras aplicar el avance desde `current`.
    public func advance(from current: BodybuildingPhase) -> BodybuildingPhase {
        current.next
    }

    /// Valida que una transición propuesta respete el ciclo estándar.
    public func isValidTransition(from current: BodybuildingPhase, to next: BodybuildingPhase) -> Bool {
        current.next == next
    }

    /// Aplica un cambio de fase al perfil. Sólo toca `phase`; jamás recibe ni devuelve
    /// `TrainingGoal` → el goal quedaría intacto (PR-1801: goal y fase separados).
    public func applyTransition(from current: BodybuildingPhase, to next: BodybuildingPhase) -> BodybuildingPhaseProfile? {
        guard isValidTransition(from: current, to: next) else { return nil }
        return BodybuildingPhaseProfile(phase: next)
    }
}