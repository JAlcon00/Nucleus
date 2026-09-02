//
//  AgentActionWriterTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del pipeline determinista de escritura (Phase N4, NEMOTRON §Phase N4):
//  — el mapeo intent → acción es dominio puro y determinista (el LLM nunca elige acción);
//  — se genera un preview legible ANTES de cualquier escritura;
//  — el `ActionPolicyValidator` (PR-1602) media: allowed / rejected / requiresConfirmation;
//  — la salida son comandos ESTRECHOS (`AgentWriteCommand`), nunca un handle de DB;
//  — el pipeline emite audit trail redactado por etapa (intent → actionValidation → result).
//

import XCTest
@testable import PRDomain

final class AgentActionWriterTests: XCTestCase {

    private func makeWriter() throws -> AgentActionWriter {
        try AgentActionWriter(validator: ActionPolicyValidator(config: ActionPolicyConfig(
            rule: ActionPolicyDefaults.makeRule()
        )))
    }

    // MARK: - Mapping determinista intent → acción

    func testIntentToActionMappingIsDeterministic() {
        let cases: [(AgentIntent, AgentAction)] = [
            (.setTimeConstraint(.hard(minutes: 35)), .recomputeSession),
            (.equipmentUnavailable(EquipmentReference(equipmentType: .barbell), .occupied), .updateGymKnowledge),
            (.requestExerciseSwap(ExerciseID()), .replaceExercise),
            (.reportFatigue(UserFatigueFeedback(severity: 4)), .adjustLoadTarget),
            (.reportPain(PainReport(level: .moderate)), .adjustLoadTarget),
            (.changeGoal(.strength), .recomputeSession),
            (.changePhase(.deficit), .recomputeSession),
            (.changeGym(GymID()), .updateGymKnowledge),
            (.askWhy(DecisionID()), .presentExplanation),
            (.updateRestriction(TrainingRestrictionDraft(bodyRegion: .shoulder)), .saveRestriction),
        ]
        for (intent, expected) in cases {
            XCTAssertEqual(AgentIntentActionMapper.action(for: intent), expected, "\(intent.tag)")
        }
    }

    func testRequestPlanAdjustmentScopeMapsToAction() {
        XCTAssertEqual(
            AgentIntentActionMapper.action(for: .requestPlanAdjustment(.init(scope: .volume))),
            .adjustVolume
        )
        XCTAssertEqual(
            AgentIntentActionMapper.action(for: .requestPlanAdjustment(.init(scope: .loadTarget))),
            .adjustLoadTarget
        )
        XCTAssertEqual(
            AgentIntentActionMapper.action(for: .requestPlanAdjustment(.init(scope: .fullRebuild))),
            .recomputeSession
        )
    }

    // MARK: - Preview antes de escribir

    func testPreviewIsProducedBeforeExecution() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .setTimeConstraint(.hard(minutes: 30)),
            context: .init()
        )
        XCTAssertTrue(result.preview.isWrite)
        XCTAssertTrue(result.preview.summary.contains("30 min"))
        XCTAssertTrue(result.preview.summary.contains("tiempo disponible"))
    }

    func testAskWhyPreviewIsReadOnly() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .askWhy(DecisionID()),
            context: .init()
        )
        XCTAssertFalse(result.preview.isWrite, "explicar una decisión no escribe nada")
    }

    // MARK: - Validación: allowed / rejected / requiresConfirmation

    func testAllowedProducesNarrowCommand() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .setTimeConstraint(.hard(minutes: 30)),
            context: .init()
        )
        guard case .execute(let command, _, _) = result.decision else {
            return XCTFail("debe quedar listo para ejecutar, obtuve \(result.decision)")
        }
        XCTAssertEqual(command.name, "recomputeSession")
    }

    func testReplaceExerciseWithForbiddenSubstituteRejected() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .requestExerciseSwap(ExerciseID()),
            context: .init(proposedSubstituteIsForbidden: true)
        )
        guard case .rejected(let reason, _, _) = result.decision else {
            return XCTFail("un sustituto prohibido debe rechazarse, obtuve \(result.decision)")
        }
        XCTAssertTrue(reason.contains("restricción"))
    }

    func testReportPainWithProgressionIncreaseRejectedByPainGate() throws {
        // Pain gate activo + la acción pediría progresar → rechazada (no se progresa con dolor).
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .reportPain(PainReport(level: .moderate)),
            context: .init(painGateActive: true, proposedProgressionIncrease: true)
        )
        guard case .rejected(let reason, _, _) = result.decision else {
            return XCTFail("con pain gate no se debe progresar, obtuve \(result.decision)")
        }
        XCTAssertTrue(reason.contains("pain gate") || reason.contains("progresión"))
    }

    func testWeakeningProfessionalRestrictionRequiresConfirmation() throws {
        let writer = try makeWriter()
        let draft = TrainingRestrictionDraft(bodyRegion: .shoulder, source: .professionalGuidance)
        let result = try writer.execute(
            intent: .updateRestriction(draft),
            context: .init(weakeningProfessionalRestriction: true, userConfirmed: false)
        )
        guard case .confirm(_, _, _) = result.decision else {
            return XCTFail("debilitar restricción profesional sin confirmación debe requerir confirmación, obtuve \(result.decision)")
        }
        // Con confirmación explícita → se ejecuta.
        let confirmed = try writer.execute(
            intent: .updateRestriction(draft),
            context: .init(weakeningProfessionalRestriction: true),
            userConfirmed: true
        )
        guard case .execute(_ , _, _) = confirmed.decision else {
            return XCTFail("con confirmación debe ejecutarse, obtuve \(confirmed.decision)")
        }
    }

    // MARK: - Audit trail redactado por etapa

    func testPipelineEmitsThreeStageAudit() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .setTimeConstraint(.hard(minutes: 45)),
            context: .init(),
            conversationID: UUID()
        )
        XCTAssertEqual(result.auditRecords.count, 3)
        XCTAssertEqual(result.auditRecords[0].stage, .inboundIntent)
        XCTAssertEqual(result.auditRecords[1].stage, .actionValidation)
        XCTAssertEqual(result.auditRecords[2].stage, .result)
        XCTAssertEqual(result.auditRecords[0].intentTag, "setTimeConstraint")
        XCTAssertEqual(result.auditRecords[2].resultCommand, "recomputeSession")
    }

    func testRejectedPipelineAuditsRejectedResult() throws {
        let writer = try makeWriter()
        let result = try writer.execute(
            intent: .requestExerciseSwap(ExerciseID()),
            context: .init(proposedSubstituteIsForbidden: true)
        )
        let last = result.auditRecords.last!
        XCTAssertEqual(last.stage, .result)
        XCTAssertEqual(last.resultCommand, "rejected")
    }
}
