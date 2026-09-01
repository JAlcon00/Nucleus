//
//  OccupancyController.swift
//  PRDomain
//
//  Created by PR.
//
//  Mark occupied (plan §9, RF-010, PR-0902). Decide si marcar un equipo como ocupado
//  durante la sesión activa dispara una reevaluación del orden. La ocupación es
//  session-scoped (no se persiste como hecho del gym) y se resetea al finalizar la
//  sesión. Determinista.
//

import Foundation

/// Vínculo entre una entrada ordenada y el equipamiento que utiliza.
public struct OrderedEquipmentUse: Equatable, Sendable {
    public let itemID: UUID
    public let equipmentTypes: Set<EquipmentType>

    public init(itemID: UUID, equipmentTypes: Set<EquipmentType>) {
        self.itemID = itemID
        self.equipmentTypes = equipmentTypes
    }
}

/// Resultado de marcar un equipo como ocupado.
public struct OccupancyChange: Equatable, Sendable {
    /// Perfil con la ocupación session-scoped actualizada.
    public let profile: GymProfile
    /// ¿Debe reevaluarse el orden? (true si algún ítem ordenado usa ese equipo).
    public let shouldReorder: Bool
    /// Equipo marcado.
    public let occupiedType: EquipmentType

    public init(profile: GymProfile, shouldReorder: Bool, occupiedType: EquipmentType) {
        self.profile = profile
        self.shouldReorder = shouldReorder
        self.occupiedType = occupiedType
    }
}

/// Marca equipos ocupados durante la sesión activa (PR-0902).
///
/// Reglas deterministas:
/// - `markOccupied` fija el equipo en `GymProfile.occupiedDuringSession` (session-scoped).
/// - Devuelve `shouldReorder == true` si alguno de los ítems ordenados del plan usa el
///   equipo recién ocupado (el orden debe reevaluarse ANTES de sustituir, por RF-010).
/// - La ocupación se resetea al finalizar la sesión (`GymProfile.endingSession`); nunca
///   persiste como hecho del gym.
public struct OccupancyController: Sendable {

    public init() {}

    public func markOccupied(
        _ type: EquipmentType,
        in profile: GymProfile,
        orderedUses: [OrderedEquipmentUse]
    ) -> OccupancyChange {
        let updated = profile.markingOccupied(type)
        let shouldReorder = orderedUses.contains { $0.equipmentTypes.contains(type) }
        return OccupancyChange(profile: updated, shouldReorder: shouldReorder, occupiedType: type)
    }

    /// Termina la sesión: limpia la ocupación session-scoped.
    public func endingSession(_ profile: GymProfile) -> GymProfile {
        profile.endingSession()
    }
}