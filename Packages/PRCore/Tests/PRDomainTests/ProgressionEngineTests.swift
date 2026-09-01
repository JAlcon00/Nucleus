//
//  ProgressionEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de doble progresión (PR-1001): la carga aumenta sólo bajo reglas (rango
//  superior de reps, sin fallo excesivo, sin dolor, sin caída), respetando el
//  incremento de máquina/equipo (RN-013), y cancela con dolor moderado/alto. Cada
//  evaluación crea un DecisionRecord auditable.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Double progression (PR-1001)")
struct ProgressionEngineTests {

    let engine = try! ProgressionEngine(config: DoubleProgressionConfig(rule: DoubleProgressionDefaults.makeRule()))

    private let prescription = try! SetPrescription(
        targetRepRange: 8...12,
        loadUnit: .kilograms,
        restSeconds: 90...120,
        isWarmup: false
    )

    private func set(
        reps: Int,
        difficulty: DifficultyFeedback? = nil,
        pain: PainFeedback? = nil,
        weight: Double = 40
    ) -> SetRecord {
        try! SetRecord(
            exerciseID: ExerciseID(),
            weight: weight,
            unit: .kilograms,
            reps: reps,
            perceivedDifficulty: difficulty,
            painFeedback: pain,
            lifecycle: .completed
        )
    }

    private func input(weight: Double? = 40, sets: [SetRecord], increment: Double? = 2.5) -> ProgressionEvaluationInput {
        ProgressionEvaluationInput(
            prescription: prescription,
            performedSets: sets,
            currentWeight: weight,
            unit: .kilograms,
            availableIncrement: increment,
            loadability: .discreteIncrements,
            hasRecentSignificantDrop: false
        )
    }

    @Test("Sube carga sólo cuando todas las working sets alcanzan el rango superior")
    func increasesOnlyUnderRules() throws {
        let sets = [set(reps: 12), set(reps: 12), set(reps: 12)]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5))
        guard case .increase(let newWeight, let from) = eval.outcome else {
            Issue.record("Debía incrementar la carga")
            return
        }
        #expect(newWeight == 42.5)
        #expect(from == 40)
        #expect(eval.decisionRecord.ruleReferences.first?.ruleID == DoubleProgressionDefaults.ruleID)
    }

    @Test("Mantiene carga si alguna working set no alcanza el rango superior")
    func holdsWhenRepsNotMet() throws {
        let sets = [set(reps: 10), set(reps: 12)]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5))
        guard case .hold(let weight) = eval.outcome else {
            Issue.record("No debe incrementar sin cumplir el rango superior")
            return
        }
        #expect(weight == 40)
    }

    @Test("Respeta el incremento de máquina/equipo")
    func respectsEquipmentIncrement() throws {
        let sets = [set(reps: 12)]
        // Incremento de 5 kg (pila fija): la subida es exactamente un paso.
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 5))
        guard case .increase(let newWeight, _) = eval.outcome else {
            Issue.record("Debía incrementar un paso de la máquina")
            return
        }
        #expect(newWeight == 45)
    }

    @Test("Mantiene carga si el incremento de máquina se desconoce (conservador)")
    func holdsWhenIncrementUnknown() throws {
        let sets = [set(reps: 12)]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: nil))
        #expect(eval.outcome == .hold(weight: 40))
    }

    @Test("Dolor moderado/alto cancela la progresión")
    func painCancelsProgression() throws {
        let sets = [set(reps: 12, pain: .discomfort(muscleGroup: .shoulders, severity: 3))]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5))
        #expect(eval.blockedByPain)
        #expect(eval.outcome == .hold(weight: 40))
        #expect(eval.reasons.contains { $0.contains("dolor") })
    }

    @Test("Dolor leve/none no bloquea la progresión")
    func mildPainDoesNotBlock() throws {
        let sets = [set(reps: 12, pain: .discomfort(muscleGroup: .shoulders, severity: 1))]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5))
        #expect(!eval.blockedByPain)
        guard case .increase = eval.outcome else {
            Issue.record("Dolor leve no debe cancelar la progresión")
            return
        }
    }

    @Test("Fallo excesivo cancela la progresión")
    func excessiveFailureHolds() throws {
        let sets = [set(reps: 12, difficulty: .failed)]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5))
        #expect(eval.outcome == .hold(weight: 40))
    }

    @Test("Primera vez con el ejercicio mantiene (sin carga base) y crea DecisionRecord")
    func firstTimeHolds() throws {
        let sets = [set(reps: 12)]
        let eval = try engine.evaluate(input(weight: nil, sets: sets, increment: 2.5))
        #expect(eval.outcome == .hold(weight: 0))
        #expect(eval.decisionRecord.ruleReferences.count == 1)
    }

    @Test("Caída de rendimiento reciente mantiene la carga")
    func recentDropHolds() throws {
        let sets = [set(reps: 12)]
        let eval = try engine.evaluate(input(weight: 40, sets: sets, increment: 2.5, drop: true))
        #expect(eval.outcome == .hold(weight: 40))
    }

    // MARK: - Input helpers

    private func input(weight: Double?, sets: [SetRecord], increment: Double?, drop: Bool = false) -> ProgressionEvaluationInput {
        ProgressionEvaluationInput(
            prescription: prescription,
            performedSets: sets,
            currentWeight: weight,
            unit: .kilograms,
            availableIncrement: increment,
            loadability: .discreteIncrements,
            hasRecentSignificantDrop: drop
        )
    }
}