//
//  WorkoutRecoveryTests.swift
//  PRCoreTests
//
//  SCRUM-24 / SCRUM-25: el entrenamiento no se pierde si la app se cierra y la sesión se
//  cierra bien al terminar. Todo sobre `LocalPersistence` real en un directorio temporal;
//  "cierre forzado" = descartar el coordinador y abrir otra instancia sobre el mismo
//  directorio (lo que ve la app al reabrir).
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Reloj controlable.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var messages: [String] { lock.withLock { storage } }
    var log: PersistenceLog { PersistenceLog { [self] message in lock.withLock { storage.append(message) } } }
}

private final class WriteSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [WorkoutSessionRecord] = []
    var count: Int { lock.withLock { records.count } }
    var last: WorkoutSessionRecord? { lock.withLock { records.last } }
    func add(_ record: WorkoutSessionRecord) { lock.withLock { records.append(record) } }
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-recover-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func template(sets: Int = 8, rest: ClosedRange<Int> = 120...120) throws -> SessionTemplate {
    let prescription = try SetPrescription(
        targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: rest, isWarmup: false
    )
    let exercise = ExerciseID()
    return SessionTemplate(
        title: "Press banca",
        plannedSets: (0..<sets).map { _ in PlannedSet(exerciseID: exercise, prescription: prescription) }
    )
}

@MainActor
private func openCoordinator(
    _ persistence: LocalPersistence, template: SessionTemplate, clock: TestClock
) async throws -> WorkoutSessionCoordinator {
    try await persistence.makeWorkoutCoordinator(template: template, clock: { clock.now })
}

@MainActor
@Suite("SCRUM-24 · No perder el entrenamiento si la app se cierra")
struct WorkoutRecoveryTests {

    @Test("Al iniciar, la sesión ya está en disco como activa")
    func startPersistsActiveSession() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await openCoordinator(persistence, template: try template(), clock: clock)
        _ = coordinator.start()

        let onDisk = try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            .workoutRepository().allSessions()
        #expect(onDisk.count == 1)
        #expect(onDisk.first?.lifecycle == .active)
        #expect(onDisk.first?.sets.isEmpty == true)
    }

    @Test("Cada serie queda en disco antes de que la UI avance, en menos de 100 ms")
    func eachSetIsPersistedFast() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await openCoordinator(persistence, template: try template(), clock: clock)
        _ = coordinator.start()
        let repository = try persistence.workoutRepository()

        for expected in 1...5 {
            let began = ContinuousClock.now
            _ = try coordinator.completeCurrentSet()
            let elapsed = ContinuousClock.now - began
            #expect(elapsed < .milliseconds(100), "la serie \(expected) tardó \(elapsed)")
            // Al volver de completeCurrentSet, el disco YA tiene la serie.
            let saved = try await repository.allSessions()
            #expect(saved.first?.sets.count == expected)
            clock.advance(5)
        }
    }

    @Test("Con 5 series hechas, tras un cierre forzado se retoma con las 5 y sigue la 6")
    func forcedKillRestoresExactly() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        var firstID: WorkoutID?
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await openCoordinator(persistence, template: plan, clock: clock)
            _ = coordinator.start()
            for _ in 1...5 { _ = try coordinator.completeCurrentSet(); clock.advance(10) }
            firstID = try coordinator.snapshot().session.id
        } // el coordinador se descarta: cierre forzado

        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let outcome = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now })
        guard case .restored(let restored) = outcome else {
            Issue.record("debía haber un entrenamiento en curso"); return
        }
        let snapshot = try restored.snapshot()
        #expect(snapshot.session.id == firstID)
        #expect(snapshot.session.sets.count == 5)
        #expect(snapshot.session.lifecycle == .active)
        #expect(restored.currentSet()?.index == 5, "sigue la serie 6")
    }

    @Test("El descanso se guarda como hora de fin: 120 s, cierre a los 30 s, reabrir 40 s después ⇒ ~50 s")
    func restSurvivesRestart() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        let finishAt = clock.now
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await openCoordinator(persistence, template: plan, clock: clock)
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()      // descanso de 120 s desde finishAt
            clock.advance(30)                              // cierre a los 30 s
        }
        clock.advance(40)                                  // reabre 40 s después (70 s en total)
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now }) else {
            Issue.record("debía retomarse"); return
        }
        #expect(restored.currentRest.remaining(at: clock.now) == 50)
        guard case .resting(_, let rest) = restored.phase else {
            Issue.record("debía seguir en descanso: \(restored.phase)"); return
        }
        #expect(rest.remaining(at: clock.now) == 50)
        #expect(rest.endDate == finishAt.addingTimeInterval(120))
    }

    @Test("Si el descanso ya terminó al reabrir, muestra 0 y la siguiente serie queda lista")
    func elapsedRestShowsZero() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await openCoordinator(persistence, template: plan, clock: clock)
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()
        }
        clock.advance(600)
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now }) else {
            Issue.record("debía retomarse"); return
        }
        #expect(restored.currentRest.remaining(at: clock.now) == 0)
        guard case .active(let next) = restored.phase else {
            Issue.record("la serie debía estar lista: \(restored.phase)"); return
        }
        #expect(next.index == 1)
    }

    @Test("Omitir el descanso también se guarda: al reabrir ya no hay descanso")
    func skippedRestIsPersisted() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await openCoordinator(persistence, template: plan, clock: clock)
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()
            coordinator.skipRest()
        }
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now }) else {
            Issue.record("debía retomarse"); return
        }
        if case .resting = restored.phase { Issue.record("no debía haber descanso") }
    }

    @Test("La cola se drena al arrancar, queda vacía y repetirlo no duplica series")
    func queueDrainsIdempotently() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let coordinator = try await openCoordinator(persistence, template: plan, clock: clock)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.completeCurrentSet()
        // Simula un cierre justo ENTRE encolar la serie 3 y escribir la sesión: la operación
        // está en la cola pero la sesión en disco sólo tiene 2 series.
        let live = try coordinator.snapshot().session
        let third = try SetRecord(
            exerciseID: plan.plannedSets[2].exerciseID, performedAt: clock.now,
            weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed
        )
        let queue = try persistence.pendingOperationQueue()
        _ = try SetPersistenceGuard().enqueueSetSave(third, in: live.id, queue: queue, now: clock.now)
        #expect(try queue.load().operations(kind: .saveSet).count >= 1)

        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        _ = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now })
        let afterFirst = try await reopened.workoutRepository().allSessions()
        #expect(afterFirst.first?.sets.count == 3, "la serie pendiente se aplicó")
        #expect(try reopened.pendingOperationQueue().load().operations(kind: .saveSet).isEmpty, "la cola quedó vacía")

        // Segunda vez: nada cambia ni se duplica.
        let again = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        _ = try await again.recoverWorkout(templates: [plan], clock: { clock.now })
        let afterSecond = try await again.workoutRepository().allSessions()
        #expect(afterSecond.first?.sets.count == 3)
        #expect(Set(afterSecond.first?.sets.map(\.id) ?? []).count == 3)
    }

    @Test("Drenar dos veces seguidas el mismo set no lo duplica")
    func drainTwiceDoesNotDuplicate() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let repository = try persistence.workoutRepository()
        let queue = try persistence.pendingOperationQueue()
        let session = WorkoutSessionRecord(lifecycle: .active)
        try await repository.save(session)
        let set = try SetRecord(
            exerciseID: ExerciseID(), weight: 50, unit: .kilograms, reps: 10, lifecycle: .completed
        )
        _ = try SetPersistenceGuard().enqueueSetSave(set, in: session.id, queue: queue)

        let guardian = SetPersistenceGuard()
        let first = await guardian.drain(queue: queue, workoutRepository: repository)
        let second = await guardian.drain(queue: queue, workoutRepository: repository)
        #expect(first.applied == 1)
        #expect(second.applied == 0)
        #expect(try await repository.session(id: session.id)?.sets.count == 1)
        #expect(try queue.load().operations(kind: .saveSet).isEmpty)
    }

    @Test("Una operación sin sesión se conserva en la cola para reintentar (no se pierde)")
    func orphanOperationIsRetained() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let queue = try persistence.pendingOperationQueue()
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 50, unit: .kilograms, reps: 10, lifecycle: .completed)
        _ = try SetPersistenceGuard().enqueueSetSave(set, in: WorkoutID(), queue: queue)
        let result = await SetPersistenceGuard().drain(queue: queue, workoutRepository: try persistence.workoutRepository())
        #expect(result.retained == 1)
        #expect(try queue.load().operations(kind: .saveSet).count == 1)
    }

    @Test("Terminar sin completar deja la sesión abandonada y conserva las series hechas")
    func abandonKeepsSets() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await openCoordinator(persistence, template: try template(), clock: clock)
        _ = coordinator.start()
        for _ in 1...3 { _ = try coordinator.completeCurrentSet(); clock.advance(5) }
        _ = try coordinator.abandon()

        let saved = try #require(try await persistence.workoutRepository().allSessions().first)
        #expect(saved.lifecycle == .abandoned)
        #expect(saved.sets.count == 3)
        #expect(saved.endedAt != nil)
        // No se ofrece retomarla.
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .none = try await reopened.recoverWorkout(templates: [try template()], clock: { clock.now }) else {
            Issue.record("una sesión abandonada no se retoma"); return
        }
    }

    @Test("Con dos sesiones activas por error: se retoma la más reciente, la otra queda abandonada intacta y se registra")
    func twoActiveSessions() async throws {
        let root = try makeRoot()
        let sink = LogSink()
        let persistence = try LocalPersistence(rootURL: root, log: sink.log)
        let plan = try template()
        let repository = try persistence.workoutRepository()
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 40, unit: .kilograms, reps: 8, lifecycle: .completed)
        let older = WorkoutSessionRecord(
            templateID: plan.id, startedAt: Date(timeIntervalSince1970: 100), lifecycle: .active, sets: [set, try set.withNewID(), try set.withNewID()]
        )
        let newer = WorkoutSessionRecord(
            templateID: plan.id, startedAt: Date(timeIntervalSince1970: 200), lifecycle: .active, sets: [try set.withNewID()]
        )
        try await repository.save(older)
        try await repository.save(newer)

        guard case .restored(let restored) = try await persistence.recoverWorkout(templates: [plan]) else {
            Issue.record("debía retomarse la más reciente"); return
        }
        #expect(try restored.snapshot().session.id == newer.id)
        let abandoned = try #require(try await repository.session(id: older.id))
        #expect(abandoned.lifecycle == .abandoned)
        #expect(abandoned.sets.count == 3, "sus series quedan intactas")
        #expect(sink.messages.contains { $0.contains("extraActiveSessions=1") })
        #expect(!sink.messages.contains { $0.contains(older.id.rawValue.uuidString) }, "el registro no lleva identificadores")
    }

    @Test("Si la plantilla de la sesión ya no existe, se abandona conservando las series")
    func missingTemplateAbandons() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let repository = try persistence.workoutRepository()
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 40, unit: .kilograms, reps: 8, lifecycle: .completed)
        let orphan = WorkoutSessionRecord(templateID: UUID(), lifecycle: .active, sets: [set])
        try await repository.save(orphan)

        guard case .none = try await persistence.recoverWorkout(templates: [try template()]) else {
            Issue.record("sin plantilla no hay nada que retomar"); return
        }
        let saved = try #require(try await repository.session(id: orphan.id))
        #expect(saved.lifecycle == .abandoned)
        #expect(saved.sets.count == 1)
    }

    @Test("Cierre forzado justo después de la última serie: al reabrir queda completada, no 'en curso'")
    func killAfterLastSet() async throws {
        let root = try makeRoot()
        let plan = try template(sets: 2)
        let clock = TestClock()
        // La última serie quedó en disco pero la sesión sigue `active` (se cayó antes de cerrar).
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let repository = try persistence.workoutRepository()
        let sets = try plan.plannedSets.map { planned in
            try SetRecord(exerciseID: planned.exerciseID, performedAt: clock.now, weight: 60, unit: .kilograms, reps: 8, lifecycle: .completed)
        }
        let record = WorkoutSessionRecord(templateID: plan.id, startedAt: clock.now, lifecycle: .active, sets: sets)
        try await repository.save(record)

        guard case .none = try await persistence.recoverWorkout(templates: [plan], clock: { clock.now }) else {
            Issue.record("no hay nada en curso"); return
        }
        let saved = try #require(try await repository.session(id: record.id))
        #expect(saved.lifecycle == .completed)
        #expect(saved.endedAt != nil)
        #expect(saved.sets.count == 2)
    }

    @Test("Si el disco falla, el entrenamiento sigue en memoria y se avisa (persistenceFailed)")
    func diskFailureIsSurfaced() throws {
        struct DiskFull: Error {}
        let clock = TestClock()
        let coordinator = WorkoutSessionCoordinator(
            template: try template(), clock: { clock.now },
            persistSession: { _ in throw DiskFull() }
        )
        _ = coordinator.start()
        #expect(coordinator.persistenceFailed)
        _ = try coordinator.completeCurrentSet()
        #expect(coordinator.currentSet()?.index == 1, "la serie se registró en memoria")
        #expect(coordinator.persistenceFailed)
    }
}

private extension SetRecord {
    /// Copia con otro id (para fabricar series distintas en los tests).
    func withNewID() throws -> SetRecord {
        try SetRecord(
            exerciseID: exerciseID, performedAt: performedAt, weight: weight, unit: unit, reps: reps, lifecycle: lifecycle
        )
    }
}
