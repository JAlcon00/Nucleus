//
//  VolumeAllocator.swift
//  PRDomain
//
//  Created by PR.
//
//  Volume allocator (plan §4B, PR-0502). Distribuye targets de sets semanales
//  por grupo muscular a partir de las prioridades del usuario y de reglas de
//  evidencia versionadas. No genera volumen negativo ni inventa músculos;
//  respeta maintain/normal/emphasize/specialize. Mismas entradas → mismo target.
//

import Foundation

/// Target semanal de volumen para un grupo muscular.
public struct MuscleVolumeAssignment: Codable, Sendable, Hashable {
    public let muscleGroupID: MuscleGroup.ID
    /// Sets por semana para este grupo.
    public let weeklySets: Int
    /// PriorityTier que gobernó la asignación.
    public let priority: PriorityTier
    /// Regla versionada que respalda el rango usado.
    public let ruleReference: EvidenceRuleReference

    public init(
        muscleGroupID: MuscleGroup.ID,
        weeklySets: Int,
        priority: PriorityTier,
        ruleReference: EvidenceRuleReference
    ) throws {
        guard weeklySets >= 0 else {
            throw VolumeAllocationError.negativeVolume(
                muscle: muscleGroupID.rawValue,
                sets: weeklySets
            )
        }
        self.muscleGroupID = muscleGroupID
        self.weeklySets = weeklySets
        self.priority = priority
        self.ruleReference = ruleReference
    }
}

/// Resultado del allocator: targets por músculo + presupuesto global aplicado.
public struct VolumeAllocation: Codable, Sendable, Hashable {
    public let targets: [MuscleVolumeAssignment]
    public let minTotalWeeklySets: Int
    public let maxTotalWeeklySets: Int
    /// Chequeo de presupuesto de tiempo semanal aproximado (nil si no se pidió).
    public let timeCheck: SpecializationTimeCheck?

    public init(targets: [MuscleVolumeAssignment], minTotalWeeklySets: Int, maxTotalWeeklySets: Int, timeCheck: SpecializationTimeCheck? = nil) {
        self.targets = targets
        self.minTotalWeeklySets = minTotalWeeklySets
        self.maxTotalWeeklySets = maxTotalWeeklySets
        self.timeCheck = timeCheck
    }

    /// Suma de sets semanales prescritos.
    public var totalWeeklySets: Int { targets.reduce(0) { $0 + $1.weeklySets } }

    public func target(for muscle: MuscleGroup.ID) -> Int? {
        targets.first { $0.muscleGroupID == muscle }?.weeklySets
    }
}

/// Problemas de entrada del allocator.
public enum VolumeAllocationError: Error, Equatable, Sendable {
    case negativeVolume(muscle: String, sets: Int)
    case missingVolumeRule
    case invalidGoal(goal: TrainingGoal)
    case invalidPhase(phase: BodyCompositionPhase)
}

/// Configuración versionada de los rangos de volumen semanal, en forma de regla
/// de evidencia. Centraliza las constantes científicas (SKILL.md: no magic
/// numbers) y permite auditar qué versión de regla respaldó cada target.
public struct VolumeConfig: Sendable {
    public let rule: EvidenceRule

    public init(rule: EvidenceRule) throws {
        let missing = VolumeConfigKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw VolumeAllocationError.missingVolumeRule
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }

    /// Rango [min, max] de sets semanales para un tier dado.
    public func range(for tier: PriorityTier) -> ClosedRange<Int> {
        let (minKey, maxKey) = VolumeConfigKeys.keys(for: tier)
        let min = Int(rule.parameters[minKey] ?? 0)
        let max = Int(rule.parameters[maxKey] ?? 0)
        return min...max
    }
}

/// Claves canónicas de parámetros de la regla de volumen.
public enum VolumeConfigKeys {
    public static let maintainMin = "maintainMin"
    public static let maintainMax = "maintainMax"
    public static let normalMin = "normalMin"
    public static let normalMax = "normalMax"
    public static let emphasizeMin = "emphasizeMin"
    public static let emphasizeMax = "emphasizeMax"
    public static let specializeMin = "specializeMin"
    public static let specializeMax = "specializeMax"

    public static let allRequired: Set<String> = [
        maintainMin, maintainMax,
        normalMin, normalMax,
        emphasizeMin, emphasizeMax,
        specializeMin, specializeMax,
    ]

    public static func keys(for tier: PriorityTier) -> (min: String, max: String) {
        switch tier {
        case .maintain: return (maintainMin, maintainMax)
        case .normal: return (normalMin, normalMax)
        case .emphasize: return (emphasizeMin, emphasizeMax)
        case .specialize: return (specializeMin, specializeMax)
        }
    }
}

/// Regla de evidencia por defecto que modela el rango de sets semanales por tier.
/// (Valores orientativos de producto; la UI/Evidence Registry los versiona.)
public enum VolumeDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "volume.weeklySetsPerMuscle")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        try EvidenceRule(
            id: ruleID,
            name: "Weekly sets per muscle group",
            category: .volume,
            confidence: .emerging,
            version: version,
            parameters: [
                VolumeConfigKeys.maintainMin: 4,
                VolumeConfigKeys.maintainMax: 6,
                VolumeConfigKeys.normalMin: 8,
                VolumeConfigKeys.normalMax: 12,
                VolumeConfigKeys.emphasizeMin: 12,
                VolumeConfigKeys.emphasizeMax: 16,
                VolumeConfigKeys.specializeMin: 16,
                VolumeConfigKeys.specializeMax: 20,
            ]
        )
    }
}

/// Distribuye volumen semanal por grupo muscular (plan §4B, PR-0502).
///
/// Reglas deterministas y versionadas via `VolumeConfig` (EvidenceRule):
/// - Volumen según `PriorityTier`: el rango menor para mantiene, el mayor para
///   especializa.
/// - Sin prioridades declaradas, no se inventan músculos: la asignación queda
///   vacía y el llamador (BlockPlanner) decide qué grupos incluir.
/// - Nunca se generan volúmenes negativos.
public struct VolumeAllocator: Sendable {
    private let config: VolumeConfig

    public init(config: VolumeConfig) {
        self.config = config
    }

    public func allocate(priorities: [MusclePriority]) throws -> VolumeAllocation {
        try allocate(priorities: priorities, weeklyTimeBudgetMinutes: nil, minutesPerWorkingSet: nil)
    }

    /// Distribuye volumen respetando (aproximadamente) un presupuesto de tiempo semanal.
    ///
    /// El presupuesto se respeta sin romper los rangos versionados de evidencia: el volumen
    /// asigna el representativo (mínimo) de cada tier y se estiman los minutos
    /// (`totalWeeklySets × minutesPerWorkingSet`). Si el volumen cabe en el presupuesto se
    /// reporta `fitsBudget == true`; si el presupuesto es más ajustado que el suelo de
    /// evidencia, se reporta `fitsBudget == false` en lugar de bajar volumen por debajo del
    /// mínimo versionado o generar volumen negativo. Determinista: mismas entradas →
    /// mismo chequeo.
    public func allocate(
        priorities: [MusclePriority],
        weeklyTimeBudgetMinutes: Int?,
        minutesPerWorkingSet: Double?
    ) throws -> VolumeAllocation {
        let reference = try config.reference()
        var targets: [MuscleVolumeAssignment] = []
        var minTotal = 0
        var maxTotal = 0

        for priority in priorities {
            let range = config.range(for: priority.priority)
            let sets = self.representativeSets(for: range)
            targets.append(try MuscleVolumeAssignment(
                muscleGroupID: priority.muscleGroupID,
                weeklySets: sets,
                priority: priority.priority,
                ruleReference: reference
            ))
            minTotal += range.lowerBound
            maxTotal += range.upperBound
        }

        let allocation = VolumeAllocation(
            targets: targets,
            minTotalWeeklySets: minTotal,
            maxTotalWeeklySets: maxTotal
        )

        guard let budget = weeklyTimeBudgetMinutes,
              let perSet = minutesPerWorkingSet, perSet >= 0, perSet.isFinite else {
            return allocation
        }

        let estimated = Int((Double(allocation.totalWeeklySets) * perSet).rounded(.up))
        let timeCheck = SpecializationTimeCheck(
            estimatedMinutes: estimated,
            budgetMinutes: budget,
            fitsBudget: estimated <= budget
        )
        return VolumeAllocation(
            targets: targets,
            minTotalWeeklySets: minTotal,
            maxTotalWeeklySets: maxTotal,
            timeCheck: timeCheck
        )
    }

    /// Valor representativo estable del rango. Para mantener un target constante
    /// y determinista usamos el mínimo del rango; el block planner puede subirlo
    /// dentro del máximo según experiencia/tiempo.
    private func representativeSets(for range: ClosedRange<Int>) -> Int {
        range.lowerBound
    }
}