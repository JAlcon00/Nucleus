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

    /// Resultado de drenar la cola.
    public struct DrainResult: Equatable, Sendable {
        /// Sets que se aplicaron a su sesión.
        public var applied = 0
        /// Operaciones que se conservaron en la cola para reintentar (sesión aún inexistente,
        /// error de lectura/escritura). No se pierden: el siguiente drenado las reintenta.
        public var retained = 0
        /// Operaciones ilegibles que se descartaron.
        public var discarded = 0
    }

    /// Re-aplica todas las operaciones `saveSet` pendientes de forma idempotente. Quita de la
    /// cola las cumplidas (aplicadas o ya presentes); conserva las que no se pudieron aplicar.
    /// Ningún error se traga: cada caso queda contado en el resultado.
    public func drain(
        queue: PendingOperationQueueStore,
        workoutRepository: any WorkoutRepository
    ) async -> DrainResult {
        var result = DrainResult()
        let pending: [PendingOperation]
        do {
            pending = try queue.load().operations(kind: .saveSet)
        } catch {
            result.retained = 1   // cola ilegible: no se toca, se reintenta
            return result
        }
        for op in pending {
            guard let envelope = try? JSONDecoder().decode(StoredSetSave.self, from: op.payload) else {
                do {
                    try queue.remove(id: op.id)
                    result.discarded += 1
                } catch {
                    result.retained += 1
                }
                continue
            }
            do {
                let applied = try await applySetLocally(
                    envelope.set,
                    in: envelope.sessionID,
                    workoutRepository: workoutRepository
                )
                if applied { result.applied += 1 }
                // Aplicado (o ya presente por idempotencia): se da por cumplido.
                try queue.remove(id: op.id)
            } catch {
                // Sesión no encontrada u otro fallo: se conserva para reintentar.
                result.retained += 1
            }
        }
        return result
    }

    /// Versión que devuelve sólo cuántos sets se aplicaron (compatibilidad).
    public func drainSetOperations(
        queue: PendingOperationQueueStore,
        workoutRepository: any WorkoutRepository
    ) async -> Int {
        await drain(queue: queue, workoutRepository: workoutRepository).applied
    }
}