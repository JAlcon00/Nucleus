//
//  GymAdaptationTests.swift
//  PRCoreTests
//
//  SCRUM-236 (PR-E005): "no hay esta máquina" se dice una vez y se aplica ENCIMA del plan al
//  armar el día. El bloque guardado no cambia, se puede quitar y nunca se programa una máquina
//  que no existe. `LocalPersistence` real en un directorio temporal y el catálogo real.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func press(_ name: String, primary: MuscleGroup = .chest, pattern: MovementPattern = .horizontalPress) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: pattern,
        primaryMuscles: [try MuscleContribution(muscleGroupID: primary, activation: 1.0)],
        equipment: .machine,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [.primaryCompound],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [pattern]).id
    )
}

private func block(_ sessions: [[Exercise]], pair: (Exercise, Exercise)? = nil) throws -> TrainingBlock {
    let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 80, loadUnit: .kilograms, restSeconds: 60...60)
    let templates = try sessions.map { exercises in
        SessionTemplate(
            title: "Sesión",
            plannedSets: exercises.flatMap { exercise in
                Array(repeating: PlannedSet(exerciseID: exercise.id, prescription: work), count: 2)
            },
            supersets: try pair.map { [try #require(SupersetPair(first: $0.0.id, second: $0.1.id))] }
        )
    }
    return try TrainingBlock(
        name: "Bloque", goal: .hypertrophy, phase: .maintenance, startDate: now, plannedWeeks: 6, sessions: templates,
        progressionPolicy: .doubleProgression, deloadPolicy: .afterSixWeeks, varietyPolicy: try VarietyPolicy(percentStable: 0.65)
    )
}

private func exercises(_ session: SessionTemplate?) -> [ExerciseID] {
    var seen: Set<ExerciseID> = []
    return (session?.plannedSets ?? []).compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
}

private func gym(_ marks: MissingExercise...) -> GymProfile {
    GymProfile(name: "Mi gimnasio", missingExercises: marks)
}

@Suite("SCRUM-236 · \"No hay esta máquina\": se recuerda, se aplica encima del plan y se puede quitar")
struct GymSessionAdapterTests {
    let adapter: GymSessionAdapter
    let a: Exercise
    let b: Exercise
    let c: Exercise
    let other: Exercise

    init() throws {
        adapter = try GymSessionAdapter.standard()
        a = try press("Press A")
        b = try press("Press B")
        c = try press("Press C")
        other = try press("Remo", primary: .back, pattern: .horizontalPull)
    }

    private var catalog: [Exercise] { [a, b, c, other] }

    @Test("Sin marcas el bloque no cambia")
    func noMarks() throws {
        let plan = try block([[a, other]])
        let result = try adapter.adapt(plan, gym: GymProfile(name: "Mi gimnasio"), catalog: catalog, restrictions: [], now: now)
        #expect(result.block == plan)
        #expect(result.notes.isEmpty)
    }

    @Test("Se hace B en lugar de A, en todas las sesiones, sin heredar la carga")
    func replaces() throws {
        let plan = try block([[a, other], [a]])
        let result = try adapter.adapt(
            plan, gym: gym(MissingExercise(exercise: a.id, replacement: b.id)), catalog: catalog, restrictions: [], now: now
        )

        #expect(exercises(result.block.sessions[0]) == [b.id, other.id])
        #expect(exercises(result.block.sessions[1]) == [b.id])
        #expect(result.block.sessions[0].plannedSets.filter { $0.exerciseID == b.id }.allSatisfy { $0.prescription.targetLoad == nil })
        #expect(result.notes[plan.sessions[0].id] == [.replaced(original: a.id, replacement: b.id)])
    }

    @Test("Una restricción nueva que prohíbe B propone otro sustituto")
    func restrictionPicksAnother() throws {
        let restriction = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [b.id])
        let result = try adapter.adapt(
            try block([[a]]), gym: gym(MissingExercise(exercise: a.id, replacement: b.id)), catalog: catalog,
            restrictions: [restriction], now: now
        )
        #expect(exercises(result.block.sessions.first) == [c.id])
    }

    @Test("Sin ningún sustituto seguro, A se omite y se explica")
    func omitsWhenNothingIsSafe() throws {
        let restriction = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [b.id, c.id])
        let plan = try block([[a, other]])
        let result = try adapter.adapt(
            plan, gym: gym(MissingExercise(exercise: a.id, replacement: b.id)), catalog: catalog, restrictions: [restriction], now: now
        )
        #expect(exercises(result.block.sessions.first) == [other.id])
        #expect(result.notes[plan.sessions[0].id] == [.omitted(original: a.id)])
    }

    @Test("Si B ya está en la sesión se usa el siguiente equivalente: no se repite")
    func doesNotRepeat() throws {
        let result = try adapter.adapt(
            try block([[a, b]]), gym: gym(MissingExercise(exercise: a.id, replacement: b.id)), catalog: catalog, restrictions: [], now: now
        )
        #expect(exercises(result.block.sessions.first) == [c.id, b.id])
    }

    @Test("Sin sustituto guardado busca uno; sin equivalente, nunca programa la máquina que no existe")
    func noStoredReplacement() throws {
        let found = try adapter.adapt(
            try block([[a]]), gym: gym(MissingExercise(exercise: a.id, replacement: nil)), catalog: catalog, restrictions: [], now: now
        )
        #expect(exercises(found.block.sessions.first) == [b.id])

        let alone = try adapter.adapt(
            try block([[a, other]]), gym: gym(MissingExercise(exercise: a.id, replacement: nil)), catalog: [a, other], restrictions: [], now: now
        )
        #expect(exercises(alone.block.sessions.first) == [other.id])
    }

    @Test("Lo que tampoco hay no se usa de sustituto")
    func anotherMissingIsNotASubstitute() throws {
        let result = try adapter.adapt(
            try block([[a]]),
            gym: gym(MissingExercise(exercise: a.id, replacement: b.id), MissingExercise(exercise: b.id, replacement: nil)),
            catalog: catalog, restrictions: [], now: now
        )
        #expect(exercises(result.block.sessions.first) == [c.id])
    }

    @Test("En superset, B va solo")
    func supersetBreaks() throws {
        let result = try adapter.adapt(
            try block([[a, other]], pair: (a, other)), gym: gym(MissingExercise(exercise: a.id, replacement: b.id)),
            catalog: catalog, restrictions: [], now: now
        )
        #expect(result.block.sessions.first?.supersetPairs.isEmpty == true)
    }

    @Test("Es determinista")
    func deterministic() throws {
        let plan = try block([[a, other]])
        let mark = gym(MissingExercise(exercise: a.id, replacement: nil))
        #expect(try adapter.adapt(plan, gym: mark, catalog: catalog, restrictions: [], now: now)
            == adapter.adapt(plan, gym: mark, catalog: catalog.reversed(), restrictions: [], now: now))
    }
}

@MainActor
@Suite("SCRUM-236 · De punta a punta con el plan guardado")
struct GymAdaptationFlowTests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func profile() -> OnboardingProfile {
        OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: 3,
            usualSessionMinutes: 60, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
        )
    }

    /// Lunes a mediodía: día de entrenamiento con 3 días por semana.
    private func coordinator(root: URL) throws -> (plan: TodayPlanCoordinator, store: PlanStore, persistence: LocalPersistence) {
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let store = try persistence.planStore()
        let zone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        let plan = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), planStore: store, clock: { monday }, timeZone: { zone }
        )
        return (plan, store, persistence)
    }

    @Test("Marcar → cerrar → Hoy trae el sustituto → quitar → vuelve; el plan guardado no cambia")
    func markCloseUnmark() async throws {
        let root = try makeRoot()
        let first = try coordinator(root: root)
        await first.plan.activate(profile: profile(), userID: "u1")
        guard case .loaded(let stored, let savedBlock) = await first.store.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        let today = try #require(first.plan.plan?.todayTemplate)
        let original = try #require(today.plannedSets.first?.exerciseID)

        let scoped = try first.persistence.scoped(toUser: "u1")
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await gyms.load(repository: try scoped.gymRepository())
        #expect(await gyms.markMissing(original, replacement: nil))

        // Reabrir: un coordinador nuevo sobre el mismo disco.
        let second = try coordinator(root: root)
        #expect(await second.plan.restore(userID: "u1") == .restored(profile()))
        let reopened = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await reopened.load(repository: try scoped.gymRepository())
        second.plan.applyGym(reopened.activeGym)

        let adapted = try #require(second.plan.plan?.todayTemplate)
        #expect(!adapted.plannedSets.contains { $0.exerciseID == original }, "No se programa lo que no hay")
        #expect(second.plan.plan?.gymNotes[adapted.id]?.isEmpty == false, "Y se explica")
        #expect(second.plan.plan?.sessions.contains { $0.plannedSets.contains { $0.exerciseID == original } } == false, "Semana igual")

        guard case .loaded(let after, let afterBlock) = await second.store.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        #expect(afterBlock == savedBlock, "El bloque guardado no cambia")
        #expect(after.updatedAt == stored.updatedAt, "Marcar no regenera ni guarda el plan")

        #expect(await reopened.removeMissing(original))
        second.plan.applyGym(reopened.activeGym)
        #expect(second.plan.plan?.todayTemplate?.plannedSets.contains { $0.exerciseID == original } == true, "Vuelve")
    }

    @Test("SCRUM-238: dos gimnasios, cambiar arma Hoy con lo de ese lugar y sobrevive a reabrir")
    func twoGymsChangeToday() async throws {
        let root = try makeRoot()
        let first = try coordinator(root: root)
        await first.plan.activate(profile: profile(), userID: "u1")
        guard case .loaded(let stored, let savedBlock) = await first.store.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        let original = try #require(first.plan.plan?.todayTemplate?.plannedSets.first?.exerciseID)

        let repository = try first.persistence.scoped(toUser: "u1").gymRepository()
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await gyms.load(repository: repository)
        #expect(await gyms.addGym(named: "Oficina") == .saved)
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })
        #expect(await gyms.select(office.id, duringWorkout: false))
        #expect(await gyms.markMissing(original, replacement: nil), "En Oficina no hay")
        first.plan.applyGym(gyms.activeGym)
        #expect(first.plan.plan?.todayTemplate?.plannedSets.contains { $0.exerciseID == original } == false)

        // Reabrir: sigue en Oficina y Hoy sigue armado con lo de Oficina.
        let second = try coordinator(root: root)
        #expect(await second.plan.restore(userID: "u1") == .restored(profile()))
        let reopened = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await reopened.load(repository: repository)
        second.plan.applyGym(reopened.activeGym)
        #expect(reopened.activeGym?.name == "Oficina")
        #expect(second.plan.plan?.todayTemplate?.plannedSets.contains { $0.exerciseID == original } == false)

        // Volver a Mi gimnasio: ahí sí hay, y el plan guardado nunca cambió.
        let home = try #require(reopened.gyms.first { $0.name == "Mi gimnasio" })
        #expect(await reopened.select(home.id, duringWorkout: false))
        second.plan.applyGym(reopened.activeGym)
        #expect(second.plan.plan?.todayTemplate?.plannedSets.contains { $0.exerciseID == original } == true)
        guard case .loaded(let after, let afterBlock) = await second.store.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        #expect(afterBlock == savedBlock, "El bloque guardado no cambia")
        #expect(after.updatedAt == stored.updatedAt, "Cambiar de gimnasio no regenera ni guarda el plan")
    }

    @Test("Un error al guardar el gimnasio no lo marca y avisa")
    func saveFailure() async throws {
        struct ReadOnly: RepositoryStore {
            struct Failure: Error {}
            func read(key: String) throws -> Data? { nil }
            func readAll() throws -> [Data] { [] }
            func readAllEntries() throws -> StoreReadResult { StoreReadResult(entries: [], unreadableKeys: []) }
            func write(key: String, data: Data) throws { throw Failure() }
            func delete(key: String) throws {}
        }
        let silent = PersistenceLog { _ in }
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: silent)
        await gyms.load(repository: FileGymRepository(store: ReadOnly(), log: silent))
        gyms.dismissNotice()

        #expect(await gyms.markMissing(ExerciseID(), replacement: nil) == false)
        #expect(gyms.notice == .saveFailed)
        #expect(gyms.activeGym?.missingExercises == nil)
    }

    @Test("Marcar \"no hay\" sólo afecta al gimnasio activo")
    func onlyActiveGym() async throws {
        let root = try makeRoot()
        let repository = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).scoped(toUser: "u1").gymRepository()
        let other = GymProfile(name: "Antes", lastSelectedAt: now)
        let active = GymProfile(name: "Ahora", lastSelectedAt: now.addingTimeInterval(60))
        try await repository.save(other)
        try await repository.save(active)
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await gyms.load(repository: repository)

        await gyms.markMissing(ExerciseID(), replacement: nil)

        #expect(gyms.gyms.first { $0.id == other.id }?.missingExercises == nil)
        #expect(gyms.activeGym?.missingExercises?.count == 1)
    }
}
