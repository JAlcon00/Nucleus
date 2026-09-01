import Testing
import Foundation
@testable import PRDomain

@Suite("Rest timer (PR-0604)")
struct RestTimerTests {

    private func prescription(rest: ClosedRange<Int> = 90...150) throws -> SetPrescription {
        try SetPrescription(targetRepRange: 8...12, targetLoad: 100, restSeconds: rest)
    }

    @Test("working set auto-starts with prescribed rest")
    func autoStartAfterWorkingSet() throws {
        let timer = RestTimer()
        let prescription = try prescription(rest: 90...150)
        let now = Date(timeIntervalSince1970: 1000)

        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription, now: now)

        #expect(state.isActive)
        #expect(state.recommendedSeconds == 90)
        #expect(state.endDate?.timeIntervalSince1970 == 1090)
        #expect(state.startedAt == now)
    }

    @Test("warmup set does not auto-start rest")
    func noRestAfterWarmup() throws {
        let timer = RestTimer()
        let prescription = try prescription()
        let now = Date(timeIntervalSince1970: 1000)

        let state = timer.autoStart(afterCompletedWarmup: true, prescription: prescription, now: now)

        #expect(!state.isActive)
        #expect(state.endDate == nil)
        #expect(state.recommendedSeconds == 90)
    }

    @Test("remaining is wall-clock anchored and survives background")
    func remainingWallClock() throws {
        let timer = RestTimer()
        let prescription = try prescription(rest: 120...180)
        let started = Date(timeIntervalSince1970: 1000)
        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription, now: started)

        // Relaunch "later": el resto se computa contra Date(), no respecto a ticks
        // en memoria, por lo que sobrevive background/relaunch.
        let remaining = state.remaining(at: Date(timeIntervalSince1970: 1060))
        #expect(remaining == 60)
    }

    @Test("elapsed flag flips once endDate passes")
    func elapsedFlag() throws {
        let timer = RestTimer()
        let prescription = try prescription(rest: 60...90)
        let started = Date(timeIntervalSince1970: 1000)
        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription, now: started)

        #expect(!state.hasElapsed(at: Date(timeIntervalSince1970: 1059)))
        #expect(state.hasElapsed(at: Date(timeIntervalSince1970: 1060)))
    }

    @Test("skip cancels the rest")
    func skipCancels() throws {
        let timer = RestTimer()
        let prescription = try prescription()
        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription)

        let skipped = timer.skip(state)
        #expect(!skipped.isActive)
        #expect(skipped.endDate == nil)
        #expect(skipped.recommendedSeconds == state.recommendedSeconds)
    }

    @Test("extend prolongs endDate only while active")
    func extendWhileActive() throws {
        let timer = RestTimer()
        let prescription = try prescription(rest: 90...150)
        let now = Date(timeIntervalSince1970: 1000)
        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription, now: now)

        let extended = timer.extend(state, by: 30, now: now)
        #expect(extended.endDate?.timeIntervalSince1970 == 1120)

        // Idle timer cannot be extended (no-op).
        let idle = RestTimerState(recommendedSeconds: 90)
        #expect(timer.extend(idle, by: 30, now: now) == idle)
    }

    @Test("extend ignores non-positive durations")
    func extendIgnoresNonPositive() throws {
        let timer = RestTimer()
        let prescription = try prescription()
        let state = timer.autoStart(afterCompletedWarmup: false, prescription: prescription)

        let unchanged = timer.extend(state, by: 0, now: Date(timeIntervalSince1970: 1000))
        #expect(unchanged.endDate == state.endDate)
    }

    @Test("inactive timer reports zero remaining")
    func inactiveReportsZero() {
        let idle = RestTimerState(recommendedSeconds: 90)
        #expect(idle.remaining() == 0)
    }
}