//
//  ActionPolicyValidatorTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del ActionPolicyValidator (promptMaster §20.3, PR-1602): el agente no evita
//  restricciones, no escribe directo en repositorio, no progresa con pain gate activo,
//  y todo queda auditado en un DecisionRecord.
//

import XCTest
@testable import PRDomain

final class ActionPolicyValidatorTests: XCTestCase {
    private func makeValidator() throws -> ActionPolicyValidator {
        try ActionPolicyValidator(config: ActionPolicyConfig(rule: ActionPolicyDefaults.makeRule()))
    }

    // MARK: - 1. El agente no puede evadir restricciones

    func testReplaceExerciseWithForbiddenSubstituteRejected() throws {
        let v = try makeValidator()
        let verdict = try v.validate(.replaceExercise, context: .init(proposedSubstituteIsForbidden: true))
        XCTAssertTrue(verdict.isRejected, "un sustituto prohibido por restricción NO se adopta (no evade §16.2)")
        let fact = verdict.decisionRecord.inputFacts.first { $0.key == "outcome" }
        XCTAssertEqual(fact?.value, "rejected")
    }

    func testReplaceExerciseWithSafeSubstituteAllowed() throws {
        let v = try makeValidator()
        let verdict = try v.validate(.replaceExercise, context: .init(proposedSubstituteIsForbidden: false))
        XCTAssertTrue(verdict.isAllowed)
    }

    func testWeakeningProfessionalRestrictionRequiresConfirmation() throws {
        let v = try makeValidator()
        let verdict = try v.validate(.saveRestriction, context: .init(weakeningProfessionalRestriction: true, userConfirmed: false))
        if case .requiresConfirmation = verdict.outcome {} else {
            return XCTFail("debilitar una restricción profesional sin confirmación debe requerir confirmación, obtuve \(verdict.outcome)")
        }
        // Con confirmación se permite.
        let confirmed = try v.validate(.saveRestriction, context: .init(weakeningProfessionalRestriction: true, userConfirmed: true))
        XCTAssertTrue(confirmed.isAllowed)
    }

    func testSaveRestrictionNormalAllowed() throws {
        let v = try makeValidator()
        XCTAssertTrue(try v.validate(.saveRestriction, context: .init()).isAllowed)
    }

    // MARK: - 2. Sin escritura directa a repositorio (comandos estrechos)

    func testAllowedOutcomesExposeNarrowCommands() throws {
        let v = try makeValidator()
        let cases: [AgentAction] = [
            .recomputeSession, .reorderExercises, .recommendRest,
            .rescheduleWorkout, .updateGymKnowledge, .presentExplanation,
        ]
        for action in cases {
            let verdict = try v.validate(action, context: .init())
            guard case .allowed(let command) = verdict.outcome else {
                return XCTFail("\(action) debía ser allowed")
            }
            XCTAssertFalse(command.isEmpty)
        }
    }

    // MARK: - 3. Sin progresión de carga cuando el pain gate está activo

    func testAdjustLoadTargetDeniedOnPainGateIncrease() throws {
        let v = try makeValidator()
        let verdict = try v.validate(.adjustLoadTarget, context: .init(painGateActive: true, proposedProgressionIncrease: true))
        XCTAssertTrue(verdict.isRejected, "no se puede aumentar la carga con pain gate activo")
    }

    func testAdjustVolumeDeniedOnPainGateIncrease() throws {
        let v = try makeValidator()
        let verdict = try v.validate(.adjustVolume, context: .init(painGateActive: true, proposedProgressionIncrease: true))
        XCTAssertTrue(verdict.isRejected)
    }

    func testPainGateNeutralOrReductionAllowed() throws {
        let v = try makeValidator()
        // Reducción / neutral → permitida pese al pain gate.
        XCTAssertTrue(try v.validate(.adjustLoadTarget, context: .init(painGateActive: true, proposedProgressionIncrease: false)).isAllowed)
        XCTAssertTrue(try v.validate(.adjustVolume, context: .init(painGateActive: true, proposedProgressionIncrease: false)).isAllowed)
    }

    func testProgressionAllowedWithoutPainGate() throws {
        let v = try makeValidator()
        XCTAssertTrue(try v.validate(.adjustLoadTarget, context: .init(painGateActive: false, proposedProgressionIncrease: true)).isAllowed)
    }

    // MARK: - 4. Auditabilidad

    func testEveryVerdictLogsDecisionRecord() throws {
        let v = try makeValidator()
        let actions: [AgentAction] = [
            .recomputeSession, .reorderExercises, .replaceExercise, .adjustVolume,
            .adjustLoadTarget, .recommendRest, .rescheduleWorkout, .updateGymKnowledge,
            .saveRestriction, .presentExplanation,
        ]
        for action in actions {
            let verdict = try v.validate(action, context: .init(proposedSubstituteIsForbidden: true))
            XCTAssertEqual(verdict.decisionRecord.type, .policyValidation, "\(action) debe auditarse")
            XCTAssertEqual(verdict.decisionRecord.ruleReferences.map(\.ruleID), [ActionPolicyDefaults.ruleID])
            XCTAssertFalse(verdict.decisionRecord.inputFacts.isEmpty)
            XCTAssertFalse(verdict.reasons.isEmpty)
        }
    }

    // MARK: - Configuración / validación

    func testWrongCategoryRejected() throws {
        var rule = try ActionPolicyDefaults.makeRule()
        rule.category = .volume
        XCTAssertThrowsError(try ActionPolicyConfig(rule: rule)) { error in
            guard case ActionPolicyError.wrongCategory = error else {
                return XCTFail("esperaba wrongCategory, obtuve \(error)")
            }
        }
    }

    func testMissingConfigRejected() throws {
        var rule = try ActionPolicyDefaults.makeRule()
        rule.parameters = [:]
        XCTAssertThrowsError(try ActionPolicyConfig(rule: rule))
    }

    // MARK: - displayName

    func testActionDisplayNamePresent() {
        for action in [AgentAction.replaceExercise, .adjustVolume, .saveRestriction, .presentExplanation] {
            XCTAssertFalse(action.displayName.isEmpty)
        }
    }
}