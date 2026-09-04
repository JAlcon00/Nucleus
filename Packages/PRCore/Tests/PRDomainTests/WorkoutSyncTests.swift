//
//  WorkoutSyncTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de la coordinación multidevice del workout (PR-1203, RNF-014):
//  - idempotencia de comandos (reintentar nunca duplica sets);
//  - conflicto sobre el mismo set lógico NO duplica (supersede por newest);
//  - convergencia al Mismo workout lógico aunque los eventos lleguen desordenados;
//  - tolerancia a desconexión (offline-first: un device continúa y luego converge).
//

import Foundation
import Testing
import PRDomain

@Suite("Multidevice workout coordination (PR-1203)")
struct WorkoutSyncTests {

    private let engine = WorkoutSyncEngine()

    private func record(
        exercise: ExerciseID,
        weight: Double = 60,
        reps: Int = 10,
        at date: Date,
        id: SetRecordID? = nil
    ) throws -> SetRecord {
        try SetRecord(
            id: id ?? SetRecordID(),
            exerciseID: exercise,
            performedAt: date,
            weight: weight,
            unit: .kilograms,
            reps: reps,
            lifecycle: .completed
        )
    }

    // MARK: - AC: comandos idempotentes

    @Test("Re-enviar el mismo evento de set es un no-op (no duplica)")
    func idempotentReplayDoesNotDuplicate() throws {
        let bench = ExerciseID()
        let base = Date(timeIntervalSince1970: 1000)
        let event = SetEvent(
            device: WorkoutDevice.phone,
            emittedAt: base,
            slot: SetSlot(exerciseID: bench, slotIndex: 1),
            action: .recorded(try record(exercise: bench, at: base))
        )

        let first = engine.apply(events: [event], to: .empty)
        let replay = engine.applySingle(event, to: first)

        #expect(first.canonicalSets.count == 1)
        #expect(replay.effect == .duplicateNoOp)
        #expect(replay.ledger.canonicalSets.count == 1, "El re-envío NO debe duplicar el set.")
    }

    @Test("Revocar dos veces el mismo set es un no-op")
    func revokeTwiceIsNoOp() throws {
        let squat = ExerciseID()
        let base = Date(timeIntervalSince1970: 2000)
        let setID = SetRecordID()
        let recordEvent = SetEvent(
            device: WorkoutDevice.watch,
            emittedAt: base,
            slot: SetSlot(exerciseID: squat, slotIndex: 1),
            action: .recorded(try record(exercise: squat, at: base, id: setID))
        )
        let revokeEvent = SetEvent(
            device: WorkoutDevice.watch,
            emittedAt: base.addingTimeInterval(1),
            action: .revoked(setID)
        )

        let withSet = engine.apply(events: [recordEvent])
        let revoked = engine.apply(events: [revokeEvent], to: withSet)
        let revokeAgain = engine.applySingle(revokeEvent, to: revoked)

        #expect(withSet.canonicalSets.count == 1)
        #expect(revoked.canonicalSets.isEmpty)
        #expect(revokeAgain.effect == .duplicateNoOp)
        #expect(revokeAgain.ledger.revision == revoked.revision)
    }

    // MARK: - AC: conflicto no duplica sets

    @Test("Dos devices graban el mismo set lógico -> queda exactamente uno (supersede por newest)")
    func conflictOverSameSlotKeepsOneSet() throws {
        let bench = ExerciseID()
        let slot = SetSlot(exerciseID: bench, slotIndex: 1)
        let older = Date(timeIntervalSince1970: 3000)
        let newer = Date(timeIntervalSince1970: 3000 + 5)

        let phone = SetEvent(
            device: WorkoutDevice.phone,
            emittedAt: older,
            slot: slot,
            action: .recorded(try record(exercise: bench, weight: 60, at: older))
        )
        let watch = SetEvent(
            device: WorkoutDevice.watch,
            emittedAt: newer,
            slot: slot,
            action: .recorded(try record(exercise: bench, weight: 62.5, at: newer))
        )

        let merged = engine.apply(events: [phone, watch])

        #expect(merged.canonicalSets.count == 1, "El conflicto NO debe duplicar el set.")
        #expect(merged.canonicalSets.first?.weight == 62.5, "Gana el set más reciente.")
    }

    @Test("Racha con empalme por device en el mismo instante queda determinista")
    func tieBreakIsDeterministic() throws {
        let squat = ExerciseID()
        let slot = SetSlot(exerciseID: squat, slotIndex: 1)
        let same = Date(timeIntervalSince1970: 4000)

        // phone.rawValue < watch.rawValue ("phone" < "watch").
        let phone = SetEvent(
            device: WorkoutDevice.phone,
            emittedAt: same,
            slot: slot,
            action: .recorded(try record(exercise: squat, weight: 80, at: same))
        )
        let watch = SetEvent(
            device: WorkoutDevice.watch,
            emittedAt: same,
            slot: slot,
            action: .recorded(try record(exercise: squat, weight: 85, at: same))
        )

        let a = engine.apply(events: [phone, watch])
        let b = engine.apply(events: [watch, phone])

        #expect(a.canonicalSets.count == 1)
        #expect(b.canonicalSets.count == 1)
        #expect(a == b, "El desempate debe converger al mismo estado en cualquier orden.")
        #expect(a.canonicalSets.first?.weight == 85, "watch (mayor) gana el empate.")
    }

    // MARK: - AC: mismo workout lógico (convergencia)

    @Test("Órdenes de llegada distintos convergen al mismo workout lógico")
    func conflictingArrivalOrdersConverge() throws {
        let bench = ExerciseID()
        let squat = ExerciseID()
        let t1 = Date(timeIntervalSince1970: 5000)
        let t2 = Date(timeIntervalSince1970: 5001)

        let events: [SetEvent] = [
            SetEvent(device: WorkoutDevice.watch, emittedAt: t1, slot: SetSlot(exerciseID: bench, slotIndex: 1),
                     action: .recorded(try record(exercise: bench, at: t1))),
            SetEvent(device: WorkoutDevice.phone, emittedAt: t2, slot: SetSlot(exerciseID: squat, slotIndex: 1),
                     action: .recorded(try record(exercise: squat, at: t2))),
        ]

        let forward = engine.apply(events: events)
        let reverse = engine.apply(events: events.reversed())

        #expect(forward == reverse, "Ambos dispositivos deben ver el MISMO workout lógico.")
        #expect(forward.canonicalSets.count == 2)
    }

    // MARK: - AC: tolerancia a desconexión

    @Test("Un dispositivo puede continuar en solitario y luego converger al reconectar")
    func disconnectToleranceConverges() throws {
        let bench = ExerciseID()
        let slot = SetSlot(exerciseID: bench, slotIndex: 1)

        // El watch se desconecta tras grabar su set localmente.
        let watchLocal = SetEvent(
            device: WorkoutDevice.watch,
            emittedAt: Date(timeIntervalSince1970: 6000),
            slot: slot,
            action: .recorded(try record(exercise: bench, weight: 60, at: Date(timeIntervalSince1970: 6000)))
        )
        let watchLedger = engine.apply(events: [watchLocal])
        #expect(watchLedger.canonicalSets.count == 1, "El watch graba offline sin depender del peer.")

        // El phone, mientras tanto, avanza con el mismo plan y graba su framework.
        let phoneLocal = SetEvent(
            device: WorkoutDevice.phone,
            emittedAt: Date(timeIntervalSince1970: 6005),
            slot: SetSlot(exerciseID: bench, slotIndex: 2),
            action: .recorded(try record(exercise: bench, weight: 62.5, at: Date(timeIntervalSince1970: 6005)))
        )
        let phoneLedger = engine.apply(events: [phoneLocal])
        #expect(phoneLedger.canonicalSets.count == 1, "El phone continúa sin el watch.")

        // Reconexión: cada cola envía sus eventos al otro.
        let watchView = engine.apply(events: [phoneLocal], to: watchLedger)
        let phoneView = engine.apply(events: [watchLocal], to: phoneLedger)

        #expect(watchView.canonicalSets.count == 2, "Se conservan AMBOS sets grabados sin duplicar.")
        // "Mismo workout lógico": el contenido de sets converge (mismos sets, sin
        // duplicados), aunque el orden de llegada local pueda diferir.
        let watchSorted = watchView.canonicalSets.sorted { $0.id.rawValue < $1.id.rawValue }
        let phoneSorted = phoneView.canonicalSets.sorted { $0.id.rawValue < $1.id.rawValue }
        #expect(watchSorted == phoneSorted, "Al reconectar, el contenido de sets converge.")
    }
}