import Testing
import Foundation
@testable import PRDomain

@Suite("Pre-workout check-in (PR-1301)")
struct FitnessCheckInTests {

    private func policyWithInterval(_ days: Int) throws -> CheckInPolicy {
        let rule = try EvidenceRule(
            id: CheckInPolicyDefaults.ruleID,
            name: "Pre-workout check-in policy",
            category: .recovery,
            confidence: .expertConsensus,
            version: 1,
            parameters: CheckInPolicyKeys.defaults().merging([CheckInPolicyKeys.requiredEveryNDays: Double(days)]) { _, new in new }
        )
        return try CheckInPolicy(rule: rule)
    }

    // MARK: - Feelings

    @Test("all feelings are representable and distinct")
    func feelingsExhaustive() {
        #expect(CheckInFeeling.allCases.count == 5)
        #expect(Set(["excellent", "normal", "tired", "veryTired", "somethingHurts"])
            == Set(CheckInFeeling.allCases.map(\.rawValue)))
    }

    // MARK: - Check-in coherence

    @Test("somethingHurts requires a region (never a diagnosis without location)")
    func somethingHurtsNeedsRegion() {
        let withoutRegion = PreWorkoutCheckIn(feeling: .somethingHurts, region: nil)
        #expect(!withoutRegion.isCoherent)
    }

    @Test("non-pain feelings must not carry a region")
    func nonPainHasNoRegion() {
        let odd: PreWorkoutCheckIn = PreWorkoutCheckIn(feeling: .normal, region: .shoulders)
        #expect(!odd.isCoherent)
    }

    @Test("healthy feelings are coherent without region")
    func healthyIsCoherent() {
        let checkIn = PreWorkoutCheckIn(feeling: .veryTired, region: nil)
        #expect(checkIn.isCoherent)
    }

    @Test("record validates coherence and passes a valid one through")
    func recordValid() throws {
        let engine = try CheckInEngine(policy: try policyWithInterval(0))
        let valid = PreWorkoutCheckIn(feeling: .normal, region: nil)
        #expect(try engine.record(valid).isCoherent)
    }

    @Test("record rejects an incoherent check-in")
    func recordRejectsIncoherent() throws {
        let engine = try CheckInEngine(policy: try policyWithInterval(0))
        let incoherent = PreWorkoutCheckIn(feeling: .somethingHurts, region: nil)
        #expect(throws: CheckInPolicyError.invalidCheckIn) {
            try engine.record(incoherent)
        }
    }

    // MARK: - Policy requirement

    @Test("interval 0 means never required by periodicity (not mandatory every day)")
    func intervalZeroNeverRequired() throws {
        let engine = try CheckInEngine(policy: try policyWithInterval(0))
        let requirement = try engine.evaluateRequirement(daysSinceLastWorkout: 30)
        guard case .optional = requirement else {
            Issue.record("intervalo 0 no debe exigir check-in")
            return
        }
    }

    @Test("interval N requires after >= N days since last workout")
    func intervalNRequires() throws {
        let engine = try CheckInEngine(policy: try policyWithInterval(4))
        #expect(isOptional(try engine.evaluateRequirement(daysSinceLastWorkout: 3)))
        #expect(isRequired(try engine.evaluateRequirement(daysSinceLastWorkout: 4)))
        #expect(isRequired(try engine.evaluateRequirement(daysSinceLastWorkout: 10)))
    }

    @Test("default policy is not mandatory every day")
    func defaultNotMandatoryEveryDay() throws {
        let rule = try CheckInPolicyDefaults.makeRule()
        let policy = try CheckInPolicy(rule: rule)
        #expect(policy.requiredEveryNDays == 0)
    }

    @Test("policy requires a recovery category rule")
    func policyRejectsWrongCategory() throws {
        let rule = try EvidenceRule(
            id: EvidenceRuleID(rawValue: "ordering.bad"),
            name: "wrong",
            category: .ordering,
            confidence: .emerging,
            version: 1,
            parameters: CheckInPolicyKeys.defaults()
        )
        #expect(throws: CheckInPolicyError.wrongCategory) {
            try CheckInPolicy(rule: rule)
        }
    }

    private func isRequired(_ requirement: CheckInRequirement) -> Bool {
        if case .required = requirement { return true }
        return false
    }

    private func isOptional(_ requirement: CheckInRequirement) -> Bool {
        if case .optional = requirement { return true }
        return false
    }
}