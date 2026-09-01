//
//  ProfileTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("MusclePriority (PR-0104)")
struct MusclePriorityTests {

    @Test("MusclePriority round-trips through Codable")
    func roundTrips() throws {
        let priority = MusclePriority(muscleGroupID: .chest, priority: .emphasize)
        let data = try JSONEncoder().encode(priority)
        let decoded = try JSONDecoder().decode(MusclePriority.self, from: data)
        #expect(decoded == priority)
        #expect(decoded.muscleGroupID == .chest)
        #expect(decoded.priority == .emphasize)
    }

    @Test("MusclePriority equality and hashing")
    func equality() {
        let a = MusclePriority(muscleGroupID: .back, priority: .normal)
        let b = MusclePriority(muscleGroupID: .back, priority: .normal)
        let c = MusclePriority(muscleGroupID: .back, priority: .specialize)
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }
}

@Suite("SchedulePreference (PR-0104)")
struct SchedulePreferenceTests {

    @Test("Valid schedule initializes")
    func validInitializes() throws {
        let schedule = try SchedulePreference(
            trainingDaysPerWeek: 4,
            usualSessionMinutes: 60,
            preferredTimeWindows: [
                try PreferredDayTime(
                    daysOfWeek: [.monday, .wednesday, .friday],
                    startTimeMinutes: 450,
                    durationMinutes: 60
                )
            ]
        )
        #expect(schedule.trainingDaysPerWeek == 4)
        #expect(schedule.usualSessionMinutes == 60)
        #expect(schedule.preferredTimeWindows.first?.daysOfWeek.contains(.friday) == true)
    }

    @Test("Out-of-range training days is rejected")
    func invalidDaysRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SchedulePreference(trainingDaysPerWeek: 1, usualSessionMinutes: 60)
        }
        #expect(throws: DomainValidationError.self) {
            _ = try SchedulePreference(trainingDaysPerWeek: 8, usualSessionMinutes: 60)
        }
    }

    @Test("Out-of-range session minutes is rejected")
    func invalidMinutesRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SchedulePreference(trainingDaysPerWeek: 3, usualSessionMinutes: 10)
        }
    }

    @Test("PreferredDayTime rejects invalid start time")
    func invalidWindowRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try PreferredDayTime(daysOfWeek: [.monday], startTimeMinutes: 1500, durationMinutes: 30)
        }
        #expect(throws: DomainValidationError.self) {
            _ = try PreferredDayTime(daysOfWeek: [], startTimeMinutes: 450, durationMinutes: 30)
        }
    }
}

@Suite("Profile independence (PR-0104)")
struct ProfileIndependenceTests {

    @Test("Goal and phase are independent")
    func goalPhaseIndependent() throws {
        var profile = try UserTrainingProfile(
            experience: .intermediate,
            goal: .strength,
            phase: .maintenance,
            trainingDaysPerWeek: 3,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            coachingDetail: .guided
        )
        profile.goal = .hypertrophy
        #expect(profile.goal == .hypertrophy)
        #expect(profile.phase == .maintenance)
    }

    @Test("Changing goal does not lose history (records intact)")
    func goalChangePreservesHistory() throws {
        let exerciseID = ExerciseID()
        // Historial existente (no se toca al modificar el perfil).
        let history = [
            try SetRecord(exerciseID: exerciseID, weight: 80, unit: .kilograms, reps: 10),
            try SetRecord(exerciseID: exerciseID, weight: 85, unit: .kilograms, reps: 8),
        ]

        var profile = try UserTrainingProfile(
            experience: .intermediate,
            goal: .strength,
            phase: .maintenance,
            trainingDaysPerWeek: 3,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            coachingDetail: .guided
        )
        let snapshot = history
        profile.goal = .bodybuilding
        profile.phase = .surplus

        #expect(profile.goal == .bodybuilding)
        #expect(profile.phase == .surplus)
        // El historial permanece intacto.
        #expect(history.count == snapshot.count)
        #expect(history[0].weight == 80)
        #expect(history[1].reps == 8)
    }
}
