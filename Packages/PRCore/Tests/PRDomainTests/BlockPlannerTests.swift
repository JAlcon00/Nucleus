//
//  BlockPlannerTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del BlockPlanner (PR-0504, plan §4F): genera un TrainingBlock completo
//  persistible (4–8 semanas), determinista y explicable; el rebuild genera un
//  bloque NUEVO sin borrar historial previo.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("BlockPlanner (PR-0504)")
struct BlockPlannerTests {

    // Un conjunto pequeño de ejercicios por cada músculo prioritario.
    private let chestExercise = Self.make(name: "Bench Press", pattern: .horizontalPress, role: .primaryCompound, muscle: .chest)
    private let chestFly = Self.make(name: "Cable Fly", pattern: .horizontalPress, role: .accessoryIsolation, muscle: .chest)
    private let bicepCurl = Self.make(name: "Dumbbell Curl", pattern: .elbowFlexion, role: .accessoryIsolation, muscle: .biceps)
    private let backRow = Self.make(name: "Barbell Row", pattern: .horizontalPull, role: .primaryCompound, muscle: .back)

    private func makeInput(
        weeks: Int = 6,
        days: Int = 3,
        priorities: [MusclePriority]? = nil,
        variety: VarietyPreference = .balanced
    ) -> BlockPlanningInput {
        BlockPlanningInput(
            goal: .hypertrophy,
            phase: .maintenance,
            experience: .intermediate,
            trainingDaysPerWeek: days,
            priorities: priorities ?? [
                MusclePriority(muscleGroupID: .chest, priority: .normal),
                MusclePriority(muscleGroupID: .biceps, priority: .normal),
            ],
            plannedWeeks: weeks,
            varietyPreference: variety,
            catalog: testCatalog,
            restrictions: [],
            equipmentKnownness: .knownAvailable([.barbell, .dumbbell, .machine, .cable])
        )
    }

    private var testCatalog: [Exercise] { [chestExercise, chestFly, bicepCurl, backRow] }

    @Test("Generates a complete persistible block with weeks in 4...8")
    func completePersistibleBlock() throws {
        let planner = makePlanner()
        let result = try planner.plan(input: makeInput(weeks: 6))
        let block = result.block
        #expect((4...8).contains(block.plannedWeeks))
        #expect(block.status == .planned)
        #expect(!block.sessions.isEmpty)
        #expect(!block.muscleTargets.isEmpty)
        // Persistible: Codable round-trip.
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(TrainingBlock.self, from: data)
        #expect(decoded.id == block.id)
        #expect(decoded.sessions.count == block.sessions.count)
    }

    @Test("Rejects weeks outside 4...8")
    func rejectsBadWeeks() throws {
        let planner = makePlanner()
        #expect(throws: BlockPlanningError.self) {
            _ = try planner.plan(input: makeInput(weeks: 9))
        }
    }

    @Test("Rejects empty priorities (does not invent muscles)")
    func rejectsEmptyPriorities() throws {
        let planner = makePlanner()
        #expect(throws: BlockPlanningError.self) {
            _ = try planner.plan(input: makeInput(priorities: []))
        }
    }

    @Test("Structure is explainable (facts + versioned rule references)")
    func explainable() throws {
        let planner = makePlanner()
        let result = try planner.plan(input: makeInput())
        let facts = result.explanation.facts
        #expect(facts.contains { $0.key == "goal" && $0.value == TrainingGoal.hypertrophy.rawValue })
        #expect(facts.contains { $0.key == "split" })
        #expect(facts.contains { $0.key == "plannedWeeks" && $0.value == "6" })
        #expect(facts.contains { $0.key == "totalWeeklySets" })
        #expect(!result.explanation.ruleReferences.isEmpty)
    }

    @Test("Rebuild produces a NEW block id and does not erase history")
    func rebuildDoesNotEraseHistory() throws {
        let planner = makePlanner()
        let first = try planner.plan(input: makeInput())
        let second = try planner.plan(input: makeInput())
        // Distintos bloques (no muta ni borra).
        #expect(first.block.id != second.block.id)
        #expect(first.block.sessions.count == second.block.sessions.count)
        #expect(first.block.sessions.count > 0)
    }

    @Test("Deterministic across runs (same input → same block structure)")
    func deterministic() throws {
        let planner = makePlanner()
        let a = try planner.plan(input: makeInput())
        let b = try planner.plan(input: makeInput())
        #expect(a.block.name == b.block.name)
        #expect(a.block.sessions.map(\.plannedSets.count) == b.block.sessions.map(\.plannedSets.count))
        #expect(a.split == b.split)
    }

    @Test("Excludes exercises blocked by restrictions (no restricted pattern in block)")
    func respectsRestrictions() throws {
        let restricted = TrainingRestriction(
            bodyRegion: .shoulder,
            forbiddenPatterns: [.horizontalPress]
        )
        let input = BlockPlanningInput(
            goal: .hypertrophy,
            phase: .maintenance,
            experience: .intermediate,
            trainingDaysPerWeek: 3,
            priorities: [MusclePriority(muscleGroupID: .chest, priority: .normal)],
            plannedWeeks: 5,
            varietyPreference: .balanced,
            catalog: testCatalog,
            restrictions: [restricted],
            equipmentKnownness: .unknown
        )
        // Con el patrón horizontalPress prohibido y un solo músculo chest, la
        // asignación no tiene candidatos válidos → error explícito.
        #expect(throws: ExerciseAssignmentError.self) {
            _ = try makePlanner().plan(input: input)
        }
    }

    // MARK: - Helpers

    private func makePlanner() -> BlockPlanner {
        BlockPlanner(volumeAllocator: VolumeAllocator(config: try! VolumeConfig(rule: VolumeDefaults.makeRule())))
    }

    private static func make(
        name: String,
        pattern: MovementPattern,
        role: ExerciseRole,
        muscle: MuscleGroup.ID
    ) -> Exercise {
        Exercise(
            id: ExerciseID(),
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: muscle, activation: 1.0)],
            equipment: .barbell,
            jointClass: role == .primaryCompound ? .multiJoint : .singleJoint,
            stabilityDemand: role == .primaryCompound ? .high : .moderate,
            skillDemand: role == .primaryCompound ? .high : .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            localFatigue: [muscle: try! FatigueCost(normalized: 0.7)],
            loadability: .discreteIncrements,
            defaultRoles: [role],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}