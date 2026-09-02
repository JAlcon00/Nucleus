//
//  RestrictionPolicyEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests exhaustivos de seguridad para el motor de política de restricciones (PR-1402):
//  patrón prohibido excluye, lista explícita refina, sustitución nunca evade, y los
//  estados resolved no aplican.
//

import XCTest
@testable import PRDomain

final class RestrictionPolicyEngineTests: XCTestCase {
    private var engine: RestrictionPolicyEngine!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        engine = try! RestrictionPolicyEngine(config: RestrictionPolicyConfig(rule: try! RestrictionPolicyDefaults.makeRule()))
    }

    // MARK: - Helpers

    private func exercise(
        _ id: ExerciseID = ExerciseID(),
        name: String = "Exercise",
        pattern: MovementPattern = .squat,
        tags: Set<RestrictionTag> = []
    ) -> Exercise {
        Exercise(
            id: id,
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: [],
            equipment: .barbell,
            jointClass: .multiJoint,
            stabilityDemand: .high,
            skillDemand: .high,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [],
            contraindicationTags: tags,
            substitutionFamilyID: ExerciseFamilyID()
        )
    }

    private func restriction(
        patterns: Set<MovementPattern> = [],
        forbidden: Set<ExerciseID> = [],
        allowed: Set<ExerciseID> = [],
        tags: Set<RestrictionTag> = [],
        status: RestrictionStatus = .active
    ) -> TrainingRestriction {
        TrainingRestriction(
            bodyRegion: .shoulder,
            status: status,
            source: .userReported,
            forbiddenPatterns: patterns,
            forbiddenExerciseIDs: forbidden,
            allowedExerciseIDs: allowed,
            restrictionTags: tags
        )
    }

    private func verify(_ input: RestrictionPolicyInput) throws -> RestrictionVerdict {
        try engine.evaluate(input).verdict
    }

    // MARK: - Patrón prohibido excluye el ejercicio

    func testForbiddenMovementPatternExcludesExercise() throws {
        let exercise = exercise(pattern: .verticalPress)
        let restriction = restriction(patterns: [.verticalPress])
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .forbiddenPattern([.verticalPress]))
    }

    func testDifferentPatternIsAllowed() throws {
        let exercise = exercise(pattern: .squat)
        let restriction = restriction(patterns: [.verticalPress])
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .allowed)
    }

    // MARK: - Lista explícita de permitidos refina un patrón prohibido

    func testExplicitAllowedListRefinesForbiddenPattern() throws {
        let exercise = exercise(pattern: .verticalPress)
        let restriction = restriction(patterns: [.verticalPress], allowed: [exercise.id])
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .allowed)
    }

    func testExplicitForbidOverridesAllow() throws {
        let exercise = exercise(pattern: .squat)
        let restriction = restriction(forbidden: [exercise.id], allowed: [exercise.id])
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .forbiddenExplicit)
    }

    // MARK: - Sustitución nunca evade la restricción

    func testSubstituteForbiddenByPatternIsExcluded() throws {
        let target = exercise(name: "Target", pattern: .verticalPress)
        let badSub = exercise(name: "BadSub", pattern: .verticalPress)  // mismo patrón prohibido
        let goodSub = exercise(name: "GoodSub", pattern: .squat)
        let restriction = restriction(patterns: [.verticalPress])

        let safe = try engine.safeSubstitutes(
            among: [badSub, goodSub],
            restrictions: [restriction],
            asOf: now
        )
        XCTAssertEqual(safe.map(\.canonicalName), ["GoodSub"])
        XCTAssertFalse(safe.contains(where: { $0.id == target.id }))
    }

    func testSubstituteForbiddenByTagIsExcluded() throws {
        let sub = exercise(tags: [.shoulder])
        let restriction = restriction(tags: [.shoulder])
        let verdict = try verify(RestrictionPolicyInput(exercise: sub, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .forbiddenByTag([.shoulder]))
    }

    // MARK: - Estados: resolved no aplica; vencido pasa a reviewNeeded pero sigue aplicando

    func testResolvedRestrictionIsIgnored() throws {
        let exercise = exercise(pattern: .verticalPress)
        let restriction = restriction(patterns: [.verticalPress], status: .resolved)
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(verdict, .allowed)
    }

    func testOverdueActiveStillAppliesUntilResolved() throws {
        let exercise = exercise(pattern: .verticalPress)
        // Fecha de revisión en el pasado; active vence a reviewNeeded pero sigue aplicando.
        let restriction = restriction(patterns: [.verticalPress])
        let asOf = now.addingTimeInterval(86400 * 10)
        let verdict = try verify(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: asOf))
        XCTAssertEqual(verdict, .forbiddenPattern([.verticalPress]))
    }

    // MARK: - Configuración / validación

    func testWrongCategoryRejected() throws {
        var rule = try RestrictionPolicyDefaults.makeRule()
        rule.category = .volume
        XCTAssertThrowsError(try RestrictionPolicyConfig(rule: rule))
    }

    func testScopeTogglesCanDisablePatternEnforcement() throws {
        var params = RestrictionPolicyKeys.defaults()
        params[RestrictionPolicyKeys.enforceForbiddenPatterns] = 0
        var rule = try RestrictionPolicyDefaults.makeRule()
        rule.parameters = params
        let scoped = try RestrictionPolicyEngine(config: RestrictionPolicyConfig(rule: rule))

        let exercise = exercise(pattern: .verticalPress)
        let restriction = restriction(patterns: [.verticalPress])
        let verdict = try scoped.evaluate(
            RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now)
        ).verdict
        XCTAssertEqual(verdict, .allowed)
    }

    // MARK: - Auditabilidad

    func testDecisionRecordIsAuditable() throws {
        let exercise = exercise(pattern: .verticalPress)
        let restriction = restriction(patterns: [.verticalPress])
        let result = try engine.evaluate(RestrictionPolicyInput(exercise: exercise, activeRestrictions: [restriction], asOf: now))
        XCTAssertEqual(result.decisionRecord.ruleReferences.map(\.ruleID), [RestrictionPolicyDefaults.ruleID])
        XCTAssertEqual(result.decisionRecord.type, .exerciseSubstitution)
        XCTAssertFalse(result.decisionRecord.inputFacts.isEmpty)
        XCTAssertFalse(result.reasons.isEmpty)
    }
}