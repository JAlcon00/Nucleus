//
//  PainReportFlowTests.swift
//  PRCoreTests
//
//  SCRUM-226: reportar el dolor en el descanso. La hoja "¿Te dolió?" sólo lee
//  `WorkoutSessionCoordinator.painReport`: el nivel guardado (gana el último), los músculos
//  del ejercicio, la recomendación del motor y si ese ejercicio todavía se puede saltar. Lo
//  que se guarda pasa por `LocalPersistence` real en un directorio temporal.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let (benchPress, row) = (ExerciseID(), ExerciseID())
private let names = [benchPress: "Press banca", row: "Remo"]
private let muscles: [ExerciseID: [MuscleGroup.ID]] = [benchPress: [.chest, .triceps, .shoulders], row: [.back, .biceps]]

/// Press y remo, todas series de trabajo con descanso. Por defecto 2 de cada uno.
private func template(benchSets: Int = 2) throws -> SessionTemplate {
    let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 50, loadUnit: .kilograms, restSeconds: 60...60, isWarmup: false)
    let order = Array(repeating: benchPress, count: benchSets) + [row, row]
    return SessionTemplate(title: "Torso", plannedSets: order.map { PlannedSet(exerciseID: $0, prescription: work) })
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-pain-flow-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func makeCoordinator(root: URL, plan: SessionTemplate) async throws -> WorkoutSessionCoordinator {
    try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).makeWorkoutCoordinator(
        template: plan, exerciseNames: names, exerciseMuscles: muscles, clock: { now }
    )
}

@MainActor
private func savedSession(root: URL) async throws -> WorkoutSessionRecord {
    try #require(try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).workoutRepository().allSessions().first)
}

/// Escritura a disco que se puede romper a mitad de la prueba.
private final class FailingDisk {
    var fails = false
    func persist(_ session: WorkoutSessionRecord) throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
    }
}

@MainActor
@Suite("SCRUM-226 · Reportar el dolor en el descanso")
struct PainReportFlowTests {

    @Test("Antes de la primera serie no hay nada que reportar; después, la hoja describe esa serie")
    func reportDescribesTheLastSet() async throws {
        let coordinator = try await makeCoordinator(root: try makeRoot(), plan: try template())
        _ = coordinator.start()
        #expect(coordinator.painReport == nil)

        guard case .resting = try coordinator.completeCurrentSet() else {
            Issue.record("Tras una serie de trabajo toca descansar"); return
        }
        #expect(coordinator.painReport == PainReportUI(
            exerciseName: "Press banca", level: nil, muscleGroup: nil,
            muscleOptions: [.chest, .triceps, .shoulders], recommendation: .continueNormal, canSkipExercise: true
        ))
    }

    @Test("Gana el último nivel elegido: se guarda en la misma serie, sin duplicarla")
    func lastChoiceWins() async throws {
        let root = try makeRoot()
        let coordinator = try await makeCoordinator(root: root, plan: try template())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()

        try coordinator.reportPain(.moderate, muscleGroup: .chest)
        try coordinator.reportPain(.high, muscleGroup: .shoulders)

        let report = try #require(coordinator.painReport)
        #expect(report.level == .high)
        #expect(report.muscleGroup == .shoulders)
        #expect(report.recommendation == .stopAndRest)
        var onDisk = try await savedSession(root: root)
        #expect(onDisk.sets.count == 1)
        #expect(onDisk.sets.last?.painFeedback == PainFeedback(level: .high, muscleGroup: .shoulders))

        // Bajarlo a leve antes de la siguiente serie también queda.
        try coordinator.reportPain(.mild, muscleGroup: .shoulders)
        onDisk = try await savedSession(root: root)
        #expect(onDisk.sets.last?.painFeedback == PainFeedback(level: .mild, muscleGroup: .shoulders))
        #expect(coordinator.painReport?.recommendation == .continueNormal)
    }

    @Test("\"Sin dolor\" se guarda sin músculo, aunque antes se hubiera indicado uno")
    func noPainHasNoMuscle() async throws {
        let root = try makeRoot()
        let coordinator = try await makeCoordinator(root: root, plan: try template())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()

        try coordinator.reportPain(.moderate, muscleGroup: .chest)
        try coordinator.reportPain(.none, muscleGroup: .chest)

        #expect(coordinator.painReport?.level == PainLevel.none)
        #expect(coordinator.painReport?.muscleGroup == nil)
        #expect(try await savedSession(root: root).sets.last?.painFeedback == PainFeedback(level: .none))
    }

    @Test("La recomendación de la hoja es la que da el motor para cada nivel")
    func recommendationMatchesTheEngine() throws {
        for level in PainLevel.allCases {
            let coordinator = WorkoutSessionCoordinator(template: try template())
            _ = coordinator.start()
            _ = try coordinator.completeCurrentSet()
            let returned = try coordinator.reportPain(level)
            #expect(coordinator.painReport?.level == level)
            #expect(coordinator.painReport?.recommendation == returned)
        }
    }

    @Test("Saltar el ejercicio que dolió salta ése aunque no sea el que sigue, y se puede retomar")
    func skipThePainfulExercise() async throws {
        let root = try makeRoot()
        let coordinator = try await makeCoordinator(root: root, plan: try template())
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()        // press 1
        try coordinator.deferCurrentExercise()          // la banca se va al final: sigue el remo
        try coordinator.reportPain(.high)
        #expect(coordinator.painReport?.canSkipExercise == true)

        guard case .resting(let next, _) = try coordinator.skipPainfulExercise() else {
            Issue.record("El descanso sigue después de saltar"); return
        }
        #expect(coordinator.template.plannedSets[next.index].exerciseID == row)
        #expect(coordinator.skippedExercises.map(\.id) == [benchPress])
        #expect(coordinator.painReport?.canSkipExercise == false)
        let onDisk = try await savedSession(root: root)
        #expect(onDisk.sets.count == 1, "Saltar no crea ni borra series")
        #expect(onDisk.queue?.skipped == [benchPress])

        try coordinator.resumeSkipped(benchPress)
        #expect(coordinator.skippedExercises.isEmpty)
    }

    @Test("Si al ejercicio que dolió ya no le quedan series, no se ofrece saltarlo y no cambia nada")
    func finishedExerciseIsNotOffered() async throws {
        let coordinator = try await makeCoordinator(root: try makeRoot(), plan: try template(benchSets: 1))
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()        // única serie de press: sigue el remo
        try coordinator.reportPain(.high)
        #expect(coordinator.painReport?.canSkipExercise == false)

        let before = coordinator.phase
        #expect(try coordinator.skipPainfulExercise() == before)
        #expect(coordinator.skippedExercises.isEmpty)
    }

    @Test("Al reabrir la app, la hoja muestra el dolor ya reportado")
    func reopeningKeepsTheReport() async throws {
        let root = try makeRoot()
        let plan = try template()
        let coordinator = try await makeCoordinator(root: root, plan: plan)
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        try coordinator.reportPain(.moderate, muscleGroup: .triceps)

        let outcome = try await LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).recoverWorkout(
            templates: [plan], exerciseNames: names, exerciseMuscles: muscles, clock: { now }
        )
        guard case .restored(let restored) = outcome else {
            Issue.record("La sesión en curso debía retomarse"); return
        }
        #expect(restored.painReport == PainReportUI(
            exerciseName: "Press banca", level: .moderate, muscleGroup: .triceps,
            muscleOptions: [.chest, .triceps, .shoulders], recommendation: .reduceIntensityAndMonitor, canSkipExercise: true
        ))
    }

    @Test("Si no se puede guardar, el dolor queda en la sesión y la pantalla avisa")
    func saveFailureIsVisible() throws {
        let disk = FailingDisk()
        let coordinator = WorkoutSessionCoordinator(template: try template(), clock: { now }, persistSession: { try disk.persist($0) })
        _ = coordinator.start()
        _ = try coordinator.completeCurrentSet()
        #expect(!coordinator.persistenceFailed)

        disk.fails = true
        try coordinator.reportPain(.moderate)

        #expect(coordinator.persistenceFailed)
        #expect(coordinator.painReport?.level == .moderate)
    }

    @Test("Con el catálogo real cada ejercicio ofrece sus músculos: primero los principales y sin repetir")
    func muscleOptionsFromTheCatalog() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let options = PainMuscleOptions.byExercise(catalog.exercises)
        for exercise in catalog.exercises {
            let list = try #require(options[exercise.id])
            #expect(!list.isEmpty, "\(exercise.canonicalName) sin músculos para elegir")
            #expect(Set(list).count == list.count, "\(exercise.canonicalName) repite músculos")
            #expect(list.first == exercise.primaryMuscles.first?.muscleGroupID)
        }
    }

    @Test("Nombres de la escala y del botón en español e inglés, sin diagnosticar")
    func texts() {
        let spanish = PainRecommendationPresenter(locale: Locale(identifier: "es_MX"))
        #expect(PainLevel.allCases.map(spanish.levelName) == ["Sin dolor", "Leve", "Moderado", "Alto"])
        #expect(spanish.reportButtonTitle(for: nil) == "Reportar dolor")
        #expect(spanish.reportButtonTitle(for: PainLevel.none) == "Sin dolor")
        #expect(spanish.reportButtonTitle(for: .moderate) == "Dolor: Moderado")
        let english = PainRecommendationPresenter(locale: Locale(identifier: "en_US"))
        #expect(PainLevel.allCases.map(english.levelName) == ["No pain", "Mild", "Moderate", "High"])
        #expect(english.reportButtonTitle(for: nil) == "Report pain")
        #expect(english.reportButtonTitle(for: .high) == "Pain: High")

        let forbidden = ["lesión", "lesion", "injur", "tendin", "desgarr", "diagnó", "diagnos", "recuper", "recover", "rehabilit"]
        let texts = [spanish, english].flatMap { presenter in
            PainLevel.allCases.map(presenter.levelName) + ([nil] + PainLevel.allCases.map(Optional.some)).map(presenter.reportButtonTitle)
        }
        for text in texts {
            for word in forbidden {
                #expect(!text.lowercased().contains(word), "\"\(text)\" contiene \"\(word)\"")
            }
        }
    }
}
