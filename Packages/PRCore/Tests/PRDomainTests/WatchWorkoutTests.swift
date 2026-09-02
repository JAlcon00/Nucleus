//
//  WatchWorkoutTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del driver del workout en el Watch (PR-1201): ejercicio actual, peso/reps
//  presets, índice del set, fin de los sets y rest timer. Lógica pura; la shell
//  SwiftUI del Watch sólo renderiza. Determinista.
//

import Foundation
import Testing
import PRDomain

@Suite("Watch workout UI driver (PR-1201)")
struct WatchWorkoutTests {

    private func prescription(
        reps: ClosedRange<Int> = 8...12,
        load: Double? = 60,
        rest: ClosedRange<Int> = 60...90,
        warmup: Bool = false
    ) throws -> SetPrescription {
        try SetPrescription(
            targetRepRange: reps,
            targetLoad: load,
            loadUnit: .kilograms,
            restSeconds: rest,
            isWarmup: warmup
        )
    }

    private func template() throws -> SessionTemplate {
        let bench = ExerciseID()
        let squat = ExerciseID()
        return SessionTemplate(
            title: "Push",
            plannedSets: [
                try PlannedSet(exerciseID: bench, prescription: prescription()),
                try PlannedSet(exerciseID: bench, prescription: prescription()),
                try PlannedSet(exerciseID: squat, prescription: prescription(load: 80)),
            ]
        )
    }

    private func completedSet(exercise: ExerciseID, weight: Double) throws -> SetRecord {
        try SetRecord(exerciseID: exercise, weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed)
    }

    // 1. Ejercicio actual: con 0 sets, muestra el primer set del primer ejercicio.
    @Test("Con 0 sets muestra el primer set del primer ejercicio")
    func firstSetShownInitially() async throws {
        let driver = WatchWorkoutDriver()
        let tp = try template()
        guard case .inProgress(let p) = driver.current(template: tp, performedSets: []) else {
            Issue.record("Se esperaba set en progreso")
            return
        }
        #expect(p.exerciseID == tp.plannedSets[0].exerciseID)
        #expect(p.currentSetIndex == 1)
        #expect(p.totalSetsInExercise == 2)
        #expect(p.weight == 60)
        #expect(p.reps == 8)
        #expect(!p.isWarmup)
    }

    // 2. Al completar un set, avanza al siguiente (mismo ejercicio → set 2/2).
    @Test("Tras completar un set, avanza al siguiente del mismo ejercicio")
    func advancesToNextSet() async throws {
        let driver = WatchWorkoutDriver()
        let tp = try template()
        let bench = tp.plannedSets[0].exerciseID
        let done = try completedSet(exercise: bench, weight: 60)

        guard case .inProgress(let p) = driver.current(template: tp, performedSets: [done]) else {
            Issue.record("Se esperaba set en progreso")
            return
        }
        #expect(p.exerciseID == bench)
        #expect(p.currentSetIndex == 2)
        #expect(p.totalSetsInExercise == 2)
    }

    // 3. Al completar todos los sets del ejercicio, pasa al siguiente ejercicio.
    @Test("Tras completar todos los sets del ejercicio pasa al siguiente ejercicio")
    func movesToNextExercise() async throws {
        let driver = WatchWorkoutDriver()
        let tp = try template()
        let bench = tp.plannedSets[0].exerciseID
        let squat = tp.plannedSets[2].exerciseID
        let done = [try completedSet(exercise: bench, weight: 60), try completedSet(exercise: bench, weight: 60)]

        guard case .inProgress(let p) = driver.current(template: tp, performedSets: done) else {
            Issue.record("Se esperaba set en progreso")
            return
        }
        #expect(p.exerciseID == squat)
        #expect(p.currentSetIndex == 1)
        #expect(p.totalSetsInExercise == 1)
        #expect(p.weight == 80)
    }

    // 4. Al completar todos los sets, la sesión apareció como .complete.
    @Test("Con todos los sets completados, la sesión queda completa")
    func completeWhenAllSetsDone() async throws {
        let driver = WatchWorkoutDriver()
        let tp = try template()
        let bench = tp.plannedSets[0].exerciseID
        let squat = tp.plannedSets[2].exerciseID
        let done = [
            try completedSet(exercise: bench, weight: 60),
            try completedSet(exercise: bench, weight: 60),
            try completedSet(exercise: squat, weight: 80),
        ]
        #expect(driver.current(template: tp, performedSets: done) == .complete)
    }

    // 5. Sin plantilla → idle.
    @Test("Sin plantilla devuelve idle")
    func idleWithoutTemplate() {
        let driver = WatchWorkoutDriver()
        #expect(driver.current(template: SessionTemplate(title: "", plannedSets: []), performedSets: []) == .idle)
    }

    // 6. El set actual puede ser un warmup (no inicia descanso).
    @Test("Un warmup se marca como warmup y no sugiere descanso")
    func warmupMarked() async throws {
        let driver = WatchWorkoutDriver()
        let warmPlan = try PlannedSet(exerciseID: ExerciseID(), prescription: prescription(load: 20, warmup: true))
        let tp = SessionTemplate(title: "P", plannedSets: [warmPlan])

        guard case .inProgress(let p) = driver.current(template: tp, performedSets: []) else {
            Issue.record("Se esperaba set en progreso")
            return
        }
        #expect(p.isWarmup)

        let rest = driver.restSuggested(afterCompleted: warmPlan)
        #expect(rest.isActive == false)
    }

    // 7. Rest timer sugerido tras un working set (RestTimer, PR-0604).
    @Test("Tras un working set se sugiere descanso con endDate anclado")
    func restSuggestedAfterWorkingSet() async throws {
        let driver = WatchWorkoutDriver()
        let plan = try PlannedSet(exerciseID: ExerciseID(), prescription: prescription(rest: 60...90))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let rest = driver.restSuggested(afterCompleted: plan, now: now)
        #expect(rest.isActive)
        #expect(rest.recommendedSeconds == 60)
        #expect(rest.remaining(at: now) == 60)
        #expect(rest.remaining(at: now.addingTimeInterval(30)) == 30)
    }
}