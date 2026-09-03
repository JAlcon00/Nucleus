//
//  PendingOperationStore.swift
//  PRCore
//
//  Created by PR.
//
//  Cola de operaciones pendientes respaldada por `RepositoryStore` (PR-0203, EPIC-02).
//  Persiste toda la cola tras una única clave atómica, de modo que la cola SOBREVIVE
//  entre launches. Se combina con `SetPersistenceGuard` para garantizar la invariante
//  de producto: un retry re-aplica sin duplicar SetRecord y la app funciona con el
//  backend apagado (offline-first).
//

import Foundation
import PRDomain

/// Persiste y recupera la cola de operaciones pendientes (misma `RepositoryStore` local).
public struct PendingOperationQueueStore: Sendable {
    /// Clave única de persistencia de la cola.
    public static let storageKey = "pending-operations"

    private let store: any RepositoryStore

    public init(store: any RepositoryStore) {
        self.store = store
    }

    /// Carga la cola persistida (vacía si no hay nada guardado). Recuperable entre launches.
    public func load() throws -> PendingOperationQueue {
        guard let data = try store.read(key: Self.storageKey) else { return PendingOperationQueue() }
        return try JSONDecoder().decode(PendingOperationQueue.self, from: data)
    }

    /// Persiste la cola completa de forma atómica.
    public func save(_ queue: PendingOperationQueue) throws {
        try store.write(key: Self.storageKey, data: JSONEncoder().encode(queue))
    }

    /// Encola una operación (persistida) si no es duplicado. Devuelve FALSE si ya estaba.
    public func enqueue(_ operation: PendingOperation) throws -> Bool {
        var queue = try load()
        let inserted = queue.enqueue(operation)
        guard inserted else { return false }
        try save(queue)
        return true
    }

    /// Elimina una operación por id (tras aplicarla con éxito).
    public func remove(id: PendingOperation.ID) throws {
        var queue = try load()
        queue.remove(id: id)
        try save(queue)
    }
}

// MARK: - Guardia idempotente de persistencia de SetRecord

/// Envelope Codable que la operación `saveSet` transporta: el set + la sesión destino.
public struct StoredSetSave: Codable, Sendable, Equatable {
    public let sessionID: WorkoutID
    public let set: SetRecord

    public init(sessionID: WorkoutID, set: SetRecord) {
        self.sessionID = sessionID
        self.set = set
    }
}

/// Errores de la guardia de persistencia de set.
public enum SetPersistenceError: Error, Equatable, Sendable {
    case sessionNotFound(WorkoutID)
}

/// Combina la escritura local autoritativa de un `SetRecord` con el encolado de la
/// operación crítica (PR-0203). Idempotente:
/// - encola con `idempotencyKey = set.id.uuidString` (estable → retry no duplica) si no hay duplicado;
/// - aplica localmente el set de forma idempotente (no re-append si la sesión ya lo contiene).
public struct SetPersistenceGuard: Sendable {

    public init() {}

    /// Encola la operación crítica de guardar un set (persistida, offline-first).
    /// Se encola (persistido) de forma independiente; el guardado local se hace luego con
    /// `applySetLocally`. Si el guardado local falla, la operación queda en cola y un drain
    /// posterior la re-aplica sin duplicar (invariante: no se pierde el dato de workout).
    public func enqueueSetSave(
        _ set: SetRecord,
        in sessionID: WorkoutID,
        queue: PendingOperationQueueStore,
        now: Date = Date()
    ) throws -> Bool {
        let envelope = StoredSetSave(sessionID: sessionID, set: set)
        let payload = try JSONEncoder().encode(envelope)
        let operation = PendingOperation(
            idempotencyKey: set.id.rawValue.persistenceKey,
            kind: .saveSet,
            payload: payload,
            createdAt: now
        )
        return try queue.enqueue(operation)
    }

    /// Aplica localmente el set a su sesión de forma idempotente. Devuelve TRUE si lo
    /// aplicó, FALSE si el set ya existía en la sesión (sin duplicado).
    @discardableResult
    public func applySetLocally(
        _ set: SetRecord,
        in sessionID: WorkoutID,
        workoutRepository: any WorkoutRepository
    ) async throws -> Bool {
        guard let session = try await workoutRepository.session(id: sessionID) else {
            throw SetPersistenceError.sessionNotFound(sessionID)
        }
        guard !session.sets.contains(where: { $0.id == set.id }) else {
            return false // ya aplicado → idempotente, no duplica
        }
        let updated = session.performedSet(set)
        try await workoutRepository.save(updated)
        return true
    }

    /// Re-aplica todas las operaciones `saveSet` pendientes de forma idempotente y
    /// devuelve cuántas se aplicaron. Elimina de la cola las exitosas (o las ilegibles);
    /// conserva las que no se pudieron aplicar (sesión aún inexistente) para reintentar.
    public func drainSetOperations(
        queue: PendingOperationQueueStore,
        workoutRepository: any WorkoutRepository
    ) async -> Int {
        let pending = (try? queue.load().operations(kind: .saveSet)) ?? []
        var applied = 0
        for op in pending {
            guard let envelope = try? JSONDecoder().decode(StoredSetSave.self, from: op.payload) else {
                try? queue.remove(id: op.id)
                continue
            }
            do {
                let result = try await applySetLocally(
                    envelope.set,
                    in: envelope.sessionID,
                    workoutRepository: workoutRepository
                )
                if result {
                    applied += 1
                }
                // Aplicado (o ya presente por idempotencia): lo damos por cumplido y lo sacamos.
                try queue.remove(id: op.id)
            } catch {
                // Sesión no encontrada (workout aún no persistido): lo mantenemos en cola
                // para reintentarlo más tarde (no se pierde el dato).
                continue
            }
        }
        return applied
    }
}