//
//  WatchSessionSnapshotTests.swift
//  PRDomainTests
//
//  SCRUM-253 (PR-G002): el reloj muestra lo mismo que el iPhone, también lo que cambió a
//  mitad de sesión, y puede seguir solo sin conexión.
//

import Foundation
import Testing
import PRDomain

private func prescription(
    load: Double? = nil, rest: Int = 90, warmup: Bool = false
) throws -> SetPrescription {
    try SetPrescription(
        targetRepRange: 8...12, targetLoad: load, loadUnit: .kilograms, restSeconds: rest...rest, isWarmup: warmup
    )
}

private struct Fixture {
    let bench = ExerciseID()
    let row = ExerciseID()
    let curl = ExerciseID()
    let sessionID = WorkoutID()
    let template: SessionTemplate

    init(supersetBenchRow: Bool = false) throws {
        let work = try prescription()
        var planned: [PlannedSet] = []
        for exercise in [bench, bench, row, row, curl] {
            planned.append(PlannedSet(exerciseID: exercise, prescription: work))
        }
        template = SessionTemplate(
            title: "Torso", plannedSets: planned,
            supersets: supersetBenchRow ? SupersetPair(first: bench, second: row).map { [$0] } : nil
        )
    }

    var names: @Sendable (ExerciseID) -> String {
        let (bench, row) = (self.bench, self.row)
        return { $0 == bench ? "Press" : ($0 == row ? "Remo" : "Curl") }
    }

    func snapshot(
        sets: [SetRecord] = [],
        queue: ExerciseQueueState? = nil,
        lifecycle: WorkoutLifecycleState = .active,
        template custom: SessionTemplate? = nil,
        draft: (@Sendable (PlannedSet) -> SetCompletionDraft)? = nil
    ) -> WatchSessionSnapshot {
        var session = WorkoutSessionRecord(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_000), lifecycle: lifecycle, sets: sets)
        session.queue = queue
        return WatchSessionSnapshotBuilder.snapshot(WatchSessionSnapshotInput(
            session: session, template: custom ?? template, revision: 7, exerciseName: names,
            draft: draft ?? { SetCompleter().preload(for: $0) }
        ))
    }
}

private func done(_ exercise: ExerciseID, weight: Double = 60) throws -> SetRecord {
    try SetRecord(exerciseID: exercise, weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed)
}

@Suite("SCRUM-253 · Qué le dice el iPhone al reloj")
struct WatchSessionSnapshotTests {

    @Test("Trae lo que el reloj necesita para mostrar la serie")
    func carriesEverything() throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot(sets: [try done(fixture.bench)])
        #expect(snapshot.revision == 7)
        #expect(snapshot.title == "Torso")
        #expect(snapshot.stage == .active)
        #expect(snapshot.confirmedSetIDs.count == 1)
        #expect(snapshot.totalSets == 5)
        let first = try #require(snapshot.remaining.first)
        #expect(first.exerciseName == "Press")
        #expect(first.slot == SetSlot(exerciseID: fixture.bench, slotIndex: 2))
        #expect(first.totalInExercise == 2)
        #expect(first.targetRepRange == 8...12)
        #expect(first.targetReps == 8)
        #expect(first.restSecondsAfter == 90)
        #expect(!first.isWarmup)
    }

    @Test("Un ejercicio saltado no aparece y uno diferido va al final, igual que en el iPhone")
    func followsTheQueue() throws {
        let fixture = try Fixture()
        let queue = ExerciseQueueState(deferred: [fixture.bench], skipped: [fixture.curl])
        let order = fixture.snapshot(queue: queue).remaining.map(\.slot.exerciseID)
        #expect(order == [fixture.row, fixture.row, fixture.bench, fixture.bench])
    }

    @Test("Cada serie coincide con la que el iPhone va a pedir después")
    func matchesPhoneOrderStepByStep() throws {
        let fixture = try Fixture(supersetBenchRow: true)
        let queue = ExerciseQueueState(deferred: [fixture.curl])
        var sets: [SetRecord] = []
        let snapshot = fixture.snapshot(queue: queue)
        for step in snapshot.remaining {
            let index = try #require(WorkoutQueue.nextPlannedIndex(template: fixture.template, sets: sets, state: queue))
            #expect(fixture.template.plannedSets[index].exerciseID == step.slot.exerciseID)
            sets.append(try done(step.slot.exerciseID))
        }
        #expect(WorkoutQueue.nextPlannedIndex(template: fixture.template, sets: sets, state: queue) == nil)
    }

    @Test("Una sustitución muestra el ejercicio nuevo con sus series pendientes")
    func followsSubstitution() throws {
        let fixture = try Fixture()
        let replacement = ExerciseID()
        let sets = [try done(fixture.bench)]
        let adapted = WorkoutQueue.substituting(fixture.bench, with: replacement, in: fixture.template, sets: sets)
        let queue = WorkoutQueue.replacing(fixture.bench, with: replacement, in: .empty, template: adapted)
        let remaining = fixture.snapshot(sets: sets, queue: queue, template: adapted).remaining
        #expect(remaining.first?.slot.exerciseID == replacement)
        #expect(!remaining.contains { $0.slot.exerciseID == fixture.bench })
        #expect(remaining.count == 4)
    }

    @Test("En superset alterna y no descansa a mitad de la ronda")
    func supersetAlternates() throws {
        let fixture = try Fixture(supersetBenchRow: true)
        let remaining = fixture.snapshot().remaining
        #expect(remaining.prefix(4).map(\.slot.exerciseID) == [fixture.bench, fixture.row, fixture.bench, fixture.row])
        #expect(remaining[0].restSecondsAfter == nil, "A → B sin descanso.")
        #expect(remaining[1].restSecondsAfter == 90, "El descanso va después de la ronda.")
        #expect(remaining[0].supersetPartner == "Remo")
        #expect(remaining[4].supersetPartner == nil)
    }

    @Test("La última serie no tiene descanso, y un calentamiento tampoco")
    func noRestWhenItDoesNotApply() throws {
        let fixture = try Fixture()
        #expect(fixture.snapshot().remaining.last?.restSecondsAfter == nil)
        let warmup = PlannedSet(exerciseID: fixture.bench, prescription: try prescription(warmup: true))
        let work = PlannedSet(exerciseID: fixture.bench, prescription: try prescription())
        let template = SessionTemplate(title: "Press", plannedSets: [warmup, work])
        let first = try #require(fixture.snapshot(template: template).remaining.first)
        #expect(first.isWarmup)
        #expect(first.restSecondsAfter == nil)
    }

    @Test("Sin historial la precarga queda vacía, nunca 0")
    func emptyPreloadIsNil() throws {
        let fixture = try Fixture()
        #expect(fixture.snapshot().remaining.allSatisfy { $0.weight == nil })
    }

    @Test("La precarga es la misma que usa el iPhone")
    func preloadMatchesPhone() throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot(draft: { SetCompleter().preload(for: $0, lastPerformedWeight: 62.5) })
        #expect(snapshot.remaining.allSatisfy { $0.weight == 62.5 })
    }

    @Test("Sin conexión la siguiente serie usa el peso de la anterior de ese ejercicio")
    func offlineCarriesPreviousWeight() throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot()
        let first = try #require(snapshot.remaining.first)
        let doneSet = WatchDoneSet(slot: first.slot, weight: 70, unit: .kilograms)
        let next = try #require(WatchSessionCursor.current(in: snapshot, done: [doneSet]))
        #expect(next.slot == SetSlot(exerciseID: fixture.bench, slotIndex: 2))
        #expect(next.weight == 70)
        #expect(WatchSessionCursor.remainingCount(in: snapshot, done: [doneSet]) == 4)
    }

    @Test("Con otra unidad no se copia el peso, y al cambiar de ejercicio tampoco")
    func doesNotCarryAcrossUnitsOrExercises() throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot()
        let pounds = WatchDoneSet(slot: SetSlot(exerciseID: fixture.bench, slotIndex: 1), weight: 150, unit: .pounds)
        #expect(WatchSessionCursor.current(in: snapshot, done: [pounds])?.weight == nil)
        let doneBench = [1, 2].map {
            WatchDoneSet(slot: SetSlot(exerciseID: fixture.bench, slotIndex: $0), weight: 70, unit: .kilograms)
        }
        let next = WatchSessionCursor.current(in: snapshot, done: doneBench)
        #expect(next?.slot.exerciseID == fixture.row)
        #expect(next?.weight == nil)
    }

    @Test("Un estado nuevo que ya trae una serie hecha en el reloj no la repite")
    func newSnapshotWithLocalSet() throws {
        let fixture = try Fixture()
        let doneSet = WatchDoneSet(slot: SetSlot(exerciseID: fixture.bench, slotIndex: 1), weight: 60, unit: .kilograms)
        let newer = fixture.snapshot(sets: [try done(fixture.bench)])
        #expect(WatchSessionCursor.current(in: newer, done: [doneSet])?.slot.slotIndex == 2)
    }

    @Test("No lleva restricciones, dolor ni datos de Salud")
    func carriesNoSensitiveData() throws {
        let fixture = try Fixture()
        var set = try done(fixture.bench)
        set.painFeedback = PainFeedback(level: .high, muscleGroup: nil)
        let data = try WatchWireCodec.encode(fixture.snapshot(sets: [set]))
        let text = try #require(String(data: data, encoding: .utf8)).lowercased()
        for word in ["pain", "restriction", "energy", "heart", "health"] {
            #expect(!text.contains(word), "No debe viajar \(word)")
        }
    }

    @Test("La sesión más grande cabe en el transporte con margen")
    func biggestSessionFits() throws {
        let work = try prescription()
        let exercises = (0..<12).map { _ in ExerciseID() }
        let planned = exercises.flatMap { exercise in (0..<5).map { _ in PlannedSet(exerciseID: exercise, prescription: work) } }
        let fixture = try Fixture()
        let snapshot = fixture.snapshot(template: SessionTemplate(title: "Sesión más larga", plannedSets: planned))
        let bytes = try WatchWireCodec.encode(snapshot).count
        print("SCRUM-253 medición: \(snapshot.remaining.count) series = \(bytes) bytes")
        #expect(bytes < WatchSessionSnapshot.transportBudgetBytes)
    }

    @Test("Dos estados iguales son idénticos en bytes")
    func equalStatesSameBytes() throws {
        let fixture = try Fixture()
        let first = fixture.snapshot()
        let second = fixture.snapshot()
        #expect(try WatchWireCodec.encode(first) == WatchWireCodec.encode(second))
        #expect(first.hasSameContent(as: second))
        let read = try WatchWireCodec.decode(WatchSessionSnapshot.self, from: WatchWireCodec.encode(first))
        #expect(read == first)
    }

    @Test("Sesión terminada: no queda nada y lo dice", arguments: [WorkoutLifecycleState.completed, .abandoned])
    func finishedSession(lifecycle: WorkoutLifecycleState) throws {
        let fixture = try Fixture()
        let snapshot = fixture.snapshot(sets: [try done(fixture.bench)], lifecycle: lifecycle)
        #expect(snapshot.stage == .finished)
        #expect(snapshot.remaining.isEmpty)
        #expect(snapshot.confirmedSetIDs.count == 1)
    }

    @Test("Plantilla vacía o todas las series hechas: no queda nada")
    func nothingLeft() throws {
        let fixture = try Fixture()
        #expect(fixture.snapshot(template: SessionTemplate(title: "Vacía", plannedSets: [])).remaining.isEmpty)
        let sets = try fixture.template.plannedSets.map { try done($0.exerciseID) }
        #expect(fixture.snapshot(sets: sets).remaining.isEmpty)
    }

    @Test("Las series en conflicto cuentan como confirmadas: el reloj las puede soltar")
    func conflictsAreConfirmed() throws {
        let fixture = try Fixture()
        let conflict = try done(fixture.bench, weight: 70)
        var session = WorkoutSessionRecord(lifecycle: .active)
        session.setConflicts = [SessionSetConflict(set: conflict, slot: SetSlot(exerciseID: fixture.bench, slotIndex: 1))]
        let snapshot = WatchSessionSnapshotBuilder.snapshot(WatchSessionSnapshotInput(
            session: session, template: fixture.template, revision: 1,
            exerciseName: fixture.names, draft: { SetCompleter().preload(for: $0) }
        ))
        #expect(snapshot.confirmedSetIDs == [conflict.id])
    }
}
