//
//  WatchSessionScreenTests.swift
//  PRCoreTests
//
//  SCRUM-257 (PR-G006): lo que decide la pantalla del reloj. No hay target de pruebas de UI
//  para el reloj: por eso toda la lógica vive fuera de la vista, y se prueba aquí.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let start = Date(timeIntervalSince1970: 1_792_670_400)

@MainActor
private final class Rig {
    var now = start
    let link = FakeWorkoutLink()
    let session = WorkoutID()
    let exercise = ExerciseID()
    private(set) var watch: WatchSessionController!

    init() {
        watch = WatchSessionController(
            store: WatchLocalStore(store: MemoryRepositoryStore()), link: link, clock: { [unowned self] in now }
        )
    }

    func set(number: Int, weight: Double? = 60, unit: LoadUnit = .kilograms, rest: Int? = 90) -> WatchPlannedSet {
        WatchPlannedSet(
            slot: SetSlot(exerciseID: exercise, slotIndex: number), exerciseName: "Press",
            totalInExercise: 3, targetRepRange: 8...12, targetReps: 8, weight: weight,
            unit: unit, isWarmup: false, restSecondsAfter: rest, supersetPartner: nil
        )
    }

    func snapshot(
        revision: Int = 1, stage: WatchSessionStage = .active, remaining: [WatchPlannedSet]? = nil
    ) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: session, revision: revision, title: "Pecho", stage: stage, confirmedSetIDs: [],
            restEndsAt: nil, remaining: remaining ?? [set(number: 1), set(number: 2), set(number: 3, rest: nil)]
        )
    }
}

@MainActor
@Suite("SCRUM-257 · Entrenar desde el reloj")
struct WatchSessionScreenTests {

    @Test("Sin sesión dice que se empieza en el iPhone")
    func idle() {
        #expect(Rig().watch.screen == .idle)
    }

    @Test("Con peso y reps de la sugerencia, una sola acción registra la serie")
    func oneTap() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        #expect(rig.watch.draftWeight == 60)
        #expect(rig.watch.draftReps == 8)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.confirmedTaps == 1)
        #expect(rig.watch.state.done == [WatchDoneSet(slot: rig.set(number: 1).slot, weight: 60, unit: .kilograms)])
    }

    @Test("La serie guarda lo que la persona puso")
    func editedValues() async throws {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        rig.watch.draftWeight = 62.5
        rig.watch.adjustReps(by: 2)
        await rig.watch.completeCurrentSet()
        guard case .event(let event)? = rig.link.sentMessages.first, case .recorded(let set) = event.action else {
            Issue.record("Se esperaba una serie")
            return
        }
        #expect(set.weight == 62.5)
        #expect(set.reps == 10)
    }

    @Test("Sin peso no se puede completar, hasta ponerlo")
    func emptyWeightBlocksCompletion() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot(remaining: [rig.set(number: 1, weight: nil)]))
        #expect(rig.watch.draftWeight == nil)
        #expect(!rig.watch.canComplete)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.confirmedTaps == 0)
        rig.watch.draftWeight = 40
        #expect(rig.watch.canComplete)
    }

    @Test("Las reps nunca bajan de 1")
    func repsFloor() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        rig.watch.adjustReps(by: -20)
        #expect(rig.watch.draftReps == 1)
    }

    @Test("Al completar arranca el descanso, se puede saltar y termina solo")
    func rest() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        await rig.watch.completeCurrentSet()
        guard case .resting(let screen, let endsAt) = rig.watch.screen else {
            Issue.record("Se esperaba descanso")
            return
        }
        #expect(endsAt == start.addingTimeInterval(90))
        #expect(screen.set.slot.slotIndex == 2)
        #expect(screen.remaining == 2)

        rig.now = start.addingTimeInterval(91)
        guard case .active = rig.watch.screen else {
            Issue.record("El descanso ya terminó: usa hora de fin")
            return
        }

        rig.now = start
        rig.watch.skipRest()
        guard case .active = rig.watch.screen else {
            Issue.record("Se saltó el descanso")
            return
        }
    }

    @Test("Un doble toque registra una sola serie")
    func doubleTap() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        await rig.watch.completeCurrentSet()
        rig.now = start.addingTimeInterval(1)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.state.done.count == 1)
        rig.now = start.addingTimeInterval(WatchSessionController.doubleTapGuardSeconds + 1)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.state.done.count == 2)
    }

    @Test("Un estado nuevo no pisa lo que la persona está ajustando")
    func draftSurvivesNewSnapshot() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        rig.watch.draftWeight = 67.5
        rig.watch.adjustReps(by: 1)
        await rig.watch.receive(rig.snapshot(revision: 2))
        #expect(rig.watch.draftWeight == 67.5)
        #expect(rig.watch.draftReps == 9)
    }

    @Test("Al cambiar de serie se precarga la nueva, con el último peso hecho")
    func nextSetPreload() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        rig.watch.draftWeight = 67.5
        rig.watch.adjustReps(by: 3)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.draftWeight == 67.5)
        #expect(rig.watch.draftReps == 8, "Las reps vuelven a la sugerencia.")
    }

    @Test("En pausa no se puede completar")
    func pausedBlocks() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot(stage: .paused))
        guard case .paused = rig.watch.screen else {
            Issue.record("Se esperaba pausa")
            return
        }
        #expect(!rig.watch.canComplete)
    }

    @Test("Sin conexión se entrena igual, y la pantalla lo sabe")
    func offline() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        await rig.watch.phoneReachabilityChanged(false)
        #expect(!rig.watch.isPhoneReachable)
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.confirmedTaps == 1)
    }

    @Test("Hecho todo, lo dice; terminada, también")
    func endStates() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot(remaining: [rig.set(number: 1, rest: nil)]))
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.screen == .allDone)
        await rig.watch.receive(rig.snapshot(revision: 2, stage: .finished, remaining: []))
        #expect(rig.watch.screen == .finished)
    }

    @Test("El paso de la Corona depende de la unidad")
    func crownStep() async {
        let rig = Rig()
        await rig.watch.receive(rig.snapshot())
        #expect(rig.watch.weightStep == 2.5)
        await rig.watch.receive(rig.snapshot(revision: 2, remaining: [rig.set(number: 1, unit: .pounds)]))
        #expect(rig.watch.weightStep == 5)
    }
}
