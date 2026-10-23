//
//  WorkoutQueueTests.swift
//  PRCoreTests
//
//  SCRUM-212 (FB-5): dentro del entrenamiento se puede dejar un ejercicio para después o
//  saltarlo. Las series hechas nunca se pierden, saltar no crea series, el estado
//  sobrevive a cerrar la app (LocalPersistence real en un directorio temporal), un
//  saltado se puede retomar y la sesión termina bien con ejercicios saltados.
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

private let (benchPress, row, curl) = (ExerciseID(), ExerciseID(), ExerciseID())

/// Press, remo y curl con 2 series de trabajo cada uno.
private func template() throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 50, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false)
    return SessionTemplate(
        title: "Torso",
        plannedSets: [benchPress, benchPress, row, row, curl, curl].map { PlannedSet(exerciseID: $0, prescription: work) }
    )
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-queue-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func exercise(of coordinator: WorkoutSessionCoordinator) -> ExerciseID? {
    coordinator.currentSet().map { coordinator.template.plannedSets[$0.index].exerciseID }
}

@MainActor
@Suite("Saltar o dejar en espera (SCRUM-212)")
struct WorkoutQueueTests {

    @Test("Sin esperas ni saltos la siguiente serie es la de siempre (por posición)")
    func defaultCursorUnchanged() throws {
        let plan = try template()
        for done in 0...plan.plannedSets.count {
            let sets = try plan.plannedSets.prefix(done).map {
                try SetRecord(exerciseID: $0.exerciseID, performedAt: Date(), weight: 50, unit: .kilograms, reps: 8)
            }
            let expected: Int? = done < plan.plannedSets.count ? done : nil
            #expect(WorkoutQueue.nextPlannedIndex(template: plan, sets: sets, state: .empty) == expected)
        }
    }

    @Test("Dejar para después manda el ejercicio al final y vuelve a aparecer; las series hechas se quedan")
    func deferMovesToEnd() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), clock: { clock.now })
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()           // press 1 de 2
        #expect(exercise(of: coordinator) == benchPress)

        try coordinator.deferCurrentExercise()             // la banca está ocupada
        #expect(exercise(of: coordinator) == row, "Sigue el remo")
        #expect(try coordinator.snapshot().session.sets.count == 1, "La serie hecha se queda")
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.completeCurrentSet()           // remo listo
        _ = try coordinator.completeCurrentSet()
        _ = try coordinator.completeCurrentSet()           // curl listo
        #expect(exercise(of: coordinator) == benchPress, "El press vuelve al final")
        #expect(coordinator.currentSet()?.position == 6, "Serie 6 de 6")
        _ = try coordinator.completeCurrentSet()
        guard case .finished = coordinator.phase else { Issue.record("Debía terminar"); return }
        let session = try await persistence.workoutRepository().allSessions().first
        #expect(session?.sets.map(\.exerciseID) == [benchPress, row, row, curl, curl, benchPress])
        #expect(session?.lifecycle == .completed)
    }

    @Test("Saltar no crea series; el resumen sabe qué se saltó y la sesión termina bien")
    func skipCreatesNoSets() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), clock: { clock.now })
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()           // press 1
        try coordinator.skipCurrentExercise()              // salta el resto del press
        #expect(exercise(of: coordinator) == row)
        #expect(coordinator.currentSet()?.total == 5, "La serie pendiente del press ya no cuenta")
        #expect(coordinator.skippedExercises.map(\.id) == [benchPress])
        for _ in 1...4 { _ = try coordinator.completeCurrentSet() }
        guard case .finished = coordinator.phase else { Issue.record("Debía terminar con un saltado"); return }
        let session = try #require(try await persistence.workoutRepository().allSessions().first)
        #expect(session.sets.count == 5, "Ninguna serie inventada")
        #expect(session.sets.filter { $0.exerciseID == benchPress }.count == 1, "La serie hecha del saltado se conserva")
        #expect(session.queue?.skipped == [benchPress])
        #expect(session.lifecycle == .completed)
    }

    @Test("Saltar lo último que queda cierra la sesión sin series de más")
    func skippingTheLastExerciseFinishes() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), clock: { clock.now })
        _ = coordinator.start()
        for _ in 1...4 { _ = try coordinator.completeCurrentSet() }
        try coordinator.skipCurrentExercise()              // no hay curl hoy
        guard case .finished = coordinator.phase else { Issue.record("Debía terminar"); return }
        let session = try await persistence.workoutRepository().allSessions().first
        #expect(session?.sets.count == 4)
        #expect(session?.lifecycle == .completed)
    }

    @Test("Un saltado se retoma: vuelve al final de la cola")
    func resumeSkipped() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), clock: { clock.now })
        _ = coordinator.start()
        try coordinator.skipCurrentExercise()              // salta el press completo
        #expect(exercise(of: coordinator) == row)
        try coordinator.resumeSkipped(benchPress)          // al final sí hay banca libre
        #expect(coordinator.skippedExercises.isEmpty)
        #expect(coordinator.currentSet()?.total == 6)
        for _ in 1...4 { _ = try coordinator.completeCurrentSet() }
        #expect(exercise(of: coordinator) == benchPress, "Retomado: al final")
        try coordinator.resumeSkipped(benchPress)          // reintento: no cambia nada
        #expect(exercise(of: coordinator) == benchPress)
    }

    @Test("Esperas y saltos sobreviven a un cierre forzado y el descanso sigue")
    func queueSurvivesForcedKill() async throws {
        let root = try makeRoot()
        let plan = try template()
        let clock = TestClock()
        do {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let coordinator = try await persistence.makeWorkoutCoordinator(template: plan, clock: { clock.now })
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()       // press 1 → descanso
            guard case .resting = coordinator.phase else { Issue.record("Debía estar en descanso"); return }
            try coordinator.deferCurrentExercise()         // en pleno descanso
            guard case .resting = coordinator.phase else { Issue.record("El descanso no se rompe"); return }
            #expect(exercise(of: coordinator) == row)
            _ = try coordinator.completeCurrentSet()       // remo 1
            try coordinator.skipCurrentExercise()          // salta el remo
            #expect(exercise(of: coordinator) == curl)
        } // cierre forzado

        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: [plan], clock: { clock.now }) else {
            Issue.record("Debía haber un entrenamiento en curso"); return
        }
        #expect(exercise(of: restored) == curl, "Retoma donde iba")
        #expect(restored.skippedExercises.map(\.id) == [row])
        let session = try restored.snapshot().session
        #expect(session.sets.map(\.exerciseID) == [benchPress, row])
        #expect(session.queue == ExerciseQueueState(deferred: [benchPress], skipped: [row]))
    }

    @Test("En pausa no se puede saltar ni dejar en espera")
    func pausedRejectsQueueChanges() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let clock = TestClock()
        let coordinator = try await persistence.makeWorkoutCoordinator(template: try template(), clock: { clock.now })
        _ = coordinator.start()
        _ = try coordinator.pause()
        #expect(throws: WorkoutSessionError.self) { try coordinator.skipCurrentExercise() }
        #expect(throws: WorkoutSessionError.self) { try coordinator.deferCurrentExercise() }
        #expect(try coordinator.snapshot().session.queue == nil)
    }

    @Test("Una sesión guardada antes (sin cola) se lee igual")
    func legacySessionDecodes() throws {
        let record = WorkoutSessionRecord(templateID: UUID(), lifecycle: .active)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "queue")
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.queue == nil)
        #expect(decoded.id == record.id)
    }
}
