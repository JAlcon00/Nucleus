//
//  PlanStore.swift
//  PRCore
//
//  SCRUM-26: persistencia del plan por usuario y de la sesión recordada.
//  - `plans/`: un `StoredPlan` por usuario (clave derivada del ID opaco de Apple: ni el
//    ID ni nada personal aparece en nombres de archivo).
//  - `blocks/`: los bloques (los usa `FileTrainingBlockRepository`); el plan sólo los
//    referencia, así un bloque cerrado conserva su historial.
//  - `session/`: SOLO el ID opaco del usuario (sin tokens ni correo).
//  Orden de escritura: primero los bloques y al final el registro del plan, de modo que
//  el registro nunca apunta a un bloque que no existe; reintentar es idempotente.
//

import Foundation
import PRDomain

public struct PlanStore: Sendable {

    /// Resultado de leer el plan de un usuario.
    public enum LoadResult: Sendable, Equatable {
        /// Aún no hay plan guardado (primer arranque de este usuario).
        case none
        case loaded(StoredPlan, TrainingBlock)
        /// El registro del plan o su bloque no se pueden leer. No se borra nada.
        case unreadable
    }

    private let plans: any RepositoryStore
    private let sessions: any RepositoryStore
    private let blocks: FileTrainingBlockRepository

    private static let sessionKey = "current"

    public init(plans: some RepositoryStore, sessions: some RepositoryStore, blocks: some RepositoryStore, log: PersistenceLog = .standard) {
        self.plans = plans
        self.sessions = sessions
        self.blocks = FileTrainingBlockRepository(store: blocks, log: log)
    }

    /// Clave estable por usuario, derivada (no contiene el ID de Apple).
    static func key(forUser userID: String) -> String {
        SeedID.uuid(namespace: "user", slug: userID).persistenceKey
    }

    // MARK: - Plan

    public func loadPlan(userID: String) async -> LoadResult {
        let data: Data?
        do {
            data = try plans.read(key: Self.key(forUser: userID))
        } catch {
            return .unreadable
        }
        guard let data else { return .none }
        guard let plan = try? JSONDecoder().decode(StoredPlan.self, from: data),
              plan.userID == userID,
              let block = try? await blocks.block(id: plan.activeBlockID) else {
            return .unreadable
        }
        return .loaded(plan, block)
    }

    /// Guarda el plan. `closing` es el bloque anterior ya marcado como cerrado (cambio de
    /// plan): se conserva, no se borra. Lanza si cualquier escritura falla.
    public func save(plan: StoredPlan, block: TrainingBlock, closing: TrainingBlock? = nil) async throws {
        if let closing {
            try await blocks.save(closing)
        }
        try await blocks.save(block)
        try plans.write(key: Self.key(forUser: plan.userID), data: JSONEncoder().encode(plan))
    }

    /// Todos los bloques de un usuario (activo y cerrados), en el orden de su historial.
    public func blockHistory(of plan: StoredPlan) async -> [TrainingBlock] {
        var result: [TrainingBlock] = []
        for id in plan.blockHistory {
            if let block = try? await blocks.block(id: id) { result.append(block) }
        }
        return result
    }

    // MARK: - Sesión recordada

    /// ID del último usuario con sesión, o `nil` (sin sesión o registro ilegible).
    public func loadSession() -> String? {
        guard let data = try? sessions.read(key: Self.sessionKey),
              let session = try? JSONDecoder().decode(StoredSession.self, from: data),
              !session.userID.isEmpty else { return nil }
        return session.userID
    }

    public func saveSession(userID: String) throws {
        try sessions.write(key: Self.sessionKey, data: JSONEncoder().encode(StoredSession(userID: userID)))
    }

    /// Olvida la sesión (no toca planes, bloques ni entrenamientos).
    public func clearSession() throws {
        try sessions.delete(key: Self.sessionKey)
    }
}

extension LocalPersistence {
    public func planStore() throws -> PlanStore {
        PlanStore(
            plans: try store(for: .plans),
            sessions: try store(for: .session),
            blocks: try store(for: .blocks),
            log: log
        )
    }
}
