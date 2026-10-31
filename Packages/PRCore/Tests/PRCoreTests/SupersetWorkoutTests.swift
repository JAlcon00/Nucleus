//
//  SupersetWorkoutTests.swift
//  PRCoreTests
//
//  SCRUM-224: un entrenamiento con un superset, con el coordinador real y `LocalPersistence`
//  en un directorio temporal. Se alterna A1/A2 con un toque y el descanso va tras la ronda;
//  "Para después" y "Saltar" separan el par (la pareja sigue sola); tras un cierre forzado a
//  mitad de la ronda se retoma sin perder ni duplicar series; Exportar y Progreso cuentan las
//  series igual que sin superset.
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

private let (press, curl, pushdown) = (ExerciseID(), ExerciseID(), ExerciseID())
private let names = [press: "Press", curl: "Curl", pushdown: "Extensión de tríceps"]

/// Press (3 series) y luego curl + extensión en superset (3 y 3).
private func template() throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 10...10, targetLoad: 20, loadUnit: .kilograms, restSeconds: 90...90, isWarmup: false)
    let sets = [press, press, press, curl, curl, curl, pushdown, pushdown, pushdown].map { PlannedSet(exerciseID: $0, prescription: work) }
    return SessionTemplate(title: "Torso", plannedSets: sets, supersets: [try #require(SupersetPair(first: curl, second: pushdown))])
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-superset-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func current(_ coordinator: WorkoutSessionCoordinator) -> ExerciseID? {
    coordinator.currentSet().map { coordinator.template.plannedSets[$0.index].exerciseID }
}

@MainActor
private func isResting(_ phase: WorkoutSessionPhase) -> Bool {
    if case .resting = phase { return true }
    return false
}

@MainActor
@Suite("SCRUM-224 · Entrenamiento con superset")
struct SupersetWorkoutTests {

    @Test("Se alterna curl y extensión con un toque; sin descanso a mitad de la ronda; la pantalla sabe el par")
    func alternatesWithRestAfterTheRound() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), exerciseNames: names, clock: { clock.now })
        _ = coordinator.start()
        for _ in 1...3 { _ = try coordinator.completeCurrentSet() }
        #expect(current(coordinator) == curl)
        #expect(coordinator.currentSet()?.superset == ActiveSupersetUI(isFirst: true, partnerName: "Extensión de tríceps"))

        var order: [ExerciseID] = []
        var restAfter: [Bool] = []
        while let exercise = current(coordinator) {
            order.append(exercise)
            let phase = try coordinator.completeCurrentSet()
            restAfter.append(isResting(phase))
            if case .finished = phase { break }
        }
        #expect(order == [curl, pushdown, curl, pushdown, curl, pushdown])
        #expect(restAfter.dropLast() == [false, true, false, true, false], "Descanso sólo después de cada ronda")
        let session = try coordinator.snapshot().session
        #expect(session.sets.count == 9, "Ni una serie de más ni de menos")
    }

    @Test("\"Para después\" separa el par: la extensión sigue sola y el curl vuelve al final, sin perder series")
    func deferSplitsThePair() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), exerciseNames: names, clock: { clock.now })
        _ = coordinator.start()
        for _ in 1...4 { _ = try coordinator.completeCurrentSet() }      // press ×3, curl 1
        #expect(current(coordinator) == pushdown)
        _ = try coordinator.completeCurrentSet()                         // extensión 1 → descanso
        #expect(current(coordinator) == curl)
        try coordinator.deferCurrentExercise()                           // la polea del curl está ocupada
        #expect(current(coordinator) == pushdown, "La pareja sigue sola")
        #expect(coordinator.currentSet()?.superset == nil, "Separados ya no se muestra el par")
        var rest: [ExerciseID] = []
        while let exercise = current(coordinator) {
            rest.append(exercise)
            if case .finished = try coordinator.completeCurrentSet() { break }
        }
        #expect(rest == [pushdown, pushdown, curl, curl])
        let sets = try coordinator.snapshot().session.sets
        #expect(sets.filter { $0.exerciseID == curl }.count == 3 && sets.filter { $0.exerciseID == pushdown }.count == 3)
    }

    @Test("\"Saltar\" el que se ve: la pareja sigue sola; el saltado se puede retomar y no crea series")
    func skipSplitsThePair() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), exerciseNames: names, clock: { clock.now })
        _ = coordinator.start()
        for _ in 1...4 { _ = try coordinator.completeCurrentSet() }      // press ×3, curl 1
        #expect(current(coordinator) == pushdown)
        try coordinator.skipCurrentExercise()                            // salta la extensión
        #expect(coordinator.skippedExercises.map(\.id) == [pushdown])
        #expect(current(coordinator) == curl)
        _ = try coordinator.completeCurrentSet()
        try coordinator.resumeSkipped(pushdown)                          // al final sí hay polea
        var rest: [ExerciseID] = []
        while let exercise = current(coordinator) {
            rest.append(exercise)
            if case .finished = try coordinator.completeCurrentSet() { break }
        }
        #expect(rest == [curl, pushdown, pushdown, pushdown], "Retomado vuelve al final, solo")
        #expect(try coordinator.snapshot().session.sets.count == 9)
    }

    @Test("Cierre forzado a mitad de la ronda: al reabrir sigue la extensión, sin descanso, y nada se duplica")
    func forcedKillMidRoundResumes() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await persistence.makeWorkoutCoordinator(template: plan, exerciseNames: names, clock: { clock.now })
            _ = coordinator.start()
            for _ in 1...4 { _ = try coordinator.completeCurrentSet() }  // press ×3, curl 1
            #expect(!isResting(coordinator.phase), "A mitad de la ronda no hay descanso")
        } // cierre forzado

        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: [plan], exerciseNames: names, clock: { clock.now }) else {
            Issue.record("Debía haber un entrenamiento en curso"); return
        }
        #expect(current(restored) == pushdown, "Retoma la ronda donde iba")
        #expect(!isResting(restored.phase))
        #expect(restored.currentSet()?.superset == ActiveSupersetUI(isFirst: false, partnerName: "Curl"))
        var order: [ExerciseID] = []
        while let exercise = current(restored) {
            order.append(exercise)
            if case .finished = try restored.completeCurrentSet() { break }
        }
        #expect(order == [pushdown, curl, pushdown, curl, pushdown])
        let session = try restored.snapshot().session
        #expect(session.sets.map(\.exerciseID) == [press, press, press, curl, pushdown, curl, pushdown, curl, pushdown])
        #expect(Set(session.sets.map(\.id)).count == 9, "Ninguna serie duplicada")
    }

    @Test("Exportar y Progreso cuentan las series igual que sin superset")
    func exportAndProgressCountTheSame() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), exerciseNames: names, clock: { clock.now })
        _ = coordinator.start()
        while current(coordinator) != nil {
            clock.advance(60)
            if case .finished = try coordinator.completeCurrentSet() { break }
        }
        let session = try coordinator.snapshot().session
        let csv = ExportEngine().workoutSetsCSV(sessions: [session])
        #expect(csv.split(separator: "\n").count == 1 + 9, "Encabezado y una fila por serie")
        let overview = ProgressOverviewBuilder().overview(
            history: [session], templateTitles: [:], exerciseNames: names, plannedPerWeek: nil,
            date: clock.now, timeZone: TimeZone(identifier: "UTC") ?? .current
        )
        #expect(overview.entries.first?.workingSets == 9)
        #expect(overview.entries.first?.exercises.map(\.sets.count).reduce(0, +) == 9)
    }
}
