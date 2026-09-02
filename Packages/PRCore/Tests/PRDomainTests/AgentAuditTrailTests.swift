//
//  AgentAuditTrailTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del Agent audit trail (promptMaster §20, PR-1607): el pipeline del agente
//  (intent → action → result) es trazable y minimiza datos sensibles (no se guarda
//  texto crudo del usuario ni payload sensible).
//

import XCTest
@testable import PRDomain

final class AgentAuditTrailTests: XCTestCase {

    // MARK: - Trazabilidad intent → action → result

    func testFullPipelineIsTraceableByConversation() throws {
        let conversation = UUID()
        var journal = AgentAuditJournal()

        let intent: AgentIntent = .setTimeConstraint(.hard(minutes: 30))
        let validator = try ActionPolicyValidator(
            config: ActionPolicyConfig(rule: ActionPolicyDefaults.makeRule())
        )
        let verdict = try validator.validate(.recomputeSession, context: .init())

        journal.append(.intent(intent, conversationID: conversation))
        journal.append(.validation(verdict, conversationID: conversation))
        journal.append(.result(command: "recomputeSession", conversationID: conversation))

        let chain = journal.records(conversationID: conversation)
        XCTAssertEqual(chain.count, 3)

        XCTAssertEqual(chain[0].stage, .inboundIntent)
        XCTAssertEqual(chain[0].intentTag, "setTimeConstraint")
        XCTAssertEqual(chain[1].stage, .actionValidation)
        XCTAssertEqual(chain[1].actionName, "Recomputar sesión")
        XCTAssertEqual(chain[1].outcome?.hasPrefix("allowed"), true)
        XCTAssertEqual(chain[2].stage, .result)
        XCTAssertEqual(chain[2].resultCommand, "recomputeSession")

        let summary = journal.traceSummary(conversationID: conversation)
        XCTAssertTrue(summary.contains("intent=setTimeConstraint"))
        XCTAssertTrue(summary.contains("action=Recomputar sesión"))
        XCTAssertTrue(summary.contains("result=recomputeSession"))
    }

    func testNeedsClarificationRecordsTagSafely() {
        let journal = AgentAuditJournal(records: [
            .needsClarification(conversationID: UUID()),
        ])
        XCTAssertEqual(journal.count, 1)
        XCTAssertEqual(journal.all.first?.intentTag, "needsClarification")
    }

    // MARK: - Mínima retención de datos sensibles

    func testIntentRecordKeepsOnlyTagAndNameNotRawPayload() throws {
        // reportPain lleva payload sensible (nivel, región, notas). El audit record
        // nunca debe retener esas notas crudas.
        let pain = AgentIntent.reportPain(PainReport(
            level: .high, bodyRegion: .shoulder, side: nil, notes: "dolor punzante al subir"
        ))
        let record = AgentAuditRecord.intent(pain)
        XCTAssertEqual(record.intentTag, "reportPain")
        XCTAssertEqual(record.intentDisplayName, "Reportar dolor")
        XCTAssertTrue(record.notes.isEmpty)
        XCTAssertFalse(jsonContains(record, needle: "dolor punzante"))
        XCTAssertFalse(jsonContains(record, needle: "hombro"))
    }

    func testNoRawUserTextStored() {
        let record = AgentAuditRecord.intent(.setTimeConstraint(.hard(minutes: 30)))
        XCTAssertFalse(jsonContains(record, needle: "30"))
    }

    // MARK: - Journal append-only + orden

    func testJournalIsAppendOnlyAndNeverRemoves() {
        var journal = AgentAuditJournal()
        XCTAssertTrue(journal.isEmpty)
        journal.append(.result(command: "a"))
        journal.append(.result(command: "b"))
        XCTAssertEqual(journal.count, 2)
        XCTAssertEqual(journal.all.map(\.resultCommand), ["a", "b"])
    }

    func testLatestOrdersByDateDescending() {
        let older = AgentAuditRecord.intent(.changeGoal(.hypertrophy), date: Date(timeIntervalSince1970: 1000))
        let newer = AgentAuditRecord.intent(.changePhase(.surplus), date: Date(timeIntervalSince1970: 2000))
        let journal = AgentAuditJournal(records: [older, newer])
        XCTAssertEqual(journal.latest(limit: 1).first?.intentTag, "changePhase")
        XCTAssertEqual(journal.latest().count, 2)
    }

    func testOtherConversationIsNotMixed() {
        let a = UUID()
        let b = UUID()
        let journal = AgentAuditJournal(records: [
            .intent(.changeGoal(.strength), conversationID: a),
            .intent(.changeGoal(.hypertrophy), conversationID: b),
        ])
        XCTAssertEqual(journal.records(conversationID: a).count, 1)
        XCTAssertEqual(journal.records(conversationID: b).count, 1)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let record = AgentAuditRecord.validation(
            ActionPolicyVerdict(
                action: .saveRestriction,
                outcome: .rejected(reason: "no evade"),
                reasons: ["restricción profesional"],
                ruleReference: try EvidenceRuleReference(ruleID: ActionPolicyDefaults.ruleID, version: 1),
                decisionRecord: DecisionRecord(type: .policyValidation, action: .init(title: "t"))
            ),
            conversationID: UUID()
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AgentAuditRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    // MARK: - Helpers

    private func jsonContains(_ record: AgentAuditRecord, needle: String) -> Bool {
        guard let data = try? JSONEncoder().encode(record),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        return json.contains(needle)
    }
}
