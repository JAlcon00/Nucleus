import Testing
import Foundation
@testable import PRDomain

@Suite("Weekly adherence engine (PR-1701)")
struct WeeklyAdherenceTests {

    private let exerciseA = ExerciseID(rawValue: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)

    private let templateA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let templateB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let templateC = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private let week = Date(timeIntervalSince1970: 1_000_000) // lunes de la ventana

    private func completedSet(at date: Date) throws -> SetRecord {
        try SetRecord(exerciseID: exerciseA, performedAt: date, weight: 100, unit: .kilograms, reps: 8, lifecycle: .completed)
    }

    private func executedSession(
        templateID: UUID,
        startedAt: Date,
        completedSets: Int,
        lifecycle: WorkoutLifecycleState = .completed
    ) throws -> WorkoutSessionRecord {
        let sets = try (0..<completedSets).map { _ in try completedSet(at: startedAt) }
        return WorkoutSessionRecord(
            templateID: templateID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1800),
            lifecycle: lifecycle,
            sets: sets
        )
    }

    private func planned(_ templateID: UUID, dayOffset: Int, isRest: Bool = false, workingSets: Int = 2) -> PlannedAdherenceSession {
        PlannedAdherenceSession(
            templateID: templateID,
            plannedDate: week.addingTimeInterval(Double(dayOffset) * 24 * 3600),
            isRest: isRest,
            plannedWorkingSets: workingSets
        )
    }

    // MARK: - planned vs completed/adjusted/rest/missed

    @Test("clasifica cada sesión planeada: completed, adjusted, missed")
    func classifiesOutcomes() async throws {
        let executed = [
            try executedSession(templateID: templateA, startedAt: week.addingTimeInterval(2 * 24 * 3600), completedSets: 2),
            try executedSession(templateID: templateB, startedAt: week.addingTimeInterval(3 * 24 * 3600), completedSets: 1),
        ]
        let plan = [
            planned(templateA, dayOffset: 1, workingSets: 2), // completed
            planned(templateB, dayOffset: 2, workingSets: 3), // adjusted: menos sets
            planned(templateC, dayOffset: 5, workingSets: 2), // missed
        ]

        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: executed)

        #expect(result.planned == 3)
        #expect(result.completed == 1)
        #expect(result.adjusted == 1)
        #expect(result.missed == 1)
        #expect(result.rest == 0)
        #expect(result.fulfilledCount == 2)
        #expect(result.adherence == 2.0 / 3.0)
        #expect(result.records.count == 3)
    }

    // MARK: - planned rest no rompe consistency

    @Test("descanso programado no es missed y no baja adherence")
    func plannedRestDoesNotBreak() async throws {
        let plan = [
            planned(templateA, dayOffset: 1, workingSets: 0),
            planned(templateB, dayOffset: 0, isRest: true),
            planned(templateC, dayOffset: 0, isRest: true, workingSets: 0),
        ]
        let result = try WeeklyAdherenceEngine().adherence(
            weekStart: week,
            planned: plan,
            executed: [
                // solo A se ejecuta
                try executedSession(templateID: templateA, startedAt: week.addingTimeInterval(6 * 24 * 3600), completedSets: 1),
            ]
        )

        #expect(result.completed == 1)
        #expect(result.adjusted == 0)
        #expect(result.missed == 0)
        #expect(result.rest == 2)
        #expect(result.adherence == 1.0, "rest programado no penaliza (1/1 exigida cumplida)")
    }

    @Test("semana de solo descanso (deload) → adherence 1.0 sin penalizar")
    func allRestWeek() async throws {
        let plan = [
            planned(templateA, dayOffset: 0, isRest: true, workingSets: 0),
            planned(templateB, dayOffset: 1, isRest: true, workingSets: 0),
        ]
        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: [])
        #expect(result.planned == 0)
        #expect(result.rest == 2)
        #expect(result.adherence == 1.0)
    }

    // MARK: - rescheduled se cuenta correctamente

    @Test("sesión reprogramada dentro de la semana cuenta como cumplida (match por templateID)")
    func rescheduledCounts() async throws {
        let plan = [planned(templateA, dayOffset: 1, workingSets: 2)]
        // Originalmente planeada el día 1 pero ejecutada el día 6 (misma ventana).
        let executed = [
            try executedSession(templateID: templateA, startedAt: week.addingTimeInterval(6 * 24 * 3600), completedSets: 2),
        ]
        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: executed)
        #expect(result.completed == 1)
        #expect(result.missed == 0)
        #expect(result.adherence == 1.0)
    }

    @Test("una ejecución satisface UNA sola sesión planeada (no doble cuenta)")
    func noDoubleCount() async throws {
        // Dos entradas planeadas para el mismo templateID, una sola ejecución.
        let plan = [
            planned(templateA, dayOffset: 1, workingSets: 2),
            planned(templateA, dayOffset: 3, workingSets: 2),
        ]
        let executed = [try executedSession(templateID: templateA, startedAt: week.addingTimeInterval(2 * 24 * 3600), completedSets: 2)]
        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: executed)
        #expect(result.completed == 1)
        #expect(result.missed == 1)
        #expect(result.adherence == 0.5)
    }

    // MARK: - ventana semanal

    @Test("ejecución fuera de la semana no satisface la planeada de esta semana")
    func crossWeekNotCounted() async throws {
        let plan = [planned(templateA, dayOffset: 1, workingSets: 2)]
        // Ejecutada en la semana siguiente (> 7 días de weekStart).
        let nextWeek = week.addingTimeInterval(8 * 24 * 3600)
        let executed = [try executedSession(templateID: templateA, startedAt: nextWeek, completedSets: 2)]
        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: executed)
        #expect(result.completed == 0)
        #expect(result.missed == 1)
    }

    // MARK: - adjusted cuando no se completó como se planeó

    @Test("abandono tras empezar → adjusted, no completed ni missed")
    func abandonedIsAdjusted() async throws {
        let plan = [planned(templateA, dayOffset: 1, workingSets: 2)]
        let executed = [try executedSession(templateID: templateA, startedAt: week.addingTimeInterval(2 * 24 * 3600), completedSets: 1, lifecycle: .abandoned)]
        let result = try WeeklyAdherenceEngine().adherence(weekStart: week, planned: plan, executed: executed)
        #expect(result.adjusted == 1)
        #expect(result.completed == 0)
        #expect(result.missed == 0)
    }

    // MARK: - validación

    @Test("working sets planeado negativo lanza error")
    func invalidPlannedSetsThrows() async throws {
        let bad = PlannedAdherenceSession(templateID: templateA, plannedDate: week, isRest: false, plannedWorkingSets: -1)
        let engine = WeeklyAdherenceEngine()
        await #expect(throws: DomainValidationError.invalidAdherencePlannedSets) {
            _ = try engine.adherence(weekStart: week, planned: [bad], executed: [])
        }
    }
}