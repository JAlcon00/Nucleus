//
//  Exercise.swift
//  PRDomain
//
//  Created by PR.
//
//  Dominio de conocimiento de ejercicios (promptMaster §6.2, PR-0102).
//  Un ejercicio representa biomecánica y función programática, no sólo
//  nombre y músculo. Permite distinguir variantes (e.g. DB Bench vs
//  Smith Bench vs machine press) y modelar sustituciones por familia.
//

import Foundation

// MARK: - MovementPattern

/// Patrón de movimiento principal de un ejercicio.
public enum MovementPattern: String, Codable, Sendable, CaseIterable, Hashable {
    case horizontalPress
    case verticalPress
    case horizontalPull
    case verticalPull
    case squat
    case hinge
    case lunge
    case kneeExtension
    case kneeFlexion
    case hipExtension
    case shoulderAbduction
    case shoulderExtension
    case elbowFlexion
    case elbowExtension
    case calfPlantarFlexion
    case trunkFlexion
    case trunkExtension
    case trunkRotation
    case carry
    case conditioning
    case mobility
    case posing
}

// MARK: - ExerciseRole

/// Rol funcional de un ejercicio dentro de la programación.
public enum ExerciseRole: String, Codable, Sendable, CaseIterable, Hashable {
    case anchor
    case primaryCompound
    case secondaryCompound
    case priorityIsolation
    case accessoryIsolation
    case optionalAccessory
    case warmup
    case mobility
    case conditioning
    case posing
}

// MARK: - EquipmentType

/// Tipo de equipamiento requerido por el ejercicio.
/// Permite distinguir variantes (e.g. DB Bench vs Smith Bench vs machine press).
public enum EquipmentType: String, Codable, Sendable, CaseIterable, Hashable {
    case barbell
    case dumbbell
    case smithMachine
    case cable
    case machine
    case bodyweight
    case bands
    case kettlebell
    case sled
    case plateLoaded
    case other
}

// MARK: - MovementAngle

/// Angulo del movimiento (predominantemente para press/remo).
public enum MovementAngle: String, Codable, Sendable, CaseIterable, Hashable {
    case flat
    case incline
    case decline
    case upright
    case overhead
    case neutral
    case declined
}

// MARK: - Laterality

/// Lateralidad de un ejercicio.
public enum Laterality: String, Codable, Sendable, CaseIterable, Hashable {
    case bilateral
    case unilateralLeft
    case unilateralRight
    case alternating
}

// MARK: - JointClass

/// Clasificación según número de articulaciones involucradas.
public enum JointClass: String, Codable, Sendable, CaseIterable, Hashable {
    case singleJoint
    case multiJoint
}

// MARK: - DemandLevel

/// Nivel de demanda (estabilidad / skill).
public enum DemandLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case low
    case moderate
    case high
}

// MARK: - Loadability

/// Cómo se incrementa la carga sobre el ejercicio.
public enum Loadability: String, Codable, Sendable, CaseIterable, Hashable {
    case fixedStack
    case discreteIncrements
    case continuous
    case bodyweight
    case resisted
}

// MARK: - RestrictionTag

/// Etiqueta de contraindicación / restricción asociable a un ejercicio.
public enum RestrictionTag: String, Codable, Sendable, CaseIterable, Hashable {
    case shoulder
    case knee
    case wrist
    case elbow
    case lowerBack
    case neck
    case hip
    case ankle
    case grip
    case vestibular
    case coreStability
}

// MARK: - MuscleGroup

/// Grupo muscular canónico. `ID` == el propio tipo (tipos con identidad).
public enum MuscleGroup: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case quadriceps
    case hamstrings
    case glutes
    case calves
    case spinalErectors
    case core

    public typealias ID = MuscleGroup
    public var id: MuscleGroup { self }
}

// MARK: - MuscleContribution

/// Contribución de un grupo muscular a un ejercicio.
/// Reemplaza el modelo plano `muscle: String` (PR-0102).
public struct MuscleContribution: Codable, Sendable, Hashable {
    public var muscleGroupID: MuscleGroup.ID
    /// Nivel normalizado de activación (0...1). Valor programático para
    /// asignación de volumen; no pretende diagnosticar.
    public var activation: Double

    public init(muscleGroupID: MuscleGroup.ID, activation: Double) throws {
        guard activation.isFinite, (0...1).contains(activation) else {
            throw DomainValidationError.invalidNormalized(value: activation)
        }
        self.muscleGroupID = muscleGroupID
        self.activation = activation
    }
}

// MARK: - FatigueCost

/// Costo de fatiga normalizado (0...1) generado por el ejercicio.
public struct FatigueCost: Codable, Sendable, Hashable {
    public let normalized: Double

    public init(normalized: Double) throws {
        guard normalized.isFinite, (0...1).contains(normalized) else {
            throw DomainValidationError.invalidNormalized(value: normalized)
        }
        self.normalized = normalized
    }
}

// MARK: - ExerciseFamily

/// Identificador tipado de una familia de ejercicios sustituibles.
public struct ExerciseFamilyID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Familia de ejercicios sustituibles entre sí con función programática equivalente.
public struct ExerciseFamily: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = ExerciseFamilyID

    public let id: ExerciseFamilyID
    public var name: String
    /// Patrones de movimiento compatibles dentro de la familia.
    public var movementPatterns: Set<MovementPattern>

    public init(
        id: ExerciseFamilyID = ExerciseFamilyID(),
        name: String,
        movementPatterns: Set<MovementPattern>
    ) {
        self.id = id
        self.name = name
        self.movementPatterns = movementPatterns
    }

    /// Valida que un patrón de movimiento pertenezca a la familia.
    public func contains(_ pattern: MovementPattern) -> Bool {
        movementPatterns.contains(pattern)
    }
}

// MARK: - Exercise

/// Un ejercicio del catálogo de conocimiento (PR-0102).
/// Modela biomecánica y función programática; NO un mero nombre+músculo.
public struct Exercise: Identifiable, Codable, Sendable, Equatable {
    public let id: ExerciseID
    public var canonicalName: String
    public var aliases: [String]
    public var movementPattern: MovementPattern
    public var movementAngle: MovementAngle?
    public var primaryMuscles: [MuscleContribution]
    public var secondaryMuscles: [MuscleContribution]
    public var equipment: EquipmentType
    public var laterality: Laterality
    public var jointClass: JointClass
    public var stabilityDemand: DemandLevel
    public var skillDemand: DemandLevel
    public var systemicFatigueCost: FatigueCost
    public var localFatigue: [MuscleGroup.ID: FatigueCost]
    public var loadability: Loadability
    public var defaultRoles: Set<ExerciseRole>
    public var contraindicationTags: Set<RestrictionTag>
    public var substitutionFamilyID: ExerciseFamily.ID

    public init(
        id: ExerciseID = ExerciseID(),
        canonicalName: String,
        aliases: [String] = [],
        movementPattern: MovementPattern,
        movementAngle: MovementAngle? = nil,
        primaryMuscles: [MuscleContribution],
        secondaryMuscles: [MuscleContribution] = [],
        equipment: EquipmentType,
        laterality: Laterality = .bilateral,
        jointClass: JointClass,
        stabilityDemand: DemandLevel,
        skillDemand: DemandLevel,
        systemicFatigueCost: FatigueCost,
        localFatigue: [MuscleGroup.ID: FatigueCost] = [:],
        loadability: Loadability,
        defaultRoles: Set<ExerciseRole>,
        contraindicationTags: Set<RestrictionTag> = [],
        substitutionFamilyID: ExerciseFamily.ID
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.aliases = aliases
        self.movementPattern = movementPattern
        self.movementAngle = movementAngle
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.laterality = laterality
        self.jointClass = jointClass
        self.stabilityDemand = stabilityDemand
        self.skillDemand = skillDemand
        self.systemicFatigueCost = systemicFatigueCost
        self.localFatigue = localFatigue
        self.loadability = loadability
        self.defaultRoles = defaultRoles
        self.contraindicationTags = contraindicationTags
        self.substitutionFamilyID = substitutionFamilyID
    }
}
