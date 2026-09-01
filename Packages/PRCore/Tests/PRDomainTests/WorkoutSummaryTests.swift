import Testing
import Foundation
@testable import PRDomain

@Suite("Workout completion summary (PR-0605)")
struct WorkoutSummaryTests {

    private let exerciseA = ExerciseID(rawValue: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    private let exerciseB = ExerciseID(rawValue: UUID(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)

    private func completedSet(exercise: ExerciseID, weight: Double, reps: Int, at date: Date) throws -> SetRecord {
        try SetRecord(exerciseID: exercise, performedAt: date, weight: weight, unit: .kilograms, reps: reps, lifecycle: .completed)
    }

    private func session(startedAt: Date, endedAt: Date?, sets: [SetRecord], lifecycle: WorkoutLifecycleState = .completed) -> WorkoutSessionRecord {
        WorkoutSessionRecord(startedAt: startedAt, endedAt: endedAt, lifecycle: lifecycle, sets: sets)
    }

    @Test("summary computes duration, working sets and volume")
    func computesBasics() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1500)
        let session = self.session(
            startedAt: start,
            endedAt: end,
            sets: [
                try completedSet(exercise: exerciseA, weight: 100, reps: 8, at: start),
                try completedSet(exercise: exerciseA, weight: 100, reps: 8, at: start),
            ]
        )

        let summary = WorkoutSummaryBuilder().summarize(session)

        #expect(summary.durationSeconds == 500)
        #expect(summary.workingSets == 2)
        #expect(summary.volume == 1600)
        #expect(summary.nextAction == .completed)
    }

    @Test("skipped and planned sets are not counted nor added to volume")
    func ignoresNonCompletedSets() throws {
        let start = Date(timeIntervalSince1970: 0)
        var skipped = try completedSet(exercise: exerciseA, weight: 100, reps: 8, at: start)
        skipped.lifecycle = .skipped
        let session = self.session(startedAt: start, endedAt: start.addingTimeInterval(100), sets: [skipped])

        let summary = WorkoutSummaryBuilder().summarize(session)
        #expect(summary.workingSets == 0)
        #expect(summary.volume == 0)
    }

    @Test("unfinished session reports inProgress")
    func inProgressAction() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let session = self.session(startedAt: start, endedAt: nil, sets: [], lifecycle: .active)
        let summary = WorkoutSummaryBuilder().summarize(session, now: Date(timeIntervalSince1970: 1100))
        #expect(summary.nextAction == .inProgress)
        #expect(summary.durationSeconds == 100)
    }

    @Test("finishing state maps to readyToFinish")
    func readyToFinishAction() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let session = self.session(startedAt: start, endedAt: nil, sets: [], lifecycle: .finishing)
        let summary = WorkoutSummaryBuilder().summarize(session, now: Date(timeIntervalSince1970: 1000))
        #expect(summary.nextAction == .readyToFinish)
    }

    @Test("PR detector flags sets exceeding previous best weight")
    func detectsPRs() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let session = self.session(
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            sets: [
                try completedSet(exercise: exerciseA, weight: 110, reps: 5, at: start),
                try completedSet(exercise: exerciseB, weight: 60, reps: 10, at: start),
            ]
        )

        let summary = WorkoutSummaryBuilder().summarize(
            session,
            previousBestWeight: [exerciseA: 100, exerciseB: 80]
        )

        #expect(summary.records.count == 1)
        #expect(summary.records[0].exerciseID == exerciseA)
        #expect(summary.records[0].weight == 110)
    }

    @Test("PR detector never invents a record without baseline")
    func noInventedPR() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let session = self.session(
            startedAt: start,
            endedAt: start.addingTimeInterval(100),
            sets: [try completedSet(exercise: exerciseA, weight: 120, reps: 5, at: start)]
        )
        // Sin baseline: no hay referencia previa, por lo que NO se inventa un PR.
        let summary = WorkoutSummaryBuilder().summarize(session, previousBestWeight: [:])
        #expect(summary.records.isEmpty)
    }

    @Test("energy is only propagated when reconciled (RN-008)")
    func energyOnlyWhenReconciled() throws {
        let session = self.session(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), sets: [])

        let withEnergy = WorkoutSummaryBuilder().summarize(session, energyKcal: 250)
        #expect(withEnergy.energyKcal == 250)

        let negative = WorkoutSummaryBuilder().summarize(session, energyKcal: -10)
        #expect(negative.energyKcal == nil)

        // Sin valor reconciliado externo, nunca se inventa energía.
        let none = WorkoutSummaryBuilder().summarize(session)
        #expect(none.energyKcal == nil)
    }

    @Test("summary is Codable")
    func summaryCodable() throws {
        let session = self.session(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60), sets: [])
        let summary = WorkoutSummaryBuilder().summarize(session, energyKcal: 120)

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(WorkoutSummary.self, from: data)
        #expect(decoded == summary)
    }
}