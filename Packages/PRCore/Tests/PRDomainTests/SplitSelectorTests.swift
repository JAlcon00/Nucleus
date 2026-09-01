//
//  SplitSelectorTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del SplitSelector (PR-0501, promptMaster §8.2): selección por días/
//  objetivo/experiencia, determinismo y explicabilidad. Cubre la matriz de
//  fixtures del plan §7 (A–E) donde el split es determinable.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("SplitSelector selection (PR-0501)")
struct SplitSelectionTests {
    let selector = SplitSelector()

    @Test("2-3 days selects full body")
    func twoThreeDaysFullBody() throws {
        for days in [2, 3] {
            let split = try selector.select(
                trainingDaysPerWeek: days,
                goal: .hypertrophy,
                experience: .novice,
                phase: .surplus
            )
            #expect(split.split == .fullBody)
            #expect(split.reason == .trainingDays)
        }
    }

    @Test("4 days selects upper/lower by default")
    func fourDaysUpperLower() throws {
        let split = try selector.select(
            trainingDaysPerWeek: 4,
            goal: .hypertrophy,
            experience: .intermediate,
            phase: .surplus
        )
        #expect(split.split == .upperLower)
    }

    @Test("4 days advanced bodybuilding surplus allows push/pull/legs")
    func fourDaysAdvancedBodybuilding() throws {
        let split = try selector.select(
            trainingDaysPerWeek: 4,
            goal: .bodybuilding,
            experience: .advanced,
            phase: .surplus
        )
        #expect(split.split == .pushPullLegs)
        #expect(split.reason == .goalRequirement)
    }

    @Test("5 days selects push/pull/legs")
    func fiveDaysPPL() throws {
        let split = try selector.select(
            trainingDaysPerWeek: 5,
            goal: .strength,
            experience: .advanced,
            phase: .maintenance
        )
        #expect(split.split == .pushPullLegs)
    }

    @Test("6-7 days selects push/pull/legs for adherence")
    func highFrequencyPPL() throws {
        for days in [6, 7] {
            let split = try selector.select(
                trainingDaysPerWeek: days,
                goal: .generalHealth,
                experience: .beginner,
                phase: .maintenance
            )
            #expect(split.split == .pushPullLegs)
            #expect(split.reason == .adherence)
        }
    }

    @Test("Plan matrix fixture A is a simple full body")
    func matrixFixtureA() throws {
        // A: hypertrophy/surplus/novice → simple full body.
        let split = try selector.select(
            trainingDaysPerWeek: 3,
            goal: .hypertrophy,
            experience: .novice,
            phase: .surplus
        )
        #expect(split.split == .fullBody)
        #expect(split.trainingDaysPerWeek == 3)
    }
}

@Suite("SplitSelector determinism & validation (PR-0501)")
struct SplitSelectorDeterminismTests {
    let selector = SplitSelector()

    @Test("Same inputs always select the same split")
    func deterministic() throws {
        let a = try selector.select(trainingDaysPerWeek: 4, goal: .hypertrophy, experience: .intermediate, phase: .surplus)
        let b = try selector.select(trainingDaysPerWeek: 4, goal: .hypertrophy, experience: .intermediate, phase: .surplus)
        #expect(a == b)
    }

    @Test("Training days must be within 2...7")
    func rejectsInvalidDays() {
        #expect(throws: SplitSelectionError.invalidTrainingDays(value: 1)) {
            _ = try selector.select(trainingDaysPerWeek: 1, goal: .hypertrophy, experience: .novice, phase: .surplus)
        }
        #expect(throws: SplitSelectionError.invalidTrainingDays(value: 8)) {
            _ = try selector.select(trainingDaysPerWeek: 8, goal: .hypertrophy, experience: .novice, phase: .surplus)
        }
    }

    @Test("Selection produces explainable facts")
    func explainableFacts() throws {
        let split = try selector.select(trainingDaysPerWeek: 3, goal: .hypertrophy, experience: .novice, phase: .surplus)
        let facts = split.explanationFacts
        #expect(facts.contains { $0.key == "split" && $0.value == "fullBody" })
        #expect(facts.contains { $0.key == "trainingDaysPerWeek" && $0.value == "3" })
        #expect(facts.contains { $0.key == "reason" })
    }

    @Test("TrainingSplit is a closed enum and Codable")
    func splitCodable() throws {
        let data = try JSONEncoder().encode(TrainingSplit.upperLower)
        let decoded = try JSONDecoder().decode(TrainingSplit.self, from: data)
        #expect(decoded == .upperLower)
    }
}