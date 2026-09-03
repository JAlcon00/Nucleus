//
//  PendingOperationStoreTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de la cola de operaciones pendientes respaldada por `RepositoryStore`
//  (PR-0203, EPIC-02): persiste entre launches y el guardado idempotente de sets
//  re-aplica sin duplicar SetRecord (invariante de producto).
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Pending operation store (PR-0203)")
struct PendingOperationStoreTests {

    private func makeWorkout() -> WorkoutSessionRecord {
        WorkoutSessionRecord(lifecycle: .active)
    }

    private func makeSet(id: SetRecordID = SetRecordID(), weight: Double = 50) throws -> SetRecord {
        try SetRecord(
            id: id,
            exerciseID: ExerciseID(),
            weight: weight,
            unit: .kilograms,
            reps: 8
        )
    }

    @Test("La cola persiste entre renders del store (mismo store subyacente)")
    func storePersistsAcrossLoads() throws {
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let op = PendingOperation(idempotencyKey: "set-1", kind: .saveSet, payload: Data("x".utf8))
        let inserted = try queue.enqueue(op)
        #expect(inserted)
        // Un segunto objeto sobre el mismo store recupera la misma cola (simula relaunch).
        let reloaded = PendingOperationQueueStore(store: store)
        let loaded = try reloaded.load()
        #expect(loaded.contains(idempotencyKey: "set-1"))
    }

    @Test("Encolar el mismo idempotencyKey no duplica")
    func enqueueDoesNotDuplicate() throws {
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let opA = PendingOperation(idempotencyKey: "set-1", kind: .saveSet, payload: Data())
        let opB = PendingOperation(idempotencyKey: "set-1", kind: .saveSet, payload: Data())
        let first = try queue.enqueue(opA)
        let second = try queue.enqueue(opB)
        #expect(first)
        #expect(!second)
        #expect(try queue.load().count == 1)
    }

    @Test("Guard: aplicar un set localmente no duplica en reintento")
    func applySetLocallyIsIdempotent() async throws {
        let workout = makeWorkout()
        let repo = InMemoryWorkoutRepository([workout])
        let guardInstance = SetPersistenceGuard()
        let set = try makeSet()

        let first = try await guardInstance.applySetLocally(set, in: workout.id, workoutRepository: repo)
        #expect(first) // aplicado
        let second = try await guardInstance.applySetLocally(set, in: workout.id, workoutRepository: repo)
        #expect(!second) // ya presente → idempotente, no duplica

        let session = try await repo.session(id: workout.id)
        #expect(session?.sets.count == 1)
    }

    @Test("Drain re-aplica una operación pendiente de guardar set")
    func drainAppliesPendingSet() async throws {
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let workout = makeWorkout()
        let repo = InMemoryWorkoutRepository()
        // Guardar la sesión vacía primero para que el drain encuentre la sesión.
        try await repo.save(workout)

        let guardInstance = SetPersistenceGuard()
        let set = try makeSet()
        #expect(try guardInstance.enqueueSetSave(set, in: workout.id, queue: queue))
        #expect(try queue.load().count == 1)

        let applied = await guardInstance.drainSetOperations(queue: queue, workoutRepository: repo)
        #expect(applied == 1)
        #expect(try queue.load().count == 0) // se sacó de la cola

        let session = try await repo.session(id: workout.id)
        #expect(session?.sets.count == 1)
        #expect(session?.sets.first?.id == set.id)
    }

    @Test("Drain no se pierde ni duplica si la sesión ya tenía el set")
    func drainIsIdempotentWhenAlreadyApplied() async throws {
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let workout = makeWorkout()
        let repo = InMemoryWorkoutRepository()
        try await repo.save(workout)

        let guardInstance = SetPersistenceGuard()
        let set = try makeSet()
        // Estado: el set ya está localmente (p. ej. guardado en un intento previo).
        let updated = workout.performedSet(set)
        // Se guarda reemplazando la sesión vacía por una que ya contiene el set.
        let savedSession = WorkoutSessionRecord(
            id: workout.id,
            lifecycle: .active,
            sets: [set]
        )
        try await repo.save(savedSession)

        // Aunque la operación sigue pendiente, el drain no debe duplicar el set.
        #expect(try guardInstance.enqueueSetSave(set, in: workout.id, queue: queue))
        #expect(try queue.load().count == 1)

        let applied = await guardInstance.drainSetOperations(queue: queue, workoutRepository: repo)
        #expect(applied == 0) // ya aplicado por idempotencia → no cuenta como nuevo
        let session = try await repo.session(id: workout.id)
        #expect(session?.sets.count == 1)
        #expect(try queue.load().count == 0) // y se saca de la cola
    }

    @Test("Drain conserva la operación si la sesión aún no existe (restry sin pérdida)")
    func drainKeepsWhenSessionMissing() async throws {
        let store = MemoryRepositoryStore()
        let queue = PendingOperationQueueStore(store: store)
        let workout = makeWorkout()

        let guardInstance = SetPersistenceGuard()
        let set = try makeSet()
        // Se encola pero nunca se guardó la sesión localmente.
        #expect(try guardInstance.enqueueSetSave(set, in: workout.id, queue: queue))

        let emptyRepo = InMemoryWorkoutRepository()
        let applied = await guardInstance.drainSetOperations(queue: queue, workoutRepository: emptyRepo)
        #expect(applied == 0)
        #expect(try queue.load().count == 1) // sigue en cola para reintentar

        // Una vez la sesión existe, el drain la aplica.
        try await emptyRepo.save(workout)
        let applied2 = await guardInstance.drainSetOperations(queue: queue, workoutRepository: emptyRepo)
        #expect(applied2 == 1)
        #expect(try queue.load().count == 0)
    }
}