//
//  PendingOperationTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de la cola de operaciones pendientes (PR-0203): modelo puro y determinista.
//  Verifica que el mismo `idempotencyKey` no se encola dos veces (base para el
//  "retry no duplica SetRecord") y que la cola persiste de forma Codable.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Pending operations queue (PR-0203)")
struct PendingOperationTests {

    private func makeOperation(
        key: String = "set-1",
        kind: PendingOperationKind = .saveSet,
        payload: Data = Data("x".utf8),
        id: UUID = UUID()
    ) -> PendingOperation {
        PendingOperation(id: id, idempotencyKey: key, kind: kind, payload: payload)
    }

    @Test("Empieza vacía")
    func startsEmpty() {
        let queue = PendingOperationQueue()
        #expect(queue.isEmpty)
        #expect(queue.count == 0)
    }

    @Test("Encola una operación y reporta su presencia")
    func enqueuesAndReports() {
        var queue = PendingOperationQueue()
        let op = makeOperation(key: "set-1")
        let inserted = queue.enqueue(op)
        #expect(inserted)
        #expect(queue.count == 1)
        #expect(queue.contains(idempotencyKey: "set-1"))
        #expect(queue.contains(id: op.id))
    }

    @Test("El mismo idempotencyKey NO se encola dos veces")
    func duplicateIdempotencyKeyRejected() {
        var queue = PendingOperationQueue()
        let a = makeOperation(key: "set-1")
        let b = makeOperation(key: "set-1", id: UUID())
        let first = queue.enqueue(a)
        let second = queue.enqueue(b)
        #expect(first)
        #expect(!second) // mismo idempotencyKey → duplicado
        #expect(queue.count == 1)
    }

    @Test("El mismo id tampoco se encola dos veces")
    func duplicateIdRejected() {
        var queue = PendingOperationQueue()
        let id = UUID()
        let a = makeOperation(key: "set-1", id: id)
        let b = makeOperation(key: "set-2", id: id)
        let first = queue.enqueue(a)
        let second = queue.enqueue(b)
        #expect(first)
        #expect(!second)
        #expect(queue.count == 1)
    }

    @Test("Distintas claves se encolan") 
    func distinctKeysEnqueue() {
        var queue = PendingOperationQueue()
        let first = queue.enqueue(makeOperation(key: "set-1"))
        let second = queue.enqueue(makeOperation(key: "set-2"))
        #expect(first)
        #expect(second)
        #expect(queue.count == 2)
    }

    @Test("remove(id:) elimina la operación")
    func removeById() {
        var queue = PendingOperationQueue()
        let op = makeOperation(key: "set-1")
        let op2 = makeOperation(key: "set-2")
        queue.enqueue(op)
        queue.enqueue(op2)
        queue.remove(id: op.id)
        #expect(queue.count == 1)
        #expect(!queue.contains(id: op.id))
        #expect(queue.contains(idempotencyKey: "set-2"))
    }

    @Test("Es Codable (persiste entre launches)")
    func codableRoundTrip() throws {
        var queue = PendingOperationQueue()
        queue.enqueue(makeOperation(key: "set-1", kind: .saveSet))
        queue.enqueue(makeOperation(key: "set-2", kind: .saveSet))
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(PendingOperationQueue.self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded.contains(idempotencyKey: "set-1"))
        #expect(decoded.contains(idempotencyKey: "set-2"))
    }

    @Test("operations(kind:) devuelve las de ese tipo en orden de creación")
    func kindFilterAndOrder() {
        var queue = PendingOperationQueue()
        let earlier = PendingOperation(
            idempotencyKey: "a",
            kind: .saveSet,
            payload: Data(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let later = PendingOperation(
            idempotencyKey: "b",
            kind: .saveSet,
            payload: Data(),
            createdAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        queue.enqueue(later)
        queue.enqueue(earlier)
        let sorted = queue.operations(kind: .saveSet)
        #expect(sorted.first?.idempotencyKey == "a") // earlier primero
        #expect(sorted.last?.idempotencyKey == "b")
    }
}