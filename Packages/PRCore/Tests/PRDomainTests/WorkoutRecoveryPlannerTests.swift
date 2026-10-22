//
//  WorkoutRecoveryPlannerTests.swift
//  PRDomainTests
//
//  SCRUM-24: qué hace la app con las sesiones que quedaron abiertas. Puro y determinista.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("SCRUM-24 · Plan de recuperación de sesiones")
struct WorkoutRecoveryPlannerTests {

    private let now = Date(timeIntervalSince1970: 10_000)

    private func set(_ n: Int) throws -> SetRecord {
        try SetRecord(
            exerciseID: ExerciseID(), performedAt: Date(timeIntervalSince1970: Double(n)),
            weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed
        )
    }

    private func session(
        _ lifecycle: WorkoutLifecycleState, started: TimeInterval, sets: Int = 0
    ) throws -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            startedAt: Date(timeIntervalSince1970: started), lifecycle: lifecycle,
            sets: try (0..<sets).map(set)
        )
    }

    @Test("Una sola sesión activa se retoma y no cambia nada más")
    func singleActiveIsRestored() throws {
        let active = try session(.active, started: 100, sets: 5)
        let plan = WorkoutRecoveryPlanner().plan(for: [active, try session(.completed, started: 1)], now: now)
        #expect(plan.restore == active)
        #expect(plan.updates.isEmpty)
        #expect(plan.extraActiveCount == 0)
    }

    @Test("Una pausada también se retoma")
    func pausedIsRestored() throws {
        let paused = try session(.paused, started: 100, sets: 2)
        #expect(WorkoutRecoveryPlanner().plan(for: [paused], now: now).restore == paused)
    }

    @Test("Con dos activas se retoma la más reciente y la otra queda abandonada con sus series")
    func twoActiveKeepsTheNewest() throws {
        let older = try session(.active, started: 100, sets: 4)
        let newer = try session(.active, started: 200, sets: 2)
        let plan = WorkoutRecoveryPlanner().plan(for: [older, newer], now: now)

        #expect(plan.restore == newer)
        #expect(plan.extraActiveCount == 1)
        let abandoned = try #require(plan.updates.first)
        #expect(plan.updates.count == 1)
        #expect(abandoned.id == older.id)
        #expect(abandoned.lifecycle == .abandoned)
        #expect(abandoned.sets == older.sets, "las series no se tocan")
        #expect(abandoned.endedAt == now)
    }

    @Test("El orden de entrada no cambia el resultado (determinismo)")
    func orderIndependent() throws {
        let a = try session(.active, started: 100)
        let b = try session(.active, started: 100)   // empate de hora: desempata por id
        let c = try session(.paused, started: 50)
        let first = WorkoutRecoveryPlanner().plan(for: [a, b, c], now: now)
        let second = WorkoutRecoveryPlanner().plan(for: [c, b, a], now: now)
        #expect(first.restore?.id == second.restore?.id)
        #expect(Set(first.updates.map(\.id)) == Set(second.updates.map(\.id)))
    }

    @Test("Cierre a medias se completa; lo que nunca empezó se abandona; lo cerrado no se toca")
    func otherStates() throws {
        let finishing = try session(.finishing, started: 10, sets: 3)
        let planned = try session(.planned, started: 20)
        let preparing = try session(.preparing, started: 30)
        let done = try session(.completed, started: 40, sets: 3)
        let gone = try session(.abandoned, started: 50, sets: 1)
        let plan = WorkoutRecoveryPlanner().plan(for: [finishing, planned, preparing, done, gone], now: now)

        #expect(plan.restore == nil)
        let byID = Dictionary(uniqueKeysWithValues: plan.updates.map { ($0.id, $0) })
        #expect(byID[finishing.id]?.lifecycle == .completed)
        #expect(byID[finishing.id]?.sets == finishing.sets)
        #expect(byID[planned.id]?.lifecycle == .abandoned)
        #expect(byID[preparing.id]?.lifecycle == .abandoned)
        #expect(byID[done.id] == nil)
        #expect(byID[gone.id] == nil)
    }

    @Test("Descanso de 120 s: tras 70 s quedan unos 50 s; vencido queda en 0 y sin descanso activo")
    func restRemainingFromEndTime() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let snapshot = RestSnapshot(recommendedSeconds: 120, startedAt: start, endDate: start.addingTimeInterval(120))

        let midway = snapshot.timerState(at: start.addingTimeInterval(70))
        #expect(midway.isActive)
        #expect(midway.remaining(at: start.addingTimeInterval(70)) == 50)

        let late = snapshot.timerState(at: start.addingTimeInterval(500))
        #expect(!late.isActive)
        #expect(late.remaining(at: start.addingTimeInterval(500)) == 0)
    }

    @Test("Un registro viejo sin descanso sigue decodificándose")
    func legacyRecordDecodes() throws {
        let record = WorkoutSessionRecord(lifecycle: .completed)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "rest")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: data)
        #expect(decoded.rest == nil)
        #expect(decoded.id == record.id)
    }
}
