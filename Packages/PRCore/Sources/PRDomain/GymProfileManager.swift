//
//  GymProfileManager.swift
//  PRDomain
//
//  Created by PR.
//
//  Gym profile manager (plan §9, RF-011, PR-0901). Crea/renombra/objetivo el perfil
//  de un gym, gestiona la disponibilidad del equipamiento (unknown/available/
//  doesNotExist) y NO obliga a un formulario inicial de todas las máquinas: lo que no
//  se ha confirmado queda `.unknown` (progressive disclosure). Determinista.
//

import Foundation

/// Problemas del manager de perfil de gym.
public enum GymProfileManagerError: Error, Equatable, Sendable {
    case emptyName
    case occupancyIsSessionScoped
    case invalidTransition(from: EquipmentAvailabilityState, to: EquipmentAvailabilityState)
}

/// Estados permitidos de forma persistente en el perfil.
public let persistentAvailabilityStates: Set<EquipmentAvailabilityState> = [
    .unknown, .available, .doesNotExist,
]

/// Gestiona un perfil de gym (PR-0901).
public struct GymProfileManager: Sendable {
    public var activeGymID: GymID?

    public init(activeGymID: GymID? = nil) {
        self.activeGymID = activeGymID
    }

    /// Crea un gym vacío. NO fuerza listar máquinas: el equipamiento sin confirmar
    /// queda `.unknown` y se aprende de forma progresiva.
    public func create(name: String) throws -> GymProfile {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GymProfileManagerError.emptyName
        }
        return GymProfile(name: name)
    }

    /// Renombra el gym (nombre no vacío).
    public func rename(_ profile: GymProfile, to name: String) throws -> GymProfile {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GymProfileManagerError.emptyName
        }
        var copy = profile
        copy.name = name
        return copy
    }

    /// Selecciona el gym como activo.
    public func select(_ profile: GymProfile) -> GymProfileManager {
        var copy = self
        copy.activeGymID = profile.id
        return copy
    }

    /// Fija la disponibilidad persistente de un equipamiento.
    /// Sólo `.unknown`/`.available`/`.doesNotExist` son persistentes; `.occupied` es
    /// session-scoped y se marca con `markingOccupied` de `GymProfile`.
    public func setAvailability(
        _ type: EquipmentType,
        to state: EquipmentAvailabilityState,
        on profile: GymProfile
    ) throws -> GymProfile {
        guard state != .occupied else {
            throw GymProfileManagerError.occupancyIsSessionScoped
        }
        var copy = profile
        let current = copy.state(of: type)
        guard persistentAvailabilityStates.contains(state) else {
            throw GymProfileManagerError.invalidTransition(from: current, to: state)
        }
        if let idx = copy.equipmentAvailability.firstIndex(where: { $0.equipmentType == type }) {
            copy.equipmentAvailability[idx].state = state
        } else {
            copy.equipmentAvailability.append(EquipmentAvailability(equipmentType: type, state: state))
        }
        return copy
    }

    /// Tipos de equipamiento confirmados como disponibles o inexistentes (no unknown).
    public func knownEquipmentTypes(_ profile: GymProfile) -> [EquipmentType] {
        profile.equipmentAvailability
            .filter { $0.state != .unknown }
            .map { $0.equipmentType }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// Un equipamiento no confirmado permanece `.unknown` (sin formulario obligatorio
    /// de 100 máquinas).
    public func state(of type: EquipmentType, in profile: GymProfile) -> EquipmentAvailabilityState {
        profile.state(of: type)
    }
}