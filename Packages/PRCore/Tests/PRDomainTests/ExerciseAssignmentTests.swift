//
//  ExerciseAssignmentTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del ExerciseAssigner (PR-0503, promptMaster §6): asignación de anchors
//  y rotatables por grupo muscular, respetando equipo disponible, restricciones
//  y variedad. Determinista y sin depender de strings.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("ExerciseAssigner (PR-0503)")
struct ExerciseAssignerTests {

    // Positive control: chest exercises in the horizontal-press family.

    @Test("Assigns anchor and rotatable separately")
    func anchorAndRotatable() throws {
        let input = makeInput(for: .chest, catalog: ExerciseFixtures.pressCatalog, equipment: [.dumbbell, .smithMachine, .machine])
        let result = try ExerciseAssigner().assign(input: input)
        #expect(result.muscleGroupID == .chest)
        #expect(result.anchor != nil)
        #expect(!result.assignments.isEmpty)
        #expect(result.assignments.filter { $0.role == .anchor }.count == 1)
        #expect(result.assignments.contains { $0.role == .rotatable })
    }

    @Test("Known equipment excludes non-available machines")
    func knownEquipmentExcludes() throws {
        // Only dumbbells available → smith + machine excluded.
        let available: Set<EquipmentType> = [.dumbbell]
        let input = makeInput(for: .chest, catalog: ExerciseFixtures.pressCatalog, equipment: available)
        let result = try ExerciseAssigner().assign(input: input)
        let selectedIDs = Set(result.assignments.map(\.exercise))
        #expect(!selectedIDs.contains(ExerciseFixtures.smithBench.id))
        #expect(!selectedIDs.contains(ExerciseFixtures.machineChestPress.id))
        #expect(selectedIDs == [ExerciseFixtures.dbBench.id])
    }

    @Test("Unknown equipment does not silently drop exercises")
    func unknownEquipmentKeepsSuggestions() throws {
        let input = makeInput(for: .chest, catalog: ExerciseFixtures.pressCatalog, equipmentKnownness: .unknown)
        let result = try ExerciseAssigner().assign(input: input)
        #expect(result.assignments.count >= 2)
        #expect(result.anchor != nil)
    }

    @Test("Restriction forbidding a movement pattern excludes those exercises")
    func restrictionPatternExcludes() throws {
        let restriction = makeRestriction(forbiddingPatterns: [.horizontalPress])
        let input = makeInput(
            for: .chest,
            catalog: ExerciseFixtures.pressCatalog,
            equipment: [.dumbbell, .smithMachine, .machine],
            restrictions: [restriction]
        )
        #expect(throws: ExerciseAssignmentError.self) {
            _ = try ExerciseAssigner().assign(input: input)
        }
    }

    @Test("Restriction forbidding one exercise still allows the rest")
    func restrictionExerciseExcludes() throws {
        let smithID = ExerciseFixtures.smithBench.id
        let restriction = makeRestriction(forbiddenExerciseIDs: [smithID])
        let input = makeInput(
            for: .chest,
            catalog: ExerciseFixtures.pressCatalog,
            equipment: [.dumbbell, .smithMachine, .machine],
            restrictions: [restriction]
        )
        let result = try ExerciseAssigner().assign(input: input)
        #expect(!result.assignments.contains { $0.exercise == smithID })
        #expect(result.assignments.contains { $0.exercise == ExerciseFixtures.dbBench.id })
    }

    @Test("Explicitly allowed exercise survives forbidden pattern")
    func allowedListPrecedence() throws {
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            forbiddenPatterns: [.horizontalPress],
            allowedExerciseIDs: [ExerciseFixtures.machineChestPress.id]
        )
        let input = makeInput(
            for: .chest,
            catalog: ExerciseFixtures.pressCatalog,
            equipment: [.dumbbell, .smithMachine, .machine],
            restrictions: [restriction]
        )
        let result = try ExerciseAssigner().assign(input: input)
        #expect(result.anchor == ExerciseFixtures.machineChestPress.id)
    }

    @Test("Many rotatables for varied preference")
    func variedKeepsMoreRotatables() throws {
        let input = makeInput(
            for: .chest,
            catalog: ExerciseFixtures.pressCatalog,
            equipment: [.dumbbell, .smithMachine, .machine],
            variety: .varied
        )
        let result = try ExerciseAssigner().assign(input: input)
        #expect(result.assignments.filter { $0.role == .rotatable }.count >= 2)
    }

    @Test("Stable preference keeps fewer rotatables")
    func stableKeepsFewerRotatables() throws {
        let input = makeInput(
            for: .chest,
            catalog: ExerciseFixtures.pressCatalog,
            equipment: [.dumbbell, .smithMachine, .machine],
            variety: .stable
        )
        let result = try ExerciseAssigner().assign(input: input)
        #expect(result.assignments.filter { $0.role == .rotatable }.count <= ExerciseAssignerTests.rotatable(for: .balanced) + 1)
        #expect(result.anchor != nil)
    }

    @Test("Determinstic across runs")
    func deterministic() throws {
        let base = makeInput(for: .chest, catalog: ExerciseFixtures.pressCatalog, equipment: [.dumbbell, .smithMachine, .machine])
        let a = try ExerciseAssigner().assign(input: base)
        let b = try ExerciseAssigner().assign(input: base)
        #expect(a.assignments.map(\.exercise) == b.assignments.map(\.exercise))
        #expect(a.assignments.map(\.role) == b.assignments.map(\.role))
    }

    @Test("No available exercise throws explicit error")
    func noAvailableThrows() throws {
        // Catalog empty for the muscle → no candidates.
        let input = makeInput(for: .chest, catalog: [], equipment: [.dumbbell])
        #expect(throws: ExerciseAssignmentError.self) {
            _ = try ExerciseAssigner().assign(input: input)
        }
    }

    // MARK: - Fixtures

    private static func rotatable(for variety: VarietyPreference) -> Int {
        switch variety {
        case .stable: return 1
        case .balanced: return 2
        case .varied: return 3
        }
    }

    private func makeInput(
        for muscle: MuscleGroup.ID,
        catalog: [Exercise],
        equipment: Set<EquipmentType>? = nil,
        variety: VarietyPreference = .balanced,
        restrictions: [TrainingRestriction] = [],
        equipmentKnownness: EquipmentKnownness? = nil
    ) -> ExerciseAssignmentInput {
        ExerciseAssignmentInput(
            muscleGroupID: muscle,
            catalog: catalog,
            varietyPreference: variety,
            restrictions: restrictions,
            equipmentKnownness: equipmentKnownness ?? .knownAvailable(equipment ?? [])
        )
    }

    private func makeRestriction(
        forbiddingPatterns: Set<MovementPattern> = [],
        forbiddenExerciseIDs: Set<ExerciseID> = []
    ) -> TrainingRestriction {
        TrainingRestriction(
            bodyRegion: .shoulder,
            forbiddenPatterns: forbiddingPatterns,
            forbiddenExerciseIDs: forbiddenExerciseIDs
        )
    }
}

private extension ExerciseFixtures {
    static var pressCatalog: [Exercise] { [dbBench, smithBench, machineChestPress] }
}