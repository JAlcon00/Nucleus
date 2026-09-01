//
//  SubstitutionScoringTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del motor de sustitución (PR-0904): gate de seguridad, ranking por
//  pattern/muscle/role/angle/fatigue/history/preference/availability, determinismo
//  reproducible y "no safe substitute" cuando no hay candidatos seguros.
//

import Foundation
import Testing
@testable import PRDomain

private let familyChest = ExerciseFamilyID()

private enum SubFixture {
    static let flatDBPress = make(
        name: "DB Flat Press",
        pattern: .horizontalPress,
        equipment: .dumbbell,
        primary: [.chest],
        angle: .flat,
        fatigue: 0.6,
        role: .primaryCompound,
        family: familyChest,
        contraindications: []
    )

    static let smithPress = make(
        name: "Smith Machine Press",
        pattern: .horizontalPress,
        equipment: .smithMachine,
        primary: [.chest],
        angle: .flat,
        fatigue: 0.7,
        role: .primaryCompound,
        family: familyChest,
        contraindications: []
    )

    static let inclineDBPress = make(
        name: "DB Incline Press",
        pattern: .horizontalPress,
        equipment: .dumbbell,
        primary: [.chest],
        angle: .incline,
        fatigue: 0.6,
        role: .primaryCompound,
        family: familyChest,
        contraindications: [.shoulder]
    )

    static let pauseBicepCurl = make(
        name: "Rope Pause Curl",
        pattern: .elbowFlexion,
        equipment: .cable,
        primary: [.biceps],
        angle: nil,
        fatigue: 0.3,
        role: .accessoryIsolation,
        family: ExerciseFamilyID(),
        contraindications: []
    )

    private static func make(
        name: String,
        pattern: MovementPattern,
        equipment: EquipmentType,
        primary: [MuscleGroup],
        angle: MovementAngle?,
        fatigue: Double,
        role: ExerciseRole,
        family: ExerciseFamilyID,
        contraindications: Set<RestrictionTag>
    ) -> Exercise {
        Exercise(
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: primary.map { try! MuscleContribution(muscleGroupID: $0, activation: 1.0) },
            equipment: equipment,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: fatigue),
            loadability: .discreteIncrements,
            defaultRoles: [role],
            contraindicationTags: contraindications,
            substitutionFamilyID: family
        )
    }
}

@Suite("Substitution scoring engine (PR-0904)")
struct SubstitutionScoringTests {

    @Test("Gate de seguridad excluye candidatos con contraindicación activa")
    func safetyGate() {
        let engine = SubstitutionScoringEngine()
        let result = engine.rank(SubstitutionInput(
            target: SubFixture.flatDBPress,
            requestedRole: .primaryCompound,
            activeRestrictions: [.shoulder],
            candidates: [SubFixture.smithPress, SubFixture.inclineDBPress]
        ))

        #expect(result.noSafeSubstitute == false)
        #expect(result.safeSubstitutes.map(\.exercise.canonicalName) == ["Smith Machine Press"])
        #expect(!SubFixture.inclineDBPress.contraindicationTags.isDisjoint(with: [.shoulder]))
    }

    @Test("No safe substitute cuando ningún candidato pasa el gate")
    func noSafeSubstitute() {
        let engine = SubstitutionScoringEngine()
        let result = engine.rank(SubstitutionInput(
            target: SubFixture.flatDBPress,
            requestedRole: .primaryCompound,
            activeRestrictions: [.shoulder],
            candidates: [SubFixture.inclineDBPress]
        ))

        #expect(result.noSafeSubstitute == true)
        #expect(result.safeSubstitutes.isEmpty)
    }

    @Test("Ranking ordena candidatos compatibles por score descendente")
    func rankingOrder() {
        let engine = SubstitutionScoringEngine()
        let result = engine.rank(SubstitutionInput(
            target: SubFixture.flatDBPress,
            requestedRole: .primaryCompound,
            candidates: [SubFixture.pauseBicepCurl, SubFixture.smithPress]
        ))

        let names = result.safeSubstitutes.map(\.exercise.canonicalName)
        #expect(names == ["Smith Machine Press", "Rope Pause Curl"])
        #expect(engine.passesSafetyGate(SubFixture.smithPress, restrictions: []))
    }

    @Test("Ranking reproducible para la misma entrada")
    func reproducibleRanking() {
        let engine = SubstitutionScoringEngine()
        let input = SubstitutionInput(
            target: SubFixture.flatDBPress,
            requestedRole: .primaryCompound,
            candidates: [SubFixture.smithPress, SubFixture.pauseBicepCurl]
        )
        let a = engine.rank(input)
        let b = engine.rank(input)
        #expect(a.safeSubstitutes == b.safeSubstitutes)
        #expect(a.allEvaluated == b.allEvaluated)
    }

    @Test("Pesos configurables versionados")
    func configurableWeights() {
        let weights = SubstitutionWeights.defaultConfig()
        #expect(weights.muscleMatch == 0.30)
        #expect(weights.movementPatternMatch == 0.20)
        #expect(weights.trainingRoleMatch == 0.15)
        #expect(weights.angleMatch == 0.10)
        #expect(weights.fatigueProfileMatch == 0.08)
        #expect(weights.stabilityMatch == 0.05)
        #expect(weights.userHistoryConfidence == 0.05)
        #expect(weights.preferenceMatch == 0.04)
        #expect(weights.equipmentConfidence == 0.03)
        #expect(weights.muscleMatch + weights.movementPatternMatch + weights.trainingRoleMatch + weights.angleMatch
            + weights.fatigueProfileMatch + weights.stabilityMatch + weights.userHistoryConfidence
            + weights.preferenceMatch + weights.equipmentConfidence == 1.0)
    }

    @Test("Preferencia e historia influyen pero no superan el gate de seguridad")
    func preferenceDoesNotOverrideSafety() {
        let engine = SubstitutionScoringEngine()
        let result = engine.rank(SubstitutionInput(
            target: SubFixture.flatDBPress,
            requestedRole: .primaryCompound,
            activeRestrictions: [.shoulder],
            candidates: [SubFixture.inclineDBPress, SubFixture.smithPress],
            preferences: [SubFixture.inclineDBPress.id: 1.0]
        ))

        let names = result.safeSubstitutes.map(\.exercise.canonicalName)
        #expect(names == ["Smith Machine Press"])
    }
}