//
//  InMemoryRepositories.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Implementaciones in-memory de los contratos de persistencia (PR-0201)
//  usadas en los tests. No realizan IO real: sirven de fake determinista.
//

import Foundation
import PRCore
import PRDomain

final class InMemoryExerciseRepository: ExerciseRepository, @unchecked Sendable {
    private var store: [ExerciseID: Exercise]

    init(_ seed: [Exercise] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allExercises() async throws -> [Exercise] {
        store.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        store[id]
    }

    func save(_ exercise: Exercise) async throws {
        store[exercise.id] = exercise
    }

    func delete(id: ExerciseID) async throws {
        store[id] = nil
    }
}

final class InMemoryTrainingBlockRepository: TrainingBlockRepository, @unchecked Sendable {
    private var store: [TrainingBlockID: TrainingBlock]

    init(_ seed: [TrainingBlock] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allBlocks() async throws -> [TrainingBlock] {
        store.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func block(id: TrainingBlockID) async throws -> TrainingBlock? {
        store[id]
    }

    func save(_ block: TrainingBlock) async throws {
        store[block.id] = block
    }

    func delete(id: TrainingBlockID) async throws {
        store[id] = nil
    }
}

final class InMemoryWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private var store: [WorkoutID: WorkoutSessionRecord]

    init(_ seed: [WorkoutSessionRecord] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allSessions() async throws -> [WorkoutSessionRecord] {
        store.values.sorted { $0.startedAt < $1.startedAt }
    }

    func session(id: WorkoutID) async throws -> WorkoutSessionRecord? {
        store[id]
    }

    func save(_ session: WorkoutSessionRecord) async throws {
        store[session.id] = session
    }

    func delete(id: WorkoutID) async throws {
        store[id] = nil
    }
}

final class InMemoryGymRepository: GymRepository, @unchecked Sendable {
    private var store: [GymID: GymProfile]

    init(_ seed: [GymProfile] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allGyms() async throws -> [GymProfile] {
        store.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func gym(id: GymID) async throws -> GymProfile? {
        store[id]
    }

    func save(_ gym: GymProfile) async throws {
        store[gym.id] = gym
    }

    func delete(id: GymID) async throws {
        store[id] = nil
    }
}

final class InMemoryRestrictionRepository: RestrictionRepository, @unchecked Sendable {
    private var store: [RestrictionID: TrainingRestriction]

    init(_ seed: [TrainingRestriction] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allRestrictions() async throws -> [TrainingRestriction] {
        store.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func restriction(id: RestrictionID) async throws -> TrainingRestriction? {
        store[id]
    }

    func save(_ restriction: TrainingRestriction) async throws {
        store[restriction.id] = restriction
    }

    func delete(id: RestrictionID) async throws {
        store[id] = nil
    }
}

final class InMemoryDecisionRepository: DecisionRepository, @unchecked Sendable {
    private var store: [DecisionID: DecisionRecord]

    init(_ seed: [DecisionRecord] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allDecisions() async throws -> [DecisionRecord] {
        store.values.sorted { $0.date < $1.date }
    }

    func decision(id: DecisionID) async throws -> DecisionRecord? {
        store[id]
    }

    func save(_ record: DecisionRecord) async throws {
        store[record.id] = record
    }
}

final class InMemoryAgentAuditRepository: AgentAuditRepository, @unchecked Sendable {
    private var store: [UUID: AgentAuditRecord]

    init(_ seed: [AgentAuditRecord] = []) {
        self.store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func allAuditRecords() async throws -> [AgentAuditRecord] {
        store.values.sorted { $0.date < $1.date }
    }

    func auditRecords(conversationID: UUID) async throws -> [AgentAuditRecord] {
        try await allAuditRecords()
            .filter { $0.conversationID == conversationID }
    }

    func auditRecords(stage: AgentAuditStage) async throws -> [AgentAuditRecord] {
        try await allAuditRecords().filter { $0.stage == stage }
    }

    func save(_ record: AgentAuditRecord) async throws {
        store[record.id] = record
    }

    func save(contentsOf records: [AgentAuditRecord]) async throws {
        for record in records {
            try await save(record)
        }
    }
}

final class InMemoryUserProfileRepository: UserProfileRepository, @unchecked Sendable {
    private var profile: UserTrainingProfile?

    init(_ seed: UserTrainingProfile? = nil) {
        self.profile = seed
    }

    func loadProfile() async throws -> UserTrainingProfile? {
        profile
    }

    func save(_ profile: UserTrainingProfile) async throws {
        self.profile = profile
    }
}
