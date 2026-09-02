//
//  AgentIntentTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del schema de intents del agente (promptMaster §20.2, PR-1601):
//  representación wire Codable independiente de backend, round-trip por caso,
//  y decodificación segura de intent desconocido (unknown intent seguro).
//

import XCTest
@testable import PRDomain

final class AgentIntentTests: XCTestCase {
    private func roundTrip(_ intent: AgentIntent, file: StaticString = #filePath, line: UInt = #line) throws -> AgentIntent {
        let data = try JSONEncoder().encode(intent)
        return try JSONDecoder().decode(AgentIntent.self, from: data)
    }

    // MARK: - Round-trip por caso

    func testRoundTripSetTimeConstraint() throws {
        let a = AgentIntent.setTimeConstraint(.hard(minutes: 30))
        XCTAssertEqual(try roundTrip(a), a)
        let b = AgentIntent.setTimeConstraint(.unconstrained)
        XCTAssertEqual(try roundTrip(b), b)
    }

    func testRoundTripEquipmentUnavailable() throws {
        let a = AgentIntent.equipmentUnavailable(
            EquipmentReference(equipmentType: .barbell),
            .occupied
        )
        XCTAssertEqual(try roundTrip(a), a)
        let b = AgentIntent.equipmentUnavailable(
            EquipmentReference(equipmentType: .plateLoaded),
            .doesNotExist
        )
        XCTAssertEqual(try roundTrip(b), b)
    }

    func testRoundTripRequestExerciseSwap() throws {
        let a = AgentIntent.requestExerciseSwap(ExerciseID())
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripReportFatigue() throws {
        let a = AgentIntent.reportFatigue(UserFatigueFeedback(severity: 4))
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripReportPain() throws {
        let a = AgentIntent.reportPain(PainReport(level: .high, bodyRegion: .shoulder, side: .left))
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripChangeGoalAndPhase() throws {
        let goal = AgentIntent.changeGoal(.strength)
        XCTAssertEqual(try roundTrip(goal), goal)
        let phase = AgentIntent.changePhase(.deficit)
        XCTAssertEqual(try roundTrip(phase), phase)
    }

    func testRoundTripChangeGym() throws {
        let a = AgentIntent.changeGym(GymID())
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripAskWhy() throws {
        let a = AgentIntent.askWhy(DecisionID())
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripUpdateRestriction() throws {
        let draft = TrainingRestrictionDraft(
            bodyRegion: .knee,
            side: .right,
            source: .professionalGuidance,
            forbiddenPatterns: [.squat],
            notes: "hablar con el profe"
        )
        let a = AgentIntent.updateRestriction(draft)
        XCTAssertEqual(try roundTrip(a), a)
    }

    func testRoundTripRequestPlanAdjustment() throws {
        let a = AgentIntent.requestPlanAdjustment(PlanAdjustmentRequest(scope: .volume))
        XCTAssertEqual(try roundTrip(a), a)
    }

    // MARK: - Unknown intent seguro

    func testUnknownTagFailsSafely() throws {
        let payload = """
        {"intent":"totallyUnknownIntent","payload":{"value":42}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AgentIntent.self, from: payload)) { error in
            guard case AgentIntentError.unsupported(let tag) = error else {
                return XCTFail("esperaba AgentIntentError.unsupported, obtuve \(error)")
            }
            XCTAssertEqual(tag, "totallyUnknownIntent")
        }
    }

    // MARK: - displayName

    func testDisplayNameNonEmptyForEveryIntent() throws {
        let cases: [AgentIntent] = [
            .setTimeConstraint(.hard(minutes: 30)),
            .equipmentUnavailable(.init(equipmentType: .barbell), .occupied),
            .requestExerciseSwap(ExerciseID()),
            .reportFatigue(.init(severity: 3)),
            .reportPain(.init(level: .moderate)),
            .changeGoal(.hypertrophy),
            .changePhase(.surplus),
            .changeGym(GymID()),
            .askWhy(DecisionID()),
            .updateRestriction(.init(bodyRegion: .shoulder)),
            .requestPlanAdjustment(.init(scope: .fullRebuild)),
        ]
        for intent in cases {
            XCTAssertFalse(intent.displayName.isEmpty, "displayName vacío para \(intent.tag)")
            XCTAssertFalse(intent.tag.isEmpty)
        }
    }

    // MARK: - El intent no interpola estado clínico

    func testPainReportCarriesReportOnly() {
        let pain = PainReport(level: .high, bodyRegion: .knee, side: .bilateral)
        // El informe es dato, no veredicto: no expone diagnóstico textual.
        XCTAssertEqual(pain.level, .high)
        XCTAssertEqual(pain.bodyRegion, .knee)
    }

    func testFatigueSeverityBounds() {
        XCTAssertTrue(UserFatigueFeedback.validSeverity(1))
        XCTAssertTrue(UserFatigueFeedback.validSeverity(5))
        XCTAssertFalse(UserFatigueFeedback.validSeverity(0))
        XCTAssertFalse(UserFatigueFeedback.validSeverity(6))
    }
}