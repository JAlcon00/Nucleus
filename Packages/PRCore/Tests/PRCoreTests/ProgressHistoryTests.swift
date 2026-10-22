//
//  ProgressHistoryTests.swift
//  PRCoreTests
//
//  SCRUM-186 (F-06): Progreso muestra el registro desde el primer entrenamiento. Sólo
//  cuentan los completados; cada uno con su sesión, duración, series, ejercicios y récords
//  (frente a los anteriores, igual que el resumen al terminar). El volumen nunca suma
//  kilos con libras. Sin historial legible se dice, no se muestra "vacío".
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

/// Día de la semana del 19 de octubre de 2026 (lunes = 0) a la hora indicada, en UTC.
private func day(_ mondayIndex: Int, hour: Int = 9) throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 19 + mondayIndex
    components.hour = hour
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private let squat = ExerciseID()
private let row = ExerciseID()
private let pushTemplate = SessionTemplate(title: "Push", plannedSets: [])

private func set(_ exercise: ExerciseID, _ weight: Double, _ reps: Int, at date: Date, unit: LoadUnit = .kilograms) throws -> SetRecord {
    try SetRecord(exerciseID: exercise, performedAt: date, weight: weight, unit: unit, reps: reps, lifecycle: .completed)
}

private func workout(
    on date: Date,
    minutes: Int = 45,
    lifecycle: WorkoutLifecycleState = .completed,
    template: SessionTemplate.ID? = pushTemplate.id,
    sets: [SetRecord]
) -> WorkoutSessionRecord {
    WorkoutSessionRecord(
        templateID: template, startedAt: date, endedAt: date.addingTimeInterval(Double(minutes * 60)),
        lifecycle: lifecycle, sets: sets
    )
}

private func overview(_ history: [WorkoutSessionRecord], on date: Date) -> ProgressOverview {
    ProgressOverviewBuilder().overview(
        history: history,
        templateTitles: [pushTemplate.id: pushTemplate.title],
        exerciseNames: [squat: "Sentadilla con barra", row: "Remo con barra"],
        plannedPerWeek: 3,
        date: date,
        timeZone: utc
    )
}

@Suite("Progreso: registro desde el primer entrenamiento (SCRUM-186)")
struct ProgressHistoryTests {

    @Test("El primer entrenamiento completado ya aparece, con su sesión, duración, series y ejercicios")
    func firstWorkoutIsLogged() throws {
        let monday = try day(0)
        let first = workout(on: monday, minutes: 42, sets: [
            try set(squat, 60, 10, at: monday),
            try set(squat, 60, 8, at: monday.addingTimeInterval(120)),
            try set(row, 50, 10, at: monday.addingTimeInterval(300)),
        ])
        let result = overview([first], on: monday)
        #expect(result.totalWorkouts == 1)
        let entry = try #require(result.entries.first)
        #expect(entry.sessionTitle == "Push")
        #expect(entry.durationSeconds == 42 * 60)
        #expect(entry.workingSets == 3)
        #expect(entry.exercises.map(\.name) == ["Sentadilla con barra", "Remo con barra"])
        #expect(entry.exercises.first?.sets.map(\.reps) == [10, 8])
        #expect(entry.volume == Double(60 * 10 + 60 * 8 + 50 * 10))
        #expect(entry.volumeUnit == .kilograms)
        #expect(entry.recordCount == 0, "Sin referencia previa no se inventa un récord")
    }

    @Test("Sólo cuentan los completados: abandonados y en curso no entran al registro")
    func onlyCompletedWorkouts() throws {
        let monday = try day(0)
        let history = [
            workout(on: monday, sets: [try set(squat, 60, 10, at: monday)]),
            workout(on: try day(1), lifecycle: .abandoned, sets: [try set(squat, 70, 5, at: try day(1))]),
            workout(on: try day(2), lifecycle: .active, sets: []),
        ]
        #expect(overview(history, on: try day(2)).totalWorkouts == 1)
    }

    @Test("Del más reciente al primero, y los récords se miden contra los anteriores")
    func orderAndRecords() throws {
        let monday = try day(0)
        let wednesday = try day(2)
        let history = [
            workout(on: wednesday, sets: [try set(squat, 70, 8, at: wednesday)]),
            workout(on: monday, sets: [try set(squat, 60, 10, at: monday)]),
        ]
        let result = overview(history, on: wednesday)
        #expect(result.entries.map(\.startedAt) == [wednesday, monday])
        #expect(result.entries.first?.recordCount == 1, "70 kg supera los 60 kg del lunes")
        #expect(result.entries.last?.recordCount == 0)
        #expect(result.totalRecords == 1)
    }

    @Test("Volumen: nunca se suman kilos con libras")
    func mixedUnitsHaveNoVolume() throws {
        let monday = try day(0)
        let mixed = workout(on: monday, sets: [
            try set(squat, 60, 10, at: monday),
            try set(row, 100, 10, at: monday, unit: .pounds),
        ])
        let entry = try #require(overview([mixed], on: monday).entries.first)
        #expect(entry.volume == nil)
        #expect(entry.volumeUnit == nil)
        #expect(entry.workingSets == 2)
    }

    @Test("Esta semana cuenta de lunes a domingo, frente a lo planeado")
    func thisWeek() throws {
        let lastSunday = try day(-1)
        let history = [
            workout(on: lastSunday, sets: [try set(squat, 60, 10, at: lastSunday)]),
            workout(on: try day(0), sets: [try set(squat, 60, 10, at: try day(0))]),
            workout(on: try day(2), sets: [try set(squat, 60, 10, at: try day(2))]),
        ]
        let result = overview(history, on: try day(3))
        #expect(result.completedThisWeek == 2)
        #expect(result.plannedPerWeek == 3)
        #expect(result.totalWorkouts == 3)
    }

    @Test("Una sesión cuya plantilla ya no se conoce queda sin título (no se inventa)")
    func unknownTemplateHasNoTitle() throws {
        let monday = try day(0)
        let entry = try #require(overview([
            workout(on: monday, template: UUID(), sets: [try set(squat, 60, 10, at: monday)]),
        ], on: monday).entries.first)
        #expect(entry.sessionTitle == nil)
    }

    @Test("Textos del registro: serie y volumen con su unidad")
    func texts() {
        let spanish = TrainingVocabularyPresenter(locale: Locale(identifier: "es_MX"))
        #expect(spanish.setText(weight: 60, unit: .kilograms, reps: 10) == "60 kg × 10")
        #expect(spanish.setText(weight: 82.5, unit: .kilograms, reps: 8) == "82.5 kg × 8")
        #expect(spanish.load(1580, unit: .kilograms) == "1,580 kg")
    }

    // MARK: - Coordinador

    @MainActor
    @Test("Progreso: cargando hasta leer el historial; vacío sin entrenamientos; registro tras el primero")
    func coordinatorScreens() throws {
        let monday = try day(0)
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), clock: { monday }, timeZone: { utc }
        )
        #expect(coordinator.progress == .loading)
        coordinator.updateHistory([])
        #expect(coordinator.progress == .empty(unreadable: 0))
        coordinator.updateHistory(
            [workout(on: monday, sets: [try set(squat, 60, 10, at: monday)])],
            unreadable: 1,
            knownTemplates: [pushTemplate]
        )
        guard case .loaded(let overview, let unreadable) = coordinator.progress else {
            Issue.record("Debía haber registro, estado \(coordinator.progress)"); return
        }
        #expect(overview.totalWorkouts == 1)
        #expect(overview.entries.first?.sessionTitle == "Push")
        #expect(unreadable == 1, "Lo ilegible se avisa")
    }

    @MainActor
    @Test("Si el historial no se puede leer: fallido (no 'vacío'); si ya había uno, se conserva")
    func coordinatorFailure() throws {
        let monday = try day(0)
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), clock: { monday }, timeZone: { utc }
        )
        coordinator.historyLoadFailed()
        #expect(coordinator.progress == .failed)

        coordinator.updateHistory([workout(on: monday, sets: [try set(squat, 60, 10, at: monday)])])
        coordinator.historyLoadFailed()
        guard case .loaded = coordinator.progress else {
            Issue.record("Con historial en memoria no debía pasar a fallido"); return
        }
    }
}
