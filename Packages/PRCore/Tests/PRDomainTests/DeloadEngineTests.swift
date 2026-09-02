//
//  DeloadEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests para el motor determinista de deload (PR-1303): planeado, triggered,
//  reducción de variables (carga/RIR/volumen) con guardas, y adherencia.
//

import XCTest
@testable import PRDomain

final class DeloadEngineTests: XCTestCase {
    private let exA = ExerciseID(rawValue: UUID())
    private let exB = ExerciseID(rawValue: UUID())

    private func makeEngine() throws -> DeloadEngine {
        try DeloadEngine(config: DeloadPolicyConfig(rule: try DeloadPolicyDefaults.makeRule()))
    }

    private func prescription(
        load: Double? = 100,
        rir: ClosedRange<Int>? = 2...2,
        isWarmup: Bool = false,
        exercise: ExerciseID? = nil
    ) throws -> SetPrescription {
        try SetPrescription(
            targetRepRange: 8...10,
            targetRIR: rir,
            targetLoad: load,
            loadUnit: .kilograms,
            restSeconds: 120...180,
            isWarmup: isWarmup
        )
    }

    private func session(sets: [PlannedSet]) -> SessionTemplate {
        SessionTemplate(id: UUID(), title: "Push A", plannedSets: sets)
    }

    private func planned(exercise: ExerciseID, prescription: SetPrescription) -> PlannedSet {
        PlannedSet(exerciseID: exercise, prescription: prescription)
    }

    // MARK: - Sin deload

    func testNoPolicyNeverDeloads() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .none,
            weeksElapsed: 12,
            session: session(sets: [])
        ))
        XCTAssertNil(result.prescription)
        XCTAssertNil(result.kind)
        XCTAssertFalse(result.countsTowardAdherence)
        XCTAssertEqual(result.decisionRecord.type, .deload)
    }

    func testBeforeScheduledWeekNoDeload() throws {
        let engine = try makeEngine()
        // afterSixWeeks => semana programada 5 (0-indexado).
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks,
            weeksElapsed: 4,
            session: session(sets: [])
        ))
        XCTAssertNil(result.prescription)
    }

    // MARK: - Planeado

    func testPlannedDeloadAtOrAfterScheduledWeek() throws {
        let engine = try makeEngine()
        for week in [5, 6, 9] {
            let result = try engine.evaluate(DeloadInput(
                policy: .afterSixWeeks,
                weeksElapsed: week,
                session: session(sets: [])
            ))
            XCTAssertNotNil(result.prescription, "week \(week) should deload")
            XCTAssertEqual(result.kind, .planned)
            XCTAssertTrue(result.countsTowardAdherence)
        }
    }

    func testEightWeekDeloadScheduledLater() throws {
        let engine = try makeEngine()
        XCTAssertNil(try engine.evaluate(DeloadInput(
            policy: .afterEightWeeks, weeksElapsed: 6, session: session(sets: [])
        )).prescription)
        XCTAssertNotNil(try engine.evaluate(DeloadInput(
            policy: .afterEightWeeks, weeksElapsed: 7, session: session(sets: [])
        )).prescription)
    }

    // MARK: - Triggered

    func testTriggeredByHighFatigue() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .none, // no planeado
            weeksElapsed: 0,
            session: session(sets: []),
            recoveryState: .highFatigue
        ))
        XCTAssertNotNil(result.prescription)
        XCTAssertEqual(result.kind, .triggered)
    }

    func testTriggeredByRestRecommended() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .none,
            weeksElapsed: 0,
            session: session(sets: []),
            recoveryState: .restRecommended
        ))
        XCTAssertNotNil(result.prescription)
        XCTAssertEqual(result.kind, .triggered)
    }

    func testNormalRecoveryDoesNotTrigger() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .none,
            weeksElapsed: 0,
            session: session(sets: []),
            recoveryState: .normal
        ))
        XCTAssertNil(result.prescription)
    }

    func testNoRecoveryStateNoTrigger() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .none,
            weeksElapsed: 0,
            session: session(sets: []),
            recoveryState: nil
        ))
        XCTAssertNil(result.prescription)
    }

    // MARK: - Reducción de variables

    func testReducesLoadByDefaultFraction() throws {
        let engine = try makeEngine()
        let sets = [planned(exercise: exA, prescription: try prescription(load: 100))]
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: sets)
        ))
        let reducedLoad = try XCTUnwrap(result.prescription?.session.plannedSets[0].prescription.targetLoad)
        XCTAssertEqual(reducedLoad, 60.0, accuracy: 0.001) // 0.4 fracción
        XCTAssertTrue(result.prescription!.reductions.contains { $0.variable == .load })
    }

    func testAddsRIR() throws {
        let engine = try makeEngine()
        let sets = [planned(exercise: exA, prescription: try prescription(rir: 2...2))]
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: sets)
        ))
        let rir = try XCTUnwrap(result.prescription?.session.plannedSets[0].prescription.targetRIR)
        XCTAssertEqual(rir, 4...4) // +2 RIR por defecto
        XCTAssertTrue(result.prescription!.reductions.contains { $0.variable == .intensity })
    }

    func testReducesVolumeKeepingAtLeastOnePerExercise() throws {
        // Policy con volumeReductionSets configurado.
        var params = DeloadPolicyKeys.defaults()
        params[DeloadPolicyKeys.volumeReductionSets] = 2
        var deloadRule = try DeloadPolicyDefaults.makeRule()
        deloadRule.parameters = params
        let engine = try DeloadEngine(config: DeloadPolicyConfig(rule: deloadRule))

        let sets = [
            Try(exA), Try(exA), Try(exA), // 3 de trabajo de A
            Try(exB), Try(exB),          // 2 de trabajo de B
            Try(exA, warmup: true),
        ]
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: sets)
        ))
        let remaining = try XCTUnwrap(result.prescription?.session.plannedSets)
        XCTAssertTrue(remaining.contains { $0.prescription.isWarmup })
        let workA = remaining.filter { !$0.prescription.isWarmup && $0.exerciseID == exA }.count
        let workB = remaining.filter { !$0.prescription.isWarmup && $0.exerciseID == exB }.count
        XCTAssertGreaterThanOrEqual(workA, 1)
        XCTAssertGreaterThanOrEqual(workB, 1)
        // Se quitaron 2 sets de trabajo (nunca vaciar un ejercicio).
        XCTAssertEqual(workA + workB, 5 - 2)
        XCTAssertTrue(result.prescription!.reductions.contains { $0.variable == .volume })
    }

    // MARK: - Adherencia y auditabilidad

    func testDeloadCountsTowardAdherence() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: [])
        ))
        XCTAssertTrue(result.countsTowardAdherence)
        let fact = result.decisionRecord.inputFacts.first { $0.key == "countsTowardAdherence" }
        XCTAssertEqual(fact?.value, "true")
    }

    func testDecisionRecordRulesReferenced() throws {
        let engine = try makeEngine()
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: [])
        ))
        XCTAssertEqual(result.decisionRecord.ruleReferences.map(\.ruleID), [DeloadPolicyDefaults.ruleID])
        XCTAssertEqual(result.decisionRecord.type, .deload)
    }

    // MARK: - Validaciones

    func testWrongCategoryRejected() throws {
        var rule = try DeloadPolicyDefaults.makeRule()
        rule.category = .volume
        XCTAssertThrowsError(try DeloadPolicyConfig(rule: rule))
    }

    func testInvalidLoadFractionRejected() throws {
        var rule = try DeloadPolicyDefaults.makeRule()
        rule.parameters[DeloadPolicyKeys.loadReductionFraction] = 1.5
        XCTAssertThrowsError(try DeloadPolicyConfig(rule: rule))
    }

    func testInvalidVolumeReductionRejected() throws {
        var rule = try DeloadPolicyDefaults.makeRule()
        rule.parameters[DeloadPolicyKeys.volumeReductionSets] = -1
        XCTAssertThrowsError(try DeloadPolicyConfig(rule: rule))
    }

    func testLoadAndRirReductionNeverNegative() throws {
        let engine = try makeEngine()
        // Load 10 con fracción 0.4 ⇒ 6 (no negativo); RIR ya arriba.
        let sets = [planned(exercise: exA, prescription: try prescription(load: 10, rir: 0...0))]
        let result = try engine.evaluate(DeloadInput(
            policy: .afterSixWeeks, weeksElapsed: 5, session: session(sets: sets)
        ))
        let load = try XCTUnwrap(result.prescription?.session.plannedSets[0].prescription.targetLoad)
        XCTAssertGreaterThanOrEqual(load, 0)
        let rir = try XCTUnwrap(result.prescription?.session.plannedSets[0].prescription.targetRIR)
        XCTAssertGreaterThanOrEqual(rir.lowerBound, 0)
    }

    // MARK: - Helper

    private func Try(_ exercise: ExerciseID, warmup: Bool = false) -> PlannedSet {
        let pres = try! SetPrescription(
            targetRepRange: 8...10,
            targetRIR: 0...0,
            targetLoad: 100,
            loadUnit: .kilograms,
            restSeconds: 120...180,
            isWarmup: warmup
        )
        return PlannedSet(exerciseID: exercise, prescription: pres)
    }
}