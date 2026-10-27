//
//  PainReportTests.swift
//  PRCoreTests
//
//  SCRUM-32: el dolor se reporta en la escala única desde el entrenamiento, se guarda como
//  una serie y frena la progresión; los entrenamientos y series pendientes guardados con
//  la escala anterior pasan a la única al abrir la app (ADR-0003, v1 → v2). Todo sobre
//  `LocalPersistence` real en un directorio temporal.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_000_000)

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-pain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func template() throws -> SessionTemplate {
    let prescription = try SetPrescription(
        targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 90...90
    )
    let exercise = ExerciseID()
    return SessionTemplate(
        title: "Press banca",
        plannedSets: (0..<3).map { _ in PlannedSet(exerciseID: exercise, prescription: prescription) }
    )
}

private func legacyFixture(_ collection: PersistenceCollection) throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: collection.rawValue, withExtension: "json", subdirectory: "Fixtures/Persistence/\(SchemaVersion.initial)"
    ))
    return try Data(contentsOf: url)
}

@MainActor
@Suite("SCRUM-32 · Reportar dolor en la escala única")
struct PainReportTests {

    // MARK: - Reportar desde el entrenamiento

    @Test("Dolor moderado: se guarda en la última serie antes de responder, recomienda bajar la intensidad y frena la carga")
    func moderatePainIsSavedAndHoldsLoad() async throws {
        let root = try makeRoot()
        let plan = try template()
        let coordinator = try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            .makeWorkoutCoordinator(template: plan, clock: { now })
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()

        let recommendation = try coordinator.reportPain(.moderate, muscleGroup: .chest)

        #expect(recommendation == .reduceIntensityAndMonitor)
        let onDisk = try #require(try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            .workoutRepository().allSessions().first)
        let set = try #require(onDisk.sets.last)
        #expect(set.painFeedback == PainFeedback(level: .moderate, muscleGroup: .chest))

        // La siguiente serie no propone más peso que la que dolió.
        let next = try #require(coordinator.currentSet())
        #expect(next.draft.targetWeight <= set.weight)

        let engine = try ProgressionEngine(config: DoubleProgressionConfig(rule: DoubleProgressionDefaults.makeRule()))
        let evaluation = try engine.evaluate(ProgressionEvaluationInput(
            prescription: plan.plannedSets[0].prescription, performedSets: onDisk.sets, currentWeight: set.weight,
            unit: .kilograms, availableIncrement: 2.5, loadability: .discreteIncrements, hasRecentSignificantDrop: false
        ))
        #expect(evaluation.blockedByPain)
        #expect(evaluation.outcome == .hold(weight: set.weight))
    }

    @Test("Al reabrir la app, la serie pendiente sin dolor no borra el dolor reportado después")
    func reopeningKeepsReportedPain() async throws {
        let root = try makeRoot()
        let plan = try template()
        let coordinator = try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            .makeWorkoutCoordinator(template: plan, clock: { now })
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.reportPain(.high)

        // Reabrir drena la cola de pendientes, que guardó la serie antes del dolor.
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let outcome = try await reopened.recoverWorkout(templates: [plan], clock: { now })
        guard case .restored = outcome else {
            Issue.record("La sesión en curso debía retomarse"); return
        }
        let onDisk = try #require(try await reopened.workoutRepository().allSessions().first)
        #expect(onDisk.sets.count == 1, "Sin series duplicadas")
        #expect(onDisk.sets.last?.painFeedback == PainFeedback(level: .high))
    }

    @Test("Cada nivel da la recomendación del motor; sólo moderado y alto dicen algo")
    func eachLevelRecommendation() throws {
        let presenter = PainRecommendationPresenter(locale: Locale(identifier: "es_MX"))
        for level in PainLevel.allCases {
            let coordinator = WorkoutSessionCoordinator(template: try template())
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()
            let recommendation = try coordinator.reportPain(level)
            switch level {
            case .none, .mild:
                #expect(recommendation == .continueNormal)
                #expect(presenter.message(for: recommendation) == nil)
            case .moderate:
                #expect(recommendation == .reduceIntensityAndMonitor)
                #expect(presenter.message(for: recommendation) != nil)
            case .high:
                #expect(recommendation == .stopAndRest)
                #expect(presenter.message(for: recommendation) != nil)
            }
        }
    }

    @Test("Sin series registradas no hay dónde reportar el dolor")
    func noSetsThrows() throws {
        let coordinator = WorkoutSessionCoordinator(template: try template())
        _ = coordinator.start()
        #expect(throws: WorkoutSessionError.invalidTransition) { try coordinator.reportPain(.mild) }
    }

    // MARK: - Textos

    @Test("Textos de la recomendación en español e inglés, sin diagnosticar ni prometer recuperación")
    func recommendationTexts() {
        let spanish = PainRecommendationPresenter(locale: Locale(identifier: "es_MX"))
        #expect(spanish.message(for: .reduceIntensityAndMonitor) == "Baja la intensidad y observa cómo te sientes en las próximas series.")
        #expect(spanish.message(for: .stopAndRest) == "Detén este ejercicio o cámbialo por otro. Si el dolor sigue, consulta a un profesional de la salud.")
        let english = PainRecommendationPresenter(locale: Locale(identifier: "en_US"))
        #expect(english.message(for: .reduceIntensityAndMonitor) == "Lower the intensity and notice how you feel over the next sets.")
        #expect(english.message(for: .stopAndRest) == "Stop this exercise or swap it for another. If the pain continues, see a health professional.")

        let forbidden = ["lesión", "lesion", "injur", "tendin", "desgarr", "diagnó", "diagnos", "recuper", "recover", "rehabilit"]
        let messages = [spanish, english].flatMap { presenter in
            [PainRecommendation.reduceIntensityAndMonitor, .stopAndRest].compactMap { presenter.message(for: $0) }
        }
        #expect(messages.count == 4)
        for message in messages {
            for word in forbidden {
                #expect(!message.lowercased().contains(word), "\"\(message)\" contiene \"\(word)\"")
            }
        }
    }

    // MARK: - Migración v1 → v2

    @Test("Los entrenamientos guardados con la escala anterior pasan a la única al abrir la app")
    func savedWorkoutsMigrate() async throws {
        let root = try makeRoot()
        let legacy = try legacyFixture(.workouts)
        let record = try JSONDecoder().decode(WorkoutSessionRecord.self, from: legacy)
        let directory = root.appendingPathComponent(PersistenceCollection.workouts.rawValue, isDirectory: true)
        try AtomicFileRepositoryStore(directory: directory).write(key: record.id.rawValue.persistenceKey, data: legacy)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })

        let outcomes = persistence.migrateSchemas()

        #expect(outcomes[.workouts] == .migrated(from: .initial, to: .initial.next, records: 1, quarantined: 0))
        let migrated = try #require(try await persistence.workoutRepository().session(id: record.id))
        // Molestia 3 → moderado; punzante 1 → moderado (nunca por debajo).
        #expect(migrated.sets[0].painFeedback == PainFeedback(level: .moderate, muscleGroup: .chest))
        #expect(migrated.sets[1].painFeedback == PainFeedback(level: .moderate, muscleGroup: .chest))
        // Fuera del dolor, nada cambia.
        #expect(migrated.sets.map(\.id) == record.sets.map(\.id))
        #expect(migrated.sets.map(\.weight) == record.sets.map(\.weight))
        #expect(migrated.sets.map(\.reps) == record.sets.map(\.reps))
        let stored = try #require(try AtomicFileRepositoryStore(directory: directory).readAllEntries().entries.first?.data)
        let text = String(decoding: stored, as: UTF8.self)
        #expect(!text.contains("severity") && !text.contains("sharpPain"), "En disco ya no queda la escala anterior")
    }

    @Test("Las series pendientes guardadas con la escala anterior también pasan a la única")
    func pendingSetsMigrate() throws {
        let legacy = try JSONDecoder().decode(PendingOperationQueue.self, from: try legacyFixture(.pendingOperations))
        let migrated = try PainScaleMigration.pendingOperations(try legacyFixture(.pendingOperations))
        let queue = try JSONDecoder().decode(PendingOperationQueue.self, from: migrated)
        let saves = try queue.operations.map { try JSONDecoder().decode(StoredSetSave.self, from: $0.payload) }

        // La serie pendiente con molestia 3 pasa a moderado; las demás no cambian.
        #expect(saves.compactMap(\.set.painFeedback) == [PainFeedback(level: .moderate, muscleGroup: .chest)])
        #expect(queue.operations.map(\.id) == legacy.operations.map(\.id))
        #expect(queue.operations.map(\.idempotencyKey) == legacy.operations.map(\.idempotencyKey))
        #expect(saves.map(\.set.id) == (try legacy.operations.map { try JSONDecoder().decode(StoredSetSave.self, from: $0.payload).set.id }))
        #expect(queue.operations.allSatisfy { !String(decoding: $0.payload, as: UTF8.self).contains("severity") })
        #expect(PersistenceCollection.pendingOperations.decodes(migrated))
    }
}
