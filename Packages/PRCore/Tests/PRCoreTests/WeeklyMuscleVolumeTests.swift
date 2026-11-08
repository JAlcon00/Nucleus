//
//  WeeklyMuscleVolumeTests.swift
//  PRCoreTests
//
//  SCRUM-268 (PR-H006): series por músculo de la semana contra su rango. Cada serie cuenta
//  una vez, para el músculo principal de su ejercicio (como reparte el motor); los
//  secundarios no suman. El rango sale de la regla versionada según la prioridad del
//  músculo. Semana de lunes a domingo. Fuera del plan se dice, sin nivel.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

/// Día de la semana del 19 de octubre de 2026 (lunes = 0) a la hora indicada, en UTC.
private func day(_ mondayIndex: Int, hour: Int = 9) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19 + mondayIndex, hour: hour)))
}

/// Resolvedor fijo: cada ejercicio con su músculo.
private struct FixedResolver: ExercisePrimaryResolver {
    let muscles: [ExerciseID: MuscleGroup]
    func primaryMuscle(of exerciseID: ExerciseID) -> MuscleGroup.ID? { muscles[exerciseID] }
}

private let press = ExerciseID()
private let fly = ExerciseID()
private let row = ExerciseID()
private let curl = ExerciseID()

private func rule(_ muscles: [ExerciseID: MuscleGroup] = [press: .chest, fly: .chest, row: .back, curl: .biceps]) throws -> WeeklyMuscleVolumeRule {
    WeeklyMuscleVolumeRule(config: try VolumeConfig(rule: VolumeDefaults.makeRule()), resolver: FixedResolver(muscles: muscles))
}

private func target(_ muscle: MuscleGroup, _ sets: Int) throws -> MuscleVolumeTarget {
    try MuscleVolumeTarget(muscleGroupID: muscle, targetSetsPerWeek: sets)
}

private func sets(_ exercise: ExerciseID, _ count: Int, at date: Date) throws -> [SetRecord] {
    try (0..<count).map { index in
        try SetRecord(
            exerciseID: exercise, performedAt: date.addingTimeInterval(Double(index * 120)),
            weight: 40, unit: .kilograms, reps: 10, lifecycle: .completed
        )
    }
}

private func workout(on date: Date, _ sets: [SetRecord]) -> WorkoutSessionRecord {
    WorkoutSessionRecord(startedAt: date, endedAt: date.addingTimeInterval(45 * 60), lifecycle: .completed, sets: sets)
}

private func status(_ muscle: MuscleGroup, in volume: [MuscleWeekVolume]) -> MuscleWeekVolume? {
    volume.first { $0.muscle == muscle }
}

@Suite("Fase H · Series por músculo de la semana (SCRUM-268)")
struct WeeklyMuscleVolumeTests {

    @Test("Cada serie cuenta una vez, para el músculo de su ejercicio")
    func countsByPrimaryMuscle() throws {
        let volume = try rule().volume(
            completedSets: [press: 4, fly: 3, row: 5],
            targets: [try target(.chest, 10), try target(.back, 10)],
            priorities: []
        )
        #expect(status(.chest, in: volume)?.sets == 7)
        #expect(status(.back, in: volume)?.sets == 5)
    }

    @Test("Los secundarios no suman: con el catálogo real, un press de pecho no cuenta para el tríceps")
    func secondaryMusclesDoNotCount() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let resolver = CatalogExercisePrimaryResolver(catalog: catalog.exercises)
        let exercise = try #require(catalog.exercises.first { exercise in
            resolver.primaryMuscle(of: exercise.id) == .chest
                && exercise.secondaryMuscles.contains { $0.muscleGroupID == .triceps }
        })
        let volume = WeeklyMuscleVolumeRule(config: try VolumeConfig(rule: VolumeDefaults.makeRule()), resolver: resolver)
            .volume(completedSets: [exercise.id: 3], targets: [try target(.chest, 10), try target(.triceps, 8)], priorities: [])
        #expect(status(.chest, in: volume)?.sets == 3)
        #expect(status(.triceps, in: volume)?.sets == 0)
    }

    @Test("Tres niveles contra el rango normal 8–12: faltan N, en rango, sobre el máximo")
    func threeLevels() throws {
        let targets = [try target(.chest, 10), try target(.back, 10), try target(.biceps, 10)]
        let volume = try rule().volume(completedSets: [press: 5, row: 10, curl: 13], targets: targets, priorities: [])
        #expect(status(.chest, in: volume)?.status == .planned(target: 10, range: 8...12, level: .belowRange(missing: 3)))
        #expect(status(.back, in: volume)?.status == .planned(target: 10, range: 8...12, level: .inRange))
        #expect(status(.biceps, in: volume)?.status == .planned(target: 10, range: 8...12, level: .aboveRange))
    }

    @Test("Los bordes del rango están dentro")
    func rangeBoundsAreInside() throws {
        let targets = [try target(.chest, 10), try target(.back, 10)]
        let volume = try rule().volume(completedSets: [press: 8, row: 12], targets: targets, priorities: [])
        #expect(status(.chest, in: volume)?.status == .planned(target: 10, range: 8...12, level: .inRange))
        #expect(status(.back, in: volume)?.status == .planned(target: 10, range: 8...12, level: .inRange))
    }

    @Test("El rango sale de la prioridad del músculo en el bloque", arguments: [
        (PriorityTier.maintain, 4...6),
        (.normal, 8...12),
        (.emphasize, 12...16),
        (.specialize, 16...20),
    ])
    func rangeFollowsPriority(tier: PriorityTier, expected: ClosedRange<Int>) throws {
        let volume = try rule().volume(
            completedSets: [:], targets: [try target(.chest, expected.lowerBound)],
            priorities: [MusclePriority(muscleGroupID: .chest, priority: tier)]
        )
        guard case .planned(_, let range, _) = status(.chest, in: volume)?.status else {
            Issue.record("Pecho debía estar en el plan"); return
        }
        #expect(range == expected)
    }

    @Test("Un músculo entrenado fuera del plan se dice, sin nivel; un ejercicio desconocido no suma")
    func outsidePlanAndUnknown() throws {
        let unknown = ExerciseID()
        let volume = try rule().volume(completedSets: [press: 3, curl: 4, unknown: 6], targets: [try target(.chest, 10)], priorities: [])
        #expect(volume.map(\.muscle) == [.chest, .biceps], "El plan primero; después lo de fuera")
        #expect(status(.biceps, in: volume)?.status == .outsidePlan)
        #expect(volume.reduce(0) { $0 + $1.sets } == 7, "Las 6 series del desconocido no van a ningún músculo")
    }

    // MARK: - En Progreso

    private func overview(_ history: [WorkoutSessionRecord], on date: Date, targets: [MuscleVolumeTarget]) throws -> ProgressOverview {
        ProgressOverviewBuilder().overview(
            history: history, templateTitles: [:], exerciseNames: [:], plannedPerWeek: 3,
            date: date, timeZone: utc,
            musclePlan: MuscleVolumePlan(rule: try rule(), targets: targets, priorities: [])
        )
    }

    @Test("La suma de la lista es igual a 'Series esta semana'")
    func sumMatchesTheWeeklyKPI() throws {
        let monday = try day(0)
        let wednesday = try day(2)
        let history = [
            workout(on: monday, try sets(press, 3, at: monday) + sets(row, 4, at: monday.addingTimeInterval(900))),
            workout(on: wednesday, try sets(fly, 2, at: wednesday) + sets(curl, 3, at: wednesday.addingTimeInterval(900))),
        ]
        let insights = try overview(history, on: wednesday, targets: [try target(.chest, 10), try target(.back, 10)]).insights
        let volume = try #require(insights.muscleVolume)
        #expect(volume.reduce(0) { $0 + $1.sets } == insights.setsThisWeek)
        #expect(insights.setsThisWeek == 12)
    }

    @Test("La semana va de lunes a domingo: lo del domingo pasado no cuenta el lunes")
    func mondayToSunday() throws {
        let lastSunday = try day(-1, hour: 20)
        let monday = try day(0)
        let history = [
            workout(on: lastSunday, try sets(press, 5, at: lastSunday)),
            workout(on: monday, try sets(press, 2, at: monday)),
        ]
        let volume = try #require(try overview(history, on: monday, targets: [try target(.chest, 10)]).insights.muscleVolume)
        #expect(status(.chest, in: volume)?.sets == 2)
    }

    @Test("Sin entrenamientos esta semana: los músculos del plan en 0, todos con lo que les falta")
    func emptyWeek() throws {
        let lastWeek = try day(-3)
        let history = [workout(on: lastWeek, try sets(press, 5, at: lastWeek))]
        let volume = try #require(try overview(history, on: try day(1), targets: [try target(.chest, 10), try target(.back, 8)]).insights.muscleVolume)
        #expect(volume.map(\.sets) == [0, 0])
        #expect(volume.allSatisfy {
            if case .planned(_, _, .belowRange) = $0.status { return true }
            return false
        })
    }

    @Test("Sin plan no hay lista")
    func noPlanNoList() throws {
        let monday = try day(0)
        let insights = ProgressOverviewBuilder().overview(
            history: [workout(on: monday, try sets(press, 3, at: monday))],
            templateTitles: [:], exerciseNames: [:], plannedPerWeek: nil, date: monday, timeZone: utc
        ).insights
        #expect(insights.muscleVolume == nil)
    }

    // MARK: - Integración

    @MainActor
    @Test("Integración: un entrenamiento guardado de verdad mueve el músculo correcto del plan")
    func integrationWithRealPersistenceAndCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-muscles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let tuesday = try day(1)
        let coordinator = TodayPlanCoordinator(
            catalog: catalog, planStore: try persistence.planStore(), clock: { tuesday }, timeZone: { utc }
        )
        await coordinator.activate(profile: OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: 3,
            usualSessionMinutes: 60, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
        ), userID: "ana")
        let block = try #require(coordinator.plan?.block)
        let exerciseID = try #require(block.sessions.first?.plannedSets.first?.exerciseID)
        let muscle = try #require(CatalogExercisePrimaryResolver(catalog: catalog.exercises).primaryMuscle(of: exerciseID))
        #expect(block.muscleTargets.contains { $0.muscleGroupID == muscle }, "El ejercicio del plan es de un músculo del plan")

        let history = try persistence.scoped(toUser: "ana").workoutRepository()
        try await history.save(workout(on: tuesday, try sets(exerciseID, 3, at: tuesday)))
        coordinator.updateHistory(try await history.loadAllSessions().items)

        guard case .loaded(let progress, _) = coordinator.progress else {
            Issue.record("Debía haber registro, estado \(coordinator.progress)"); return
        }
        let volume = try #require(progress.insights.muscleVolume)
        #expect(status(muscle, in: volume)?.sets == 3)
        #expect(volume.filter { $0.muscle != muscle }.allSatisfy { $0.sets == 0 })
        #expect(volume.count == block.muscleTargets.count, "Todos los músculos del plan, en el orden del bloque")
    }
}
