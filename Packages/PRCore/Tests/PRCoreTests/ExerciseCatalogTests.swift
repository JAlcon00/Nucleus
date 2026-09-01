//
//  ExerciseCatalogTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del catálogo inicial de ejercicios (PR-0301): carga desde el bundle,
//  determinismo de IDs (import idempotente), cobertura de patrones MVP y
//  mapeo de ejercicios conocidos a la ontología PRDomain.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

@Suite("ExerciseCatalog bundle (PR-0301)")
struct ExerciseCatalogBundleTests {
    @Test("Bundled catalog loads and has curated dataset size")
    func bundleLoads() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        // Dataset curado: strength + powerlifting + olympic + strongman.
        #expect(catalog.exercises.count == 678)
        #expect(!catalog.families.isEmpty)
        #expect(catalog.source.license == "Unlicense (public domain)")
        #expect(catalog.source.name == "free-exercise-db")
    }

    @Test("Catalog version is present and source is public-domain")
    func sourceMetadata() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        #expect(!catalog.source.version.isEmpty)
        #expect(catalog.source.url == "https://github.com/yuhonas/free-exercise-db")
    }
}

@Suite("ExerciseCatalog determinism (PR-0301)")
struct ExerciseCatalogDeterminismTests {
    private let sampleJSON = """
    [
      {"id": "Barbell_Bench_Press", "name": "Barbell Bench Press", "force": "push",
       "level": "beginner", "mechanic": "compound", "equipment": "barbell",
       "primaryMuscles": ["chest", "triceps", "shoulders"], "secondaryMuscles": [],
       "category": "strength"},
      {"id": "Romanian_Deadlift", "name": "Romanian Deadlift", "force": "pull",
       "level": "intermediate", "mechanic": "compound", "equipment": "barbell",
       "primaryMuscles": ["hamstrings", "glutes"], "secondaryMuscles": [],
       "category": "strength"}
    ]
    """.data(using: .utf8)!

    @Test("Same dataset maps to same IDs across two loads")
    func deterministicIDs() async throws {
        let a = try ExerciseCatalogLoader.load(from: sampleJSON)
        let b = try ExerciseCatalogLoader.load(from: sampleJSON)
        #expect(a.exercises.count == 2)
        #expect(a.exercises.map(\.id) == b.exercises.map(\.id))
        #expect(a.exercises.map(\.substitutionFamilyID) == b.exercises.map(\.substitutionFamilyID))
    }

    @Test("SeedID is stable per slug and distinct per namespace")
    func seedIDStable() {
        let e1 = SeedID.uuid(namespace: "exercise", slug: "Barbell_Bench_Press")
        let e2 = SeedID.uuid(namespace: "exercise", slug: "Barbell_Bench_Press")
        let f1 = SeedID.uuid(namespace: "family", slug: "horizontalPress")
        #expect(e1 == e2)
        #expect(e1 != f1)
    }

    @Test("Romanian Deadlift maps to hinge pattern and hamstrings")
    func knownMapping() async throws {
        let catalog = try ExerciseCatalogLoader.load(from: sampleJSON)
        let rdl = try #require(catalog.exercises.first { $0.canonicalName == "Romanian Deadlift" })
        #expect(rdl.movementPattern == .hinge)
        #expect(rdl.equipment == .barbell)
        #expect(rdl.jointClass == .multiJoint)
        #expect(rdl.primaryMuscles.first?.muscleGroupID == .hamstrings)
    }

    @Test("Imported exercises reference an existing family")
    func familyReferences() async throws {
        let catalog = try ExerciseCatalogLoader.load(from: sampleJSON)
        let familyIDs = Set(catalog.families.map(\.id))
        for exercise in catalog.exercises {
            #expect(familyIDs.contains(exercise.substitutionFamilyID))
        }
    }
}

@Suite("ExerciseCatalog MVP coverage (PR-0301)")
struct ExerciseCatalogCoverageTests {
    /// Patrones que el split selector y la asignación del MVP deben poder
    /// resolver con ejercicios reales del catálogo.
    private let mvpPatterns: [MovementPattern] = [
        .horizontalPress, .verticalPress, .horizontalPull, .verticalPull,
        .squat, .hinge, .lunge, .kneeExtension, .kneeFlexion, .hipExtension,
        .shoulderAbduction, .shoulderExtension, .elbowFlexion, .elbowExtension,
        .calfPlantarFlexion, .trunkFlexion, .trunkExtension, .trunkRotation,
    ]

    @Test("Every MVP movement pattern has at least one exercise")
    func allMVPPatternsCovered() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let covered = Set(catalog.exercises.map(\.movementPattern))
        for pattern in mvpPatterns {
            #expect(covered.contains(pattern), "Falta cobertura del patrón \(pattern)")
        }
    }

    @Test("Every exercise has a non-empty family and valid fatigue")
    func everyExerciseWellFormed() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        for exercise in catalog.exercises {
            #expect(exercise.canonicalName.isEmpty == false)
            #expect(exercise.primaryMuscles.isEmpty == false)
            #expect((0...1).contains(exercise.systemicFatigueCost.normalized))
            #expect(exercise.localFatigue.values.allSatisfy { (0...1).contains($0.normalized) })
            #expect(!exercise.defaultRoles.isEmpty)
        }
    }

    @Test("Families are one per movement pattern")
    func oneFamilyPerPattern() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let familyPatternCounts = catalog.families.reduce(into: [ExerciseFamily.ID: Int]()) { counts, family in
            counts[family.id, default: 0] += 1
        }
        #expect(familyPatternCounts.values.allSatisfy { $0 == 1 })
    }
}

@Suite("ExerciseCatalogSeeder idempotency (PR-0301)")
struct ExerciseCatalogSeederTests {
    @Test("First seed inserts everything, second seed skips everything")
    func idempotentSeed() async throws {
        let repo = InMemoryExerciseRepository()
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let seeder = ExerciseCatalogSeeder()

        let first = try await seeder.seed(catalogLoader: { catalog }, into: repo)
        #expect(first.inserted == catalog.exercises.count)
        #expect(first.skipped == 0)
        #expect(try await repo.allExercises().count == catalog.exercises.count)

        let second = try await seeder.seed(catalogLoader: { catalog }, into: repo)
        #expect(second.inserted == 0)
        #expect(second.skipped == catalog.exercises.count)
        #expect(try await repo.allExercises().count == catalog.exercises.count)
    }

    @Test("Reseeding into non-empty repo never duplicates")
    func noDuplicatesOnReseed() async throws {
        let repo = InMemoryExerciseRepository()
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let seeder = ExerciseCatalogSeeder()

        _ = try await seeder.seed(catalogLoader: { catalog }, into: repo)
        let all = try await repo.allExercises()
        let distinctIDs = Set(all.map(\.id))
        #expect(distinctIDs.count == all.count)

        let mixed = try await seeder.seed(catalogLoader: { catalog }, into: repo)
        #expect(mixed.inserted == 0)
        #expect(mixed.skipped == catalog.exercises.count)
    }
}