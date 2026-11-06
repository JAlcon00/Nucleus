//
//  WorkoutSyncConvergenceTests.swift
//  PRDomainTests
//
//  SCRUM-254 (PR-G003): WatchConnectivity entrega de uno en uno y en cualquier orden. Al
//  reconectar tienen que estar todas las series: ni una de más ni una de menos, y una serie
//  ya confirmada nunca se descarta (DG-3, RNF-004).
//

import Foundation
import Testing
import PRDomain

private let engine = WorkoutSyncEngine()

private func record(
    _ exercise: ExerciseID,
    weight: Double = 60,
    at seconds: TimeInterval,
    id: SetRecordID = SetRecordID()
) throws -> SetRecord {
    try SetRecord(
        id: id, exerciseID: exercise, performedAt: Date(timeIntervalSince1970: seconds),
        weight: weight, unit: .kilograms, reps: 10, lifecycle: .completed
    )
}

private func recorded(
    _ set: SetRecord,
    device: WorkoutDeviceKey = WorkoutDevice.watch,
    slot: Int? = nil,
    session: WorkoutID? = nil
) -> SetEvent {
    SetEvent(
        device: device,
        emittedAt: set.performedAt,
        slot: slot.map { SetSlot(exerciseID: set.exerciseID, slotIndex: $0) },
        action: .recorded(set),
        sessionID: session
    )
}

private func revoked(_ id: SetRecordID, at seconds: TimeInterval) -> SetEvent {
    SetEvent(device: WorkoutDevice.watch, emittedAt: Date(timeIntervalSince1970: seconds), action: .revoked(id))
}

/// Aplica de uno en uno, como llega por WatchConnectivity.
private func oneByOne(_ events: [SetEvent], to ledger: WorkoutSyncLedger = .empty) -> WorkoutSyncLedger {
    events.reduce(ledger) { engine.applySingle($1, to: $0).ledger }
}

/// Barajado reproducible (generador lineal): cada semilla da siempre el mismo orden.
private func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
    var state = seed
    var result = items
    for index in result.indices.reversed() where index > 0 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        result.swapAt(index, Int(state >> 33) % (index + 1))
    }
    return result
}

@Suite("SCRUM-254 · Sincronización que converge y no pierde series")
struct WorkoutSyncConvergenceTests {

    @Test("Una revocación que llega antes que su serie la deja revocada")
    func revokeBeforeRecord() throws {
        let set = try record(ExerciseID(), at: 100)
        let ledger = oneByOne([revoked(set.id, at: 200), recorded(set, slot: 1)])
        #expect(ledger.canonicalSets.isEmpty)
        #expect(ledger.conflictingSets.isEmpty)
    }

    @Test("Cualquier orden de llegada, de uno en uno, da exactamente lo mismo")
    func anyArrivalOrderConverges() throws {
        let bench = ExerciseID()
        let squat = ExerciseID()
        let first = try record(bench, weight: 60, at: 100)
        let conflict = try record(bench, weight: 62.5, at: 105)
        let other = try record(squat, weight: 100, at: 200)
        let revokedSet = try record(squat, weight: 90, at: 150)
        let events = [
            recorded(first, device: WorkoutDevice.phone, slot: 1),
            recorded(conflict, slot: 1),
            recorded(other, slot: 2),
            recorded(revokedSet, slot: 1),
            revoked(revokedSet.id, at: 300),
        ]
        let expected = oneByOne(events)
        #expect(expected.canonicalSets.map(\.id) == [conflict.id, other.id])
        #expect(expected.conflictingSets.map(\.id) == [first.id])
        for seed in UInt64(1)...40 {
            #expect(oneByOne(shuffled(events, seed: seed)) == expected)
        }
    }

    @Test("Un evento repetido no cambia nada")
    func repeatedEventChangesNothing() throws {
        let event = recorded(try record(ExerciseID(), at: 100), slot: 1)
        let once = oneByOne([event])
        let replay = engine.applySingle(event, to: once)
        #expect(replay.effect == .duplicateNoOp)
        #expect(replay.ledger == once)
    }

    @Test("La misma serie desde los dos dispositivos cuenta una vez")
    func sameSetFromBothDevices() throws {
        let set = try record(ExerciseID(), at: 100)
        let ledger = oneByOne([recorded(set, device: WorkoutDevice.phone, slot: 1), recorded(set, slot: 1)])
        #expect(ledger.canonicalSets.map(\.id) == [set.id])
        #expect(ledger.conflictingSets.isEmpty)
    }

    @Test("Dos series distintas en la misma ranura: una canónica y la otra guardada aparte")
    func conflictKeepsBothSets() throws {
        let bench = ExerciseID()
        let older = try record(bench, weight: 60, at: 100)
        let newer = try record(bench, weight: 62.5, at: 105)
        let ledger = oneByOne([recorded(newer, slot: 1), recorded(older, device: WorkoutDevice.phone, slot: 1)])
        #expect(ledger.canonicalSets.map(\.id) == [newer.id])
        #expect(ledger.conflictingSets.map(\.id) == [older.id], "Una serie confirmada nunca se pierde.")
        #expect(engine.applySingle(recorded(try record(bench, at: 90), slot: 1), to: ledger).effect == .keptAsConflict)
    }

    @Test("Al revocar la ganadora de un conflicto, vuelve la otra")
    func revokingWinnerPromotesConflict() throws {
        let bench = ExerciseID()
        let older = try record(bench, weight: 60, at: 100)
        let newer = try record(bench, weight: 62.5, at: 105)
        let ledger = oneByOne([recorded(older, slot: 1), recorded(newer, slot: 1), revoked(newer.id, at: 200)])
        #expect(ledger.canonicalSets.map(\.id) == [older.id])
        #expect(ledger.conflictingSets.isEmpty)
    }

    @Test("El registro se guarda y se lee idéntico")
    func ledgerIsCodable() throws {
        let bench = ExerciseID()
        let older = try record(bench, at: 100)
        let newer = try record(bench, at: 105)
        let gone = try record(bench, at: 110)
        let ledger = oneByOne([recorded(older, slot: 1), recorded(newer, slot: 1), recorded(gone, slot: 2), revoked(gone.id, at: 200)])
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(WorkoutSyncLedger.self, from: data) == ledger)
    }

    @Test("Con relojes 2 minutos desfasados el resultado sigue siendo el mismo")
    func clockSkewStaysDeterministic() throws {
        let bench = ExerciseID()
        let phone = try record(bench, weight: 60, at: 1_000)
        let watch = try record(bench, weight: 62.5, at: 1_000 - 120)
        let events = [recorded(phone, device: WorkoutDevice.phone, slot: 1), recorded(watch, slot: 1)]
        let forward = oneByOne(events)
        #expect(forward == oneByOne(events.reversed()))
        #expect(forward.canonicalSets.count + forward.conflictingSets.count == 2)
    }

    @Test("`view(for:)` incluye las ranuras vacías")
    func viewIncludesEmptySlots() throws {
        let bench = ExerciseID()
        let prescription = try SetPrescription(targetRepRange: 8...10, restSeconds: 60...60)
        let template = SessionTemplate(title: "Pecho", plannedSets: [
            PlannedSet(exerciseID: bench, prescription: prescription),
            PlannedSet(exerciseID: bench, prescription: prescription),
        ])
        let done = try record(bench, at: 100)
        let view = engine.view(for: template, ledger: oneByOne([recorded(done, slot: 1)]))
        #expect(view.count == 2)
        #expect(view[SetSlot(exerciseID: bench, slotIndex: 1)]??.id == done.id)
        let empty = view[SetSlot(exerciseID: bench, slotIndex: 2)]
        #expect(empty != nil, "La ranura existe.")
        #expect(empty == .some(.none), "Y sigue vacía.")
    }

    @Test("Revocar lo que no existe deja la marca y no falla")
    func revokingUnknownIsSafe() {
        let id = SetRecordID()
        let result = engine.applySingle(revoked(id, at: 100), to: .empty)
        #expect(result.effect == .duplicateNoOp)
        #expect(result.ledger.canonicalSets.isEmpty)
        #expect(result.ledger.revokedSetIDs == [id])
    }

    @Test("200 eventos convergen y conservan todo")
    func manyEvents() throws {
        let exercises = (0..<10).map { _ in ExerciseID() }
        var events: [SetEvent] = []
        for (position, exercise) in exercises.enumerated() {
            for slot in 1...20 {
                let at = TimeInterval(position * 100 + slot)
                events.append(recorded(try record(exercise, at: at), slot: slot))
            }
        }
        let ledger = oneByOne(shuffled(events, seed: 7))
        #expect(ledger.canonicalSets.count == 200)
        #expect(ledger == oneByOne(events))
    }

    @Test("Un evento de otra sesión se rechaza")
    func otherSessionIsRejected() throws {
        let session = WorkoutID()
        let ledger = WorkoutSyncLedger(sessionID: session)
        let result = engine.applySingle(recorded(try record(ExerciseID(), at: 100), slot: 1, session: WorkoutID()), to: ledger)
        #expect(result.effect == .rejectedOtherSession)
        #expect(result.ledger == ledger)
        let own = engine.applySingle(recorded(try record(ExerciseID(), at: 100), slot: 1, session: session), to: ledger)
        #expect(own.ledger.canonicalSets.count == 1)
    }
}
