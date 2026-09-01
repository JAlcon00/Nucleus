//
//  IdentifiersTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Core identifiers")
struct CoreIdentifiersTests {

    @Test("ExerciseID round-trips through Codable")
    func exerciseIDCodableRoundTrip() throws {
        let id = ExerciseID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ExerciseID.self, from: data)
        #expect(decoded == id)
    }

    @Test("Typed IDs preserve equality and hashing")
    func typedIDsHashAndEquate() {
        let a = ExerciseID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = ExerciseID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let c = ExerciseID()
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }
}

@Suite("Load validation")
struct LoadTests {

    @Test("Valid load initializes")
    func validLoadInitializes() throws {
        let load = try Load(value: 82.5, unit: .kilograms)
        #expect(load.value == 82.5)
        #expect(load.unit == .kilograms)
    }

    @Test("Zero is a valid load")
    func zeroLoadIsValid() throws {
        _ = try Load(value: 0, unit: .pounds)
    }

    @Test("Negative load is rejected")
    func negativeLoadIsRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try Load(value: -1, unit: .kilograms)
        }
    }

    @Test("NaN load is rejected")
    func nanLoadIsRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try Load(value: .nan, unit: .kilograms)
        }
    }
}

@Suite("TimeConstraint")
struct TimeConstraintTests {

    @Test("Hard constraint reports guaranteed minutes")
    func hardConstraintGuaranteedMinutes() {
        let constraint = TimeConstraint.hard(minutes: 30)
        #expect(constraint.guaranteedMinutes == 30)
    }

    @Test("Unconstrained has no guaranteed minutes")
    func unconstrainedHasNoMinutes() {
        #expect(TimeConstraint.unconstrained.guaranteedMinutes == nil)
    }

    @Test("TimeConstraint round-trips through Codable")
    func timeConstraintCodableRoundTrip() throws {
        let cases: [TimeConstraint] = [
            .hard(minutes: 30),
            .flexible(targetMinutes: 45, toleranceMinutes: 15),
            .unconstrained,
        ]
        for constraint in cases {
            let data = try JSONEncoder().encode(constraint)
            let decoded = try JSONDecoder().decode(TimeConstraint.self, from: data)
            #expect(decoded == constraint)
        }
    }

    @Test("Negative hard minutes are rejected on decode")
    func negativeHardMinutesRejected() {
        #expect(throws: DomainValidationError.self) {
            let data = Data("\"hard:-5\"".utf8)
            _ = try JSONDecoder().decode(TimeConstraint.self, from: data)
        }
    }

    @Test("Negative tolerance is rejected on decode")
    func negativeToleranceRejected() {
        #expect(throws: DomainValidationError.self) {
            let data = Data("\"flexible:30:-10\"".utf8)
            _ = try JSONDecoder().decode(TimeConstraint.self, from: data)
        }
    }

    @Test("validated() rejects negative direct construction")
    func validatedRejectsNegativeConstruction() {
        #expect(throws: DomainValidationError.self) {
            _ = try TimeConstraint.hard(minutes: -1).validated()
        }
    }
}

@Suite("UserTrainingProfile validation")
struct UserProfileTests {

    @Test("Valid profile initializes and rounds via Codable")
    func validProfileRoundTrips() throws {
        let profile = try UserTrainingProfile(
            experience: .novice,
            goal: .hypertrophy,
            phase: .surplus,
            trainingDaysPerWeek: 3,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            coachingDetail: .guided
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserTrainingProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("Out-of-range training days is rejected")
    func outOfRangeDaysRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try UserTrainingProfile(
                experience: .novice,
                goal: .hypertrophy,
                phase: .surplus,
                trainingDaysPerWeek: 8,
                usualSessionMinutes: 60,
                varietyPreference: .balanced,
                coachingDetail: .guided
            )
        }
    }

    @Test("Out-of-range session minutes is rejected")
    func outOfRangeMinutesRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try UserTrainingProfile(
                experience: .novice,
                goal: .hypertrophy,
                phase: .surplus,
                trainingDaysPerWeek: 3,
                usualSessionMinutes: 10,
                varietyPreference: .balanced,
                coachingDetail: .guided
            )
        }
    }
}
