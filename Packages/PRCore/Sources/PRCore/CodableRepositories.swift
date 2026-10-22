//
//  CodableRepositories.swift
//  PRCore
//
//  Created by PR.
//
//  Implementaciones persistentes de los contratos de persistencia (PR-0201)
//  respaldadas por `RepositoryStore` (PR-0202, EPIC-02). Cada agregado de
//  dominio se codifica como blob JSON tras su clave tipada; el save es
//  inmediato y autoritativo (un fallo de sync remoto jamás lo revierte).
//
//  Al confirmar un set, `WorkoutRepository.save` persiste la sesión completa
//  (incluye sus sets) de forma atómica, cumpliendo el flujo crítico del plan.
//

import Foundation
import PRDomain

// MARK: - Helpers

enum JSONBlob {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// Lectura tolerante de una colección completa (SCRUM-23): decodifica lo válido y
    /// cuenta lo ilegible (IO o decode). Si hubo ilegibles, lo registra sin datos
    /// personales. Lanza sólo si la colección entera no es accesible.
    static func decodeAll<T: Decodable & Sendable>(
        _ type: T.Type,
        from store: any RepositoryStore,
        collection: PersistenceCollection,
        log: PersistenceLog
    ) throws -> RepositoryReadResult<T> {
        let raw = try store.readAllEntries()
        var items: [T] = []
        var unreadable = raw.unreadableKeys.count
        for entry in raw.entries {
            do {
                items.append(try decode(type, from: entry.data))
            } catch {
                unreadable += 1
            }
        }
        if unreadable > 0 {
            log.unreadableRecords(collection, count: unreadable)
        }
        return RepositoryReadResult(items: items, unreadableCount: unreadable)
    }
}

// MARK: - ExerciseRepository

/// Implementación persistente de `ExerciseRepository`.
public final class FileExerciseRepository: ExerciseRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allExercises() async throws -> [Exercise] {
        try JSONBlob.decodeAll(Exercise.self, from: store, collection: .exercises, log: log).items
    }

    public func exercise(id: ExerciseID) async throws -> Exercise? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(Exercise.self, from: data)
    }

    public func save(_ exercise: Exercise) async throws {
        try store.write(key: exercise.id.rawValue.persistenceKey, data: JSONBlob.encode(exercise))
    }

    public func delete(id: ExerciseID) async throws {
        try store.delete(key: id.rawValue.persistenceKey)
    }
}

// MARK: - TrainingBlockRepository

/// Implementación persistente de `TrainingBlockRepository`.
public final class FileTrainingBlockRepository: TrainingBlockRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allBlocks() async throws -> [TrainingBlock] {
        try JSONBlob.decodeAll(TrainingBlock.self, from: store, collection: .blocks, log: log).items
    }

    public func block(id: TrainingBlockID) async throws -> TrainingBlock? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(TrainingBlock.self, from: data)
    }

    public func save(_ block: TrainingBlock) async throws {
        try store.write(key: block.id.rawValue.persistenceKey, data: JSONBlob.encode(block))
    }

    public func delete(id: TrainingBlockID) async throws {
        try store.delete(key: id.rawValue.persistenceKey)
    }
}

// MARK: - WorkoutRepository

/// Implementación persistente de `WorkoutRepository`.
/// Guarda la sesión completa (incluye sus sets) de forma atómica e inmediata.
public final class FileWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allSessions() async throws -> [WorkoutSessionRecord] {
        try await loadAllSessions().items
    }

    public func loadAllSessions() async throws -> RepositoryReadResult<WorkoutSessionRecord> {
        try JSONBlob.decodeAll(WorkoutSessionRecord.self, from: store, collection: .workouts, log: log)
    }

    public func session(id: WorkoutID) async throws -> WorkoutSessionRecord? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(WorkoutSessionRecord.self, from: data)
    }

    public func save(_ session: WorkoutSessionRecord) async throws {
        try persist(session)
    }

    /// Escritura SÍNCRONA y atómica de la sesión (SCRUM-24): el coordinador del workout la
    /// usa para que cada serie esté en disco antes de que la UI avance.
    public func persist(_ session: WorkoutSessionRecord) throws {
        try store.write(key: session.id.rawValue.persistenceKey, data: JSONBlob.encode(session))
    }

    public func delete(id: WorkoutID) async throws {
        try store.delete(key: id.rawValue.persistenceKey)
    }
}

// MARK: - GymRepository

/// Implementación persistente de `GymRepository`.
public final class FileGymRepository: GymRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allGyms() async throws -> [GymProfile] {
        try JSONBlob.decodeAll(GymProfile.self, from: store, collection: .gyms, log: log).items
    }

    public func gym(id: GymID) async throws -> GymProfile? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(GymProfile.self, from: data)
    }

    public func save(_ gym: GymProfile) async throws {
        try store.write(key: gym.id.rawValue.persistenceKey, data: JSONBlob.encode(gym))
    }

    public func delete(id: GymID) async throws {
        try store.delete(key: id.rawValue.persistenceKey)
    }
}

// MARK: - RestrictionRepository

/// Implementación persistente de `RestrictionRepository`.
public final class FileRestrictionRepository: RestrictionRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allRestrictions() async throws -> [TrainingRestriction] {
        try JSONBlob.decodeAll(TrainingRestriction.self, from: store, collection: .restrictions, log: log).items
    }

    public func restriction(id: RestrictionID) async throws -> TrainingRestriction? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(TrainingRestriction.self, from: data)
    }

    public func save(_ restriction: TrainingRestriction) async throws {
        try store.write(key: restriction.id.rawValue.persistenceKey, data: JSONBlob.encode(restriction))
    }

    public func delete(id: RestrictionID) async throws {
        try store.delete(key: id.rawValue.persistenceKey)
    }
}

// MARK: - DecisionRepository

/// Implementación persistente de `DecisionRepository`.
public final class FileDecisionRepository: DecisionRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allDecisions() async throws -> [DecisionRecord] {
        try JSONBlob.decodeAll(DecisionRecord.self, from: store, collection: .decisions, log: log).items
    }

    public func decision(id: DecisionID) async throws -> DecisionRecord? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(DecisionRecord.self, from: data)
    }

    public func save(_ record: DecisionRecord) async throws {
        try store.write(key: record.id.rawValue.persistenceKey, data: JSONBlob.encode(record))
    }
}

// MARK: - AgentAuditRepository (audit trail PR-1607)

/// Implementación persistente (append-only) del audit trail del agente. Cada fila
/// se guarda bajo su propio UUID, de modo que añadir nunca reemplaza ni borra.
/// Los datos retenidos son mínimos (ver `AgentAuditRecord`): sin PII cruda.
public final class FileAgentAuditRepository: AgentAuditRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func allAuditRecords() async throws -> [AgentAuditRecord] {
        try JSONBlob.decodeAll(AgentAuditRecord.self, from: store, collection: .agentAudit, log: log).items
    }

    public func auditRecords(conversationID: UUID) async throws -> [AgentAuditRecord] {
        try await allAuditRecords()
            .filter { $0.conversationID == conversationID }
            .sorted { $0.date < $1.date }
    }

    public func auditRecords(stage: AgentAuditStage) async throws -> [AgentAuditRecord] {
        try await allAuditRecords()
            .filter { $0.stage == stage }
            .sorted { $0.date > $1.date }
    }

    public func save(_ record: AgentAuditRecord) async throws {
        try store.write(key: record.id.persistenceKey, data: JSONBlob.encode(record))
    }

    public func save(contentsOf records: [AgentAuditRecord]) async throws {
        for record in records {
            try await save(record)
        }
    }
}

// MARK: - UserProfileRepository

/// Implementación persistente de `UserProfileRepository` (perfil único).
/// El perfil vive bajo una clave fija, de modo que guardar siempre reemplaza el
/// valor anterior y nunca se duplica.
public final class FileUserProfileRepository: UserProfileRepository, @unchecked Sendable {
    private let store: any RepositoryStore
    private static let scopeKey = "scope.single"

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func loadProfile() async throws -> UserTrainingProfile? {
        guard let data = try store.read(key: Self.scopeKey) else { return nil }
        return try JSONBlob.decode(UserTrainingProfile.self, from: data)
    }

    public func save(_ profile: UserTrainingProfile) async throws {
        try store.write(key: Self.scopeKey, data: JSONBlob.encode(profile))
    }
}
