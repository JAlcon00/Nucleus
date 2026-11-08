//
//  ProgressRecordsTests.swift
//  PRCoreTests
//
//  Fase H (SCRUM-13).
//  - SCRUM-264 (PR-H002): Progreso cuenta los récords igual que el resumen al terminar:
//    uno por ejercicio por entrenamiento, aunque varias series superen la marca anterior.
//  - SCRUM-265 (PR-H003): cuáles son: cada entrenamiento sabe su récord y la lista del
//    bloque tiene tantas filas como dice la KPI.
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

private let bench = ExerciseID()
private let row = ExerciseID()
private let pushTemplate = SessionTemplate(title: "Push", plannedSets: [])

private func set(_ exercise: ExerciseID, _ weight: Double, _ reps: Int, at date: Date, unit: LoadUnit = .kilograms) throws -> SetRecord {
    try SetRecord(exerciseID: exercise, performedAt: date, weight: weight, unit: unit, reps: reps, lifecycle: .completed)
}

private func workout(on date: Date, sets: [SetRecord]) -> WorkoutSessionRecord {
    WorkoutSessionRecord(
        templateID: pushTemplate.id, startedAt: date, endedAt: date.addingTimeInterval(45 * 60),
        lifecycle: .completed, sets: sets
    )
}

private func overview(_ history: [WorkoutSessionRecord], on date: Date, blockStart: Date? = nil) -> ProgressOverview {
    ProgressOverviewBuilder().overview(
        history: history,
        templateTitles: [pushTemplate.id: pushTemplate.title],
        exerciseNames: [bench: "Press banca", row: "Remo con barra"],
        plannedPerWeek: 3,
        blockStart: blockStart,
        date: date,
        timeZone: utc
    )
}

/// Lunes: press banca a 80 kg. Miércoles: tres series sobre esa marca.
private func benchWeek() throws -> [WorkoutSessionRecord] {
    let monday = try day(0)
    let wednesday = try day(2)
    return [
        workout(on: monday, sets: [try set(bench, 80, 8, at: monday)]),
        workout(on: wednesday, sets: [
            try set(bench, 82.5, 8, at: wednesday),
            try set(bench, 85, 6, at: wednesday.addingTimeInterval(180)),
            try set(bench, 85, 5, at: wednesday.addingTimeInterval(360)),
        ]),
    ]
}

@Suite("Fase H · Récords en Progreso (SCRUM-264)")
struct ProgressRecordCountTests {

    @Test("Tres series sobre la marca anterior son 1 récord, igual que en el resumen")
    func severalSetsOverTheMarkAreOneRecord() throws {
        let history = try benchWeek()
        let entry = try #require(overview(history, on: try day(2)).entries.first)
        #expect(entry.recordCount == 1)

        // El resumen al terminar celebra lo mismo.
        let summary = WorkoutSummaryBuilder().summarize(
            history[1], baselines: PersonalRecordBaselineBuilder.baselines(from: [history[0]])
        )
        let celebration = try #require(PRCelebrationBuilder().celebration(for: summary.records, level: .balanced))
        #expect(celebration.items.count == entry.recordCount)
    }

    @Test("Récord en dos ejercicios del mismo entrenamiento: 2")
    func twoExercisesAreTwoRecords() throws {
        let monday = try day(0)
        let thursday = try day(3)
        let history = [
            workout(on: monday, sets: [try set(bench, 80, 8, at: monday), try set(row, 60, 10, at: monday)]),
            workout(on: thursday, sets: [
                try set(bench, 85, 6, at: thursday),
                try set(bench, 85, 6, at: thursday.addingTimeInterval(180)),
                try set(row, 65, 10, at: thursday.addingTimeInterval(400)),
                try set(row, 67.5, 8, at: thursday.addingTimeInterval(600)),
            ]),
        ]
        let result = overview(history, on: thursday)
        #expect(result.entries.first?.recordCount == 2)
        #expect(result.totalRecords == 2)
    }

    @Test("Récords del bloque: suma de las entradas del bloque con la misma regla")
    func blockKPIUsesTheSameRule() throws {
        let history = try benchWeek()
        let result = overview(history, on: try day(2), blockStart: try day(0))
        #expect(result.insights.recordsInBlock == 1)
        #expect(result.insights.recordsInBlock == result.entries.reduce(0) { $0 + $1.recordCount })
    }

    @Test("La regla vive una vez en el dominio: un récord por ejercicio, el mejor")
    func domainRule() throws {
        let wednesday = try day(2)
        let records = [
            PersonalRecord(exerciseID: bench, weight: 82.5, unit: .kilograms, reps: 8, achievedAt: wednesday),
            PersonalRecord(exerciseID: bench, weight: 85, unit: .kilograms, reps: 6, achievedAt: wednesday.addingTimeInterval(180)),
            PersonalRecord(exerciseID: bench, weight: 85, unit: .kilograms, reps: 5, achievedAt: wednesday.addingTimeInterval(360)),
        ]
        let best = PersonalRecordRanking.bestPerExercise(records)
        #expect(best.count == 1)
        #expect(best.first?.weight == 85)
        #expect(best.first?.reps == 6, "Empate de carga: gana la de más repeticiones")
    }

    @MainActor
    @Test("Integración: dos entrenamientos guardados de verdad dan 1 récord en Progreso")
    func integrationWithRealPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-records-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).scoped(toUser: "ana")
        for session in try benchWeek() {
            try await persistence.workoutRepository().save(session)
        }
        let saved = try await persistence.workoutRepository().loadAllSessions().items

        let wednesday = try day(2)
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), clock: { wednesday }, timeZone: { utc }
        )
        coordinator.updateHistory(saved, knownTemplates: [pushTemplate])
        guard case .loaded(let progress, _) = coordinator.progress else {
            Issue.record("Debía haber registro, estado \(coordinator.progress)"); return
        }
        #expect(progress.entries.first?.recordCount == 1)
        #expect(progress.totalRecords == 1)
    }
}

// MARK: - SCRUM-265 (PR-H003): cuáles son mis récords

@Suite("Fase H · Ver cuáles son mis récords (SCRUM-265)")
struct ProgressRecordListTests {

    @Test("El detalle del entrenamiento sabe qué ejercicio tuvo récord y con qué serie")
    func entryKnowsItsRecords() throws {
        let entry = try #require(overview(try benchWeek(), on: try day(2)).entries.first)
        let record = try #require(entry.records.first)
        #expect(entry.records.count == entry.recordCount)
        #expect(record.exerciseID == bench)
        #expect(record.name == "Press banca")
        #expect(record.weight == 85)
        #expect(record.reps == 6)
        #expect(record.unit == .kilograms)
        #expect(record.workoutID == entry.id)
    }

    @Test("Récords del bloque: tantas filas como dice la KPI, del más reciente al más antiguo")
    func blockListMatchesTheKPI() throws {
        let monday = try day(0)
        let wednesday = try day(2)
        let friday = try day(4)
        let history = [
            workout(on: monday, sets: [try set(bench, 80, 8, at: monday), try set(row, 60, 10, at: monday)]),
            workout(on: wednesday, sets: [try set(bench, 82.5, 8, at: wednesday)]),
            workout(on: friday, sets: [try set(bench, 85, 6, at: friday), try set(row, 62.5, 10, at: friday.addingTimeInterval(300))]),
        ]
        let insights = overview(history, on: friday, blockStart: monday).insights
        #expect(insights.blockRecords.count == insights.recordsInBlock)
        #expect(insights.recordsInBlock == 3)
        #expect(insights.blockRecords.map(\.achievedAt) == insights.blockRecords.map(\.achievedAt).sorted(by: >))
        #expect(insights.blockRecords.last?.weight == 82.5, "El más antiguo va al final")
    }

    @Test("Los récords de antes del bloque no entran en la lista del bloque")
    func onlyRecordsInTheBlock() throws {
        let insights = overview(try benchWeek(), on: try day(2), blockStart: try day(3)).insights
        #expect(insights.blockRecords.isEmpty)
        #expect(insights.recordsInBlock == 0)
    }

    @Test("Sin bloque, la lista toma todo el historial, igual que la KPI")
    func noBlockUsesAllHistory() throws {
        let insights = overview(try benchWeek(), on: try day(2), blockStart: nil).insights
        #expect(insights.blockRecords.count == 1)
        #expect(insights.recordsInBlock == 1)
    }

    @Test("Un ejercicio que ya no está en el catálogo no tiene nombre inventado")
    func unknownExerciseHasNoName() throws {
        let unknown = ExerciseID()
        let monday = try day(0)
        let wednesday = try day(2)
        let history = [
            workout(on: monday, sets: [try set(unknown, 40, 10, at: monday)]),
            workout(on: wednesday, sets: [try set(unknown, 45, 10, at: wednesday)]),
        ]
        let record = try #require(overview(history, on: wednesday).insights.blockRecords.first)
        #expect(record.name == nil)
    }

    @Test("Cada récord va en su unidad, sin convertir")
    func recordsKeepTheirUnit() throws {
        let monday = try day(0)
        let wednesday = try day(2)
        let history = [
            workout(on: monday, sets: [try set(row, 100, 10, at: monday, unit: .pounds)]),
            workout(on: wednesday, sets: [try set(row, 110, 8, at: wednesday, unit: .pounds)]),
        ]
        let record = try #require(overview(history, on: wednesday).insights.blockRecords.first)
        #expect(record.unit == .pounds)
        #expect(record.weight == 110)
    }

    @MainActor
    @Test("Integración: dos entrenamientos guardados de verdad → un récord en la lista con su ejercicio")
    func integrationListWithRealPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-record-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let exercise = try #require(catalog.exercises.first)
        let monday = try day(0)
        let wednesday = try day(2)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).scoped(toUser: "ana")
        try await persistence.workoutRepository().save(workout(on: monday, sets: [try set(exercise.id, 50, 10, at: monday)]))
        try await persistence.workoutRepository().save(workout(on: wednesday, sets: [try set(exercise.id, 55, 8, at: wednesday)]))

        let coordinator = TodayPlanCoordinator(catalog: catalog, clock: { wednesday }, timeZone: { utc })
        coordinator.updateHistory(try await persistence.workoutRepository().loadAllSessions().items, knownTemplates: [pushTemplate])
        guard case .loaded(let progress, _) = coordinator.progress else {
            Issue.record("Debía haber registro, estado \(coordinator.progress)"); return
        }
        let record = try #require(progress.insights.blockRecords.first)
        #expect(progress.insights.blockRecords.count == 1)
        #expect(record.name == exercise.canonicalName)
        #expect(record.weight == 55)
    }
}
