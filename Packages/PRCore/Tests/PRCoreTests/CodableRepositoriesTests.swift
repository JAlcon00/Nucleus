//
//  CodableRepositoriesTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de integración de los adaptadores de persistencia (PR-0202, EPIC-02)
//  contra un `MemoryRepositoryStore`. Verifican round-trip por entidad,
//  relaciones (sets dentro de una sesión), delete policies, perfil único y el
//  save local atómico/autoritativo de una sesión completa.
//
//  Racional: SwiftData no puede vivir en un target de librería SPM (ADR-0001);
//  esta suite valida los contratos de persistencia sobre el almacén codificable.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("FileExerciseRepository persistence (PR-0202)")
struct CodableExerciseRepositoryTests {
    @Test("Round-trips an exercise and lists it")
    func roundTrip() async throws {
        let repo = FileExerciseRepository(store: MemoryRepositoryStore())
        let ex = RepoFixtures.exercise()
        try await repo.save(ex)
        #expect(try await repo.exercise(id: ex.id) == ex)
        #expect(try await repo.allExercises().count == 1)
    }

    @Test("Delete policy removes the exercise")
    func deletePolicy() async throws {
        let repo = FileExerciseRepository(store: MemoryRepositoryStore())
        let ex = RepoFixtures.exercise()
        try await repo.save(ex)
        try await repo.delete(id: ex.id)
        #expect(try await repo.exercise(id: ex.id) == nil)
        #expect(try await repo.allExercises().isEmpty)
    }
}

@Suite("FileTrainingBlockRepository persistence (PR-0202)")
struct CodableTrainingBlockRepositoryTests {
    @Test("Round-trips a training block")
    func roundTrip() async throws {
        let repo = FileTrainingBlockRepository(store: MemoryRepositoryStore())
        let block = RepoFixtures.block()
        try await repo.save(block)
        #expect(try await repo.block(id: block.id) == block)
        #expect(try await repo.allBlocks().count == 1)
    }
}

@Suite("FileWorkoutRepository persistence (PR-0202)")
struct CodableWorkoutRepositoryTests {
    @Test("Round-trips a session including its sets (relationship intact)")
    func roundTripWithSets() async throws {
        let repo = FileWorkoutRepository(store: MemoryRepositoryStore())
        var session = RepoFixtures.session()
        for _ in 0..<3 {
            session = session.performedSet(try SetRecord(
                exerciseID: ExerciseID(),
                weight: 50,
                unit: .kilograms,
                reps: 10,
                rir: 2
            ))
        }
        try await repo.save(session)
        let loaded = try await repo.session(id: session.id)
        #expect(loaded == session)
        #expect(loaded?.sets.count == 3)
    }

    @Test("Save is atomic and authoritative: later save replaces whole session")
    func atomicSaveReplaces() async throws {
        let repo = FileWorkoutRepository(store: MemoryRepositoryStore())
        let empty = RepoFixtures.session()
        try await repo.save(empty)

        var withSets = WorkoutSessionRecord(
            id: empty.id,
            lifecycle: empty.lifecycle
        )
        withSets = withSets.performedSet(try SetRecord(
            exerciseID: ExerciseID(),
            weight: 100,
            unit: .kilograms,
            reps: 5
        ))
        try await repo.save(withSets)

        let loaded = try await repo.session(id: withSets.id)
        #expect(loaded?.id == empty.id)
        #expect(loaded?.sets.count == 1)
        #expect(try await repo.allSessions().count == 1)
    }

    @Test("Delete policy removes the session")
    func deletePolicy() async throws {
        let repo = FileWorkoutRepository(store: MemoryRepositoryStore())
        let session = RepoFixtures.session()
        try await repo.save(session)
        try await repo.delete(id: session.id)
        #expect(try await repo.session(id: session.id) == nil)
    }
}

@Suite("FileGymRepository persistence (PR-0202)")
struct CodableGymRepositoryTests {
    @Test("Round-trips a gym profile")
    func roundTrip() async throws {
        let repo = FileGymRepository(store: MemoryRepositoryStore())
        let gym = RepoFixtures.gym()
        try await repo.save(gym)
        #expect(try await repo.gym(id: gym.id) == gym)
        #expect(try await repo.allGyms().count == 1)
    }
}

@Suite("FileRestrictionRepository persistence (PR-0202)")
struct CodableRestrictionRepositoryTests {
    @Test("Round-trips a restriction")
    func roundTrip() async throws {
        let repo = FileRestrictionRepository(store: MemoryRepositoryStore())
        let restriction = RepoFixtures.restriction()
        try await repo.save(restriction)
        #expect(try await repo.restriction(id: restriction.id) == restriction)
        #expect(try await repo.allRestrictions().count == 1)
    }
}

@Suite("FileDecisionRepository persistence (PR-0202)")
struct CodableDecisionRepositoryTests {
    @Test("Round-trips a decision record")
    func roundTrip() async throws {
        let repo = FileDecisionRepository(store: MemoryRepositoryStore())
        let record = RepoFixtures.decision()
        try await repo.save(record)
        #expect(try await repo.decision(id: record.id) == record)
        #expect(try await repo.allDecisions().count == 1)
    }
}

@Suite("FileAgentAuditRepository persistence (PR-1607)")
struct CodableAgentAuditRepositoryTests {
    @Test("Persists audit rows, append-only, and groups by conversation")
    func roundTripAndGrouping() async throws {
        let repo = FileAgentAuditRepository(store: MemoryRepositoryStore())
        let conversation = UUID()
        let rows = [
            AgentAuditRecord.intent(.setTimeConstraint(.hard(minutes: 30)), conversationID: conversation),
            AgentAuditRecord.result(command: "recomputeSession", conversationID: conversation),
            AgentAuditRecord.needsClarification(conversationID: UUID()),
        ]
        try await repo.save(contentsOf: rows)

        // Append-only: las tres persisten.
        let all = try await repo.allAuditRecords()
        #expect(all.count == 3)

        // Trazabilidad por turno.
        let chain = try await repo.auditRecords(conversationID: conversation)
        #expect(chain.count == 2)
        #expect(chain.contains { $0.intentTag == "setTimeConstraint" })
        #expect(chain.contains { $0.resultCommand == "recomputeSession" })

        // Filtro por etapa.
        let intents = try await repo.auditRecords(stage: .inboundIntent)
        #expect(intents.count == 2)
    }
}

@Suite("FileUserProfileRepository persistence (PR-0202)")
struct CodableUserProfileRepositoryTests {
    @Test("Nil profile before any save")
    func emptyIsNil() async throws {
        let repo = FileUserProfileRepository(store: MemoryRepositoryStore())
        #expect(try await repo.loadProfile() == nil)
    }

    @Test("Profile is a single row: overwrite replaces, never duplicates")
    func singleRowProfile() async throws {
        let repo = FileUserProfileRepository(store: MemoryRepositoryStore())
        let profile = RepoFixtures.profile()
        try await repo.save(profile)
        try await repo.save(profile)
        let loaded = try await repo.loadProfile()
        #expect(loaded == profile)
    }
}

@Suite("AtomicFileRepositoryStore persistence (PR-0202)")
struct AtomicFileRepositoryStoreTests {
    private struct TempDirectory: RepositoryDirectoryProviding {
        let url: URL
        func directoryURL() throws -> URL { url }
    }

    @Test("File-backed store persists a blob across instances")
    func persistsAcrossInstances() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let key = ExerciseID().rawValue.persistenceKey
        let data = try JSONEncoder().encode(RepoFixtures.exercise())

        try AtomicFileRepositoryStore(directoryProvider: TempDirectory(url: dir))
            .write(key: key, data: data)
        let loaded = try AtomicFileRepositoryStore(directoryProvider: TempDirectory(url: dir))
            .read(key: key)

        #expect(loaded == data)
    }
}
