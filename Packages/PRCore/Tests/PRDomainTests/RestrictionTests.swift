//
//  RestrictionTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("TrainingRestriction fields (PR-0106)")
struct RestrictionFieldsTests {

    @Test("Restriction captures body region, side, source and review date")
    func capturesFields() {
        let reviewDate = Date(timeIntervalSinceNow: 30 * 86_400)
        let restriction = TrainingRestriction(
            bodyRegion: .knee,
            side: .left,
            reviewDate: reviewDate,
            source: .professionalGuidance,
            forbiddenPatterns: [.squat, .lunge],
            restrictionTags: [.knee]
        )
        #expect(restriction.bodyRegion == .knee)
        #expect(restriction.side == .left)
        #expect(restriction.source == .professionalGuidance)
        #expect(restriction.reviewDate == reviewDate)
        #expect(restriction.forbids(.squat))
        #expect(restriction.forbids(.lunge))
        #expect(!restriction.forbids(.hinge))
    }

    @Test("Restriction forbids explicit exercises")
    func forbidsExercises() {
        let exerciseID = ExerciseID()
        let other = ExerciseID()
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            forbiddenExerciseIDs: [exerciseID]
        )
        #expect(restriction.forbids(exercise: exerciseID))
        #expect(!restriction.forbids(exercise: other))
    }

    @Test("Restriction round-trips through Codable")
    func roundTrips() throws {
        let restriction = TrainingRestriction(
            bodyRegion: .lumbar,
            side: .bilateral,
            forbiddenPatterns: [.hinge]
        )
        let data = try JSONEncoder().encode(restriction)
        let decoded = try JSONDecoder().decode(TrainingRestriction.self, from: data)
        #expect(decoded == restriction)
        #expect(decoded.bodyRegion == .lumbar)
    }
}

@Suite("Restriction lifecycle (PR-0106)")
struct RestrictionLifecycleTests {

    @Test("Passing reviewDate triggers reviewNeeded, never auto-removes")
    func reviewDateTriggersReviewNeeded() {
        let past = Date(timeIntervalSinceNow: -86_400) // ayer
        let restriction = TrainingRestriction(
            bodyRegion: .knee,
            reviewDate: past,
            status: .active
        )
        let refreshed = restriction.refreshed(asOf: Date())
        #expect(refreshed.status == .reviewNeeded)
        // No se autoelimina ni se resuelve: sigue presente como reviewNeeded.
        #expect(refreshed.status != .resolved)
        #expect(refreshed.id == restriction.id)
    }

    @Test("Before reviewDate the restriction stays active")
    func beforeReviewDateStaysActive() {
        let future = Date(timeIntervalSinceNow: 86_400)
        let restriction = TrainingRestriction(
            bodyRegion: .knee,
            reviewDate: future,
            status: .active
        )
        #expect(restriction.refreshed(asOf: Date()).status == .active)
    }

    @Test("Restriction can be resolved by explicit user action only")
    func explicitResolution() {
        let pastReview = Date(timeIntervalSinceNow: -86_400)
        var restriction = TrainingRestriction(bodyRegion: .wrist, reviewDate: pastReview, status: .active)
        restriction = restriction.refreshed(asOf: Date())
        #expect(restriction.status == .reviewNeeded)

        restriction = restriction.updatedStatus(.resolved)
        #expect(restriction.status == .resolved)
    }

    @Test("Invalid status transition is rejected")
    func invalidTransitionRejected() {
        let restriction = TrainingRestriction(bodyRegion: .wrist, status: .resolved)
        // resolved -> active no es válido; se mantiene el estado original.
        #expect(restriction.updatedStatus(.active).status == .resolved)
    }
}
