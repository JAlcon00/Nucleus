//
//  PendingOperations.swift
//  PRDomain
//
//  Created by PR.
//
//  Cola de operaciones pendientes (plan §2, RF-005, PR-0203): modelo puro y
//  determinista (sin IO, sin Views) de operaciones críticas pendientes de aplicar/
//  propagar. Cada operación lleva un `idempotencyKey` ESTABLE (p. ej. el id del
//  SetRecord) para que un retry re-aplique sin duplicar. Invar. de producto: la
//  persistencia local protege los datos de workout aun con el backend apagado.
//

import Foundation

/// Tipo de operación pendiente. El dominio acota qué operaciones son críticas.
public enum PendingOperationKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Persistir un `SetRecord` (dato de workout crítico). Idempotencia por `SetRecordID`.
    case saveSet
}

/// Una operación pendiente de la cola.
public struct PendingOperation: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = UUID

    public let id: UUID
    /// Clave de idempotencia ESTABLE: los reintentos reutilizan la misma clave; con ella
    /// se evita encolar o aplicar la misma operación dos veces (p. ej. retry no duplica SetRecord).
    public let idempotencyKey: String
    public let kind: PendingOperationKind
    /// Payload Codable (Data opaco al dominio; el consumidor de PRCore lo decodifica).
    public let payload: Data
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        idempotencyKey: String,
        kind: PendingOperationKind,
        payload: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Cola pura de operaciones pendientes. API inmutable (value semantic).
public struct PendingOperationQueue: Codable, Sendable, Equatable {
    public private(set) var operations: [PendingOperation]

    public init(operations: [PendingOperation] = []) {
        self.operations = operations
    }

    public var count: Int { operations.count }
    public var isEmpty: Bool { operations.isEmpty }

    /// ¿Hay una operación pendiente con la clave de idempotencia dada?
    public func contains(idempotencyKey: String) -> Bool {
        operations.contains { $0.idempotencyKey == idempotencyKey }
    }

    /// ¿Hay una operación pendiente con el id dado?
    public func contains(id: PendingOperation.ID) -> Bool {
        operations.contains { $0.id == id }
    }

    /// Encola una operación si no es un duplicado (por idempotencyKey o por id).
    /// Devuelve TRUE si se encoló; FALSE si era un duplicado (prevención de duplicados).
    public mutating func enqueue(_ operation: PendingOperation) -> Bool {
        guard !contains(idempotencyKey: operation.idempotencyKey), !contains(id: operation.id) else {
            return false
        }
        operations.append(operation)
        return true
    }

    /// Elimina una operación por id (tras aplicarla con éxito, sin reintento accidental).
    public mutating func remove(id: PendingOperation.ID) {
        operations.removeAll { $0.id == id }
    }

    /// Elimina todas las operaciones del tipo dado.
    public mutating func removeAll(kind: PendingOperationKind) {
        operations.removeAll { $0.kind == kind }
    }

    /// Operaciones en orden de creación (determinista).
    public func operations(kind: PendingOperationKind) -> [PendingOperation] {
        operations
            .filter { $0.kind == kind }
            .sorted { $0.createdAt < $1.createdAt }
    }
}