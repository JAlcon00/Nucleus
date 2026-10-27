//
//  SessionCompositionTests.swift
//  PRDomainTests
//
//  SCRUM-218 (PR-B004): composición de sesión con un catálogo sintético donde cada
//  ejercicio trabaja un solo músculo, así las series de cada músculo por sesión se cuentan
//  sin ambigüedad.
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
    ]
}

private func input(days: Int, minutes: Int?) throws -> BlockPlanningInput {
    BlockPlanningInput(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: days,
        priorities: [.chest, .back, .biceps].map { MusclePriority(muscleGroupID: $0, priority: .normal) },
        plannedWeeks: 6, varietyPreference: .balanced, catalog: try catalog(), restrictions: [],
        equipmentKnownness: .knownAvailable([.barbell, .dumbbell, .machine, .cable]), sessionMinutes: minutes
    )
}

private func planner() throws -> BlockPlanner {
    BlockPlanner(volumeAllocator: VolumeAllocator(config: try VolumeConfig(rule: VolumeDefaults.makeRule())))
}

@Suite("SCRUM-218 · Composición de sesión (PR-B004)")
struct SessionCompositionTests {

    @Test("Rango de ejercicios por duración en la regla versionada")
    func rangesByDuration() {
        let rule = SessionCompositionRule.standard
        #expect(rule.exerciseRange(forMinutes: 20) == 3...4)
        #expect(rule.exerciseRange(forMinutes: 30) == 3...4)
        #expect(rule.exerciseRange(forMinutes: 45) == 4...5)
        #expect(rule.exerciseRange(forMinutes: 60) == 5...7)
        #expect(rule.exerciseRange(forMinutes: 90) == 7...9)
        #expect(rule.exerciseRange(forMinutes: 180) == 7...9, "Más tiempo no agrega ejercicios por encima del último tramo")
        #expect(rule.minimumWorkSets == 2)
        #expect(rule.strengthAnchorMinimumSets == 3)
    }

    @Test("Un músculo entrenado 3 veces: su ancla sale en al menos 2 sesiones y sus series por sesión difieren en 1 como máximo")
    func anchorTwiceAndEvenSplit() throws {
        let input = try input(days: 3, minutes: nil)
        let planner = try planner()
        let result = try planner.plan(input: input)
        let anchors = planner.anchorExercises(input: input)
        let byID = Dictionary(input.catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(result.block.sessions.count == 3)

        for muscle in [MuscleGroup.ID.chest, .back, .biceps] {
            let anchor = try #require(anchors.first { byID[$0]?.primaryMuscles.first?.muscleGroupID == muscle })
            let perSession = result.block.sessions.map { session in
                session.plannedSets.filter { byID[$0.exerciseID]?.primaryMuscles.first?.muscleGroupID == muscle }.count
            }
            let withAnchor = result.block.sessions.filter { $0.plannedSets.contains { $0.exerciseID == anchor } }.count
            #expect(withAnchor >= 2, "\(muscle): el ancla sale en \(withAnchor) sesiones")
            #expect((perSession.max() ?? 0) - (perSession.min() ?? 0) <= 1, "\(muscle): \(perSession)")
        }
    }

    @Test("Ningún ejercicio con 1 serie, con o sin límite de tiempo", arguments: [nil, 30, 45, 60] as [Int?])
    func neverOneSet(minutes: Int?) throws {
        for days in 2...5 {
            let result = try planner().plan(input: try input(days: days, minutes: minutes))
            for session in result.block.sessions {
                let counts = Dictionary(grouping: session.plannedSets, by: \.exerciseID).mapValues(\.count)
                #expect(counts.values.allSatisfy { $0 >= 2 }, "\(days) días, \(minutes.map(String.init) ?? "sin límite") min, \(session.title): \(counts.values.sorted())")
            }
        }
    }

    @Test("Sin límite de tiempo no hay tope ni recorte: la semana suma el objetivo")
    func noTimeLimitKeepsWeeklyVolume() throws {
        let result = try planner().plan(input: try input(days: 2, minutes: nil))
        let total = result.block.sessions.map(\.plannedSets.count).reduce(0, +)
        let target = result.block.muscleTargets.map(\.targetSetsPerWeek).reduce(0, +)
        #expect(total == target)
        #expect(!result.explanation.facts.contains { $0.key == "sessionsOverRange" || $0.key == "sessionsOverTime" })
        #expect(result.explanation.facts.contains(DecisionFact(key: "sessionComposition", value: SessionCompositionRule.standard.version)))
    }
}
