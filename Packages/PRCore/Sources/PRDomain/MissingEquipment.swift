//
//  MissingEquipment.swift
//  PRDomain
//
//  Created by PR.
//
//  Mark missing (plan §9, RF-011, PR-0903). Persiste un equipo como inexistente en el
//  perfil del gym y garantiza que las futuras sesiones NO programan ejercicios que lo
//  requieran, salvo que el usuario revierta (unknown/available). Determinista.
//

import Foundation

/// Un ítem candidato con el equipamiento que requiere.
public struct EquipmentRequiringItem: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let requiredEquipment: Set<EquipmentType>

    public init(id: UUID, name: String, requiredEquipment: Set<EquipmentType>) {
        self.id = id
        self.name = name
        self.requiredEquipment = requiredEquipment
    }
}

/// Resultado de filtrar ítems frente a equipos marcados como inexistentes.
public struct MissingEquipmentFilter: Equatable, Sendable {
    /// Ítems cuya maquinaria SÍ existe (programables).
    public let allowed: [EquipmentRequiringItem]
    /// Ítems bloqueados por máquina marcada inexistente.
    public let blocked: [EquipmentRequiringItem]
    /// Tipos de máquina marcados como inexistentes en el perfil.
    public let missingTypes: Set<EquipmentType>

    public init(allowed: [EquipmentRequiringItem], blocked: [EquipmentRequiringItem], missingTypes: Set<EquipmentType>) {
        self.allowed = allowed
        self.blocked = blocked
        self.missingTypes = missingTypes
    }
}

/// Bloquea las máquinas marcadas como inexistentes en planificaciones futuras (PR-0903).
public struct MissingEquipmentGuard: Sendable {

    public init() {}

    /// ¿Está este tipo de equipo marcado como inexistente (missing) en el perfil?
    public func isMissing(_ type: EquipmentType, in profile: GymProfile) -> Bool {
        profile.state(of: type) == .doesNotExist
    }

    /// ¿El ítem requiere alguna máquina inexistente en el perfil?
    public func isBlocked(_ item: EquipmentRequiringItem, in profile: GymProfile) -> Bool {
        item.requiredEquipment.contains { isMissing($0, in: profile) }
    }

    /// Filtra: sólo se permiten ítems cuya maquinaria existe. Las sesiones futuras
    /// no programan las máquinas marcadas inexistentes.
    public func filter(_ items: [EquipmentRequiringItem], in profile: GymProfile) -> MissingEquipmentFilter {
        let missingTypes = items
            .flatMap { $0.requiredEquipment }
            .filter { isMissing($0, in: profile) }
        let missingSet = Set(missingTypes)
        let allowed = items.filter { !isBlocked($0, in: profile) }
        let blocked = items.filter { isBlocked($0, in: profile) }
        return MissingEquipmentFilter(allowed: allowed, blocked: blocked, missingTypes: missingSet)
    }

    /// Permite al usuario revertir la marca de inexistente (vuelve a `.unknown`),
    /// de modo que futuras sesiones puedan volver a programar esa máquina.
    public func revert(_ type: EquipmentType, in profile: GymProfile) throws -> GymProfile {
        try GymProfileManager().setAvailability(type, to: .unknown, on: profile)
    }
}