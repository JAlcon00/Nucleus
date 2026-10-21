//
//  PRCelebrationTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de PR-1004: baselines de PR desde historial (comparables por unidad y
//  máquina, RN-007), detector que no inventa récords fuera de contexto, y la
//  celebración determinista (una entrada por ejercicio, unidad real, copy por nivel,
//  anuncio VoiceOver).
//

import Foundation
import Testing
import PRDomain

@Suite("PR celebration (PR-1004)")
struct PRCelebrationTests {

    private let bench = ExerciseID()
    private let row = ExerciseID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func set(
        _ exercise: ExerciseID,
        _ weight: Double,
        reps: Int = 8,
        unit: LoadUnit = .kilograms,
        machine: UUID? = nil,
        at offset: TimeInterval = 0,
        lifecycle: SetLifecycleState = .completed
    ) throws -> SetRecord {
        try SetRecord(
            exerciseID: exercise,
            machineProfileID: machine,
            performedAt: t0.addingTimeInterval(offset),
            weight: weight,
            unit: unit,
            reps: reps,
            lifecycle: lifecycle
        )
    }

    private func session(_ sets: [SetRecord]) -> WorkoutSessionRecord {
        var record = WorkoutSessionRecord(lifecycle: .completed)
        record.sets = sets
        return record
    }

    private func record(_ exercise: ExerciseID, _ weight: Double, reps: Int = 8, unit: LoadUnit = .kilograms, at offset: TimeInterval = 0) -> PersonalRecord {
        PersonalRecord(exerciseID: exercise, weight: weight, unit: unit, reps: reps, achievedAt: t0.addingTimeInterval(offset))
    }

    // MARK: - Baselines

    @Test("Baseline = mejor carga completada del historial; skipped no cuenta")
    func baselineIsBestCompletedSet() throws {
        let history = [
            session([try set(bench, 80), try set(bench, 82.5, at: 60)]),
            session([try set(bench, 100, at: 120, lifecycle: .skipped)]),
        ]
        let baselines = PersonalRecordBaselineBuilder.baselines(from: history)
        #expect(baselines[bench]?.bestWeight == 82.5)
        #expect(baselines[bench]?.context == PersonalRecordBaselineContext(unit: .kilograms))
    }

    @Test("Sin historial no hay baseline (no se inventa)")
    func noHistoryNoBaseline() {
        #expect(PersonalRecordBaselineBuilder.baselines(from: []).isEmpty)
    }

    @Test("Varios contextos: se usa el del set más reciente (máquina actual)")
    func baselineUsesMostRecentContext() throws {
        let machineA = UUID()
        let machineB = UUID()
        let history = [session([
            try set(row, 90, machine: machineA, at: 0),
            try set(row, 60, machine: machineB, at: 100),
        ])]
        let baseline = PersonalRecordBaselineBuilder.baselines(from: history)[row]
        #expect(baseline?.bestWeight == 60)
        #expect(baseline?.context.machineProfileID == machineB)
    }

    @Test("Baselines deterministas independientemente del orden del historial")
    func baselinesAreOrderIndependent() throws {
        let a = session([try set(bench, 80, at: 0)])
        let b = session([try set(bench, 85, unit: .pounds, at: 0)])
        #expect(PersonalRecordBaselineBuilder.baselines(from: [a, b])
            == PersonalRecordBaselineBuilder.baselines(from: [b, a]))
    }

    // MARK: - Detector con contexto

    @Test("Superar el baseline en el mismo contexto es PR")
    func samContextBeatsBaseline() throws {
        let baselines = PersonalRecordBaselineBuilder.baselines(from: [session([try set(bench, 80)])])
        let today = session([try set(bench, 82.5, at: 3600)])
        let records = PersonalRecordDetector(baselines: baselines).detect(in: today)
        #expect(records.map(\.weight) == [82.5])
    }

    @Test("Otra unidad no es comparable: 100 lb no supera 80 kg como PR")
    func differentUnitIsNotAPR() throws {
        let baselines = PersonalRecordBaselineBuilder.baselines(from: [session([try set(bench, 80)])])
        let today = session([try set(bench, 100, unit: .pounds, at: 3600)])
        #expect(PersonalRecordDetector(baselines: baselines).detect(in: today).isEmpty)
    }

    @Test("Otra máquina no es comparable (RN-007)")
    func differentMachineIsNotAPR() throws {
        let baselines = PersonalRecordBaselineBuilder.baselines(from: [session([try set(row, 60, machine: UUID())])])
        let today = session([try set(row, 90, machine: UUID(), at: 3600)])
        #expect(PersonalRecordDetector(baselines: baselines).detect(in: today).isEmpty)
    }

    @Test("Resumen con baselines del historial reporta el PR")
    func summaryUsesHistoryBaselines() throws {
        let baselines = PersonalRecordBaselineBuilder.baselines(from: [session([try set(bench, 80)])])
        let summary = WorkoutSummaryBuilder().summarize(
            session([try set(bench, 85, at: 3600)]),
            now: t0.addingTimeInterval(4000),
            baselines: baselines
        )
        #expect(summary.records.count == 1)
    }

    // MARK: - Celebración

    private let builder = PRCelebrationBuilder()

    @Test("Sin récords no hay celebración")
    func noRecordsNoCelebration() {
        #expect(builder.celebration(for: [], level: .guided) == nil)
    }

    @Test("Una entrada por ejercicio: la de mayor peso")
    func onePerExerciseKeepsBest() {
        let celebration = builder.celebration(
            for: [record(bench, 82.5, at: 0), record(bench, 85, reps: 6, at: 60), record(bench, 85, reps: 5, at: 120)],
            exerciseNames: [bench: "Press banca"],
            level: .balanced
        )
        let item = try? #require(celebration?.items.first)
        #expect(celebration?.items.count == 1)
        #expect(item?.weight == 85)
        #expect(item?.reps == 6)
        #expect(item?.exerciseName == "Press banca")
    }

    @Test("Conserva la unidad real del set (lb), nunca asume kg ni convierte")
    func keepsRealUnit() {
        let item = builder.celebration(for: [record(bench, 185, unit: .pounds)], level: .advanced)?.items.first
        #expect(item?.unit == .pounds)
        #expect(item?.weight == 185)
    }

    @Test("Varios ejercicios: una entrada por cada uno, ordenadas por momento del récord")
    func multipleExercisesOrdered() {
        let celebration = builder.celebration(
            for: [record(row, 70, at: 300), record(bench, 85, at: 0)],
            exerciseNames: [bench: "Press banca", row: "Remo"],
            level: .balanced
        )
        #expect(celebration?.items.map(\.exerciseName) == ["Press banca", "Remo"])
    }

    @Test("Guided explica sobrecarga progresiva, balanced una línea, advanced sin explicación")
    func detailByCoachingLevel() {
        let records = [record(bench, 85)]
        #expect(builder.celebration(for: records, level: .guided)?.detail == .progressiveOverloadExplained)
        #expect(builder.celebration(for: records, level: .balanced)?.detail == .bestLoadSurpassed)
        let advanced = builder.celebration(for: records, level: .advanced)
        #expect(advanced != nil)
        #expect(advanced?.detail == nil)
    }

    @Test("Ejercicio fuera del catálogo: nombre nil, no se inventa")
    func unknownExerciseNameIsNil() {
        let item = builder.celebration(for: [record(bench, 85)], level: .guided)?.items.first
        #expect(item != nil)
        #expect(item?.exerciseName == nil)
    }

    @Test("Récords inválidos (reps < 1) se descartan; si no queda ninguno, no hay celebración")
    func invalidRecordsAreDropped() {
        #expect(builder.celebration(for: [record(bench, 85, reps: 0)], level: .guided) == nil)
    }

    @Test("Determinista: mismo input, misma celebración")
    func deterministic() {
        let records = [record(row, 70, at: 300), record(bench, 85, at: 0), record(bench, 80, at: 10)]
        #expect(builder.celebration(for: records, level: .guided) == builder.celebration(for: records.reversed(), level: .guided))
    }
}
