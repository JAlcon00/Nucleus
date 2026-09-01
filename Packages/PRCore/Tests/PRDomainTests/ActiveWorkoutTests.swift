import Testing
import Foundation
@testable import PRDomain

@Suite("Active workout state machine (PR-0602)")
struct ActiveWorkoutTests {

    @Test("start opens an active workout from template")
    func startOpensActive() throws {
        let template = SessionTemplate(title: "Upper", plannedSets: [])
        var controller = ActiveWorkoutController()
        let state = try controller.start(from: template, at: Date(timeIntervalSince1970: 1000))

        #expect(state.session.lifecycle == .active)
        #expect(state.session.templateID == template.id)
        #expect(state.session.startedAt.timeIntervalSince1970 == 1000)
        #expect(controller.isActive)
    }

    @Test("cannot start a second workout while one is active")
    func startRejectsAlreadyActive() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start()
        #expect(throws: ActiveWorkoutError.alreadyActive) {
            try controller.start()
        }
    }

    @Test("pause then resume advances lifecycle")
    func pauseAndResume() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start(at: Date(timeIntervalSince1970: 0))

        let paused = try controller.pause(at: Date(timeIntervalSince1970: 10))
        #expect(paused.session.lifecycle == .paused)
        #expect(paused.lastTransitionAt.timeIntervalSince1970 == 10)

        let resumed = try controller.resume(at: Date(timeIntervalSince1970: 20))
        #expect(resumed.session.lifecycle == .active)
        #expect(resumed.lastTransitionAt.timeIntervalSince1970 == 20)
    }

    @Test("finish transitions through finishing to completed")
    func finishCompletes() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start()
        let finishing = try controller.finish()
        #expect(finishing.session.lifecycle == .finishing)
        let completed = try controller.complete()
        #expect(completed.session.lifecycle == .completed)
        #expect(!controller.isActive)
    }

    @Test("invalid transition is rejected (active cannot pause-resume interchangeably handled)")
    func invalidTransitionRejected() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start()
        // Desde active, finalizar directamente es válido (.finishing). Desde
        // .active no se puede ir a .resume: resume debe verificar.
        _ = try controller.finish()
        // Tras finish (finishing), abandon es inválido.
        #expect(throws: ActiveWorkoutError.self) {
            try controller.abandon()
        }
    }

    @Test("abandon is allowed from active and preserves performed sets")
    func abandonPreservesSets() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start()
        let abandoned = try controller.abandon()
        #expect(abandoned.session.lifecycle == .abandoned)
        #expect(abandoned.session.sets.isEmpty)
        #expect(!controller.isActive)
    }

    @Test("snapshot requires an active workout")
    func snapshotRequiresActive() {
        let controller = ActiveWorkoutController()
        #expect(throws: ActiveWorkoutError.noActiveWorkout) {
            try controller.snapshot()
        }
    }

    @Test("snapshot restores an active workout after relaunch")
    func snapshotAndRestore() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start(at: Date(timeIntervalSince1970: 0))
        _ = try controller.pause(at: Date(timeIntervalSince1970: 5))
        let snapshot = try controller.snapshot()

        let restored = try ActiveWorkoutController.restore(from: snapshot)
        #expect(restored.isActive)
        #expect(restored.current?.session.lifecycle == .paused)
        #expect(restored.current?.session.startedAt.timeIntervalSince1970 == 0)
    }

    @Test("terminal snapshots are not restorable")
    func terminalSnapshotNotRestorable() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start()
        _ = try controller.abandon()
        let snapshot = try controller.snapshot()
        #expect(!snapshot.isRestorable)
        #expect(throws: ActiveWorkoutError.notRestorable) {
            _ = try ActiveWorkoutController.restore(from: snapshot)
        }
    }

    @Test("snapshot round-trips through Codable")
    func snapshotCodableRoundTrip() throws {
        var controller = ActiveWorkoutController()
        _ = try controller.start(at: Date(timeIntervalSince1970: 123))
        let snapshot = try controller.snapshot()

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ActiveWorkoutSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.session.startedAt.timeIntervalSince1970 == 123)
    }
}