//
//  ExerciseTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

/// Fixtures reutilizables del catálogo mínimo (PR-0102).
enum ExerciseFixtures {
    static let horizontalPressFamily = ExerciseFamily(
        name: "Horizontal Press",
        movementPatterns: [.horizontalPress]
    )

    static let hingeFamily = ExerciseFamily(
        name: "Hinge",
        movementPatterns: [.hinge]
    )

    static let squatFamily = ExerciseFamily(
        name: "Squat",
        movementPatterns: [.squat]
    )

    static let curlFamily = ExerciseFamily(
        name: "Elbow Flexion",
        movementPatterns: [.elbowFlexion]
    )

    static let dbBench = makeExercise(
        name: "Dumbbell Bench Press",
        aliases: ["DB Press", "Dumbbell Flat Press"],
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .dumbbell,
        jointClass: .multiJoint,
        family: horizontalPressFamily
    )

    static let smithBench = makeExercise(
        name: "Smith Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .smithMachine,
        jointClass: .multiJoint,
        family: horizontalPressFamily
    )

    static let machineChestPress = makeExercise(
        name: "Machine Chest Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .machine,
        jointClass: .multiJoint,
        family: horizontalPressFamily
    )

    static let romanianDeadlift = makeExercise(
        name: "Romanian Deadlift",
        pattern: .hinge,
        equipment: .barbell,
        jointClass: .multiJoint,
        family: hingeFamily
    )

    static let backSquat = makeExercise(
        name: "Back Squat",
        pattern: .squat,
        equipment: .barbell,
        jointClass: .multiJoint,
        family: squatFamily
    )

    static let bicepCurl = makeExercise(
        name: "Dumbbell Biceps Curl",
        pattern: .elbowFlexion,
        equipment: .dumbbell,
        jointClass: .singleJoint,
        family: curlFamily
    )

    private static func makeExercise(
        name: String,
        aliases: [String] = [],
        pattern: MovementPattern,
        angle: MovementAngle? = nil,
        equipment: EquipmentType,
        jointClass: JointClass,
        family: ExerciseFamily
    ) -> Exercise {
        Exercise(
            canonicalName: name,
            aliases: aliases,
            movementPattern: pattern,
            movementAngle: angle,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
            secondaryMuscles: [
                try! MuscleContribution(muscleGroupID: .triceps, activation: 0.6),
                try! MuscleContribution(muscleGroupID: .shoulders, activation: 0.4),
            ],
            equipment: equipment,
            laterality: .bilateral,
            jointClass: jointClass,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            localFatigue: [.chest: try! FatigueCost(normalized: 0.8)],
            loadability: .discreteIncrements,
            defaultRoles: [.anchor, .primaryCompound],
            contraindicationTags: [],
            substitutionFamilyID: family.id
        )
    }
}

@Suite("Exercise fixtures")
struct ExerciseFixturesTests {

    @Test("Press variants are distinct exercises but share a family")
    func pressVariantsDistinct() {
        let variants = [ExerciseFixtures.dbBench, ExerciseFixtures.smithBench, ExerciseFixtures.machineChestPress]
        #expect(Set(variants.map(\.id)).count == 3)
        #expect(Set(variants.map(\.equipment)).count == 3)
        #expect(Set(variants.map(\.substitutionFamilyID)).count == 1)
    }

    @Test("Horizontal press is compatible with its family")
    func pressFamilyCompatibility() {
        #expect(ExerciseFixtures.horizontalPressFamily.contains(.horizontalPress))
        #expect(!ExerciseFixtures.horizontalPressFamily.contains(.squat))
    }

    @Test("Exercise supports multiple secondary muscles")
    func supportsMultipleSecondaryMuscles() {
        #expect(ExerciseFixtures.dbBench.secondaryMuscles.count == 2)
        #expect(ExerciseFixtures.dbBench.primaryMuscles.count == 1)
    }

    @Test("No single muscle string; muscles are structured")
    func structuredMuscles() {
        let exercise = ExerciseFixtures.dbBench
        let allSegments = exercise.primaryMuscles + exercise.secondaryMuscles
        #expect(allSegments.map(\.muscleGroupID).contains(.chest))
        #expect(allSegments.map(\.muscleGroupID).contains(.triceps))
    }

    @Test("Exercise round-trips through Codable")
    func exerciseCodableRoundTrip() throws {
        let fixture = ExerciseFixtures.romanianDeadlift
        let data = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(Exercise.self, from: data)
        #expect(decoded == fixture)
        #expect(decoded.movementPattern == .hinge)
    }
}

@Suite("Value validation (PR-0102)")
struct ExerciseValueValidationTests {

    @Test("MuscleContribution rejects activation outside 0...1")
    func invalidActivationRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try MuscleContribution(muscleGroupID: .chest, activation: 1.5)
        }
    }

    @Test("FatigueCost rejects normalized outside 0...1")
    func invalidFatigueRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try FatigueCost(normalized: -0.1)
        }
    }

    @Test("ExerciseFamily validation distinguishes incompatible patterns")
    func familyValidation() {
        #expect(ExerciseFixtures.squatFamily.contains(.squat))
        #expect(!ExerciseFixtures.squatFamily.contains(ExerciseFixtures.bicepCurl.movementPattern))
    }
}
