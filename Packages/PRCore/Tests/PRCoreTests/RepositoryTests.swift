//
//  RepositoryTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de los contratos de persistencia (PR-0201) contra fakes in-memory.
//  PRCore no importa SwiftData; estas pruebas validan los contratos async.
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Fixtures mínimos reutilizables por los tests de repositorios.
enum RepoFixtures {
    static func exercise(name: String = "Dumbbell Bench Press") -> Exercise {
        let family = ExerciseFamily(name: "Horizontal Press", movementPatterns: [.horizontalPress])
        return Exercise(
            canonicalName: name,
            movementPattern: .horizontalPress,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
            equipment: .dumbbell,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [.anchor],
            substitutionFamilyID: family.id
        )
    }

    static func block() -> TrainingBlock {
        try! TrainingBlock(
            name: "Hypertrophy Block",
            goal: .hypertrophy,
            phase: .surplus,
            plannedWeeks: 6,
            progressionPolicy: .doubleProgression,
            deloadPolicy: .afterSixWeeks,
            varietyPolicy: try! VarietyPolicy(percentStable: 0.8)
        )
    }

    static func session() -> WorkoutSessionRecord {
        WorkoutSessionRecord(lifecycle: .completed)
    }

    static func gym() -> GymProfile {
        GymProfile(name: "Main Gym")
    }

    static func restriction() -> TrainingRestriction {
        TrainingRestriction(bodyRegion: .shoulder, forbiddenPatterns: [.verticalPress])
    }

    static func decision() -> DecisionRecord {
        DecisionRecord(
            type: .loadChange,
            action: DecisionActionSummary(title: "Subir carga", detail: "2.5kg"),
            ruleReferences: []
        )
    }

    static func profile() -> UserTrainingProfile {
        try! UserTrainingProfile(
            experience: .intermediate,
            goal: .hypertrophy,
            phase: .surplus,
            trainingDaysPerWeek: 4,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            coachingDetail: .balanced
        )
    }
}

@Suite("ExerciseRepository contracts (PR-0201)")
struct ExerciseRepositoryTests {
    @Test("Save then fetch by id and list all")
    func saveAndFetch() async throws {
        let repo = InMemoryExerciseRepository()
        let ex = RepoFixtures.exercise(name: "Squat")
        try await repo.save(ex)
        let fetched = try await repo.exercise(id: ex.id)
        #expect(fetched == ex)
        #expect(try await repo.allExercises().count == 1)
    }

    @Test("Delete removes the exercise")
    func deleteRemoves() async throws {
        let ex = RepoFixtures.exercise()
        let repo = InMemoryExerciseRepository([ex])
        try await repo.delete(id: ex.id)
        #expect(try await repo.exercise(id: ex.id) == nil)
        #expect(try await repo.allExercises().isEmpty)
    }
}

@Suite("TrainingBlockRepository contracts (PR-0201)")
struct TrainingBlockRepositoryTests {
    @Test("Save then fetch block by id")
    func saveAndFetch() async throws {
        let repo = InMemoryTrainingBlockRepository()
        let block = RepoFixtures.block()
        try await repo.save(block)
        #expect(try await repo.block(id: block.id) == block)
    }

    @Test("Deleting a block removes it")
    func deleteRemoves() async throws {
        let block = RepoFixtures.block()
        let repo = InMemoryTrainingBlockRepository([block])
        try await repo.delete(id: block.id)
        #expect(try await repo.block(id: block.id) == nil)
    }
}

@Suite("WorkoutRepository contracts (PR-0201)")
struct WorkoutRepositoryTests {
    @Test("Save and load workout session")
    func saveAndLoad() async throws {
        let repo = InMemoryWorkoutRepository()
        let session = RepoFixtures.session()
        try await repo.save(session)
        #expect(try await repo.session(id: session.id) == session)
    }

    @Test("Delete removes session")
    func deleteRemoves() async throws {
        let session = RepoFixtures.session()
        let repo = InMemoryWorkoutRepository([session])
        try await repo.delete(id: session.id)
        #expect(try await repo.session(id: session.id) == nil)
    }
}

@Suite("GymRepository contracts (PR-0201)")
struct GymRepositoryTests {
    @Test("Save and fetch gym")
    func saveAndFetch() async throws {
        let repo = InMemoryGymRepository()
        let gym = RepoFixtures.gym()
        try await repo.save(gym)
        #expect(try await repo.gym(id: gym.id) == gym)
    }
}

@Suite("RestrictionRepository contracts (PR-0201)")
struct RestrictionRepositoryTests {
    @Test("Save and fetch restriction")
    func saveAndFetch() async throws {
        let repo = InMemoryRestrictionRepository()
        let restriction = RepoFixtures.restriction()
        try await repo.save(restriction)
        #expect(try await repo.restriction(id: restriction.id) == restriction)
    }
}

@Suite("DecisionRepository contracts (PR-0201)")
struct DecisionRepositoryTests {
    @Test("Save and fetch decision record")
    func saveAndFetch() async throws {
        let repo = InMemoryDecisionRepository()
        let record = RepoFixtures.decision()
        try await repo.save(record)
        #expect(try await repo.decision(id: record.id) == record)
        #expect(try await repo.allDecisions().count == 1)
    }
}

@Suite("UserProfileRepository contracts (PR-0201)")
struct UserProfileRepositoryTests {
    @Test("Nil profile before any save")
    func emptyIsNil() async throws {
        let repo = InMemoryUserProfileRepository()
        #expect(try await repo.loadProfile() == nil)
    }

    @Test("Save then load returns the profile")
    func saveThenLoad() async throws {
        let repo = InMemoryUserProfileRepository()
        let profile = RepoFixtures.profile()
        try await repo.save(profile)
        #expect(try await repo.loadProfile() == profile)
    }

    @Test("Overwrite replaces the profile")
    func overwrite() async throws {
        let repo = InMemoryUserProfileRepository(RepoFixtures.profile())
        let updated = RepoFixtures.profile()
        try await repo.save(updated)
        #expect(try await repo.loadProfile() == updated)
    }
}
