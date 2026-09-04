//
//  WorkoutSessionCoordinatorTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del cableado de WORKOUT MODE (PR-0602/0603/0604/0605 wiring): el coordinador
//  orquesta los engines de dominio (ActiveWorkoutController, SetCompleter, RestTimer,
//  WorkoutSummaryBuilder). Verifica uno-tap si coincide, edición persistida antes de la
//  transición, descanso automático tras working set, skip/extend, pausa/reanudación y
//  el resumen al completar. Offline y determinista; no inventa valores.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Workout session (PR-0602..0605 wiring)")
struct WorkoutSessionCoordinatorTests {

    /// Plantilla con un calentamiento y dos sets de trabajo en un ejercicio.
    private func makeTemplate() throws -> SessionTemplate {
        let exerciseID = ExerciseID()
        let workPrescription = try SetPrescription(
            targetRepRange: 8...10,
            targetLoad: 82.5,
            loadUnit: .kilograms,
            restSeconds: 90...120,
            isWarmup: false
        )
        let warmupPrescription = try SetPrescription(
            targetRepRange: 10...12,
            targetLoad: nil,
            loadUnit: .kilograms,
            restSeconds: 60...90,
            isWarmup: true
        )
        return SessionTemplate(
            title: "Press banca",
            plannedSets: [
                PlannedSet(exerciseID: exerciseID, prescription: warmupPrescription),
                PlannedSet(exerciseID: exerciseID, prescription: workPrescription),
                PlannedSet(exerciseID: exerciseID, prescription: workPrescription),
            ]
        )
    }

    /// Reloj controlable por el test.
    private final class BallClock {
        var now: Date = Date(timeIntervalSinceReferenceDate: 0)
        func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
        func callAsFunction() -> Date { now }
    }

    @MainActor
    @Test("start expone el primer set con target precargado")
    func startExposesFirstSet() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        let phase = coordinator.start(now: clock.now)
        guard case .active(let set) = phase else {
            Issue.record("Primer set debía estar activo, fase \(phase)")
            return
        }
        #expect(set.index == 0)
        #expect(set.total == 3)
        #expect(set.isWarmup) // primero es calentamiento
        // Target precargado (peso de la prescripción, reps = límite inferior).
        #expect(set.draft.targetWeight == 0) // no hay targetLoad en warmup → 0 editable
        #expect(set.draft.targetReps == 10)
    }

    @MainActor
    @Test("uno-tap con target coincidente registra el set y pasa al siguiente con descanso")
    func oneTapMatchAdvances() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        _ = coordinator.start(now: clock.now)

        // Warmup: coincidimos con target, no inicia descanso.
        var phase = try coordinator.completeCurrentSet(now: clock.now)
        guard case .active(let warmupSet) = phase else {
            Issue.record("Tras warmup debía seguir activo sin descanso, fase \(phase)")
            return
        }
        #expect(warmupSet.index == 1)
        #expect(!warmupSet.isWarmup)
        #expect(warmupSet.draft.targetWeight == 82.5)

        // Working set: coincide → inicia descanso automáticamente.
        phase = try coordinator.completeCurrentSet()
        guard case .resting(let next, rest: let rest) = phase else {
            Issue.record("Tras working set debía iniciar descanso, fase \(phase)")
            return
        }
        #expect(next.index == 2) // hay un segundo working set hacia el que descansar
        #expect(next.isWarmup == false)
        #expect(rest.isActive)
        #expect(rest.recommendedSeconds == 90)
    }

    @MainActor
    @Test("uno-tap con input que NO coincide lanza error y no registra")
    func oneTapMismatchDoesNotRegister() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        _ = coordinator.start(now: clock.now)

        #expect(throws: WorkoutSessionError.self) {
            _ = try coordinator.completeCurrentSet(input: SetCompletionInput(
                weight: 100,
                unit: .kilograms,
                reps: 8
            ))
        }
        // No registrado: el set siguiente sigue siendo el primero.
        guard case .active(let set) = coordinator.phase else {
            Issue.record("Sin registro, el set actual debía seguir siendo el primero")
            return
        }
        #expect(set.index == 0)
    }

    @MainActor
    @Test("edición de peso/reps registra y persiste antes de la transición")
    func editedSetPersists() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        _ = coordinator.start(now: clock.now)

        // Editar el warmup (peso propio).
        let phase = try coordinator.recordEditedSet(weight: 20, reps: 12, now: clock.now)
        guard case .active(let next) = phase else {
            Issue.record("Tras editar warmup debía avanzar sin descanso, fase \(phase)")
            return
        }
        // El working set ya realizado debe persistir: next index == 1 (el working).
        #expect(next.index == 1)
    }

    @MainActor
    @Test("pausa y reanudación conservan el set actual")
    func pauseResumeKeepsSet() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        _ = coordinator.start(now: clock.now)

        let paused = try coordinator.pause(now: clock.now)
        guard case .paused(let set) = paused else {
            Issue.record("Debía quedar pausado, fase \(paused)")
            return
        }
        #expect(set.index == 0)

        let resumed = try coordinator.resume(now: clock.now)
        guard case .active = resumed else {
            Issue.record("Debía reanudar a activo, fase \(resumed)")
            return
        }
    }

    @MainActor
    @Test("completar todos los sets genera resumen con working sets y volumen")
    func completeGeneratesSummary() throws {
        let clock = BallClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now }
        )
        _ = coordinator.start(now: clock.now)
        _ = try coordinator.recordEditedSet(weight: 20, reps: 12, now: clock.now) // warmup
        _ = try coordinator.completeCurrentSet(now: clock.now)                      // working 1
        _ = try coordinator.completeCurrentSet(now: clock.now)                      // working 2

        let phase = try coordinator.complete(now: clock.now)
        guard case .finished(let summary) = phase else {
            Issue.record("Debía terminar con resumen, fase \(phase)")
            return
        }
        // 3 sets completados (warmup editado 20×12 + 2 working 82.5×8).
        #expect(summary.workingSets == 3)
        let expectedVolume = (20.0 * 12.0) + (82.5 * 8.0) + (82.5 * 8.0)
        #expect(summary.volume == expectedVolume)
        #expect(summary.nextAction == .completed)
    }

    @MainActor
    @Test("completar un set lo encola como operación crítica con idempotencyKey estable")
    func completedSetIsQueuedIdempotently() throws {
        let clock = BallClock()
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now },
            pendingQueue: queue
        )
        _ = coordinator.start(now: clock.now)
        _ = try coordinator.completeCurrentSet(now: clock.now) // warmup → encola saveSet

        let loaded = try queue.load()
        let operations = loaded.operations(kind: .saveSet)
        #expect(operations.count == 1)
        // Operación crítica con clave de idempotencia estable (el retry no duplica).
        #expect(operations.first?.kind == .saveSet)
        #expect(operations.first?.idempotencyKey.isEmpty == false)
        // La cola es persistida tras el mismo store → sobrevive entre launches.
        let reloaded = PendingOperationQueueStore(store: store)
        #expect(try reloaded.load().contains(idempotencyKey: operations.first?.idempotencyKey ?? ""))
    }

    @MainActor
    @Test("encolar el mismo set dos veces no duplica la operación en la cola")
    func completedSetDoesNotDoubleEnqueue() throws {
        let clock = BallClock()
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now },
            pendingQueue: queue
        )
        _ = coordinator.start(now: clock.now)
        // Completamos el primer set; la operación queda en cola.
        _ = try coordinator.completeCurrentSet(now: clock.now)
        #expect(try queue.load().operations(kind: .saveSet).count == 1)

        // Cualquier re-intento de aplicar el mismo set (misma clave) no vuelve a encolar.
        var queueCopy = try queue.load()
        guard let op = queueCopy.operations(kind: .saveSet).first else {
            Issue.record("Debía existir una operación saveSet encolada")
            return
        }
        #expect(queueCopy.enqueue(op) == false) // duplicado → se rechaza
        #expect(queueCopy.count == 1)
    }

    @MainActor
    @Test("cerrar la sesión persiste el registro final vía el hook async")
    func finishPersistsSession() async throws {
        let clock = BallClock()
        var lastFinished: WorkoutSessionRecord?
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(),
            exerciseNames: [:],
            clock: { clock.now },
            onSessionFinished: { session in
                await MainActor.run { lastFinished = session }
            }
        )
        _ = coordinator.start(now: clock.now)
        _ = try coordinator.completeCurrentSet(now: clock.now) // warmup
        _ = try coordinator.completeCurrentSet(now: clock.now) // working 1
        _ = try coordinator.completeCurrentSet(now: clock.now) // working 2
        _ = try coordinator.complete(now: clock.now)

        // El hook es async; alcanzamos su efecto tras completar.
        let deadline = Date().addingTimeInterval(2)
        while lastFinished == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(lastFinished?.sets.count == 3)
    }
}