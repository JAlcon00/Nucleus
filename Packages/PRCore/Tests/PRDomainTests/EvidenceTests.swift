//
//  EvidenceTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del Evidence Registry (PR-0303, promptMaster §22): reglas versionadas,
//  parámetros centralizados y DecisionRecord con referencia (id + versión).
//

import Foundation
import Testing
@testable import PRDomain

enum EvidenceFixtures {
    static func doubleProgressionRule() throws -> EvidenceRule {
        try EvidenceRule(
            id: EvidenceRuleID(rawValue: "progression.doubleProgression"),
            name: "Double Progression",
            category: .progression,
            confidence: .established,
            version: 1,
            parameters: [
                "repsAtTopOfRangeFractionRequired": 1.0,
                "defaultLoadIncrementKg": 2.5,
            ],
            references: [
                try EvidenceReference(title: "Progressive overload", source: "Product Spec §12.3", year: 2026),
            ]
        )
    }

    static func volumeRule() throws -> EvidenceRule {
        try EvidenceRule(
            id: EvidenceRuleID(rawValue: "volume.hypertrophyWeeklySets"),
            name: "Hypertrophy Weekly Volume",
            category: .volume,
            confidence: .emerging,
            version: 2,
            parameters: ["setsPerMusclePerWeek": 15]
        )
    }
}

@Suite("EvidenceRule modeling (PR-0303)")
struct EvidenceRuleTests {
    @Test("Round-trips through Codable preserving fields")
    func codableRoundTrip() throws {
        let rule = try EvidenceFixtures.doubleProgressionRule()
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(EvidenceRule.self, from: data)
        #expect(decoded == rule)
        #expect(decoded.id == rule.id)
        #expect(decoded.version == 1)
        #expect(decoded.active)
    }

    @Test("Rejects empty name")
    func emptyNameRejected() {
        #expect(throws: DomainValidationError.emptyRuleName) {
            _ = try EvidenceRule(
                id: EvidenceRuleID(rawValue: "x"),
                name: "   ",
                category: .volume,
                confidence: .established,
                version: 1
            )
        }
    }

    @Test("Rejects version below 1")
    func versionBelowOneRejected() {
        #expect(throws: DomainValidationError.invalidRuleVersion(value: 0)) {
            _ = try EvidenceRule(
                id: EvidenceRuleID(rawValue: "x"),
                name: "Rule",
                category: .volume,
                confidence: .established,
                version: 0
            )
        }
    }

    @Test("Rejects non-finite parameter values")
    func nonFiniteParameterRejected() {
        #expect(throws: DomainValidationError.nonFiniteRuleParameter(name: "x", value: .infinity)) {
            _ = try EvidenceRule(
                id: EvidenceRuleID(rawValue: "x"),
                name: "Rule",
                category: .volume,
                confidence: .established,
                version: 1,
                parameters: ["x": .infinity]
            )
        }
    }

    @Test("Rejects empty evidence reference title")
    func emptyReferenceRejected() {
        #expect(throws: DomainValidationError.emptyEvidenceReferenceTitle) {
            _ = try EvidenceReference(title: "  ")
        }
    }
}

@Suite("EvidenceRuleReference (PR-0303)")
struct EvidenceRuleReferenceTests {
    @Test("Bundles rule id with its version")
    func bundlesIDAndVersion() throws {
        let rule = try EvidenceFixtures.doubleProgressionRule()
        let reference = try EvidenceRuleReference(rule)
        #expect(reference.ruleID == rule.id)
        #expect(reference.version == rule.version)
    }

    @Test("Rejects version below 1")
    func rejectsInvalidVersion() {
        #expect(throws: DomainValidationError.invalidRuleVersion(value: 0)) {
            _ = try EvidenceRuleReference(ruleID: EvidenceRuleID(rawValue: "x"), version: 0)
        }
    }
}

@Suite("EvidenceRegistry (PR-0303)")
struct EvidenceRegistryTests {
    @Test("Registers and centralizes parameters")
    func registersAndCentralizesParameters() throws {
        var registry = try EvidenceRegistry()
        let rule = try EvidenceFixtures.doubleProgressionRule()
        try registry.register(rule)
        #expect(registry.activeRules().count == 1)
        #expect(registry.parameters(id: rule.id) == rule.parameters)
        let expectedReference = try EvidenceRuleReference(rule)
        #expect(registry.reference(for: rule.id) == expectedReference)
    }

    @Test("Rejects a change without a version bump")
    func rejectsSameVersionChange() throws {
        var registry = try EvidenceRegistry([try EvidenceFixtures.doubleProgressionRule()])
        #expect(throws: DomainValidationError.ruleVersionNotAdvanced(id: "progression.doubleProgression", current: 1, proposed: 1)) {
            try registry.register(try EvidenceFixtures.doubleProgressionRule())
        }
    }

    @Test("Accepts a version bump and exposes the new version")
    func acceptsVersionBump() throws {
        var registry = try EvidenceRegistry([try EvidenceFixtures.doubleProgressionRule()])
        let updated = try EvidenceRule(
            id: EvidenceRuleID(rawValue: "progression.doubleProgression"),
            name: "Double Progression",
            category: .progression,
            confidence: .established,
            version: 2,
            parameters: [
                "repsAtTopOfRangeFractionRequired": 0.8,
                "defaultLoadIncrementKg": 1.25,
            ]
        )
        try registry.register(updated)
        #expect(registry.activeRules().count == 1)
        #expect(registry.rule(id: updated.id)?.version == 2)
        let current = registry.reference(for: updated.id)
        let expected = try EvidenceRuleReference(updated)
        #expect(current == expected)
    }

    @Test("Rejects duplicate id with same version on init")
    func rejectsDuplicateOnInit() {
        let rule = try! EvidenceFixtures.doubleProgressionRule()
        #expect(throws: DomainValidationError.duplicateRuleID(id: rule.id.rawValue, existingVersion: 1, newVersion: 1)) {
            _ = try EvidenceRegistry([rule, rule])
        }
    }

    @Test("Deactivated rule is excluded from parameters and references")
    func deactivateExcludesRule() throws {
        var registry = try EvidenceRegistry([try EvidenceFixtures.doubleProgressionRule()])
        let id = EvidenceRuleID(rawValue: "progression.doubleProgression")
        try registry.deactivate(id: id)
        #expect(registry.activeRules().isEmpty)
        #expect(registry.parameters(id: id) == nil)
        #expect(registry.reference(for: id) == nil)
        #expect(registry.rule(id: id)?.active == false)
    }

    @Test("Lists rules in stable id order")
    func stableOrdering() throws {
        let registry = try EvidenceRegistry([try EvidenceFixtures.volumeRule(), try EvidenceFixtures.doubleProgressionRule()])
        let ids = registry.activeRules().map(\.id.rawValue)
        #expect(ids == ["progression.doubleProgression", "volume.hypertrophyWeeklySets"])
    }
}

@Suite("DecisionRecord rule references (PR-0303)")
struct DecisionRecordReferencesTests {
    @Test("DecisionRecord stores versioned rule references")
    func storesVersionedReferences() throws {
        let rule = try EvidenceFixtures.doubleProgressionRule()
        let reference = try EvidenceRuleReference(rule)
        let record = DecisionRecord(
            type: .loadChange,
            action: DecisionActionSummary(title: "Subir carga"),
            ruleReferences: [reference]
        )
        #expect(record.ruleReferences == [reference])
        #expect(record.ruleIDs == [rule.id])
    }

    @Test("Survives Codable round-trip with version intact")
    func codableRoundTrip() throws {
        let reference = try EvidenceRuleReference(
            ruleID: EvidenceRuleID(rawValue: "progression.doubleProgression"),
            version: 3
        )
        let record = DecisionRecord(
            type: .deload,
            action: DecisionActionSummary(title: "Deload"),
            ruleReferences: [reference]
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DecisionRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.ruleReferences.first?.version == 3)
    }

    @Test("Old decision keeps the rule version that was in force then")
    func oldDecisionKeepsVersion() throws {
        var registry = try EvidenceRegistry([try EvidenceFixtures.doubleProgressionRule()])
        let id = EvidenceRuleID(rawValue: "progression.doubleProgression")

        guard let refAtV1 = registry.reference(for: id) else {
            Issue.record("Expected a reference for \(id.rawValue)")
            return
        }
        let decisionAtV1 = DecisionRecord(
            type: .loadChange,
            action: DecisionActionSummary(title: "Subir carga"),
            ruleReferences: [refAtV1]
        )

        let updated = try EvidenceRule(
            id: id,
            name: "Double Progression",
            category: .progression,
            confidence: .established,
            version: 2,
            parameters: ["repsAtTopOfRangeFractionRequired": 0.8]
        )
        try registry.register(updated)

        #expect(decisionAtV1.ruleReferences.first?.version == 1)
        #expect(registry.reference(for: id)?.version == 2)
    }
}