//
//  ExerciseOrderTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del ExerciseOrderEngine (PR-0701, promptMaster §9): ordenación base
//  determinista por prioridad muscular, rol funcional y demanda técnica.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("ExerciseOrderEngine (PR-0701)")
struct ExerciseOrderTests {

    let engine = ExerciseOrderEngine()

    // Fixtures del block de prueba.
    private let benchChest = Self.make(
        name: "Bench Press",
        pattern: .horizontalPress,
        role: .primaryCompound,
        muscle: .chest,
        skill: .moderate
    )
    private let squat = Self.make(
        name: "Back Squat",
        pattern: .squat,
        role: .primaryCompound,
        muscle: .quadriceps,
        skill: .high
    )
    private let flies = Self.make(
        name: "Cable Fly",
        pattern: .horizontalPress,
        role: .accessoryIsolation,
        muscle: .chest,
        skill: .low
    )
    private let bicepCurl = Self.make(
        name: "Dumbbell Curl",
        pattern: .elbowFlexion,
        role: .accessoryIsolation,
        muscle: .biceps,
        skill: .low
    )
    private let sideDeltRaise = Self.make(
        name: "Side Lateral Raise",
        pattern: .shoulderAbduction,
        role: .priorityIsolation,
        muscle: .shoulders,
        skill: .low
    )
    private let conditioning = Self.make(
        name: "Sled Push",
        pattern: .conditioning,
        role: .conditioning,
        muscle: .quadriceps,
        skill: .low
    )

    @Test("Primary compounds before accessory isolation")
    func compoundsBeforeAccessories() throws {
        let input = ExerciseOrderInput(exercises: [bicepCurl, benchChest, flies], priorities: [], goal: .hypertrophy)
        let ordered = try engine.order(input: input).map(\.id)
        checkOrder([benchChest, flies, bicepCurl].map(\.id), in: ordered)
    }

    @Test("Higher skill (technique) comes before lower skill within same role")
    func skillLiftsPriorityItemEarlier() throws {
        let input = ExerciseOrderInput(exercises: [benchChest, squat], priorities: [], goal: .strength)
        let ordered = try engine.order(input: input).map(\.id)
        // Ambas primary compound; squat high skill → antes del bench moderate.
        checkOrder([squat, benchChest].map(\.id), in: ordered)
    }

    @Test("Specialized priority isolation comes before non-priority accessories")
    func priorityIsolationCanComeEarlier() throws {
        let priorities = [MusclePriority(muscleGroupID: .shoulders, priority: .specialize)]
        let input = ExerciseOrderInput(
            exercises: [bicepCurl, flies, sideDeltRaise],
            priorities: priorities,
            goal: .bodybuilding
        )
        let ordered = try engine.order(input: input).map(\.id)
        #expect(ordered.first == sideDeltRaise.id)
        #expect(ordered.last == bicepCurl.id)
    }

    @Test("Optional + conditioning/posing go last")
    func optionalConditioningLast() throws {
        let input = ExerciseOrderInput(exercises: [benchChest, flies, conditioning], priorities: [], goal: .generalHealth)
        let ordered = try engine.order(input: input).map(\.id)
        #expect(ordered.first == benchChest.id)
        #expect(ordered.last == conditioning.id)
    }

    @Test("Empty input throws")
    func emptyThrows() throws {
        let input = ExerciseOrderInput(exercises: [], priorities: [], goal: .generalHealth)
        #expect(throws: ExerciseOrderError.self) {
            _ = try engine.order(input: input)
        }
    }

    @Test("Deterministic across runs")
    func deterministic() throws {
        let input = ExerciseOrderInput(
            exercises: [bicepCurl, flies, sideDeltRaise, conditioning, benchChest, squat],
            priorities: [MusclePriority(muscleGroupID: .shoulders, priority: .specialize)],
            goal: .bodybuilding
        )
        let a = try engine.order(input: input).map(\.id)
        let b = try engine.order(input: input).map(\.id)
        #expect(a == b)
    }

    @Test("Ranks are contiguous 1...N")
    func ranksContiguous() throws {
        let input = ExerciseOrderInput(
            exercises: [bicepCurl, flies, sideDeltRaise, conditioning, benchChest, squat],
            priorities: [],
            goal: .generalHealth
        )
        let ranks = try engine.order(input: input).map(\.rank)
        #expect(ranks == Array(1...ranks.count))
    }

    // MARK: - Fixtures

    private static func make(
        name: String,
        pattern: MovementPattern,
        role: ExerciseRole,
        muscle: MuscleGroup.ID,
        skill: DemandLevel
    ) -> Exercise {
        Exercise(
            id: ExerciseID(),
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: muscle, activation: 1.0)],
            equipment: role == .conditioning ? .sled : .machine,
            jointClass: role == .conditioning ? .multiJoint : (role == .priorityIsolation ? .singleJoint : .multiJoint),
            stabilityDemand: .moderate,
            skillDemand: skill,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [role],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}

private extension ExerciseOrderTests {
    /// Comprueba que `expectedOrder` aparece exactamente en ese orden dentro de `ordered`.
    func checkOrder(_ expectedOrder: [ExerciseID], in ordered: [ExerciseID]) {
        for i in 0..<(expectedOrder.count - 1) {
            #expect(ordered.firstIndex(of: expectedOrder[i])! < ordered.firstIndex(of: expectedOrder[i + 1])!)
        }
    }
}