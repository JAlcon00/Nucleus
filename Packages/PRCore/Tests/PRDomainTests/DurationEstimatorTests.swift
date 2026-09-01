import Testing
import Foundation
@testable import PRDomain

@Suite("Duration estimator (PR-0801)")
struct DurationEstimatorTests {

    private let exerciseA = ExerciseID(rawValue: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    private let exerciseB = ExerciseID(rawValue: UUID(uuidString: "A621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)

    private func plannedSet(_ exercise: ExerciseID, isWarmup: Bool = false, rest: ClosedRange<Int> = 90...150) throws -> PlannedSet {
        let prescription = try SetPrescription(
            targetRepRange: 8...12,
            targetLoad: 100,
            restSeconds: rest,
            isWarmup: isWarmup
        )
        return PlannedSet(exerciseID: exercise, prescription: prescription)
    }

    @Test("estimate sums per-set, rest and transition")
    func estimateSumsComponents() throws {
        // defaultSet 60, transition 30, rest 90
        let estimator = DurationEstimator()
        let sets = [
            try plannedSet(exerciseA, rest: 90...150),
            try plannedSet(exerciseA, rest: 90...150),
        ]
        // set1: 60 + 90 rest = 150; set2: 60 + 90 rest + 30 transition (before last? no)
        // orden: (60+90) + (60+90+30) = 150 + 180 = 330
        let est = estimator.estimate(plannedSets: sets)
        #expect(est == 330)
    }

    @Test("warmup sets use faster multiplier")
    func warmupFaster() throws {
        let estimator = DurationEstimator(defaults: DurationDefaults(defaultSetSeconds: 60, defaultTransitionSeconds: 30))
        let sets = [
            try plannedSet(exerciseA, isWarmup: true, rest: 90...150), // 60*0.6 + 90 = 126
            try plannedSet(exerciseA, rest: 90...150),                 // 60 + 90 + 30 transition = 180
        ]
        let est = estimator.estimate(plannedSets: sets)
        #expect(est == 306)
    }

    @Test("personal profile is preferred when confidence is sufficient")
    func prefersPersonalWhenConfident() throws {
        let profile = ExerciseDurationProfile(averageSeconds: 40, sampleCount: 50) // confidence 50/60 = 0.83
        let estimator = DurationEstimator(defaults: DurationDefaults(perExerciseSeconds: [exerciseA: 60]))
        #expect(estimator.shouldPreferPersonal(profile))
        #expect(estimator.setDuration(for: exerciseA, profile: profile) == 40)
    }

    @Test("defaults used when profile has low confidence")
    func usesDefaultsWhenUncertain() throws {
        let lowConfidence = ExerciseDurationProfile(averageSeconds: 20, sampleCount: 0) // ~0 confidence
        let estimator = DurationEstimator(defaults: DurationDefaults(perExerciseSeconds: [exerciseA: 60], personalThreshold: 0.5))
        #expect(!estimator.shouldPreferPersonal(lowConfidence))
        #expect(estimator.setDuration(for: exerciseA, profile: lowConfidence) == 60)
    }

    @Test("per-exercise default overrides generic default")
    func perExerciseOverride() {
        let estimator = DurationEstimator(defaults: DurationDefaults(defaultSetSeconds: 60, perExerciseSeconds: [exerciseA: 45]))
        #expect(estimator.setDuration(for: exerciseA, profile: nil) == 45)
        #expect(estimator.setDuration(for: exerciseB, profile: nil) == 60)
    }

    @Test("confidence grows with sample count")
    func confidenceGrows() {
        let c1 = ExerciseDurationProfile.confidence(forSampleCount: 1)
        let c10 = ExerciseDurationProfile.confidence(forSampleCount: 10)
        let c100 = ExerciseDurationProfile.confidence(forSampleCount: 100)
        #expect(c1 < c10)
        #expect(c10 < c100)
        #expect(c100 < 1)
        #expect(ExerciseDurationProfile.confidence(forSampleCount: 0) == 0)
    }

    @Test("record updates EWMA and increments count")
    func recordEWMA() {
        let estimator = DurationEstimator()
        let first = estimator.record(observationSecondsPerSet: 60, current: nil)
        #expect(first.sampleCount == 1)
        // segunda observación: α = 1/(2+1)=0.333, avg = 0.333*90 + 0.667*60 = 70
        let second = estimator.record(observationSecondsPerSet: 90, current: first)
        #expect(second.sampleCount == 2)
        #expect(second.confidence > first.confidence)
    }

    @Test("many samples increase confidence and set recovery toward personal average")
    func convergence() {
        let estimator = DurationEstimator()
        var profile: ExerciseDurationProfile?
        for _ in 0..<20 {
            profile = estimator.record(observationSecondsPerSet: 50, current: profile)
        }
        let p = try! #require(profile)
        #expect(p.sampleCount == 20)
        #expect(abs(p.averageSeconds - 50) < 1)
        #expect(p.confidence > 0.5)
    }
}