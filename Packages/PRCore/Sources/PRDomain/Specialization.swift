//
//  Specialization.swift
//  PRDomain
//
//  Created by PR.
//
//  Specialization blocks (plan §18, promptMaster §18.2, PR-1802). Un bloque que
//  ESPECIALIZA unos músculos seleccionados (`.specialize`/`.emphasize`) mientras MANTIENE
//  el volumen de los no prioritarios en su propio tier, y VALIDA contra un presupuesto de
//  tiempo semanal. La distribución de volumen se delega a `VolumeAllocator` (PR-0502): este
//  motor no reinventa las reglas de volumen, sólo selecciona, categoriza y chequea el tiempo.
//
//  INVARIANTES: determinista; nunca rompe el presupuesto de tiempo en silencio (lo reporta);
//  los no prioritarios quedan en su rango de tier (maintain/normal) — no suben por capricho.
//

import Foundation

/// Selección de especialización a partir de las prioridades musculares (dependiente de la
/// fase de bodybuilding, PR-1801/PR-0502).
public struct SpecializationSelection: Equatable, Sendable {
    /// Músculos en tier `.specialize`.
    public let specializeTargets: [MuscleGroup.ID]
    /// Músculos en tier `.emphasize`.
    public let emphasizeTargets: [MuscleGroup.ID]
    /// ¿Hay al menos un músculo a especializar/enfatizar? Sin él no hay bloque de
    /// especialización (el motor no inventa targets).
    public let isSpecialization: Bool

    public init(specializeTargets: [MuscleGroup.ID], emphasizeTargets: [MuscleGroup.ID]) {
        self.specializeTargets = specializeTargets
        self.emphasizeTargets = emphasizeTargets
        self.isSpecialization = !specializeTargets.isEmpty || !emphasizeTargets.isEmpty
    }
}

/// Chequeo de presupuesto de tiempo semanal del bloque de especialización (PR-1802).
public struct SpecializationTimeCheck: Equatable, Sendable {
    /// Minutos estimados para el volumen total semanal del bloque.
    public let estimatedMinutes: Int
    /// Presupuesto de tiempo semanal disponible.
    public let budgetMinutes: Int
    /// ¿El bloque cabe dentro del presupuesto?
    public let fitsBudget: Bool

    public init(estimatedMinutes: Int, budgetMinutes: Int, fitsBudget: Bool) {
        self.estimatedMinutes = estimatedMinutes
        self.budgetMinutes = budgetMinutes
        self.fitsBudget = fitsBudget
    }
}

/// Resultado de construir un bloque de especialización (PR-1802).
public struct SpecializationBlock: Equatable, Sendable {
    /// Asignación de volumen semanal por músculo (de `VolumeAllocator`, PR-0502).
    public let allocation: VolumeAllocation
    /// Músculos que se especializan/enfatizan (targets del bloque).
    public let specializedMuscles: [MuscleGroup.ID]
    /// Músculos que se mantienen en su tier (no especializados).
    public let maintainedMuscles: [MuscleGroup.ID]
    /// Chequeo del presupuesto de tiempo semanal.
    public let timeCheck: SpecializationTimeCheck

    public init(
        allocation: VolumeAllocation,
        specializedMuscles: [MuscleGroup.ID],
        maintainedMuscles: [MuscleGroup.ID],
        timeCheck: SpecializationTimeCheck
    ) {
        self.allocation = allocation
        self.specializedMuscles = specializedMuscles
        self.maintainedMuscles = maintainedMuscles
        self.timeCheck = timeCheck
    }
}

/// Entrada del motor de especialización (PR-1802).
public struct SpecializationInput: Sendable {
    /// Prioridades musculares (tiers en la fase de bodybuilding).
    public let priorities: [MusclePriority]
    /// Presupuesto semanal de tiempo en minutos.
    public let weeklyTimeBudgetMinutes: Int
    /// Minutos estimados por working set (p. ej. desde `DurationEstimator`/perfil). No
    /// se inventa: lo provee el llamador/app.
    public let minutesPerWorkingSet: Double

    public init(priorities: [MusclePriority], weeklyTimeBudgetMinutes: Int, minutesPerWorkingSet: Double = 3.0) {
        self.priorities = priorities
        self.weeklyTimeBudgetMinutes = weeklyTimeBudgetMinutes
        self.minutesPerWorkingSet = minutesPerWorkingSet
    }
}

/// Motor determinista de bloques de especialización (PR-1802).
public struct SpecializationBlockEngine: Sendable {
    private let allocator: VolumeAllocator

    public init(allocator: VolumeAllocator) {
        self.allocator = allocator
    }

    /// Construye el bloque de especialización y valida el presupuesto de tiempo.
    ///
    /// Reglas:
    /// 1. `selected muscles emphasize/specialize`: los músculos en `.specialize`/`.emphasize`
    ///    son los targets de especialización.
    /// 2. `maintain targets for non-priorities`: los musculos no especializados conservan su
    ///    rango de tier (el `VolumeAllocator` les asigna su propio rango; no suben).
    /// 3. `time budget respected`: se estima el tiempo y se reporta si cabe; nunca se rompe
    ///    el presupuesto en silencio.
    public func build(input: SpecializationInput) throws -> SpecializationBlock {
        guard input.weeklyTimeBudgetMinutes >= 0, input.minutesPerWorkingSet.isFinite, input.minutesPerWorkingSet >= 0 else {
            throw DomainValidationError.invalidSpecializationInput
        }
        guard !input.priorities.isEmpty else {
            throw DomainValidationError.invalidSpecializationInput
        }

        let selection = Self.selection(from: input.priorities)

        // Volumen semanal por músculo según PR-0502 (cada uno en su propio tier).
        let allocation = try allocator.allocate(priorities: input.priorities)

        let specializedSet = Set(selection.specializeTargets).union(selection.emphasizeTargets)
        let targeted = allocation.targets.filter { specializedSet.contains($0.muscleGroupID) }
        let maintained = allocation.targets.filter { !specializedSet.contains($0.muscleGroupID) }

        // Chequeo de tiempo: volumen total × minutos por working set.
        let estimated = Int((Double(allocation.totalWeeklySets) * input.minutesPerWorkingSet).rounded(.up))
        let timeCheck = SpecializationTimeCheck(
            estimatedMinutes: estimated,
            budgetMinutes: input.weeklyTimeBudgetMinutes,
            fitsBudget: estimated <= input.weeklyTimeBudgetMinutes
        )

        return SpecializationBlock(
            allocation: allocation,
            specializedMuscles: targeted.map(\.muscleGroupID),
            maintainedMuscles: maintained.map(\.muscleGroupID),
            timeCheck: timeCheck
        )
    }

    /// Selecciona los músculos de especialización desde las prioridades (determinista, en
    /// orden de la entrada). Devuelve selección vacía si no hay ningún `.specialize`/`.emphasize`.
    public static func selection(from priorities: [MusclePriority]) -> SpecializationSelection {
        let specialize = priorities
            .filter { $0.priority == .specialize }
            .map(\.muscleGroupID)
        let emphasize = priorities
            .filter { $0.priority == .emphasize }
            .map(\.muscleGroupID)
        return SpecializationSelection(specializeTargets: specialize, emphasizeTargets: emphasize)
    }
}