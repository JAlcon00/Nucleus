//
//  HealthLiveWorkoutTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del ciclo de vida de un workout live durante la sesión del Watch (PR-1202):
//  la state machine start/pause/resume/end, rechazo de transiciones inválidas, el
//  comportamiento terminal (un fallo conserva métricas y no se puede resumir), el
//  origen measured/estimated de métricas (sin doble-conteo) y el coordinador con un
//  fake builder. HealthKit real queda detrás de `LiveWorkoutBuilder`; no se importa.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Live workout lifecycle (PR-1202)")
struct HealthLiveWorkoutTests {

    private func metrics(_ kcal: Double?, origin: MeasurementOrigin? = nil) -> HealthLiveMetrics {
        HealthLiveMetrics(activeKilocalories: kcal, energyOrigin: origin)
    }

    // MARK: - State machine: arrangement

    @Test("running starts from idle and is live")
    func startsFromIdle() {
        var sm = HealthLiveWorkoutStateMachine(state: .idle)
        #expect(throws: Never.self) {
            try sm.apply(.didStart)
        }
        #expect(sm.state == .running)
        #expect(sm.state.isLive)
    }

    @Test("running cannot start again directly")
    func cannotStartTwice() {
        var sm = HealthLiveWorkoutStateMachine(state: .running)
        #expect(throws: (any Error).self) {
            try sm.apply(.didStart)
        }
    }

    @Test("pause requires running")
    func pauseRequiresRunning() {
        var idle = HealthLiveWorkoutStateMachine(state: .idle)
        #expect(throws: (any Error).self) {
            try idle.apply(.didPause)
        }

        var running = HealthLiveWorkoutStateMachine(state: .running)
        #expect(throws: Never.self) {
            try running.apply(.didPause)
        }
        #expect(running.state == .paused)
    }

    @Test("resume requires paused")
    func resumeRequiresPaused() {
        var running = HealthLiveWorkoutStateMachine(state: .running)
        #expect(throws: (any Error).self) {
            try running.apply(.didResume)
        }

        var paused = HealthLiveWorkoutStateMachine(state: .paused)
        #expect(throws: Never.self) {
            try paused.apply(.didResume)
        }
        #expect(paused.state == .running)
    }

    @Test("pause.resume.pause preserves running then paused")
    func pauseResumeCycle() {
        var sm = HealthLiveWorkoutStateMachine(state: .idle)
        try! sm.apply(.didStart)      // running
        try! sm.apply(.didPause)      // paused
        try! sm.apply(.didResume)     // running
        try! sm.apply(.didPause)      // paused
        #expect(sm.state == .paused)
        #expect(!sm.state.isLive)
    }

    // MARK: - Metrics

    @Test("metrics update is captured only while running or paused")
    func metricsCapturedWhileActive() {
        var idle = HealthLiveWorkoutStateMachine(state: .idle)
        try? idle.apply(.didUpdateMetrics(metrics(100)))
        #expect(idle.lastMetrics.activeKilocalories == nil, "idle no debe capturar métricas")

        var sm = HealthLiveWorkoutStateMachine(state: .running)
        try! sm.apply(.didUpdateMetrics(metrics(120, origin: .measured)))
        #expect(sm.lastMetrics.activeKilocalories == 120)
        #expect(sm.lastMetrics.energyOrigin == .measured)
        #expect(sm.state == .running, "una actualización de métricas no cambia de estado")
    }

    @Test("metrics without value are unavailable; never invented")
    func missingMetricsUnavailable() {
        let zero = metrics(nil)
        #expect(zero.energyOrigin == .unavailable)
        #expect(zero.activeKilocalories == nil)
    }

    // MARK: - Termination

    @Test("end transitions to ended and retains last metrics")
    func endCapturesMetrics() {
        var sm = HealthLiveWorkoutStateMachine(state: .running)
        let final = metrics(240, origin: .measured)
        try! sm.apply(.didEnd(final))
        #expect(sm.state == .ended)
        #expect(sm.lastMetrics.activeKilocalories == 240)
    }

    @Test("end is terminal: further events are rejected")
    func endIsTerminal() {
        var sm = HealthLiveWorkoutStateMachine(state: .idle)
        try! sm.apply(.didStart)
        try! sm.apply(.didEnd(metrics(100)))
        #expect(throws: (any Error).self) {
            try sm.apply(.didResume)
        }
        #expect(throws: (any Error).self) {
            try sm.apply(.didEnd(metrics(200)))
        }
        #expect(sm.state == .ended)
        #expect(sm.lastMetrics.activeKilocalories == 100)
    }

    @Test("fail is terminal and preserves partial metrics")
    func failPreservesPartialMetrics() {
        var sm = HealthLiveWorkoutStateMachine(state: .running)
        try! sm.apply(.didUpdateMetrics(metrics(150, origin: .measured)))
        try? sm.apply(.didFail(reason: "interrupted"))
        guard case .failed(let reason) = sm.state else {
            Issue.record("se esperaba .failed")
            return
        }
        #expect(reason == "interrupted")
        #expect(sm.state.isFailed)
        #expect(sm.state.isTerminal)
        #expect(sm.lastMetrics.activeKilocalories == 150)
    }

    @Test("cannot fail/end before starting")
    func cannotEndBeforeStart() {
        var sm = HealthLiveWorkoutStateMachine(state: .idle)
        #expect(throws: (any Error).self) {
            try sm.apply(.didEnd(metrics(0)))
        }
        #expect(throws: (any Error).self) {
            try sm.apply(.didFail(reason: "x"))
        }
        #expect(sm.state == .idle)
    }

    // MARK: - allGranted-style domain rules

    @Test("transitioning rejects invalid state transitions deterministically")
    func invalidTransitionThrows() {
        #expect(throws: (any Error).self) {
            try HealthLiveWorkoutState.idle.transitioning(to: .paused)
        }
        #expect(throws: (any Error).self) {
            try HealthLiveWorkoutState.running.transitioning(to: .idle)
        }
        #expect(throws: Never.self) {
            try HealthLiveWorkoutState.running.transitioning(to: .ended)
        }
    }
}

// MARK: - Coordinator (fake builder, PR-1202)

/// Fake de `LiveWorkoutBuilder` para testear el coordinador sin HealthKit real (§7).
private actor FakeLiveWorkoutBuilder: LiveWorkoutBuilder {
    var failOnStart = false
    var failOnPause = false
    var failOnResume = false
    var failOnEnd = false
    var starts = 0
    var pauses = 0
    var resumes = 0
    var ends = 0

    init(
        failOnStart: Bool = false,
        failOnPause: Bool = false,
        failOnResume: Bool = false,
        failOnEnd: Bool = false
    ) {
        self.failOnStart = failOnStart
        self.failOnPause = failOnPause
        self.failOnResume = failOnResume
        self.failOnEnd = failOnEnd
    }

    func start() async throws {
        if failOnStart { throw NSError(domain: "HealthKit", code: 1, userInfo: nil) }
        starts += 1
    }
    func pause() async throws {
        if failOnPause { throw NSError(domain: "HealthKit", code: 1, userInfo: nil) }
        pauses += 1
    }
    func resume() async throws {
        if failOnResume { throw NSError(domain: "HealthKit", code: 1, userInfo: nil) }
        resumes += 1
    }
    func end() async throws -> HealthLiveMetrics {
        if failOnEnd { throw NSError(domain: "HealthKit", code: 1, userInfo: nil) }
        ends += 1
        return HealthLiveMetrics(activeKilocalories: 300, energyOrigin: .measured)
    }
}

@Suite("Live workout coordinator with fake builder (PR-1202)")
struct HealthLiveWorkoutCoordinatorTests {

    @Test("start runs builder and transitions to running")
    func startRuns() async throws {
        let fake = FakeLiveWorkoutBuilder()
        let coordinator = HealthLiveWorkoutCoordinator(builder: fake)
        let next = try await coordinator.start(stateMachine: HealthLiveWorkoutStateMachine())
        #expect(next.state == .running)
    }

    @Test("full cycle start.pause.resume.end yields ended with final metrics")
    func fullCycle() async throws {
        let fake = FakeLiveWorkoutBuilder()
        let coordinator = HealthLiveWorkoutCoordinator(builder: fake)
        var sm = HealthLiveWorkoutStateMachine()
        sm = try await coordinator.start(stateMachine: sm)
        sm = try await coordinator.pause(stateMachine: sm)
        sm = try await coordinator.resume(stateMachine: sm)
        let (metrics, ended) = try await coordinator.end(stateMachine: sm)
        #expect(metrics.activeKilocalories == 300)
        #expect(ended.state == .ended)
    }

    @Test("start failure throws infrastructure and does not end up running")
    func startFailure() async throws {
        let fake = FakeLiveWorkoutBuilder(failOnStart: true)
        let coordinator = HealthLiveWorkoutCoordinator(builder: fake)
        await #expect(throws: HealthLiveWorkoutError.self) {
            _ = try await coordinator.start(stateMachine: HealthLiveWorkoutStateMachine())
        }
    }

    @Test("end failure throws infrastructure (local sets already persisted by app)")
    func endFailure() async throws {
        let fake = FakeLiveWorkoutBuilder(failOnEnd: true)
        let coordinator = HealthLiveWorkoutCoordinator(builder: fake)
        var sm = HealthLiveWorkoutStateMachine(state: .running)
        await #expect(throws: HealthLiveWorkoutError.self) {
            _ = try await coordinator.end(stateMachine: sm)
        }
    }

    @Test("starting a non-idle machine is rejected")
    func nonIdleStartRejected() async throws {
        let fake = FakeLiveWorkoutBuilder()
        let coordinator = HealthLiveWorkoutCoordinator(builder: fake)
        var sm = HealthLiveWorkoutStateMachine(state: .paused)
        await #expect(throws: HealthLiveWorkoutError.self) {
            _ = try await coordinator.start(stateMachine: sm)
        }
    }
}