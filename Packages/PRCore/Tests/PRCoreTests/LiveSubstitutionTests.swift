//
//  LiveSubstitutionTests.swift
//  PRCoreTests
//
//  SCRUM-234 (PR-E003): sin nada que adelantar, "Máquina ocupada" ofrece sustitutos de
//  PR-E001. Lo pendiente pasa a B, lo hecho se queda como A, ninguna carga se transfiere y
//  todo sobrevive a un cierre forzado (`LocalPersistence` real en un directorio temporal).
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func press(_ name: String, primary: [MuscleGroup] = [.chest]) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: .horizontalPress,
        primaryMuscles: try primary.map { try MuscleContribution(muscleGroupID: $0, activation: 1.0) },
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

    init() throws {
        a = try press("Press A")
        b = try press("Press B")
        c = try press("Press C")
    }

    var catalog: [Exercise] { [a, b, c] }
    var names: [ExerciseID: String] { Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.canonicalName) }) }
}

/// Sólo `exercise`, con un calentamiento y 3 series de trabajo con carga planeada.
private func template(_ exercise: Exercise) throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 80, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false)
    let warmup = try SetPrescription(targetRepRange: 8...10, targetLoad: 40, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: true)
    return SessionTemplate(title: "Pecho", plannedSets: [warmup, work, work, work].map { PlannedSet(exerciseID: exercise.id, prescription: $0) })
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func make(
    _ plan: SessionTemplate, _ chest: Chest, root: URL, restrictions: [TrainingRestriction] = []
) async throws -> WorkoutSessionCoordinator {
    let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
    return try await persistence.makeWorkoutCoordinator(
        template: plan, exerciseNames: chest.names, catalog: chest.catalog, restrictions: restrictions, clock: { now }
    )
}

@MainActor
private func choice(_ coordinator: WorkoutSessionCoordinator) throws -> OccupiedChoice {
    guard case .needsChoice(let choice) = try coordinator.markCurrentExerciseOccupied() else {
        throw WorkoutSessionError.invalidTransition
    }
    return choice
}

@MainActor
private func exercise(of coordinator: WorkoutSessionCoordinator) -> ExerciseID? {
    coordinator.currentSet().map { coordinator.template.plannedSets[$0.index].exerciseID }
}

@MainActor
@Suite("SCRUM-234 · Cambiar por un sustituto equivalente durante el entrenamiento")
struct LiveSubstitutionTests {

    @Test("La hoja ofrece hasta 3 sustitutos, con su razón, y nada cambia hasta elegir")
    func offersSubstitutes() async throws {
        let chest = try Chest()
        let plan = try template(chest.a)
        let coordinator = try await make(plan, chest, root: try makeRoot())
        _ = coordinator.start()

        let offered = try choice(coordinator)

        #expect(offered.options.map(\.name) == ["Press B", "Press C"])
        #expect(offered.options.allSatisfy { $0.sameMuscles })
        #expect(offered.isOnlyExercise)
        #expect(coordinator.template == plan, "Abrir la hoja no cambia nada")
    }

    @Test("Lo pendiente pasa a B, lo hecho se queda como A y el total no cambia")
    func pendingMovesDoneStays() async throws {
        let chest = try Chest()
        let plan = try template(chest.a)
        let coordinator = try await make(plan, chest, root: try makeRoot())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.recordEditedSet(weight: 80, reps: 10)
        let done = try coordinator.snapshot().session.sets
        let total = coordinator.currentSet()?.total

        try coordinator.substituteCurrentExercise(with: chest.b.id)

        #expect(try coordinator.snapshot().session.sets == done, "Las hechas no cambian")
        #expect(done.allSatisfy { $0.exerciseID == chest.a.id })
        #expect(exercise(of: coordinator) == chest.b.id, "La siguiente serie es de B")
        #expect(coordinator.currentSet()?.total == total)
        #expect(coordinator.template.plannedSets.map(\.exerciseID) == [chest.a.id, chest.a.id, chest.b.id, chest.b.id])
    }

    @Test("El peso de B nunca es el de A: queda vacío para escribirlo")
    func loadIsNotTransferred() async throws {
        let chest = try Chest()
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot())
        _ = coordinator.start()

        try coordinator.substituteCurrentExercise(with: chest.b.id)

        #expect(coordinator.template.plannedSets.allSatisfy { $0.prescription.targetLoad == nil })
        let draft = try #require(coordinator.currentSet()).draft
        #expect(draft.targetWeight == 0)
        #expect(!draft.weightFromHistory)
    }

    @Test("Los calentamientos pendientes pasan a B como calentamientos")
    func warmupsStayWarmups() async throws {
        let chest = try Chest()
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot())
        _ = coordinator.start()

        try coordinator.substituteCurrentExercise(with: chest.b.id)

        #expect(coordinator.template.plannedSets.map(\.prescription.isWarmup) == [true, false, false, false])
        #expect(coordinator.currentSet()?.isWarmup == true)
    }

    @Test("Con restricciones no aparece nada prohibido; sin sustitutos, la hoja lo dice")
    func restrictionsApply() async throws {
        let chest = try Chest()
        let restriction = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [chest.b.id])
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot(), restrictions: [restriction])
        _ = coordinator.start()
        #expect(try choice(coordinator).options.map(\.name) == ["Press C"])
        #expect(throws: WorkoutSessionError.self) { try coordinator.substituteCurrentExercise(with: chest.b.id) }

        let all = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [chest.b.id, chest.c.id])
        let blocked = try await make(try template(chest.a), chest, root: try makeRoot(), restrictions: [all])
        _ = blocked.start()
        #expect(try choice(blocked).options.isEmpty)
    }

    @Test("Con dolor moderado o alto en esta sesión no se ofrecen sustitutos", arguments: [PainLevel.moderate, .high])
    func painBlocksSubstitutes(level: PainLevel) async throws {
        let chest = try Chest()
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.reportPain(level)

        let offered = try choice(coordinator)

        #expect(offered.options.isEmpty)
        #expect(offered.painRecommendation != nil)
        #expect(throws: WorkoutSessionError.self) { try coordinator.substituteCurrentExercise(with: chest.b.id) }
    }

    @Test("Tras un cierre forzado se sigue con B y lo hecho de A sigue ahí")
    func survivesForceQuit() async throws {
        let chest = try Chest()
        let root = try makeRoot()
        let plan = try template(chest.a)
        let coordinator = try await make(plan, chest, root: root)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.substituteCurrentExercise(with: chest.b.id)
        let sets = try coordinator.snapshot().session.sets

        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let recovered) = try await persistence.recoverWorkout(
            templates: [plan], exerciseNames: chest.names, catalog: chest.catalog, clock: { now }
        ) else {
            Issue.record("Debe retomarse"); return
        }

        #expect(exercise(of: recovered) == chest.b.id)
        #expect(try recovered.snapshot().session.sets == sets)
    }

    @Test("Otro día toca A: la sustitución es sólo de hoy")
    func nextDayIsTheOriginal() async throws {
        let chest = try Chest()
        let root = try makeRoot()
        let plan = try template(chest.a)
        let first = try await make(plan, chest, root: root)
        _ = first.start()
        try first.substituteCurrentExercise(with: chest.b.id)
        try first.abandon()

        let next = try await make(plan, chest, root: root)
        _ = next.start()
        #expect(exercise(of: next) == chest.a.id)
    }

    @Test("La sesión guarda los hechos y el resumen y el export dicen A → B")
    func factsAndSummary() async throws {
        let chest = try Chest()
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot())
        _ = coordinator.start()
        try coordinator.substituteCurrentExercise(with: chest.b.id)
        _ = try coordinator.completeCurrentSet()

        let session = try coordinator.snapshot().session
        let fact = try #require(session.substitutions?.first)
        #expect(fact.original == chest.a.id)
        #expect(fact.replacement == chest.b.id)
        #expect(fact.reason == .occupied)
        #expect(fact.score >= 0.60)
        let rule = try EvidenceRuleReference(SubstitutionScoringDefaults.makeRule())
        #expect(fact.rule == rule)
        #expect(coordinator.substitutionSummaries.map(\.to) == ["Press B"])
        #expect(session.sets.last?.exerciseID == chest.b.id, "Las series de B salen como B")

        let file = try DataExportCoordinator().exportJSON(
            sessions: [session], exercises: chest.catalog, blocks: [], gyms: [], restrictions: [], profile: nil, exportedAt: now
        )
        #expect(String(decoding: file.data, as: UTF8.self).contains("substitutions"))
    }

    @Test("En cadena, A → B → C, no se pierde ninguna serie")
    func chain() async throws {
        let chest = try Chest()
        let coordinator = try await make(try template(chest.a), chest, root: try makeRoot())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.substituteCurrentExercise(with: chest.b.id)
        _ = try coordinator.recordEditedSet(weight: 50, reps: 10)
        try coordinator.skipRestIfNeeded()

        let offered = try choice(coordinator)
        #expect(!offered.options.contains { $0.name == "Press A" }, "A sigue ocupado y ya está en la sesión")
        try coordinator.substituteCurrentExercise(with: chest.c.id)

        #expect(exercise(of: coordinator) == chest.c.id)
        #expect(coordinator.template.plannedSets.map(\.exerciseID) == [chest.a.id, chest.b.id, chest.c.id, chest.c.id])
        #expect(try coordinator.snapshot().session.sets.count == 2)
    }

    @Test("Un superset se separa: el sustituto va solo y la pareja sigue")
    func supersetSplits() async throws {
        let chest = try Chest()
        let back = try press("Remo", primary: [.back])
        let work = try SetPrescription(targetRepRange: 8...10, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false)
        let plan = SessionTemplate(
            title: "Torso",
            plannedSets: [chest.a, back, chest.a, back].map { PlannedSet(exerciseID: $0.id, prescription: work) },
            supersets: [try #require(SupersetPair(first: chest.a.id, second: back.id))]
        )
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let coordinator = try await persistence.makeWorkoutCoordinator(
            template: plan, exerciseNames: chest.names, catalog: chest.catalog + [back], clock: { now }
        )
        _ = coordinator.start()

        try coordinator.substituteCurrentExercise(with: chest.b.id)

        #expect(exercise(of: coordinator) == chest.b.id)
        #expect(coordinator.currentSet()?.superset == nil)
    }

    @Test("Las sesiones guardadas antes se leen igual, sin el campo nuevo")
    func oldSessionsDecode() throws {
        let saved = try JSONEncoder().encode(WorkoutSessionRecord(startedAt: now))
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: saved)
        #expect(decoded.substitutions == nil)
        #expect(!String(decoding: saved, as: UTF8.self).contains("substitutions"))
    }
}

private extension WorkoutSessionCoordinator {
    func skipRestIfNeeded() throws {
        if case .resting = phase { skipRest() }
    }
}
