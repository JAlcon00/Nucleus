//
//  TrainingTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Workout lifecycle transitions")
struct WorkoutLifecycleTests {

    @Test("Valid workout transition advances state")
    func validWorkoutTransition() throws {
        let result = try WorkoutLifecycleState.planned.transitioning(to: .active)
        #expect(result == .active)
        let finishing = try WorkoutLifecycleState.active.transitioning(to: .finishing)
        #expect(finishing == .finishing)
        let completed = try WorkoutLifecycleState.finishing.transitioning(to: .completed)
        #expect(completed == .completed)
    }

    @Test("Invalid workout transition is rejected")
    func invalidWorkoutTransitionRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try WorkoutLifecycleState.planned.transitioning(to: .completed)
        }
        #expect(throws: DomainValidationError.self) {
            _ = try WorkoutLifecycleState.completed.transitioning(to: .active)
        }
    }

    @Test("Terminal workout states have no allowed next")
    func terminalStates() {
        #expect(WorkoutLifecycleState.completed.allowedNext.isEmpty)
        #expect(WorkoutLifecycleState.abandoned.allowedNext.isEmpty)
    }
}

@Suite("Set lifecycle transitions")
struct SetLifecycleTests {

    @Test("Valid set transition advances state")
    func validSetTransition() throws {
        #expect(try SetLifecycleState.planned.transitioning(to: .ready) == .ready)
        #expect(try SetLifecycleState.ready.transitioning(to: .completed) == .completed)
    }

    @Test("Invalid set transition is rejected")
    func invalidSetTransitionRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetLifecycleState.planned.transitioning(to: .completed)
        }
        #expect(throws: DomainValidationError.self) {
            _ = try SetLifecycleState.completed.transitioning(to: .ready)
        }
    }
}

@Suite("Set validity (PR-0103)")
struct SetValidityTests {

    @Test("SetRecord rejects negative weight")
    func negativeWeightRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetRecord(
                exerciseID: ExerciseID(),
                weight: -1,
                unit: .kilograms,
                reps: 5
            )
        }
    }

    @Test("SetRecord rejects zero reps")
    func zeroRepsRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetRecord(
                exerciseID: ExerciseID(),
                weight: 60,
                unit: .kilograms,
                reps: 0
            )
        }
    }

    @Test("SetPrescription rejects empty rep range")
    func emptyRepRangeRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetPrescription(
                targetRepRange: 0...2,
                restSeconds: 90...120
            )
        }
    }

    @Test("SetPrescription rejects negative rest range")
    func negativeRestRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetPrescription(
                targetRepRange: 8...12,
                restSeconds: -1...90
            )
        }
    }

    @Test("SetPrescription rejects negative target load")
    func negativeTargetLoadRejected() {
        #expect(throws: DomainValidationError.self) {
            _ = try SetPrescription(
                targetRepRange: 8...12,
                targetLoad: -5,
                restSeconds: 90...120
            )
        }
    }

    @Test("Warmup sets are distinguishable")
    func warmupDistinguishable() throws {
        let warmup = try SetPrescription(
            targetRepRange: 10...12,
            targetLoad: nil,
            restSeconds: 60...90,
            isWarmup: true
        )
        let working = try SetPrescription(
            targetRepRange: 8...10,
            restSeconds: 120...180,
            isWarmup: false
        )
        #expect(warmup.isWarmup)
        #expect(!working.isWarmup)
        #expect(warmup.isWarmup != working.isWarmup)
    }
}

@Suite("Planned vs performed integrity (PR-0103)")
struct PlannedVsPerformedTests {

    @Test("SetPrescription and SetRecord are distinct types")
    func prescriptionAndRecordDistinct() {
        let exerciseID = ExerciseID()
        let prescription = try! SetPrescription(
            targetRepRange: 8...12,
            restSeconds: 120...180
        )
        let record = try! SetRecord(
            exerciseID: exerciseID,
            weight: 80,
            unit: .kilograms,
            reps: 10
        )
        #expect(prescription.targetRepRange == 8...12)
        #expect(record.reps == 10)
        #expect(record.exerciseID == exerciseID)
        #expect(SetRecord.self != SetPrescription.self)
    }

    @Test("WorkoutSessionRecord does not mutate a SessionTemplate")
    func executionDoesNotMutatePlan() throws {
        let exerciseID = ExerciseID()
        let plan = SessionTemplate(
            title: "Upper A",
            plannedSets: [
                PlannedSet(
                    exerciseID: exerciseID,
                    prescription: try! SetPrescription(
                        targetRepRange: 8...12,
                        restSeconds: 120...180
                    )
                )
            ]
        )

        var session = WorkoutSessionRecord(templateID: plan.id)
        try session.transition(to: .active)
        session = session.performedSet(
            try! SetRecord(exerciseID: exerciseID, weight: 80, unit: .kilograms, reps: 10)
        )

        #expect(session.lifecycle == .active)
        #expect(session.sets.count == 1)
        // El plan queda intacto.
        #expect(plan.plannedSets.count == 1)
        #expect(plan.plannedSets[0].prescription.targetRepRange == 8...12)
    }

    @Test("WorkoutSessionRecord round-trips through Codable")
    func sessionCodableRoundTrip() throws {
        var session = WorkoutSessionRecord()
        try session.transition(to: .active)
        session = session.performedSet(
            try! SetRecord(exerciseID: ExerciseID(), weight: 90, unit: .kilograms, reps: 5, rir: 2)
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: data)
        #expect(decoded.lifecycle == session.lifecycle)
        #expect(decoded.sets.count == session.sets.count)
        #expect(decoded.sets.first?.rir == 2)
    }
}
