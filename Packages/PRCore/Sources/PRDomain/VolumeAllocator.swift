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

    /// Dónde cae la experiencia dentro del rango (0 = mínimo, 1 = máximo), acotado a [0, 1]
    /// (SCRUM-227, ADR-0004).
    public func position(for experience: ExperienceLevel) -> Double {
        let value = rule.parameters[VolumeConfigKeys.positionKey(for: experience)] ?? 0
        return min(1, max(0, value))
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
    /// Posición dentro del rango por experiencia (SCRUM-227, ADR-0004).
    public static let positionNovice = "positionNovice"
    public static let positionBeginner = "positionBeginner"
    public static let positionIntermediate = "positionIntermediate"
    public static let positionAdvanced = "positionAdvanced"
    public static let positionCompetitive = "positionCompetitive"

    public static let allRequired: Set<String> = [
        maintainMin, maintainMax,
        normalMin, normalMax,
        emphasizeMin, emphasizeMax,
        specializeMin, specializeMax,
        positionNovice, positionBeginner, positionIntermediate, positionAdvanced, positionCompetitive,
    ]

    public static func positionKey(for experience: ExperienceLevel) -> String {
        switch experience {
        case .novice: return positionNovice
        case .beginner: return positionBeginner
        case .intermediate: return positionIntermediate
        case .advanced: return positionAdvanced
        case .competitive: return positionCompetitive
        }
    }

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
/// v2 (SCRUM-227, ADR-0004): la experiencia elige el punto dentro del rango: novato el
/// mínimo, principiante un cuarto, intermedio la mitad, avanzado y competitivo el máximo.
public enum VolumeDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "volume.weeklySetsPerMuscle")

    public static func makeRule(version: Int = 2) throws -> EvidenceRule {
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
                VolumeConfigKeys.positionNovice: 0,
                VolumeConfigKeys.positionBeginner: 0.25,
                VolumeConfigKeys.positionIntermediate: 0.5,
                VolumeConfigKeys.positionAdvanced: 1,
                VolumeConfigKeys.positionCompetitive: 1,
            ]
        )
    }
}

/// Distribuye volumen semanal por grupo muscular (plan §4B, PR-0502).
///
/// Reglas deterministas y versionadas via `VolumeConfig` (EvidenceRule):
/// - Volumen según `PriorityTier`: el rango menor para mantiene, el mayor para
///   especializa. Dentro del rango, la experiencia elige el punto (SCRUM-227, ADR-0004):
///   novato el mínimo, avanzado el máximo. Sin experiencia, el mínimo. El tiempo no sube el
///   volumen: sólo lo recorta después la composición de la sesión (SCRUM-218).
/// - Sin prioridades declaradas, no se inventan músculos: la asignación queda
///   vacía y el llamador (BlockPlanner) decide qué grupos incluir.
/// - Nunca se generan volúmenes negativos.
public struct VolumeAllocator: Sendable {
    private let config: VolumeConfig

    public init(config: VolumeConfig) {
        self.config = config
    }

    /// `maxWeeklySets`: las series que caben en la semana con el tiempo del usuario. Si el
    /// volumen del nivel no cabe, baja hacia el mínimo del rango (nunca por debajo), una serie a
    /// la vez del músculo que más tiene sobre su mínimo (SCRUM-227: el tiempo pone el techo).
    public func allocate(
        priorities: [MusclePriority],
        experience: ExperienceLevel? = nil,
        maxWeeklySets: Int? = nil
    ) throws -> VolumeAllocation {
        try allocate(
            priorities: priorities, weeklyTimeBudgetMinutes: nil, minutesPerWorkingSet: nil,
            experience: experience, maxWeeklySets: maxWeeklySets
        )
    }

    /// Distribuye volumen respetando (aproximadamente) un presupuesto de tiempo semanal.
    ///
    /// El presupuesto se respeta sin romper los rangos versionados de evidencia: el volumen
    /// asigna el punto del rango que marca la experiencia (el mínimo sin ella) y se estiman los minutos
    /// (`totalWeeklySets × minutesPerWorkingSet`). Si el volumen cabe en el presupuesto se
    /// reporta `fitsBudget == true`; si el presupuesto es más ajustado que el suelo de
    /// evidencia, se reporta `fitsBudget == false` en lugar de bajar volumen por debajo del
    /// mínimo versionado o generar volumen negativo. Determinista: mismas entradas →
    /// mismo chequeo.
    public func allocate(
        priorities: [MusclePriority],
        weeklyTimeBudgetMinutes: Int?,
        minutesPerWorkingSet: Double?,
        experience: ExperienceLevel? = nil,
        maxWeeklySets: Int? = nil
    ) throws -> VolumeAllocation {
        let reference = try config.reference()
        let ranges = priorities.map { config.range(for: $0.priority) }
        var sets = ranges.map { representativeSets(for: $0, experience: experience) }
        if let maxWeeklySets {
            // El tiempo pone el techo: se baja hacia el mínimo, nunca por debajo.
            while sets.reduce(0, +) > maxWeeklySets,
                  let index = sets.indices
                      .filter({ sets[$0] > ranges[$0].lowerBound })
                      .max(by: { (sets[$0] - ranges[$0].lowerBound, $0) < (sets[$1] - ranges[$1].lowerBound, $1) }) {
                sets[index] -= 1
            }
        }
        var targets: [MuscleVolumeAssignment] = []
        for (index, priority) in priorities.enumerated() {
            targets.append(try MuscleVolumeAssignment(
                muscleGroupID: priority.muscleGroupID,
                weeklySets: sets[index],
                priority: priority.priority,
                ruleReference: reference
            ))
        }
        let minTotal = ranges.map(\.lowerBound).reduce(0, +)
        let maxTotal = ranges.map(\.upperBound).reduce(0, +)

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

    /// Punto del rango para la experiencia: mínimo + ⌊posición × ancho del rango⌋. Nunca
    /// sale del rango. Sin experiencia, el mínimo (como antes de SCRUM-227).
    private func representativeSets(for range: ClosedRange<Int>, experience: ExperienceLevel?) -> Int {
        guard let experience else { return range.lowerBound }
        let width = Double(range.upperBound - range.lowerBound)
        let offset = Int((config.position(for: experience) * width).rounded(.down))
        return min(range.upperBound, range.lowerBound + offset)
    }
}