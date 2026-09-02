import Testing
import Foundation
@testable import PRDomain

@Suite("Today screen driver (PR-0601)")
struct TodayScreenTests {

    private func prescription(warmup: Bool = false) -> SetPrescription {
        try! SetPrescription(
            targetRepRange: 8...12,
            restSeconds: 60...90,
            isWarmup: warmup
        )
    }

    private func template(title: String = "Upper", workSets: Int = 3, warmups: Int = 1) -> SessionTemplate {
        var planned: [PlannedSet] = []
        planned += (0..<warmups).map { _ in PlannedSet(exerciseID: ExerciseID(), prescription: prescription(warmup: true)) }
        planned += (0..<workSets).map { _ in PlannedSet(exerciseID: ExerciseID(), prescription: prescription()) }
        return SessionTemplate(title: title, plannedSets: planned)
    }

    private func session(lifecycle: WorkoutLifecycleState) -> WorkoutSessionRecord {
        WorkoutSessionRecord(lifecycle: lifecycle)
    }

    private let driver = TodayScreenDriver()

    // MARK: - Ready to start

    @Test("rest day when no template for today")
    func restDayWithoutTemplate() {
        let state = driver.derive(todayTemplate: nil, activeSession: nil)
        #expect(state == .restDay)
    }

    @Test("readyToStart shows session, counts and duration when a template exists and none active")
    func readyToStartShowsSession() {
        let day = template(title: "Upper", workSets: 3, warmups: 2)
        let state = driver.derive(todayTemplate: day, activeSession: nil, estimatedMinutes: 45)
        guard case .readyToStart(let presentation) = state else {
            Issue.record("se esperaba readyToStart")
            return
        }
        #expect(presentation.title == "Upper")
        #expect(presentation.workSetCount == 3)
        #expect(presentation.warmupSetCount == 2)
        #expect(presentation.estimatedMinutes == 45)
        #expect(presentation.templateID == day.id)
    }

    @Test("duration is not invented: nil when not provided")
    func durationOptional() {
        let day = template()
        let state = driver.derive(todayTemplate: day, activeSession: nil)
        guard case .readyToStart(let presentation) = state else { return }
        #expect(presentation.estimatedMinutes == nil)
    }

    @Test("empty planned template counts as rest day (no invented session)")
    func emptyTemplateIsRestDay() {
        let empty = SessionTemplate(title: "Empty", plannedSets: [])
        let state = driver.derive(todayTemplate: empty, activeSession: nil)
        #expect(state == .restDay)
    }

    // MARK: - Active workout

    @Test("active workout surfaces over ready-to-start (never starts over an active one)")
    func activeWorkoutWins() {
        let day = template(title: "Upper")
        let active = session(lifecycle: .active)
        let state = driver.derive(todayTemplate: day, activeSession: active, estimatedMinutes: 45)
        guard case .activeWorkout(let presentation, let isPaused) = state else {
            Issue.record("se esperaba activeWorkout")
            return
        }
        #expect(isPaused == false)
        #expect(presentation.title == "Upper")
    }

    @Test("paused workout is surfaced as paused")
    func pausedWorkoutSurfaced() {
        let day = template(title: "Upper")
        let paused = session(lifecycle: .paused)
        let state = driver.derive(todayTemplate: day, activeSession: paused)
        guard case .activeWorkout(_, let isPaused) = state else {
            Issue.record("se esperaba activeWorkout")
            return
        }
        #expect(isPaused == true)
    }

    @Test("active workout still surfaces even if today has no template (restore path)")
    func activeWorkoutWithoutTodayTemplate() {
        let active = session(lifecycle: .active)
        let state = driver.derive(todayTemplate: nil, activeSession: active)
        guard case .activeWorkout = state else {
            Issue.record("el workout activo debe primar sobre restDay")
            return
        }
    }

    @Test("completed/abandoned sessions do not count as active workout")
    func terminalSessionIsNotActive() {
        let day = template(title: "Upper")
        let done = session(lifecycle: .completed)
        let state = driver.derive(todayTemplate: day, activeSession: done)
        guard case .readyToStart = state else {
            Issue.record("una sesión completada no debe quedar como activeWorkout")
            return
        }
    }

    // MARK: - Set counts

    @Test("set counts separate warmups from work sets")
    func setCountsSplit() {
        let day = template(workSets: 4, warmups: 2)
        let (work, warmup) = driver.setCounts(of: day)
        #expect(work == 4)
        #expect(warmup == 2)
    }

    @Test("set counts are zero for an empty template")
    func setCountsEmpty() {
        let empty = SessionTemplate(title: "Empty", plannedSets: [])
        let (work, warmup) = driver.setCounts(of: empty)
        #expect(work == 0)
        #expect(warmup == 0)
    }
}