//
//  SessionSetMergerTests.swift
//  PRDomainTests
//
//  SCRUM-255: unir al registro de la sesión una serie que llegó del reloj.
//

import Foundation
import Testing
import PRDomain

private func set(_ exercise: ExerciseID, weight: Double = 60, at seconds: TimeInterval) throws -> SetRecord {
    try SetRecord(
        exerciseID: exercise, performedAt: Date(timeIntervalSince1970: seconds),
        weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed
    )
}

private func merge(_ record: SetRecord, slot: Int, into session: WorkoutSessionRecord) -> (session: WorkoutSessionRecord, effect: SetEventEffect) {
    SessionSetMerger.merging(
        record, slot: SetSlot(exerciseID: record.exerciseID, slotIndex: slot),
        device: WorkoutDevice.watch, into: session
    )
}

@Suite("SCRUM-255 · Unir una serie del reloj a la sesión")
struct SessionSetMergerTests {

    @Test("Una serie nueva entra en su lugar por hora")
    func newSetByTime() throws {
        let bench = ExerciseID()
        let squat = ExerciseID()
        let later = try set(squat, at: 300)
        let session = WorkoutSessionRecord(lifecycle: .active, sets: [later])
        let earlier = try set(bench, at: 100)
        let merged = merge(earlier, slot: 1, into: session)
        #expect(merged.session.sets.map(\.id) == [earlier.id, later.id])
        #expect(merged.effect == .appliedNewlyAddedSet)
    }

    @Test("Con la misma hora conserva el orden en que estaban")
    func tieKeepsOrder() throws {
        let bench = ExerciseID()
        let first = try set(bench, at: 100)
        let second = try set(bench, at: 100)
        let session = WorkoutSessionRecord(lifecycle: .active, sets: [first])
        #expect(merge(second, slot: 2, into: session).session.sets.map(\.id) == [first.id, second.id])
    }

    @Test("Repetirla no cambia nada")
    func idempotent() throws {
        let record = try set(ExerciseID(), at: 100)
        let once = merge(record, slot: 1, into: WorkoutSessionRecord(lifecycle: .active))
        let twice = merge(record, slot: 1, into: once.session)
        #expect(twice.session == once.session)
        #expect(twice.effect == .duplicateNoOp)
    }

    @Test("En conflicto, la más reciente queda y la otra se guarda con su ranura")
    func conflictKeepsBoth() throws {
        let bench = ExerciseID()
        let phone = try set(bench, weight: 60, at: 100)
        let session = WorkoutSessionRecord(lifecycle: .active, sets: [phone])

        let newer = try set(bench, weight: 62.5, at: 200)
        let replaced = merge(newer, slot: 1, into: session)
        #expect(replaced.session.sets.map(\.id) == [newer.id])
        #expect(replaced.session.setConflicts == [SessionSetConflict(set: phone, slot: SetSlot(exerciseID: bench, slotIndex: 1))])

        let older = try set(bench, weight: 55, at: 50)
        let kept = merge(older, slot: 1, into: session)
        #expect(kept.session.sets.map(\.id) == [phone.id])
        #expect(kept.session.setConflicts?.map(\.set.id) == [older.id])
        #expect(kept.effect == .keptAsConflict)
    }

    @Test("Una serie ya en conflicto no se aplica dos veces")
    func conflictIsIdempotent() throws {
        let bench = ExerciseID()
        let phone = try set(bench, at: 100)
        let older = try set(bench, at: 50)
        let once = merge(older, slot: 1, into: WorkoutSessionRecord(lifecycle: .active, sets: [phone]))
        #expect(merge(older, slot: 1, into: once.session).session == once.session)
    }

    @Test("Las ranuras de lo hecho salen del orden dentro de cada ejercicio")
    func slotsFollowOrder() throws {
        let bench = ExerciseID()
        let squat = ExerciseID()
        let sets = [try set(bench, at: 1), try set(squat, at: 2), try set(bench, at: 3)]
        let slots = SessionSetMerger.slots(of: sets)
        #expect(slots[sets[0].id]?.slotIndex == 1)
        #expect(slots[sets[1].id]?.slotIndex == 1)
        #expect(slots[sets[2].id]?.slotIndex == 2)
    }
}
