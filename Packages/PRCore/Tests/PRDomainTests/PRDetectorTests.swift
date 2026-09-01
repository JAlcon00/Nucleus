//
//  PRDetectorTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del PR detector (PR-1003): load PR, rep PR, e1RM PR con fórmula versionada,
//  y política de exclusión de warmups. Determinista y nunca inventa un récord sin
//  baseline.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("PR detector (PR-1003)")
struct PRDetectorTests {

    let config = try! PRDetectorConfig(rule: PRDetectorDefaults.makeRule())

    private func set(exerciseID: ExerciseID, weight: Double, reps: Int, id: SetRecordID = SetRecordID()) -> SetRecord {
        try! SetRecord(
            id: id,
            exerciseID: exerciseID,
            weight: weight,
            unit: .kilograms,
            reps: reps,
            lifecycle: .completed
        )
    }

    @Test("Detecta load PR cuando el peso supera el mejor histórico")
    func detectsLoadPR() throws {
        let ex = ExerciseID()
        let detector = PRDetector(baselines: PRBaselines(previousBestWeight: [ex: 100]))
        let records = detector.evaluate(sets: [set(exerciseID: ex, weight: 105, reps: 8)], config: config)
        #expect(records.contains { $0.kind == .load })
        #expect(records.first { $0.kind == .load }?.weight == 105)
    }

    @Test("Detecta rep PR cuando las reps superan el máximo histórico")
    func detectsRepPR() throws {
        let ex = ExerciseID()
        let detector = PRDetector(baselines: PRBaselines(previousBestReps: [ex: 10]))
        let records = detector.evaluate(sets: [set(exerciseID: ex, weight: 80, reps: 12)], config: config)
        #expect(records.contains { $0.kind == .rep })
        #expect(records.first { $0.kind == .rep }?.reps == 12)
    }

    @Test("Detecta e1RM PR con fórmula versionada y referenciable")
    func detectsE1RMPR() throws {
        let ex = ExerciseID()
        let detector = PRDetector(baselines: PRBaselines(previousBestE1RM: [ex: 100]))
        let records = detector.evaluate(sets: [set(exerciseID: ex, weight: 100, reps: 10)], config: config)
        #expect(records.contains { $0.kind == .e1RM })
        // Epley: 100 × (1 + 10/30) = 133.33 > 100.
        let e1rm = records.first { $0.kind == .e1RM }?.e1RM
        #expect(e1rm == 100 * (1 + 10.0 / 30.0))
        #expect(detector.ruleReference(config)?.ruleID == PRDetectorDefaults.ruleID)
    }

    @Test("La fórmula de e1RM cambia con la configuración versionada")
    func e1RMFormulaIsVersioned() throws {
        let ex = ExerciseID()
        // Denominador configurado: más conservador (denominador 40).
        let conservativeRule = try EvidenceRule(
            id: PRDetectorDefaults.ruleID,
            name: "PR detection conservative",
            category: .progression,
            confidence: .emerging,
            version: 2,
            parameters: [PRConfigKeys.e1RMRepsDenominator: 40, PRConfigKeys.warmupExcluded: 1]
        )
        let conservativeConfig = try PRDetectorConfig(rule: conservativeRule)
        let detector = PRDetector(baselines: PRBaselines(previousBestE1RM: [ex: 100]))

        let defaultE1RM = detector.estimatedOneRM(weight: 100, reps: 10, config: config)
        let conservativeE1RM = detector.estimatedOneRM(weight: 100, reps: 10, config: conservativeConfig)
        #expect(defaultE1RM > conservativeE1RM) // denominador mayor ⇒ estimado más bajo.
    }

    @Test("No conta un warmup como PR si la política lo excluye")
    func warmupExcludedByPolicy() throws {
        let ex = ExerciseID()
        let warmupID = SetRecordID()
        let detector = PRDetector(baselines: PRBaselines(previousBestWeight: [ex: 100]))
        let records = detector.evaluate(
            sets: [set(exerciseID: ex, weight: 150, reps: 5, id: warmupID)],
            config: config,
            warmupSetIDs: [warmupID]
        )
        #expect(records.isEmpty)
    }

    @Test("Si la política incluye warmups, sí se detectan")
    func warmupIncludedWhenPolicyAllows() throws {
        let ex = ExerciseID()
        let warmupID = SetRecordID()
        let permissiveRule = try EvidenceRule(
            id: PRDetectorDefaults.ruleID,
            name: "PR detection permissive",
            category: .progression,
            confidence: .emerging,
            version: 3,
            parameters: [PRConfigKeys.e1RMRepsDenominator: 30, PRConfigKeys.warmupExcluded: 0]
        )
        let permissiveConfig = try PRDetectorConfig(rule: permissiveRule)
        let detector = PRDetector(baselines: PRBaselines(previousBestWeight: [ex: 100]))
        let records = detector.evaluate(
            sets: [set(exerciseID: ex, weight: 150, reps: 5, id: warmupID)],
            config: permissiveConfig,
            warmupSetIDs: [warmupID]
        )
        #expect(records.contains { $0.kind == .load })
    }

    @Test("No inventa récord sin baseline histórico")
    func noPRWithoutBaseline() throws {
        let detector = PRDetector() // sin baselines.
        let records = detector.evaluate(sets: [set(exerciseID: ExerciseID(), weight: 200, reps: 10)], config: config)
        #expect(records.isEmpty)
    }
}