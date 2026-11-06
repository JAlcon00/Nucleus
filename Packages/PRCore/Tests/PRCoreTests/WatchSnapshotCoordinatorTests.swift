//
//  WatchSnapshotCoordinatorTests.swift
//  PRCoreTests
//
//  SCRUM-253 (PR-G002): el estado para el reloj sale de la sesión viva, con `LocalPersistence`
//  real en un directorio temporal: lo que ve el reloj es lo que pide la pantalla del iPhone,
//  también después de saltar, sustituir y reabrir la app.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func press(_ name: String) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: .horizontalPress,
        primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
        equipment: .machine,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [.primaryCompound],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [.horizontalPress]).id
    )
}

private struct Chest {
    let a: Exercise
    let b: Exercise
    let c: Exercise
    let gym = GymID()
    let root: URL

    init() throws {
        a = try press("Press A")
        b = try press("Press B")
        c = try press("Press C")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var catalog: [Exercise] { [a, b, c] }
    var names: [ExerciseID: String] { Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.canonicalName) }) }

    func template(_ exercises: [Exercise]) throws -> SessionTemplate {
        let work = try SetPrescription(targetRepRange: 8...10, loadUnit: .kilograms, restSeconds: 60...60)
        return SessionTemplate(title: "Pecho", plannedSets: exercises.flatMap { exercise in
            [exercise, exercise].map { PlannedSet(exerciseID: $0.id, prescription: work) }
        })
    }

    @MainActor
    func coordinator(_ template: SessionTemplate, restoring: WorkoutSessionRecord? = nil) async throws -> WorkoutSessionCoordinator {
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        return try await persistence.makeWorkoutCoordinator(
            template: template, exerciseNames: names, catalog: catalog, gymID: gym, clock: { now }, restoring: restoring
        )
    }
}

@MainActor
@Suite("SCRUM-253 · El estado para el reloj sale de la sesión viva")
struct WatchSnapshotCoordinatorTests {

    @Test("Sin sesión no hay estado; al empezar, la primera serie es la de la pantalla")
    func startsWithCurrentSet() async throws {
        let chest = try Chest()
        let plan = try chest.template([chest.a])
        let coordinator = try await chest.coordinator(plan)
        #expect(coordinator.watchSnapshot() == nil)
        _ = coordinator.start()
        let snapshot = try #require(coordinator.watchSnapshot())
        #expect(snapshot.remaining.first?.exerciseName == coordinator.currentSet()?.exerciseName)
        #expect(snapshot.stage == .active)
    }

    @Test("La serie hecha sale de lo que falta, queda confirmada y trae el peso real")
    func afterCompletingASet() async throws {
        let chest = try Chest()
        let coordinator = try await chest.coordinator(try chest.template([chest.a]))
        _ = coordinator.start()
        _ = try coordinator.recordEditedSet(weight: 60, reps: 9)
        let snapshot = try #require(coordinator.watchSnapshot())
        #expect(snapshot.remaining.count == 1)
        #expect(snapshot.confirmedSetIDs.count == 1)
        #expect(snapshot.remaining.first?.weight == 60)
        #expect(snapshot.restEndsAt != nil)
    }

    @Test("En pausa y al terminar, el reloj lo sabe")
    func stages() async throws {
        let chest = try Chest()
        let coordinator = try await chest.coordinator(try chest.template([chest.a]))
        _ = coordinator.start()
        _ = try coordinator.pause()
        #expect(coordinator.watchSnapshot()?.stage == .paused)
        _ = try coordinator.resume()
        _ = try coordinator.complete()
        #expect(coordinator.watchSnapshot()?.stage == .finished)
        #expect(coordinator.watchSnapshot()?.remaining.isEmpty == true)
    }

    @Test("Saltar, sustituir y reabrir la app: el reloj sigue viendo lo mismo que el iPhone")
    func skipSubstituteAndReopen() async throws {
        let chest = try Chest()
        let plan = try chest.template([chest.a])
        let coordinator = try await chest.coordinator(plan)
        _ = coordinator.start()
        _ = try coordinator.recordEditedSet(weight: 60, reps: 9)
        guard case .needsChoice(let choice) = try coordinator.markCurrentExerciseOccupied(),
              let option = choice.options.first else {
            Issue.record("Se esperaba elegir un sustituto")
            return
        }
        _ = try coordinator.substituteCurrentExercise(with: option.id)
        let live = try #require(coordinator.watchSnapshot())
        #expect(live.remaining.first?.exerciseName == option.name)
        #expect(live.remaining.first?.weight == nil, "Ninguna carga se transfiere (RN-007).")

        let record = try coordinator.snapshot().session
        let reopened = try await chest.coordinator(try #require(record.template), restoring: record)
        let restored = try #require(reopened.watchSnapshot())
        #expect(restored.remaining == live.remaining)
        #expect(restored.confirmedSetIDs == live.confirmedSetIDs)
    }

    @Test("Saltar un ejercicio lo saca del reloj")
    func skipRemovesExercise() async throws {
        let chest = try Chest()
        let coordinator = try await chest.coordinator(try chest.template([chest.a, chest.b]))
        _ = coordinator.start()
        _ = try coordinator.skipCurrentExercise()
        let snapshot = try #require(coordinator.watchSnapshot())
        #expect(snapshot.remaining.map(\.exerciseName) == ["Press B", "Press B"])
        #expect(snapshot.remaining.first?.exerciseName == coordinator.currentSet()?.exerciseName)
    }
}
