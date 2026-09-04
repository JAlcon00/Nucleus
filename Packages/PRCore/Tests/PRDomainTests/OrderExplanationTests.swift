//
//  OrderExplanationTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del OrderExplanation (PR-0703): el ExerciseOrderEngine explica de forma
//  determinista "por qué va primero" con facts concretos (rol, prioridad muscular,
//  demanda técnica), en el mismo orden que el ejercicio ocupa.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Order explanation (PR-0703)")
struct OrderExplanationTests {

    let engine = ExerciseOrderEngine()

    private let primaryCompound = Self.make(
        name: "Bench Press",
        pattern: .horizontalPress,
        role: .primaryCompound,
        muscle: .chest,
        skill: .moderate
    )
    private let accessory = Self.make(
        name: "Cable Fly",
        pattern: .horizontalPress,
        role: .accessoryIsolation,
        muscle: .chest,
        skill: .low
    )
    private let priorityIsolation = Self.make(
        name: "Side Lateral Raise",
        pattern: .shoulderAbduction,
        role: .priorityIsolation,
        muscle: .shoulders,
        skill: .low
    )

    @Test("Explanation order matches the ordered exercises rank by rank")
    func explanationAlignsWithOrder() throws {
        let priorities = [MusclePriority(muscleGroupID: .shoulders, priority: .specialize)]
        let input = ExerciseOrderInput(
            exercises: [accessory, primaryCompound, priorityIsolation],
            priorities: priorities,
            goal: .bodybuilding
        )
        let result = try engine.orderWithExplanation(input: input)

        #expect(result.ordered.map(\.id) == result.explanation.perExercise.map(\.exerciseID))
        #expect(result.explanation.perExercise.map(\.rank) == result.ordered.map(\.rank))
    }

    @Test("Primary compound gets a role fact")
    func primaryCompoundHasRoleFact() throws {
        let input = ExerciseOrderInput(exercises: [primaryCompound, accessory], priorities: [], goal: .hypertrophy)
        let result = try engine.orderWithExplanation(input: input)

        let compoundFacts = result.explanation.perExercise
            .first { $0.exerciseID == primaryCompound.id }!
        #expect(compoundFacts.facts.contains { $0.key == "exercise.order.role" })
        #expect(compoundFacts.facts.contains { $0.value.contains("primaryCompound") })
    }

    @Test("Specialized muscle gets a musclePriority fact")
    func specialtyHasMusclePriorityFact() throws {
        let priorities = [MusclePriority(muscleGroupID: .shoulders, priority: .specialize)]
        let input = ExerciseOrderInput(exercises: [accessory, priorityIsolation], priorities: priorities, goal: .bodybuilding)
        let result = try engine.orderWithExplanation(input: input)

        let item = result.explanation.perExercise.first { $0.exerciseID == priorityIsolation.id }!
        #expect(item.facts.contains { $0.key == "exercise.order.musclePriority" })
        #expect(item.facts.contains { $0.value.contains("60") }) // specialize bonus
    }

    @Test("High skill demand exposes a skillDemand fact")
    func highSkillDemandFact() throws {
        let skillHeavy = Self.make(name: "Back Squat", pattern: .squat, role: .primaryCompound, muscle: .quadriceps, skill: .high)
        let input = ExerciseOrderInput(exercises: [primaryCompound, skillHeavy], priorities: [], goal: .strength)
        let result = try engine.orderWithExplanation(input: input)

        let item = result.explanation.perExercise.first { $0.exerciseID == skillHeavy.id }!
        #expect(item.facts.contains { $0.key == "exercise.order.skillDemand" })
        #expect(item.facts.contains { $0.value.contains("high") })
    }

    @Test("Facts are deterministic across runs")
    func factsDeterministic() throws {
        let priorities = [MusclePriority(muscleGroupID: .shoulders, priority: .emphasize)]
        let input = ExerciseOrderInput(
            exercises: [accessory, primaryCompound, priorityIsolation],
            priorities: priorities,
            goal: .bodybuilding
        )
        let a = try engine.orderWithExplanation(input: input).explanation
        let b = try engine.orderWithExplanation(input: input).explanation
        #expect(a.perExercise.map(\.facts) == b.perExercise.map(\.facts))
    }

    @Test("Explanation is Codable (round-trip)")
    func explanationCodable() throws {
        let input = ExerciseOrderInput(exercises: [primaryCompound, accessory, priorityIsolation], priorities: [], goal: .bodybuilding)
        let explanation = try engine.orderWithExplanation(input: input).explanation
        let data = try JSONEncoder().encode(explanation)
        let decoded = try JSONDecoder().decode(OrderExplanation.self, from: data)
        #expect(decoded.perExercise.count == explanation.perExercise.count)
        #expect(decoded.perExercise.first!.facts == explanation.perExercise.first!.facts)
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