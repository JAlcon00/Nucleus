//
//  Gym.swift
//  PRDomain
//
//  Created by PR.
//
//  Dominio de gym/máquina/equipamiento (promptMaster §6.4-6.5, PR-0105).
//  Diferencia estados de availability y permite historial por instancia de máquina.
//

import Foundation

// MARK: - Availability (promptMaster §6.4)

/// Estado de disponibilidad de un equipamiento.
/// - `doesNotExist`: persistente para ese gym hasta que el usuario lo cambie.
/// - `occupied`: estado temporal de la sesión (NO se persiste como hecho del gym).
/// - `unknown`: todavía no aprendido.
/// - `available`: confirmado o inferido.
public enum EquipmentAvailabilityState: String, Codable, Sendable, CaseIterable, Hashable {
    case doesNotExist
    case occupied
    case unknown
    case available
}

/// Disponibilidad de un tipo de equipamiento en un gym.
public struct EquipmentAvailability: Codable, Sendable, Hashable {
    public var equipmentType: EquipmentType
    public var state: EquipmentAvailabilityState

    public init(equipmentType: EquipmentType, state: EquipmentAvailabilityState) {
        self.equipmentType = equipmentType
        self.state = state
    }
}

// MARK: - MachineProfile (promptMaster §6.5)

/// Identificador tipado de una instancia de máquina.
public struct MachineProfileID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Clave para el historial de carga por `exercise + machineInstance`.
public struct MachineLoadHistoryKey: Codable, Sendable, Hashable {
    public var exerciseID: ExerciseID
    public var machineInstanceID: MachineProfileID

    public init(exerciseID: ExerciseID, machineInstanceID: MachineProfileID) {
        self.exerciseID = exerciseID
        self.machineInstanceID = machineInstanceID
    }
}

/// Instancia concreta de máquina en un gym.
/// La carga de dos máquinas del mismo tipo NO es comparable automáticamente.
public struct MachineProfile: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = MachineProfileID

    public let id: MachineProfileID
    public var gymID: GymID
    public var exerciseID: ExerciseID
    public var manufacturer: String?
    public var model: String?
    public var userLabel: String?

    public init(
        id: MachineProfileID = MachineProfileID(),
        gymID: GymID,
        exerciseID: ExerciseID,
        manufacturer: String? = nil,
        model: String? = nil,
        userLabel: String? = nil
    ) {
        self.id = id
        self.gymID = gymID
        self.exerciseID = exerciseID
        self.manufacturer = manufacturer
        self.model = model
        self.userLabel = userLabel
    }

    /// Clave de historial por instancia (exercise + máquina concreta).
    public var loadHistoryKey: MachineLoadHistoryKey {
        MachineLoadHistoryKey(exerciseID: exerciseID, machineInstanceID: id)
    }
}

// MARK: - BusyPattern

/// Nivel de ocupación aprendido para un equipamiento en un día.
public enum BusyLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case low
    case medium
    case high
}

/// Patrón de afluencia aprendido (referenciado en §6.4).
public struct BusyPattern: Codable, Sendable, Hashable {
    public var equipmentType: EquipmentType
    public var day: WeekDay
    public var busyLevel: BusyLevel

    public init(equipmentType: EquipmentType, day: WeekDay, busyLevel: BusyLevel) {
        self.equipmentType = equipmentType
        self.day = day
        self.busyLevel = busyLevel
    }
}

// MARK: - GymProfile (promptMaster §6.4)

/// Perfil de un gym: disponibilidad y máquinas instaladas.
public struct GymProfile: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = GymID

    public let id: GymID
    public var name: String
    public var equipmentAvailability: [EquipmentAvailability]
    public var machineInstances: [MachineProfile]
    public var learnedBusyPatterns: [BusyPattern]
    /// Equipos ocupados durante la sesión actual (session-scoped, no persistido).
    public var occupiedDuringSession: [EquipmentType]

    public init(
        id: GymID = GymID(),
        name: String,
        equipmentAvailability: [EquipmentAvailability] = [],
        machineInstances: [MachineProfile] = [],
        learnedBusyPatterns: [BusyPattern] = [],
        occupiedDuringSession: [EquipmentType] = []
    ) {
        self.id = id
        self.name = name
        self.equipmentAvailability = equipmentAvailability
        self.machineInstances = machineInstances
        self.learnedBusyPatterns = learnedBusyPatterns
        self.occupiedDuringSession = occupiedDuringSession
    }

    /// Consulta el estado observable de un equipamiento.
    /// La ocupación de la sesión tiene prioridad sobre el estado persistente.
    public func state(of equipmentType: EquipmentType) -> EquipmentAvailabilityState {
        if occupiedDuringSession.contains(equipmentType) {
            return .occupied
        }
        return equipmentAvailability.first { $0.equipmentType == equipmentType }?.state ?? .unknown
    }

    /// Marca un equipamiento como ocupado durante la sesión (transitorio).
    public func markingOccupied(_ equipmentType: EquipmentType) -> GymProfile {
        var copy = self
        if !copy.occupiedDuringSession.contains(equipmentType) {
            copy.occupiedDuringSession.append(equipmentType)
        }
        return copy
    }

    /// Finaliza la sesión: la ocupación es session-scoped, no persiste.
    /// Los equipos ocupados vuelven a su estado persistente (available/doesNotExist/unknown).
    public func endingSession() -> GymProfile {
        var copy = self
        copy.occupiedDuringSession = []
        return copy
    }
}
