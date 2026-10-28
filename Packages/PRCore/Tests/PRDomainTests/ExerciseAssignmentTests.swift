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

// MARK: - SCRUM-219: slots y scoring por eje

/// Pecho de referencia sintético: plano, inclinado y apertura con barra, mancuerna, máquina,
/// Smith y polea. La fatiga sigue el modelo del catálogo (lo guiado cansa menos).
private enum Chest {
    static let family = ExerciseFamily(name: "Chest", movementPatterns: [.horizontalPress])

    static func make(_ name: String, rank: Int, _ equipment: EquipmentType, angle: MovementAngle? = .flat,
                     joint: JointClass = .multiJoint, fatigue: Double) throws -> Exercise {
        Exercise(
            canonicalName: name,
            movementPattern: .horizontalPress,
            movementAngle: joint == .multiJoint ? angle : nil,
            primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1)],
            equipment: equipment,
            jointClass: joint,
            stabilityDemand: .low,
            skillDemand: .low,
            systemicFatigueCost: try FatigueCost(normalized: fatigue),
            loadability: .discreteIncrements,
            defaultRoles: joint == .multiJoint ? [.primaryCompound] : [.accessoryIsolation],
            substitutionFamilyID: family.id,
            staple: StapleSelection(muscle: .chest, rank: rank)
        )
    }

    static func catalog() throws -> [Exercise] {
        [
            try make("Barbell Bench", rank: 0, .barbell, fatigue: 0.65),
            try make("Dumbbell Incline", rank: 1, .dumbbell, angle: .incline, fatigue: 0.55),
            try make("Dumbbell Bench", rank: 2, .dumbbell, fatigue: 0.55),
            try make("Cable Fly", rank: 3, .cable, joint: .singleJoint, fatigue: 0.22),
            try make("Machine Press", rank: 4, .machine, fatigue: 0.35),
            try make("Dumbbell Fly", rank: 5, .dumbbell, joint: .singleJoint, fatigue: 0.27),
            try make("Smith Bench", rank: 6, .smithMachine, fatigue: 0.4),
            try make("Barbell Incline", rank: 7, .barbell, angle: .incline, fatigue: 0.65),
            try make("Machine Incline", rank: 8, .machine, angle: .incline, fatigue: 0.35),
            try make("Machine Fly", rank: 9, .machine, joint: .singleJoint, fatigue: 0.2),
        ]
    }
}

@Suite("SCRUM-219 · Slots y scoring por eje (ExerciseAssigner)")
struct ExerciseSelectionScoringTests {

    private let all: Set<EquipmentType> = [.barbell, .dumbbell, .machine, .smithMachine, .cable]

    private func assign(
        goal: TrainingGoal = .hypertrophy,
        experience: ExperienceLevel = .intermediate,
        phase: BodyCompositionPhase = .maintenance,
        variety: VarietyPreference = .balanced,
        sequence: Int = 0,
        equipment: Set<EquipmentType>? = nil
    ) throws -> [String] {
        let catalog = try Chest.catalog()
        let result = try ExerciseAssigner().assign(input: ExerciseAssignmentInput(
            muscleGroupID: .chest, catalog: catalog, varietyPreference: variety, restrictions: [],
            equipmentKnownness: .knownAvailable(equipment ?? all),
            selectionProfile: ExerciseSelectionProfile(goal: goal, experience: experience, phase: phase),
            blockSequence: sequence
        ))
        let names = Dictionary(catalog.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
        return result.assignments.compactMap { names[$0.exercise] }
    }

    @Test("Slots: el pecho cubre plano, inclinado y apertura antes de repetir uno")
    func slotsBeforeRepeating() throws {
        let rule = ExerciseSelectionRule.standard
        let byName = Dictionary(try Chest.catalog().map { ($0.canonicalName, $0) }, uniquingKeysWith: { first, _ in first })
        func slots(_ names: [String]) -> [ExerciseSlot] {
            names.compactMap { byName[$0].flatMap { rule.slot(of: $0, for: .chest) } }
        }
        #expect(slots(try assign(variety: .stable)) == [.flatPress, .inclinePress])
        #expect(slots(try assign(variety: .balanced)) == [.flatPress, .inclinePress, .chestFly])
        #expect(slots(try assign(variety: .varied)) == [.flatPress, .inclinePress, .chestFly, .flatPress])
    }

    @Test("Objetivo: con experiencia intermedia, la fuerza ancla en la barra y la hipertrofia en la mancuerna")
    func goalAxis() throws {
        #expect(try assign(goal: .strength).first == "Barbell Bench")
        #expect(try assign(goal: .hypertrophy).first == "Dumbbell Bench")
        #expect(try assign(goal: .generalHealth).first == "Machine Press")
    }

    @Test("Experiencia: el novato ancla en lo guiado (Smith si busca fuerza) y el avanzado con fuerza, en la barra")
    func experienceAxis() throws {
        #expect(try assign(goal: .strength, experience: .novice).first == "Smith Bench")
        #expect(try assign(goal: .hypertrophy, experience: .novice).first == "Machine Press")
        #expect(try assign(goal: .strength, experience: .advanced).first == "Barbell Bench")
    }

    @Test("Fase: en déficit los rotables pasan a lo de menos fatiga; el ancla no cambia")
    func phaseAxis() throws {
        let surplus = try assign(phase: .surplus)
        let deficit = try assign(phase: .deficit)
        #expect(surplus.first == deficit.first)
        #expect(surplus == ["Dumbbell Bench", "Dumbbell Incline", "Cable Fly"])
        #expect(deficit == ["Dumbbell Bench", "Machine Incline", "Machine Fly"])
    }

    @Test("Bloques: el mismo bloque da lo mismo; el siguiente conserva el ancla y cambia los rotables")
    func blockRotation() throws {
        let first = try assign(sequence: 0)
        let second = try assign(sequence: 1)
        #expect(try assign(sequence: 0) == first)
        #expect(first.first == second.first)
        #expect(Set(first.dropFirst()).isDisjoint(with: Set(second.dropFirst())), "\(first) → \(second)")
    }

    @Test("Un slot sin equipo: el ancla sale del siguiente slot que tenga ejercicios")
    func emptySlotFallsThrough() throws {
        #expect(try assign(equipment: [.cable]) == ["Cable Fly"])
    }
}