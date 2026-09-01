//
//  FatigueInterferenceTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del FatigueInterferenceEngine (PR-0702, promptMaster §9.2): penaliza la
//  pre-fatiga de musculatura de un movimiento prioritario posterior, no bloquea
//  supersets compatibles y usa configuración versionada.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("FatigueInterferenceEngine (PR-0702)")
struct FatigueInterferenceTests {

    let engine = FatigueInterferenceEngine()
    let config = try! FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule())

    // Triceps pushdown first pre-fatigues triceps, which bench needs as secondary.
    private let tricepsPushdown = make(
        name: "Triceps Pushdown",
        role: .accessoryIsolation,
        muscle: .triceps,
        local: [.triceps: 0.8]
    )
    private let benchPress = make(
        name: "Bench Press",
        role: .primaryCompound,
        muscle: .chest,
        primary: [.chest: 1.0],
        secondary: [.triceps: 0.6, .shoulders: 0.4],
        local: [.chest: 0.7, .triceps: 0.5]
    )
    // Bicep curl fatigues only biceps — no overlap with bench.
    private let bicepCurl = make(
        name: "Dumbbell Curl",
        role: .accessoryIsolation,
        muscle: .biceps,
        local: [.biceps: 0.8]
    )

    @Test("Pre-fatiguing a muscle needed by a later priority movement is penalized")
    func penalizesPreFatigue() throws {
        let assessment = try engine.assess(input: [tricepsPushdown, benchPress], config: config)
        #expect(assessment.totalPenalty > 0)
        #expect(assessment.penalties.count == 1)
        #expect(assessment.penalties.first!.overFatiguedMuscles.contains(.triceps))
    }

    @Test("Reverse order (priority first) has zero interference penalty")
    func priorityFirstNoPenalty() throws {
        let assessment = try engine.assess(input: [benchPress, tricepsPushdown], config: config)
        // Bench no longer pre-fatigues the priority movement after it.
        #expect(assessment.totalPenalty == 0)
    }

    @Test("Compatible superset (no shared priority muscle) is not penalized")
    func compatibleSupersetNotPenalized() throws {
        let assessment = try engine.assess(input: [bicepCurl, benchPress], config: config)
        #expect(assessment.totalPenalty == 0)
    }

    @Test("Reorder moves a pre-fatiguing accessory after a less interfering one without harming priority")
    func reorderMinimizesInterference() throws {
        // [tricepsPushdown, bicepCurl, benchPress] → bench uses triceps; engine
        // prefers to place bench before tricepsPushdown when it reduces penalty,
        // yet never moves bench (the priority/compound) later.
        let input = [tricepsPushdown, bicepCurl, benchPress]
        let assessment = try engine.reorder(input: input, config: config)
        // Bench (priority compound) must not be moved after the accessories.
        let benchIndex = assessment.orderedExercises.firstIndex { $0.id == benchPress.id }!
        let pushdownIndex = assessment.orderedExercises.firstIndex { $0.id == tricepsPushdown.id }!
        #expect(benchIndex < pushdownIndex)
    }

    @Test("Config is versioned and reference is auditable")
    func versionedConfig() throws {
        let reference = try config.reference()
        #expect(reference.ruleID == FatigueInterferenceDefaults.ruleID)
        #expect(reference.version >= 1)
    }

    @Test("Default config has all required parameters")
    func configValid() throws {
        for key in FatigueConfigKeys.allRequired {
            #expect(config.rule.parameters[key] != nil)
        }
    }

    @Test("Config missing parameters throws")
    func missingConfigThrows() {
        let bad = try! EvidenceRule(
            id: FatigueInterferenceDefaults.ruleID,
            name: "broken",
            category: .ordering,
            confidence: .emerging,
            version: 1,
            parameters: [:]
        )
        #expect(throws: FatigueInterferenceError.self) {
            _ = try FatigueInterferenceConfig(rule: bad)
        }
    }

    @Test("Insufficient exercises throws")
    func insufficientThrows() {
        #expect(throws: FatigueInterferenceError.self) {
            _ = try engine.assess(input: [bicepCurl], config: config)
        }
    }

    @Test("Deterministic across runs")
    func deterministic() throws {
        let input = [tricepsPushdown, bicepCurl, benchPress]
        let a = try engine.reorder(input: input, config: config).orderedExercises.map(\.id)
        let b = try engine.reorder(input: input, config: config).orderedExercises.map(\.id)
        #expect(a == b)
    }

    // MARK: - Fixtures

    private static func make(
        name: String,
        role: ExerciseRole,
        muscle: MuscleGroup.ID,
        primary: [MuscleGroup.ID: Double]? = nil,
        secondary: [MuscleGroup.ID: Double] = [:],
        local: [MuscleGroup.ID: Double]
    ) -> Exercise {
        Exercise(
            id: ExerciseID(),
            canonicalName: name,
            movementPattern: primary != nil ? .horizontalPress : (muscle == .triceps ? .elbowExtension : .elbowFlexion),
            primaryMuscles: (primary ?? [muscle: 1.0]).map { key, value in
                try! MuscleContribution(muscleGroupID: key, activation: value)
            },
            secondaryMuscles: secondary.map { try! MuscleContribution(muscleGroupID: $0.key, activation: $0.value) },
            equipment: role == .accessoryIsolation ? .cable : .barbell,
            jointClass: role == .accessoryIsolation ? .singleJoint : .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            localFatigue: local.mapValues { try! FatigueCost(normalized: $0) },
            loadability: .discreteIncrements,
            defaultRoles: [role],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}