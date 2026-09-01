//
//  PersistenceContracts.swift
//  PRCore
//
//  Created by PR.
//
//  Contratos de repositorio (PR-0201, EPIC-02).
//  PRCore NO importa SwiftData ni ningún framework de persistencia: estos
//  protocolos son la frontera que las implementaciones concretas satisfacen.
//  Las APIs son async cuando existe IO para no bloquear la UI.
//

import Foundation
import PRDomain

/// Repositorio de ejercicios del catálogo.
public protocol ExerciseRepository: Sendable {
    func allExercises() async throws -> [Exercise]
    func exercise(id: ExerciseID) async throws -> Exercise?
    func save(_ exercise: Exercise) async throws
    func delete(id: ExerciseID) async throws
}

/// Repositorio de bloques de entrenamiento.
public protocol TrainingBlockRepository: Sendable {
    func allBlocks() async throws -> [TrainingBlock]
    func block(id: TrainingBlockID) async throws -> TrainingBlock?
    func save(_ block: TrainingBlock) async throws
    func delete(id: TrainingBlockID) async throws
}

/// Repositorio de sesiones de workout (ejecutadas y planificadas).
public protocol WorkoutRepository: Sendable {
    func allSessions() async throws -> [WorkoutSessionRecord]
    func session(id: WorkoutID) async throws -> WorkoutSessionRecord?
    func save(_ session: WorkoutSessionRecord) async throws
    func delete(id: WorkoutID) async throws
}

/// Repositorio de gyms.
public protocol GymRepository: Sendable {
    func allGyms() async throws -> [GymProfile]
    func gym(id: GymID) async throws -> GymProfile?
    func save(_ gym: GymProfile) async throws
    func delete(id: GymID) async throws
}

/// Repositorio de restricciones de entrenamiento.
public protocol RestrictionRepository: Sendable {
    func allRestrictions() async throws -> [TrainingRestriction]
    func restriction(id: RestrictionID) async throws -> TrainingRestriction?
    func save(_ restriction: TrainingRestriction) async throws
    func delete(id: RestrictionID) async throws
}

/// Repositorio de registros de decisión (explainability).
public protocol DecisionRepository: Sendable {
    func allDecisions() async throws -> [DecisionRecord]
    func decision(id: DecisionID) async throws -> DecisionRecord?
    func save(_ record: DecisionRecord) async throws
}

/// Repositorio del perfil del usuario (single source of truth del perfil).
public protocol UserProfileRepository: Sendable {
    func loadProfile() async throws -> UserTrainingProfile?
    func save(_ profile: UserTrainingProfile) async throws
}
