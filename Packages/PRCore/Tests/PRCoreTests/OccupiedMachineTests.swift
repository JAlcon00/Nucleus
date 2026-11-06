//
//  OccupiedMachineTests.swift
//  PRCoreTests
//
//  SCRUM-233 (PR-E002): "Máquina ocupada" adelanta otro ejercicio sin cansar antes lo
//  prioritario. Las series hechas no cambian, el orden sobrevive a un cierre forzado
//  (`LocalPersistence` real en un directorio temporal) y la ocupación sólo vive en la sesión.
//

import Foundation
import Testing
import PRCore
import PRDomain

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_792_670_400)
    var now: Date { lock.withLock { current } }
}

private func exercise(
    _ name: String, equipment: EquipmentType, primary: MuscleGroup, secondary: [MuscleGroup] = [],
    role: ExerciseRole, local: [MuscleGroup: Double]
) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: .horizontalPress,
        primaryMuscles: [try MuscleContribution(muscleGroupID: primary, activation: 1.0)],
        secondaryMuscles: try secondary.map { try MuscleContribution(muscleGroupID: $0, activation: 0.6) },
        equipment: equipment,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        localFatigue: try local.mapValues { try FatigueCost(normalized: $0) },
        loadability: .discreteIncrements,
        defaultRoles: [role],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [.horizontalPress]).id
    )
}

private struct Gym {
    let bench: Exercise
    let chestMachine: Exercise
    let pushdown: Exercise

    init() throws {
        bench = try exercise(
            "Press de banca", equipment: .barbell, primary: .chest, secondary: [.triceps],
            role: .primaryCompound, local: [.chest: 0.7, .triceps: 0.5]
        )
        chestMachine = try exercise(
            "Press en máquina", equipment: .machine, primary: .chest, secondary: [.triceps], role: .primaryCompound, local: [:]
        )
        pushdown = try exercise(
            "Extensión en polea", equipment: .cable, primary: .triceps, role: .accessoryIsolation, local: [.triceps: 0.8]
        )
    }

    var catalog: [Exercise] { [bench, chestMachine, pushdown] }
    var names: [ExerciseID: String] { Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.canonicalName) }) }
}

private func template(_ exercises: [Exercise], pair: (Exercise, Exercise)? = nil) throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 50, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false)
    return SessionTemplate(
        title: "Pecho",
        plannedSets: exercises.flatMap { exercise in
            Array(repeating: PlannedSet(exerciseID: exercise.id, prescription: work), count: 2)
        },
        supersets: try pair.map { [try #require(SupersetPair(first: $0.0.id, second: $0.1.id))] }
    )
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-occupied-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func current(_ coordinator: WorkoutSessionCoordinator) -> ExerciseID? {
    coordinator.currentSet().map { coordinator.template.plannedSets[$0.index].exerciseID }
}

@MainActor
private func make(_ plan: SessionTemplate, _ gym: Gym, root: URL, clock: TestClock = TestClock()) async throws -> WorkoutSessionCoordinator {
    let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
    return try await persistence.makeWorkoutCoordinator(
        template: plan, exerciseNames: gym.names, catalog: gym.catalog, clock: { clock.now }
    )
}

@MainActor
@Suite("SCRUM-233 · Máquina ocupada: la app adelanta otro ejercicio sin romper la sesión")
struct OccupiedMachineTests {

    @Test("Con adelanto seguro, el otro pasa a ser el actual y el ocupado va justo después")
    func safeAdvance() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench, gym.chestMachine, gym.pushdown]), gym, root: try makeRoot())
        _ = coordinator.start()

        let outcome = try coordinator.markCurrentExerciseOccupied()

        #expect(outcome == .advanced(next: "Press en máquina", after: "Press de banca"))
        #expect(coordinator.occupiedNotice == outcome)
        #expect(current(coordinator) == gym.chestMachine.id)
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.skipRestIfNeeded()
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.skipRestIfNeeded()
        #expect(current(coordinator) == gym.bench.id, "El ocupado queda justo después")
        #expect(coordinator.occupiedNotice == nil, "El aviso se va al seguir entrenando")
    }

    @Test("Sin adelanto seguro va al final y lo dice: el tríceps no se adelanta al press")
    func noSafeAdvance() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench, gym.pushdown]), gym, root: try makeRoot())
        _ = coordinator.start()

        // SCRUM-234: primero pregunta y nada cambia; "Esperar" lo manda al final.
        guard case .needsChoice = try coordinator.markCurrentExerciseOccupied() else {
            Issue.record("Sin adelanto seguro debe preguntar"); return
        }
        #expect(current(coordinator) == gym.bench.id)
        #expect(try coordinator.waitForOccupiedExercise() == .movedToEnd(exercise: "Press de banca"))
        #expect(current(coordinator) == gym.pushdown.id)
    }

    @Test("Si es lo único que queda no cambia nada")
    func onlyExercise() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench]), gym, root: try makeRoot())
        _ = coordinator.start()

        guard case .needsChoice(let choice) = try coordinator.markCurrentExerciseOccupied() else {
            Issue.record("Debe ofrecer esperar o saltar"); return
        }
        #expect(choice.isOnlyExercise)
        #expect(current(coordinator) == gym.bench.id)
        #expect(try coordinator.snapshot().session.queue == nil, "No se guardó ningún cambio")
    }

    @Test("Las series hechas no cambian, el descanso sigue y no se crea ninguna serie")
    func setsAndRestAreIntact() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench, gym.chestMachine]), gym, root: try makeRoot())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        let before = try coordinator.snapshot().session.sets
        guard case .resting = coordinator.phase else { Issue.record("Debe estar descansando"); return }

        try coordinator.markCurrentExerciseOccupied()

        #expect(try coordinator.snapshot().session.sets == before)
        guard case .resting = coordinator.phase else { Issue.record("El descanso sigue"); return }
    }

    @Test("La ocupación no pasa a otra sesión: la siguiente sale en su orden normal")
    func occupancyIsOnlyForThisSession() async throws {
        let gym = try Gym()
        let root = try makeRoot()
        let plan = try template([gym.bench, gym.chestMachine])
        let first = try await make(plan, gym, root: root)
        _ = first.start()
        try first.markCurrentExerciseOccupied()
        try first.abandon()

        let next = try await make(plan, gym, root: root)
        _ = next.start()
        #expect(current(next) == gym.bench.id)
    }

    @Test("En superset el par se separa y su pareja sigue sola")
    func supersetSplits() async throws {
        let gym = try Gym()
        let plan = try template([gym.bench, gym.pushdown], pair: (gym.bench, gym.pushdown))
        let coordinator = try await make(plan, gym, root: try makeRoot())
        _ = coordinator.start()
        #expect(coordinator.currentSet()?.superset != nil)

        try coordinator.markCurrentExerciseOccupied()
        try coordinator.waitForOccupiedExercise()

        #expect(current(coordinator) == gym.pushdown.id)
        #expect(coordinator.currentSet()?.superset == nil, "Ya no va en par")
    }

    @Test("Tras un cierre forzado la sesión sigue en el mismo orden y con las mismas series")
    func survivesForceQuit() async throws {
        let gym = try Gym()
        let root = try makeRoot()
        let clock = TestClock()
        let plan = try template([gym.bench, gym.chestMachine, gym.pushdown])
        let coordinator = try await make(plan, gym, root: root, clock: clock)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.markCurrentExerciseOccupied()
        let sets = try coordinator.snapshot().session.sets

        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let recovered) = try await persistence.recoverWorkout(
            templates: [plan], exerciseNames: gym.names, catalog: gym.catalog, clock: { clock.now }
        ) else {
            Issue.record("Debe retomarse"); return
        }

        #expect(current(recovered) == gym.chestMachine.id)
        #expect(try recovered.snapshot().session.sets == sets)
    }

    @Test("En pausa no está disponible")
    func notWhilePaused() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench, gym.chestMachine]), gym, root: try makeRoot())
        _ = coordinator.start()
        _ = try coordinator.pause()

        #expect(throws: WorkoutSessionError.self) { try coordinator.markCurrentExerciseOccupied() }
    }

    @Test("Dos ocupadas seguidas: lo ya ocupado no se vuelve a adelantar")
    func twoInARow() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.bench, gym.chestMachine, gym.pushdown]), gym, root: try makeRoot())
        _ = coordinator.start()

        try coordinator.markCurrentExerciseOccupied()     // la máquina pasa adelante del press
        let second = try coordinator.markCurrentExerciseOccupied()

        if case .advanced(let next, _) = second { #expect(next != "Press de banca", "El press también está ocupado") }
        if case .needsChoice = second { try coordinator.waitForOccupiedExercise() }
        #expect(current(coordinator) != gym.chestMachine.id)
        #expect(try coordinator.snapshot().session.sets.isEmpty)
    }

    @Test("Un saltado no cuenta como candidato")
    func skippedIsNotACandidate() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.chestMachine, gym.bench]), gym, root: try makeRoot())
        _ = coordinator.start()
        try coordinator.skipCurrentExercise()             // la máquina queda saltada: toca el press

        guard case .needsChoice(let choice) = try coordinator.markCurrentExerciseOccupied() else {
            Issue.record("El saltado no se adelanta"); return
        }
        #expect(choice.isOnlyExercise)
    }

    @Test("Un ejercicio ya diferido se puede adelantar y queda antes del ocupado")
    func deferredCandidate() async throws {
        let gym = try Gym()
        let coordinator = try await make(try template([gym.chestMachine, gym.bench, gym.pushdown]), gym, root: try makeRoot())
        _ = coordinator.start()
        try coordinator.deferCurrentExercise()            // la máquina al final: toca el press

        #expect(try coordinator.markCurrentExerciseOccupied() == .advanced(next: "Press en máquina", after: "Press de banca"))
        #expect(current(coordinator) == gym.chestMachine.id)
    }

    @Test("Una sesión guardada sin los campos nuevos se lee igual")
    func oldQueueDecodes() throws {
        let saved = try JSONEncoder().encode(ExerciseQueueState(deferred: [ExerciseID()]))
        var object = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object["order"] = nil
        object["occupied"] = nil
        let json = try JSONSerialization.data(withJSONObject: object)
        let state = try JSONDecoder().decode(ExerciseQueueState.self, from: json)
        #expect(state.order == nil)
        #expect(state.occupied == nil)
        #expect(state.deferred.count == 1)
    }
}

private extension WorkoutSessionCoordinator {
    /// Salta el descanso si lo hay, para seguir con la siguiente serie.
    func skipRestIfNeeded() throws {
        if case .resting = phase { skipRest() }
    }
}
