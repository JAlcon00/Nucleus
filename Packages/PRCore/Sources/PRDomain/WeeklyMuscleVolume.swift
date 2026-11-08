//
//  WeeklyMuscleVolume.swift
//  PRDomain
//
//  SCRUM-268 (PR-H006): series por músculo de la semana contra su rango. Cuenta con la misma
//  regla con la que el motor reparte el objetivo semanal (`BlockPlanner.buildSessions`):
//  cada serie completada cuenta UNA vez, para el músculo del ejercicio, que es su principal
//  de mayor activación (`ExercisePrimaryResolver`, el mismo de `BlockTransition`). Los
//  secundarios no suman. El rango sale de la regla versionada `volume.weeklySetsPerMuscle`
//  según la prioridad del músculo en el bloque (`VolumeConfig.range(for:)`).
//
//  INVARIANTES: puro y determinista; nunca inventa un músculo para un ejercicio que no
//  conoce; un músculo entrenado fuera del plan se dice, sin nivel.
//

import Foundation

/// Dónde cae un músculo frente al rango de su prioridad.
public enum MuscleVolumeLevel: Equatable, Sendable {
    /// Por debajo del mínimo: le faltan `missing` series.
    case belowRange(missing: Int)
    case inRange
    case aboveRange
}

/// Qué se sabe de un músculo esta semana.
public enum MuscleVolumeStatus: Equatable, Sendable {
    /// Músculo del plan: su objetivo del bloque, su rango y su nivel.
    case planned(target: Int, range: ClosedRange<Int>, level: MuscleVolumeLevel)
    /// Se entrenó, pero el plan no le pide series.
    case outsidePlan
}

/// Series de un músculo en la semana.
public struct MuscleWeekVolume: Equatable, Sendable, Identifiable {
    public let muscle: MuscleGroup
    public let sets: Int
    public let status: MuscleVolumeStatus
    public var id: MuscleGroup { muscle }

    public init(muscle: MuscleGroup, sets: Int, status: MuscleVolumeStatus) {
        self.muscle = muscle
        self.sets = sets
        self.status = status
    }
}

/// Regla del conteo semanal por músculo (SCRUM-268).
public struct WeeklyMuscleVolumeRule: Sendable {
    private let config: VolumeConfig
    private let resolver: any ExercisePrimaryResolver

    public init(config: VolumeConfig, resolver: some ExercisePrimaryResolver) {
        self.config = config
        self.resolver = resolver
    }

    /// - Parameters:
    ///   - completedSets: series completadas de la semana, por ejercicio.
    ///   - targets: objetivo semanal de cada músculo del bloque.
    ///   - priorities: prioridad de cada músculo del bloque; sin prioridad, normal.
    /// - Returns: los músculos del plan en el orden del bloque y, después, los entrenados
    ///   fuera del plan en el orden de `MuscleGroup`.
    public func volume(
        completedSets: [ExerciseID: Int],
        targets: [MuscleVolumeTarget],
        priorities: [MusclePriority]
    ) -> [MuscleWeekVolume] {
        var setsByMuscle: [MuscleGroup: Int] = [:]
        for (exerciseID, count) in completedSets where count > 0 {
            guard let muscle = resolver.primaryMuscle(of: exerciseID) else { continue }
            setsByMuscle[muscle, default: 0] += count
        }
        let tierByMuscle = Dictionary(priorities.map { ($0.muscleGroupID, $0.priority) }, uniquingKeysWith: { first, _ in first })

        var result: [MuscleWeekVolume] = []
        var listed: Set<MuscleGroup> = []
        for target in targets where !listed.contains(target.muscleGroupID) {
            let muscle = target.muscleGroupID
            let sets = setsByMuscle[muscle] ?? 0
            let range = config.range(for: tierByMuscle[muscle] ?? .normal)
            result.append(MuscleWeekVolume(
                muscle: muscle,
                sets: sets,
                status: .planned(target: target.targetSetsPerWeek, range: range, level: level(sets, in: range))
            ))
            listed.insert(muscle)
        }
        for muscle in MuscleGroup.allCases where !listed.contains(muscle) {
            guard let sets = setsByMuscle[muscle], sets > 0 else { continue }
            result.append(MuscleWeekVolume(muscle: muscle, sets: sets, status: .outsidePlan))
        }
        return result
    }

    private func level(_ sets: Int, in range: ClosedRange<Int>) -> MuscleVolumeLevel {
        if sets < range.lowerBound { return .belowRange(missing: range.lowerBound - sets) }
        if sets > range.upperBound { return .aboveRange }
        return .inRange
    }
}
