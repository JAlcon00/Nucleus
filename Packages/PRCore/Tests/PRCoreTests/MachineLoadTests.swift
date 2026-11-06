//
//  MachineLoadTests.swift
//  PRCoreTests
//
//  SCRUM-237 (PR-E006): el peso de la última vez en esa misma máquina. La máquina está
//  implícita en gimnasio + ejercicio (DE-1) y sólo cuenta para máquina, polea, Smith, discos y
//  trineo (DE-4). `LocalPersistence` real en un directorio temporal.
//

import Foundation
import Testing
import PRCore
import PRDomain

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_792_670_400)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func exercise(_ name: String, equipment: EquipmentType) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: .squat,
        primaryMuscles: [try MuscleContribution(muscleGroupID: .quadriceps, activation: 1.0)],
        equipment: equipment,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [.primaryCompound],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [.squat]).id
    )
}

private func template(_ exercise: Exercise, sets: Int = 2, warmup: Bool = false, unit: LoadUnit = .kilograms) throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 8...10, loadUnit: unit, restSeconds: 60...60, isWarmup: false)
    let warm = try SetPrescription(targetRepRange: 8...10, loadUnit: unit, restSeconds: 60...60, isWarmup: true)
    let planned = (warmup ? [warm] : []) + Array(repeating: work, count: sets)
    return SessionTemplate(title: "Pierna", plannedSets: planned.map { PlannedSet(exerciseID: exercise.id, prescription: $0) })
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-load-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func session(
    _ plan: SessionTemplate, catalog: [Exercise], gym: GymID?, root: URL, clock: TestClock
) async throws -> WorkoutSessionCoordinator {
    let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
    let coordinator = try await persistence.makeWorkoutCoordinator(template: plan, catalog: catalog, gymID: gym, clock: { clock.now })
    _ = coordinator.start()
    return coordinator
}

/// Hace una sesión con `weight` y la cierra.
@MainActor
private func train(
    _ plan: SessionTemplate, weight: Double, catalog: [Exercise], gym: GymID?, root: URL, clock: TestClock
) async throws {
    let coordinator = try await session(plan, catalog: catalog, gym: gym, root: root, clock: clock)
    while coordinator.currentSet() != nil, case .active = coordinator.phase {
        _ = try coordinator.recordEditedSet(weight: weight, reps: 10)
        if case .resting = coordinator.phase { coordinator.skipRest() }
    }
    clock.advance(86_400)
}

@MainActor
@Suite("SCRUM-237 · Mis cargas por máquina concreta")
struct MachineLoadTests {

    @Test("La misma máquina en el mismo gimnasio trae el último peso y lo dice")
    func sameMachine() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let root = try makeRoot()
        let clock = TestClock()
        let gym = GymID()
        try await train(try template(press), weight: 60, catalog: [press], gym: gym, root: root, clock: clock)

        let next = try await session(try template(press), catalog: [press], gym: gym, root: root, clock: clock)

        let set = try #require(next.currentSet())
        #expect(set.draft.targetWeight == 60)
        #expect(set.draft.weightFromHistory)
        #expect(set.loadIsPerMachine)
    }

    @Test("La segunda serie de la sesión trae el peso de la anterior")
    func secondSetUsesThePrevious() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let coordinator = try await session(try template(press), catalog: [press], gym: GymID(), root: try makeRoot(), clock: TestClock())

        _ = try coordinator.recordEditedSet(weight: 70, reps: 10)

        #expect(coordinator.currentSet()?.draft.targetWeight == 70)
    }

    @Test("Con historial en otro gimnasio, la máquina aparece vacía")
    func otherGymIsEmpty() async throws {
        for equipment in [EquipmentType.machine, .cable, .smithMachine, .plateLoaded, .sled] {
            let press = try exercise("Prensa", equipment: equipment)
            let root = try makeRoot()
            let clock = TestClock()
            try await train(try template(press), weight: 60, catalog: [press], gym: GymID(), root: root, clock: clock)

            let next = try await session(try template(press), catalog: [press], gym: GymID(), root: root, clock: clock)

            #expect(next.currentSet()?.draft.targetWeight == 0, "\(equipment)")
            #expect(next.currentSet()?.draft.weightFromHistory == false)
        }
    }

    @Test("Barra, mancuernas y kettlebell comparten el último peso entre gimnasios")
    func absoluteLoadIsShared() async throws {
        for equipment in [EquipmentType.barbell, .dumbbell, .kettlebell] {
            let lift = try exercise("Sentadilla", equipment: equipment)
            let root = try makeRoot()
            let clock = TestClock()
            try await train(try template(lift), weight: 80, catalog: [lift], gym: GymID(), root: root, clock: clock)

            let next = try await session(try template(lift), catalog: [lift], gym: GymID(), root: root, clock: clock)

            #expect(next.currentSet()?.draft.targetWeight == 80, "\(equipment)")
            #expect(next.currentSet()?.loadIsPerMachine == false)
        }
    }

    @Test("Los calentamientos no cuentan y no se precargan con el peso de trabajo")
    func warmupsDoNotCount() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let root = try makeRoot()
        let clock = TestClock()
        let gym = GymID()
        let plan = try template(press, sets: 1, warmup: true)
        let first = try await session(plan, catalog: [press], gym: gym, root: root, clock: clock)
        _ = try first.recordEditedSet(weight: 20, reps: 10)     // calentamiento
        if case .resting = first.phase { first.skipRest() }
        _ = try first.recordEditedSet(weight: 60, reps: 10)     // trabajo
        clock.advance(86_400)

        let next = try await session(plan, catalog: [press], gym: gym, root: root, clock: clock)
        #expect(next.currentSet()?.draft.targetWeight == 0, "El calentamiento no se precarga")
        _ = try next.recordEditedSet(weight: 25, reps: 10)
        if case .resting = next.phase { next.skipRest() }
        #expect(next.currentSet()?.draft.targetWeight == 60, "La de trabajo usa la última de trabajo")
    }

    @Test("Un sustituto trae su último peso, nunca el del original")
    func substituteUsesItsOwnLoad() async throws {
        let original = try exercise("Prensa", equipment: .machine)
        let substitute = try exercise("Hack", equipment: .machine)
        let catalog = [original, substitute]
        let root = try makeRoot()
        let clock = TestClock()
        let gym = GymID()
        try await train(try template(substitute), weight: 45, catalog: catalog, gym: gym, root: root, clock: clock)

        let coordinator = try await session(try template(original), catalog: catalog, gym: gym, root: root, clock: clock)
        _ = try coordinator.recordEditedSet(weight: 90, reps: 10)
        if case .resting = coordinator.phase { coordinator.skipRest() }
        try coordinator.substituteCurrentExercise(with: substitute.id)

        #expect(coordinator.currentSet()?.draft.targetWeight == 45)
    }

    @Test("La serie se guarda con su máquina; la de barra no lleva máquina")
    func setsCarryTheirMachine() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let bar = try exercise("Sentadilla", equipment: .barbell)
        let gym = GymID()
        let machine = try await session(try template(press), catalog: [press, bar], gym: gym, root: try makeRoot(), clock: TestClock())
        let free = try await session(try template(bar), catalog: [press, bar], gym: gym, root: try makeRoot(), clock: TestClock())

        _ = try machine.recordEditedSet(weight: 60, reps: 10)
        _ = try free.recordEditedSet(weight: 60, reps: 10)

        #expect(try machine.snapshot().session.sets.first?.machineProfileID == ImplicitMachine.id(gym: gym, exercise: press.id))
        #expect(try free.snapshot().session.sets.first?.machineProfileID == nil)
    }

    @Test("Las series viejas sin máquina no son historial de máquina; para barra sí cuentan")
    func oldSets() throws {
        let press = ExerciseID()
        let old = WorkoutSessionRecord(
            sets: [try SetRecord(exerciseID: press, weight: 60, unit: .kilograms, reps: 10)]
        )
        let index = LastLoadIndex(history: [old])

        #expect(index.lastWeight(of: press, machine: UUID(), unit: .kilograms) == nil)
        #expect(index.lastWeight(of: press, machine: nil, unit: .kilograms) == 60)
    }

    @Test("Con otra unidad no se convierte: queda vacío")
    func otherUnitIsEmpty() async throws {
        let bar = try exercise("Sentadilla", equipment: .barbell)
        let root = try makeRoot()
        let clock = TestClock()
        try await train(try template(bar), weight: 80, catalog: [bar], gym: nil, root: root, clock: clock)

        let next = try await session(try template(bar, unit: .pounds), catalog: [bar], gym: nil, root: root, clock: clock)

        #expect(next.currentSet()?.draft.targetWeight == 0)
    }

    @Test("Después de una sesión con dolor propone lo último hecho, nunca más")
    func painNeverRaises() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let root = try makeRoot()
        let clock = TestClock()
        let gym = GymID()
        let plan = try template(press, sets: 1)
        let first = try await session(plan, catalog: [press], gym: gym, root: root, clock: clock)
        _ = try first.recordEditedSet(weight: 60, reps: 10)
        clock.advance(86_400)
        let painful = try await session(try template(press, sets: 2), catalog: [press], gym: gym, root: root, clock: clock)
        _ = try painful.recordEditedSet(weight: 60, reps: 10)
        try painful.reportPain(.high)
        if case .resting = painful.phase { painful.skipRest() }
        #expect(try #require(painful.currentSet()).draft.targetWeight == 60, "Lo último hecho, sin subir")
    }

    @Test("Una sesión retomada tras cerrar la app precarga igual")
    func recoveredSession() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let root = try makeRoot()
        let clock = TestClock()
        let gym = GymID()
        let plan = try template(press, sets: 3)
        let first = try await session(plan, catalog: [press], gym: gym, root: root, clock: clock)
        _ = try first.recordEditedSet(weight: 55, reps: 10)

        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let recovered) = try await persistence.recoverWorkout(
            templates: [plan], catalog: [press], gymID: gym, clock: { clock.now }
        ) else {
            Issue.record("Debe retomarse"); return
        }

        #expect(recovered.currentSet()?.draft.targetWeight == 55)
    }

    @Test("Dos gimnasios con la misma prensa guardan pesos independientes, también al reabrir")
    func twoGymsAreIndependent() async throws {
        let press = try exercise("Prensa", equipment: .machine)
        let root = try makeRoot()
        let clock = TestClock()
        let (home, office) = (GymID(), GymID())
        try await train(try template(press), weight: 100, catalog: [press], gym: home, root: root, clock: clock)
        try await train(try template(press), weight: 40, catalog: [press], gym: office, root: root, clock: clock)

        let atHome = try await session(try template(press), catalog: [press], gym: home, root: root, clock: clock)
        #expect(atHome.currentSet()?.draft.targetWeight == 100)
        try atHome.abandon()
        let atOffice = try await session(try template(press), catalog: [press], gym: office, root: root, clock: clock)
        #expect(atOffice.currentSet()?.draft.targetWeight == 40)
    }
}
