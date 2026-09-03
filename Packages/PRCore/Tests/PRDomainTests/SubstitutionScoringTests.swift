//
//  SubstitutionScoringTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del motor de scoring de sustitución (PR-0904): gate de seguridad, ranking
//  reproducible por pesos del §10.3, dimensiones de matching y "no safe substitute".
//

import Foundation
import Testing
@testable import PRDomain

private enum SubstitutionFixture {
    // target: DB flat bench press
    static let dbBench = make(
        name: "Dumbbell Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [.triceps, .shoulders],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .moderate,
        fatigue: 0.5
    )

    // ideal muscle + pattern + role + angle, different equipment
    static let smithBench = make(
        name: "Smith Machine Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .smithMachine,
        primary: [.chest],
        secondary: [.triceps, .shoulders],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .low,
        fatigue: 0.5
    )

    // same muscle, same pattern, but incline angle + higher stability
    static let inclineDB = make(
        name: "Incline Dumbbell Press",
        pattern: .horizontalPress,
        angle: .incline,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [.shoulders, .triceps],
        roles: [.secondaryCompound],
        stability: .high,
        fatigue: 0.45
    )

    // different pattern (vertical press) and different primary (shoulders)
    static let shoulderPress = make(
        name: "Shoulder Press",
        pattern: .verticalPress,
        angle: .overhead,
        equipment: .barbell,
        primary: [.shoulders],
        secondary: [.triceps],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .high,
        fatigue: 0.35
    )

    static let config: SubstitutionScoringConfig = {
        try! SubstitutionScoringConfig(rule: try SubstitutionScoringDefaults.makeRule())
    }()

    private static func make(
        name: String,
        pattern: MovementPattern,
        angle: MovementAngle?,
        equipment: EquipmentType,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        roles: Set<ExerciseRole>,
        stability: DemandLevel,
        fatigue: Double
    ) -> Exercise {
        try! Exercise(
            canonicalName: name,
            movementPattern: pattern,
            movementAngle: angle,
            primaryMuscles: primary.map { try! MuscleContribution(muscleGroupID: $0, activation: 1.0) },
            secondaryMuscles: secondary.map { try! MuscleContribution(muscleGroupID: $0, activation: 0.4) },
            equipment: equipment,
            jointClass: .multiJoint,
            stabilityDemand: stability,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: fatigue),
            loadability: .discreteIncrements,
            defaultRoles: roles,
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}

@Suite("Substitution scoring engine (PR-0904)")
struct SubstitutionScoringTests {

    private var engine: SubstitutionScoringEngine {
        SubstitutionScoringEngine(config: SubstitutionFixture.config)
    }

    private func request(
        target: Exercise,
        candidates: [Exercise],
        role: ExerciseRole? = .primaryCompound,
        restrictions: [TrainingRestriction] = [],
        signal: SubstitutionUserSignal = SubstitutionUserSignal()
    ) -> SubstitutionRequest {
        SubstitutionRequest(
            target: target,
            targetRole: role,
            candidates: candidates,
            userSignal: signal,
            activeRestrictions: restrictions
        )
    }

    @Test("la config exige pesos versionados que suman 1.00")
    func configWeightsSumToOne() throws {
        let rule = try SubstitutionScoringDefaults.makeRule()
        let config = try SubstitutionScoringConfig(rule: rule)
        #expect(config.muscleMatch == 0.30)
        #expect(config.movementPatternMatch == 0.20)
        #expect(config.trainingRoleMatch == 0.15)
        #expect(config.angleMatch == 0.10)
        #expect(config.fatigueProfileMatch == 0.08)
        #expect(config.stabilityMatch == 0.05)
        #expect(config.userHistoryConfidence == 0.05)
        #expect(config.preferenceMatch == 0.04)
        #expect(config.equipmentConfidence == 0.03)
    }

    @Test("rechaza pesos que no suman 1.00")
    func rejectsNonUnityWeights() throws {
        var params = SubstitutionScoringKeys.defaults()
        params[SubstitutionScoringKeys.muscleMatch] = 0.5 // desvía la suma
        let rule = try EvidenceRule(
            id: SubstitutionScoringDefaults.ruleID,
            name: "bad",
            category: .safety,
            confidence: .expertConsensus,
            version: 1,
            parameters: params
        )
        do {
            _ = try SubstitutionScoringConfig(rule: rule)
            Issue.record("Debería haber rechazado pesos que no suman 1.00")
        } catch {
            guard case SubstitutionScoringError.weightsDoNotSumToOne = error else {
                Issue.record("Error inesperado: \(error)")
                return
            }
        }
    }

    @Test("el candidato más equivalente (músculo+patrón+rol+ángulo) lidera el ranking")
    func bestEquivalentRanksFirst() throws {
        let target = SubstitutionFixture.dbBench
        // smith: mismo patrón/músculo/ángulo, equipo distinto → mejor que incline/vertical.
        let verdict = try engine.substitutes(for: request(
            target: target,
            candidates: [SubstitutionFixture.shoulderPress, SubstitutionFixture.smithBench, SubstitutionFixture.inclineDB]
        ))
        let ranked = verdict.ranked
        #expect(ranked.count == 3)
        #expect(ranked[0].exercise.canonicalName == SubstitutionFixture.smithBench.canonicalName)
        #expect(ranked[0].totalScore > ranked[1].totalScore)
        #expect(ranked[1].totalScore > ranked[2].totalScore)
    }

    @Test("el ranking es reproducible: mismos inputs → mismo orden")
    func reproducibleRanking() throws {
        let r = SubstitutionRequest(
            target: SubstitutionFixture.dbBench,
            candidates: [SubstitutionFixture.shoulderPress, SubstitutionFixture.smithBench, SubstitutionFixture.inclineDB]
        )
        let first = try engine.substitutes(for: r).ranked.map(\.exercise.id)
        let second = try engine.substitutes(for: r).ranked.map(\.exercise.id)
        #expect(first == second)
    }

    @Test("historial y preferencia del usuario elevan el score del sustituto")
    func userSignalLiftsScore() throws {
        let target = SubstitutionFixture.dbBench
        let incline = SubstitutionFixture.inclineDB

        let baseline = try engine.substitutes(for: request(
            target: target,
            candidates: [incline]
        )).ranked[0].totalScore

        let boosted = try engine.substitutes(for: request(
            target: target,
            candidates: [incline],
            signal: SubstitutionUserSignal(
                historyConfidence: [incline.id: 1.0],
                preferredExerciseIDs: [incline.id]
            )
        )).ranked[0].totalScore

        // 1.0 de historial (0.05) + 1.0 de preferencia (0.04) elevan el total.
        #expect(boosted > baseline)
    }

    @Test("un sustituto prohibido por la política nunca se adopta (gate de seguridad)")
    func forbiddenCandidateNotAdopted() throws {
        let shoulderPress = SubstitutionFixture.shoulderPress
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            status: .active,
            forbiddenPatterns: [.verticalPress]
        )
        // shoulder press lleva patrón verticalPress prohibido → excluido.
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: [SubstitutionFixture.smithBench, shoulderPress],
            restrictions: [restriction]
        ))
        let ranked = verdict.ranked
        #expect(ranked.count == 1)
        #expect(ranked[0].exercise.id == SubstitutionFixture.smithBench.id)
    }

    @Test("no safe substitute cuando todas las candidatas están prohibidas")
    func noSafeSubstituteWhenAllForbidden() throws {
        let press = SubstitutionFixture.smithBench
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            status: .active,
            forbiddenPatterns: [.horizontalPress, .verticalPress]
        )
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: [press],
            restrictions: [restriction]
        ))
        #expect(verdict.ranked.isEmpty)
    }

    @Test("sin candidatas devuelve no safe substitute")
    func noCandidatesReturnsNoSafe() throws {
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: []
        ))
        if case .safe = verdict {
            Issue.record("no candidates should not yield a safe substitute")
        }
        #expect(verdict.ranked.isEmpty)
    }

    @Test("la máquina ocupada/inexistente reduce el score del candidato")
    func occupiedOrMissingEquipmentDowngradesScore() throws {
        let target = SubstitutionFixture.dbBench
        let smith = SubstitutionFixture.smithBench

        let score = { (gym: GymProfile?) throws -> Double in
            try engine.substitutes(for: SubstitutionRequest(
                target: target,
                candidates: [smith],
                gymProfile: gym
            )).ranked[0].totalScore
        }

        let unknownGym = GymProfile(name: "A")
        let occupiedGym = unknownGym.markingOccupied(.smithMachine)

        let withOccupied = try score(occupiedGym)
        let withUnknown = try score(unknownGym)

        // occupied (confianza 0) puntúa peor que unknown (confianza 0.5).
        #expect(withOccupied < withUnknown)
    }
}