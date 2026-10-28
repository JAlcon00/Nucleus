//
//  MaintenanceCompositionTests.swift
//  PRDomainTests
//
//  SCRUM-215 (PR-B002): pantorrilla y core en mantenimiento, con un catálogo sintético
//  donde cada ejercicio trabaja un solo músculo. Al tope de ejercicios y al recortar por
//  tiempo salen después del resto de lo no protegido; si aun así no caben en la semana,
//  la explicación lo dice (gana el tiempo, decisión de Jesús del 2026-10-27).
//

import Foundation
import Testing
@testable import PRDomain

private func exercise(_ name: String, _ pattern: MovementPattern, compound: Bool, muscle: MuscleGroup.ID) throws -> Exercise {
    Exercise(
        id: ExerciseID(),
        canonicalName: name,
        movementPattern: pattern,
        primaryMuscles: [try MuscleContribution(muscleGroupID: muscle, activation: 1.0)],
        equipment: .barbell,
        jointClass: compound ? .multiJoint : .singleJoint,
        stabilityDemand: compound ? .high : .moderate,
        skillDemand: compound ? .high : .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        localFatigue: [muscle: try FatigueCost(normalized: 0.7)],
        loadability: .discreteIncrements,
        defaultRoles: [compound ? .primaryCompound : .accessoryIsolation],
        substitutionFamilyID: ExerciseFamilyID()
    )
}

private func catalog() throws -> [Exercise] {
    [
        try exercise("Bench Press", .horizontalPress, compound: true, muscle: .chest),
        try exercise("Cable Fly", .horizontalPress, compound: false, muscle: .chest),
        try exercise("Barbell Row", .horizontalPull, compound: true, muscle: .back),
        try exercise("Lat Pulldown", .verticalPull, compound: true, muscle: .back),
        try exercise("Dumbbell Curl", .elbowFlexion, compound: false, muscle: .biceps),
        try exercise("Hammer Curl", .elbowFlexion, compound: false, muscle: .biceps),
        try exercise("Standing Calf Raise", .calfPlantarFlexion, compound: false, muscle: .calves),
        try exercise("Cable Crunch", .trunkFlexion, compound: false, muscle: .core),
    ]
}

private func input(days: Int, minutes: Int?, goal: TrainingGoal = .hypertrophy) throws -> BlockPlanningInput {
    BlockPlanningInput(
        goal: goal, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: days,
        priorities: [.chest, .back, .biceps].map { MusclePriority(muscleGroupID: $0, priority: .normal) }
            + [.calves, .core].map { MusclePriority(muscleGroupID: $0, priority: .maintain) },
        plannedWeeks: 6, varietyPreference: .balanced, catalog: try catalog(), restrictions: [],
        equipmentKnownness: .knownAvailable([.barbell, .dumbbell, .machine, .cable]), sessionMinutes: minutes
    )
}

private func planner() throws -> BlockPlanner {
    BlockPlanner(volumeAllocator: VolumeAllocator(config: try VolumeConfig(rule: VolumeDefaults.makeRule())))
}

private func muscles(in session: SessionTemplate, _ catalog: [Exercise]) -> [MuscleGroup.ID] {
    let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen: [ExerciseID] = []
    for set in session.plannedSets where !seen.contains(set.exerciseID) { seen.append(set.exerciseID) }
    return seen.compactMap { byID[$0]?.primaryMuscles.first?.muscleGroupID }
}

private func leftOut(_ result: BlockPlanningResult) -> Set<String> {
    let raw = result.explanation.facts.first { $0.key == "maintenanceLeftOut" }?.value ?? ""
    return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}

@Suite("SCRUM-215 · Pantorrilla y core en mantenimiento (composición)")
struct MaintenanceCompositionTests {

    @Test("Sin límite de tiempo entran siempre, con al menos 2 series, y no hay aviso")
    func alwaysInWithoutTimeLimit() throws {
        for days in 2...5 {
            let input = try input(days: days, minutes: nil)
            let result = try planner().plan(input: input)
            let all = result.block.sessions.flatMap { muscles(in: $0, input.catalog) }
            #expect(all.contains(.calves) && all.contains(.core), "\(days) días")
            #expect(leftOut(result).isEmpty)
            for session in result.block.sessions {
                let counts = Dictionary(grouping: session.plannedSets, by: \.exerciseID).mapValues(\.count)
                #expect(counts.values.allSatisfy { $0 >= 2 })
            }
        }
    }

    @Test("Al tope de ejercicios sale antes un aislamiento normal que la pantorrilla o el core")
    func normalIsolationLeavesFirstAtCap() throws {
        // 2 días de cuerpo completo con 45 min: tope de 5 ejercicios por sesión.
        let input = try input(days: 2, minutes: 45)
        let result = try planner().plan(input: input)
        #expect(leftOut(result).isEmpty)
        for session in result.block.sessions {
            let present = muscles(in: session, input.catalog)
            #expect(present.count <= SessionCompositionRule.standard.exerciseRange(forMinutes: 45).upperBound, "\(present)")
            #expect(present.contains(.calves) && present.contains(.core), "\(session.title): \(present)")
            #expect(present.filter { $0 == .biceps }.count <= 1, "Un curl salió antes: \(present)")
        }
    }

    @Test("Con poco tiempo: lo que no cabe en la semana se dice; nunca se pierde sin aviso", arguments: [30, 45, 60])
    func leftOutIsExplained(minutes: Int) throws {
        for days in 2...5 {
            for goal in [TrainingGoal.hypertrophy, .strength] {
                let input = try input(days: days, minutes: minutes, goal: goal)
                let result = try planner().plan(input: input)
                let all = Set(result.block.sessions.flatMap { muscles(in: $0, input.catalog) })
                let notes = leftOut(result)
                for muscle in [MuscleGroup.ID.calves, .core] {
                    #expect(all.contains(muscle) != notes.contains(muscle.rawValue), "\(days) días, \(minutes) min, \(goal), \(muscle)")
                }
            }
        }
    }
}
