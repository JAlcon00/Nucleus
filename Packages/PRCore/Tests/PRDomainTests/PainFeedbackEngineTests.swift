//
//  PainFeedbackEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests para el motor determinista de feedback de dolor (PR-1403): none/mild/
//  moderate/high, moderate/high suspende progresión, y la recomendación de UI nunca
//  diagnostica.
//

import XCTest
@testable import PRDomain

final class PainFeedbackEngineTests: XCTestCase {
    private func makeEngine() throws -> PainFeedbackEngine {
        try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
    }

    // MARK: - Niveles y suspensión de progresión

    func testNoneDoesNotSuspendProgression() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(PainFeedbackInput(level: .none, exerciseName: "Press"))
        XCTAssertFalse(result.suspendsLoadProgression)
        XCTAssertEqual(result.recommendation, .continueNormal)
    }

    func testMildDoesNotSuspendProgression() throws {
        let engine = try makeEngine()
        XCTAssertFalse(try engine.evaluate(PainFeedbackInput(level: .mild)).suspendsLoadProgression)
        XCTAssertEqual(try engine.evaluate(PainFeedbackInput(level: .mild)).recommendation, .continueNormal)
    }

    func testModerateSuspendsProgressionAndReducesIntensity() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(PainFeedbackInput(level: .moderate, exerciseName: "Press"))
        XCTAssertTrue(result.suspendsLoadProgression)
        XCTAssertEqual(result.recommendation, .reduceIntensityAndMonitor)
    }

    func testHighSuspendsProgressionAndStops() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(PainFeedbackInput(level: .high, exerciseName: "Press"))
        XCTAssertTrue(result.suspendsLoadProgression)
        XCTAssertEqual(result.recommendation, .stopAndRest)
    }

    // MARK: - Es la regla de honestidad: nunca diagnostica

    func testRecommendationsAreConservativeFlowOnly() throws {
        let engine = try makeEngine()
        for level in PainLevel.allCases {
            let result = try engine.evaluate(PainFeedbackInput(level: level, exerciseName: "Press"))
            // La recomendación es SIEMPRE una de las categorías conservadoras conocidas;
            // nunca una prescripción clínica sobre una lesión.
            switch result.recommendation {
            case .continueNormal, .reduceIntensityAndMonitor, .stopAndRest:
                break
            }
            // No se prescribe un protocolo de rehabilitación como tratamiento.
            let detail = result.decisionRecord.action.detail.lowercased()
            XCTAssertFalse(detail.contains("rehabilit"), "no debe prescribir rehabilitación (level \(level.rawValue))")
        }
    }

    // MARK: - Con restricción activa relacionada (PR-1402) refuerza precaución

    func testHighWithRelatedRestrictionReinforcesCaution() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(PainFeedbackInput(
            level: .high,
            hasActiveRelatedRestriction: true,
            exerciseName: "Press"
        ))
        XCTAssertEqual(result.recommendation, .stopAndRest)
        XCTAssertTrue(result.reasons.contains { $0.contains("restricción activa relacionada") })
    }

    // MARK: - Configuración / validación

    func testWrongCategoryRejected() throws {
        var rule = try PainFeedbackPolicyDefaults.makeRule()
        rule.category = .volume
        XCTAssertThrowsError(try PainFeedbackConfig(rule: rule))
    }

    func testCustomThreshold() throws {
        // Umbral en 3 (high) ⇒ moderate NO suspende, high sí.
        var params = PainFeedbackPolicyKeys.defaults()
        params[PainFeedbackPolicyKeys.suspendProgressionFromSeverity] = 3
        var rule = try PainFeedbackPolicyDefaults.makeRule()
        rule.parameters = params
        let engine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: rule))
        XCTAssertFalse(try engine.evaluate(PainFeedbackInput(level: .moderate)).suspendsLoadProgression)
        XCTAssertTrue(try engine.evaluate(PainFeedbackInput(level: .high)).suspendsLoadProgression)
    }

    // MARK: - Auditabilidad

    func testDecisionRecordAuditable() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(PainFeedbackInput(level: .high, exerciseName: "Press"))
        XCTAssertEqual(result.decisionRecord.ruleReferences.map(\.ruleID), [PainFeedbackPolicyDefaults.ruleID])
        XCTAssertEqual(result.decisionRecord.type, .intensityChange)
        let fact = result.decisionRecord.inputFacts.first { $0.key == "suspendsLoadProgression" }
        XCTAssertEqual(fact?.value, "true")
        XCTAssertFalse(result.reasons.isEmpty)
    }

    // MARK: - helper de la regla

    func testPainLevelRawValues() {
        XCTAssertEqual(PainLevel.none.rawValue, 0)
        XCTAssertEqual(PainLevel.mild.rawValue, 1)
        XCTAssertEqual(PainLevel.moderate.rawValue, 2)
        XCTAssertEqual(PainLevel.high.rawValue, 3)
        XCTAssertTrue(PainLevel.moderate.isConservativeDisruptive)
        XCTAssertTrue(PainLevel.high.isConservativeDisruptive)
        XCTAssertFalse(PainLevel.none.isConservativeDisruptive)
        XCTAssertFalse(PainLevel.mild.isConservativeDisruptive)
    }
}