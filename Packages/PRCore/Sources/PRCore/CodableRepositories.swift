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
}

// MARK: - ExerciseRepository

/// Implementación persistente de `ExerciseRepository`.
public final class FileExerciseRepository: ExerciseRepository, @unchecked Sendable {
    private let store: any RepositoryStore

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allExercises() async throws -> [Exercise] {
        try store.readAll().map { try JSONBlob.decode(Exercise.self, from: $0) }
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

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allBlocks() async throws -> [TrainingBlock] {
        try store.readAll().map { try JSONBlob.decode(TrainingBlock.self, from: $0) }
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

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allSessions() async throws -> [WorkoutSessionRecord] {
        try store.readAll().map { try JSONBlob.decode(WorkoutSessionRecord.self, from: $0) }
    }

    public func session(id: WorkoutID) async throws -> WorkoutSessionRecord? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(WorkoutSessionRecord.self, from: data)
    }

    public func save(_ session: WorkoutSessionRecord) async throws {
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

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allGyms() async throws -> [GymProfile] {
        try store.readAll().map { try JSONBlob.decode(GymProfile.self, from: $0) }
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

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allRestrictions() async throws -> [TrainingRestriction] {
        try store.readAll().map { try JSONBlob.decode(TrainingRestriction.self, from: $0) }
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

    public init(store: some RepositoryStore) {
        self.store = store
    }

    public func allDecisions() async throws -> [DecisionRecord] {
        try store.readAll().map { try JSONBlob.decode(DecisionRecord.self, from: $0) }
    }

    public func decision(id: DecisionID) async throws -> DecisionRecord? {
        guard let data = try store.read(key: id.rawValue.persistenceKey) else { return nil }
        return try JSONBlob.decode(DecisionRecord.self, from: data)
    }

    public func save(_ record: DecisionRecord) async throws {
        try store.write(key: record.id.rawValue.persistenceKey, data: JSONBlob.encode(record))
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
