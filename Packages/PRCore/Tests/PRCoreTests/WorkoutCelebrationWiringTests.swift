//
//  WorkoutCelebrationWiringTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Cableado de PR-1004 en WORKOUT MODE: el coordinador pasa los baselines del
//  historial al resumen y expone la celebración con el nombre del catálogo. Sin
//  historial no se celebra nada (nunca se inventa un récord).
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Workout PR celebration wiring (PR-1004)")
struct WorkoutCelebrationWiringTests {

    private let exerciseID = ExerciseID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func makeTemplate(targetLoad: Double) throws -> SessionTemplate {
        let prescription = try SetPrescription(
            targetRepRange: 8...10,
            targetLoad: targetLoad,
            loadUnit: .kilograms,
            restSeconds: 90...120,
            isWarmup: false
        )
        return SessionTemplate(
            title: "Press banca",
            plannedSets: [PlannedSet(exerciseID: exerciseID, prescription: prescription)]
        )
    }

    private func history(bestWeight: Double) throws -> [WorkoutSessionRecord] {
        var past = WorkoutSessionRecord(lifecycle: .completed)
        past.sets = [try SetRecord(
            exerciseID: exerciseID,
            performedAt: t0.addingTimeInterval(-86_400),
            weight: bestWeight,
            unit: .kilograms,
            reps: 8,
            lifecycle: .completed
        )]
        return [past]
    }

    @MainActor
    private func finish(_ coordinator: WorkoutSessionCoordinator) throws -> WorkoutSummary {
        _ = coordinator.start(now: t0)
        let phase = try coordinator.completeCurrentSet(now: t0)
        guard case .finished(let summary) = phase else {
            Issue.record("La sesión de un set debía terminar, fase \(phase)")
            throw WorkoutSessionError.notActive
        }
        return summary
    }

    @MainActor
    @Test("Con historial: superar el mejor peso produce resumen con PR y celebración")
    func historyBaselineProducesCelebration() throws {
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(targetLoad: 85),
            exerciseNames: [exerciseID: "Press banca"],
            recordBaselines: PersonalRecordBaselineBuilder.baselines(from: try history(bestWeight: 80)),
            celebrationPresenter: PRCelebrationPresenter(locale: Locale(identifier: "es_MX")),
            clock: { [t0] in t0 }
        )
        let summary = try finish(coordinator)
        #expect(summary.records.count == 1)

        let celebration = coordinator.celebration(for: summary, level: .balanced)
        #expect(celebration?.rows.first?.exerciseName == "Press banca")
        #expect(celebration?.rows.first?.loadText == "85 kg × 8")
    }

    @MainActor
    @Test("Sin historial no hay PR ni celebración")
    func noHistoryNoCelebration() throws {
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(targetLoad: 85),
            exerciseNames: [exerciseID: "Press banca"],
            clock: { [t0] in t0 }
        )
        let summary = try finish(coordinator)
        #expect(summary.records.isEmpty)
        #expect(coordinator.celebration(for: summary, level: .guided) == nil)
    }

    @MainActor
    @Test("Igualar el mejor peso no es récord")
    func matchingBestIsNotARecord() throws {
        let coordinator = WorkoutSessionCoordinator(
            template: try makeTemplate(targetLoad: 80),
            recordBaselines: PersonalRecordBaselineBuilder.baselines(from: try history(bestWeight: 80)),
            clock: { [t0] in t0 }
        )
        #expect(try finish(coordinator).records.isEmpty)
    }
}
