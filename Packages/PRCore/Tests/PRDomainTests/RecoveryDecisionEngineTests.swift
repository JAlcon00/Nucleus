//
//  RecoveryDecisionEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests para el motor determinista de recovery (PR-1302). Verifica outcomes
//  categóricos sin score, precedencia y la regla de honestidad (no 0-100).
//

import XCTest
@testable import PRDomain

final class RecoveryDecisionEngineTests: XCTestCase {
    private func makeEngine() throws -> RecoveryDecisionEngine {
        try RecoveryDecisionEngine(policy: RecoveryPolicy(rule: RecoveryPolicyDefaults.makeRule()))
    }

    // MARK: - Regla de honestidad: no score

    func testOutcomesAreCategoricalAndNeverNumeric() throws {
        let cases: [RecoveryContext] = [
            RecoveryContext(),
            RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .tired)),
            RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .veryTired)),
            RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .veryTired), hasRecentPerformanceDecline: true),
            RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .normal), hasRecentNearFailureSets: true),
        ]
        let engine = try makeEngine()
        for input in cases {
            let result = try engine.evaluate(input)
            switch result.decision {
            case .trainAsPlanned, .recoverySession, .restRecommended:
                break
            case .trainWithAdjustments(let adjustments):
                XCTAssertFalse(adjustments.isEmpty)
            }
            XCTAssertFalse(result.reasons.isEmpty)
        }
    }

    // MARK: - Normal

    func testNoSignalsTrainsAsPlanned() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext())
        XCTAssertEqual(result.decision, .trainAsPlanned)
        XCTAssertEqual(result.state, .normal)
        XCTAssertEqual(result.decisionRecord.type, .loadChange)
        XCTAssertEqual(result.decisionRecord.userOverrideAllowed, true)
    }

    // MARK: - Precedencia descanso > recovery > ajuste > normal

    func testVeryTiredPlusDeclineRecommendsRest() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .veryTired),
            hasRecentPerformanceDecline: true
        ))
        XCTAssertEqual(result.decision, .restRecommended)
        XCTAssertEqual(result.state, .restRecommended)
        XCTAssertEqual(result.decisionRecord.type, .restChange)
    }

    func testVeryTiredPlusHighLoadRecommendsRest() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .veryTired),
            highRecentLoad: true
        ))
        XCTAssertEqual(result.decision, .restRecommended)
        XCTAssertEqual(result.state, .restRecommended)
    }

    func testPoorSleepWithFatigueSignalsRecommendsRest() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .tired),
            highRecentLoad: true,
            healthContext: HealthRecoveryContext(poorSleepIndicated: true)
        ))
        XCTAssertEqual(result.decision, .restRecommended)
    }

    func testPoorSleepWithoutFatigueSignalsDoesNotForceRest() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            healthContext: HealthRecoveryContext(poorSleepIndicated: true)
        ))
        XCTAssertEqual(result.decision, .trainAsPlanned)
    }

    // MARK: - Recovery session

    func testVeryTiredRecommendsRecoverySession() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .veryTired)))
        XCTAssertEqual(result.decision, .recoverySession)
        XCTAssertEqual(result.state, .highFatigue)
        XCTAssertEqual(result.decisionRecord.type, .deload)
    }

    func testDeclinePlusNearFailureRecommendsRecoverySession() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            hasRecentPerformanceDecline: true,
            hasRecentNearFailureSets: true
        ))
        XCTAssertEqual(result.decision, .recoverySession)
        XCTAssertEqual(result.state, .highFatigue)
    }

    // MARK: - Malestar subjetivo → ajuste conservador (nunca diagnóstico)

    func testSomethingHurtsAddsAvoidRegionAdjustment() throws {
        let engine = try makeEngine()
        let region: MuscleGroup.ID = .shoulders
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .somethingHurts, region: region)
        ))
        guard case .trainWithAdjustments(let adjustments) = result.decision else {
            return XCTFail("expected adjustments")
        }
        XCTAssertTrue(adjustments.contains(.reduceIntensity))
        XCTAssertTrue(adjustments.contains(.avoidRegion(region)))
        XCTAssertEqual(result.decisionRecord.type, .intensityChange)
    }

    func testSomethingHurtsNeverReportsRecoveryScore() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .somethingHurts, region: .shoulders)
        ))
        // Nunca produce un tipo de decisión que represente "score".
        XCTAssertNotEqual(result.decisionRecord.type, .loadChange)
        XCTAssertFalse(result.reasons.joined().lowercased().contains("score"))
    }

    // MARK: - Ajuste por fatiga moderada

    func testTiredAdjustsWithReduceIntensity() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(checkIn: PreWorkoutCheckIn(feeling: .tired)))
        XCTAssertEqual(result.decision, .trainWithAdjustments([.reduceIntensity]))
        XCTAssertEqual(result.state, .moderateFatigue)
    }

    func testNearFailureAloneAdjusts() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(hasRecentNearFailureSets: true))
        XCTAssertEqual(result.decision, .trainWithAdjustments([.reduceIntensity]))
    }

    func testHighLoadShortensSession() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(highRecentLoad: true))
        XCTAssertEqual(result.decision, .trainWithAdjustments([.shortenSession]))
    }

    func testDeclineAloneAdjusts() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(hasRecentPerformanceDecline: true))
        XCTAssertEqual(result.decision, .trainWithAdjustments([.reduceIntensity]))
    }

    // MARK: - Validaciones

    func testIncoherentCheckInIsRejected() throws {
        let engine = try makeEngine()
        // somethingHurts sin región ⇒ incoherente.
        XCTAssertThrowsError(try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .somethingHurts)
        )))
    }

    func testPolicyWrongCategoryRejected() throws {
        let rule = try RecoveryPolicyDefaults.makeRule()
        var reclassified = rule
        reclassified.category = .progression
        XCTAssertThrowsError(try RecoveryPolicy(rule: reclassified))
        _ = reclassified
    }

    func testDecisionRecordIsAuditable() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(RecoveryContext(
            checkIn: PreWorkoutCheckIn(feeling: .veryTired),
            hasRecentPerformanceDecline: true
        ))
        XCTAssertEqual(result.decisionRecord.ruleReferences.map(\.ruleID), [RecoveryPolicyDefaults.ruleID])
        XCTAssertFalse(result.decisionRecord.inputFacts.isEmpty)
        XCTAssertFalse(result.decisionRecord.action.title.isEmpty)
    }
}