//
//  StrengthProgressionTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de estrategias de progresión de fuerza (PR-1002): linearLoad, repGoal y
//  topSetBackoff modeladas con reglas propias (no una fórmula única), estrategia
//  explícita por block/exercise, con gate conservador (dolor/fallo/caída) y
//  doubleProgression delegando en PR-1001. Cada evaluación crea un DecisionRecord.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Strength progression strategies (PR-1002)")
struct StrengthProgressionTests {

    let engine = try! StrengthProgressionEngine(
        config: StrengthProgressionConfig(rule: StrengthProgressionDefaults.makeRule())
    )

    private let prescription = try! SetPrescription(
        targetRepRange: 8...12,
        loadUnit: .kilograms,
        restSeconds: 90...120,
        isWarmup: false
    )

    private func evidence(
        isTopSet: Bool = false,
        weight: Double = 40,
        reps: Int,
        rir: Int? = nil,
        difficulty: DifficultyFeedback? = nil,
        pain: PainFeedback? = nil
    ) -> StrengthSetEvidence {
        StrengthSetEvidence(
            isTopSet: isTopSet,
            weight: weight,
            reps: reps,
            rir: rir,
            perceivedDifficulty: difficulty,
            painFeedback: pain
        )
    }

    private func input(
        strategy: ProgressionStrategy,
        weight: Double? = 40,
        sets: [StrengthSetEvidence],
        increment: Double? = 2.5
    ) -> StrengthProgressionInput {
        StrengthProgressionInput(
            strategy: strategy,
            prescription: prescription,
            performed: sets,
            currentWeight: weight,
            unit: .kilograms,
            availableIncrement: increment
        )
    }

    // MARK: - Modelado y estrategia explícita

    @Test("ProgressionStrategy expone los seis casos del spec §12.2")
    func strategyEnumCases() {
        #expect(ProgressionStrategy.allCases.count == 6)
        for strategy in ProgressionStrategy.strengthStrategies {
            #expect(ProgressionStrategy.allCases.contains(strategy))
        }
    }

    @Test("la estrategia es explícita por block/exercise y no una única fórmula para todos")
    func strategyIsExplicitPerExercise() throws {
        // Cada estrategia con los MISMOS inputs dispara una decisión distinta ⇒
        // no hay una única fórmula global aplicada a todos.
        let sets = [evidence(reps: 12), evidence(reps: 12), evidence(reps: 12)]

        let linear = try engine.evaluate(input(strategy: .linearLoad, sets: sets))
        guard case .increaseLoad(let linearWeight, _) = linear.decision else {
            Issue.record("linearLoad debe modelar su propia subida de carga"); return
        }

        let top = try engine.evaluate(input(strategy: .strengthTopSetBackoff, sets: [evidence(isTopSet: true, reps: 12)]))
        guard case .increaseLoad(let topWeight, _) = top.decision else {
            Issue.record("topSetBackoff debe modelar su propia subida"); return
        }

        // repGoal NO sube de peso mientras esté dentro del rango (avanza reps).
        let repGoal = try engine.evaluate(input(strategy: .repGoal, sets: [evidence(reps: 10)]))
        guard case .advanceRepTarget(let to, _) = repGoal.decision else {
            Issue.record("repGoal debe avanzar reps sin tocar el peso"); return
        }

        #expect(linearWeight == topWeight)
        #expect(to == 11)
    }

    // MARK: - linearLoad

    @Test("linearLoad sube un incremento fijo cuando todas las working sets alcanzan el rango superior")
    func linearLoadIncreases() throws {
        let sets = [evidence(reps: 12), evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .linearLoad, sets: sets, increment: 2.5))
        guard case .increaseLoad(let newWeight, let from) = eval.decision else {
            Issue.record("Debía incrementar"); return
        }
        #expect(newWeight == 42.5)
        #expect(from == 40)
        #expect(eval.decisionRecord.ruleReferences.first?.ruleID == StrengthProgressionDefaults.ruleID)
    }

    @Test("linearLoad mantiene si alguna working set no alcanza el rango superior")
    func linearLoadHoldsWhenNotMet() throws {
        let sets = [evidence(reps: 12), evidence(reps: 10)]
        let eval = try engine.evaluate(input(strategy: .linearLoad, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    @Test("linearLoad respeta la discreción del equipo (incremento fijo)")
    func linearLoadRespectsEquipmentIncrement() throws {
        let sets = [evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .linearLoad, sets: sets, increment: 5))
        guard case .increaseLoad(let newWeight, _) = eval.decision else {
            Issue.record("Debía incrementar un paso de máquina"); return
        }
        #expect(newWeight == 45)
    }

    @Test("linearLoad mantiene si el incremento de equipo se desconoce (conservador)")
    func linearLoadHoldsOnUnknownIncrement() throws {
        let sets = [evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .linearLoad, sets: sets, increment: nil))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    @Test("linearLoad mantiene con fallo excesivo")
    func linearLoadHoldsOnFailure() throws {
        let sets = [evidence(reps: 12, difficulty: .failed)]
        let eval = try engine.evaluate(input(strategy: .linearLoad, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    @Test("linearLoad mantiene con caída reciente")
    func linearLoadHoldsOnDrop() throws {
        var i = input(strategy: .linearLoad, sets: [evidence(reps: 12)], increment: 2.5)
        i = StrengthProgressionInput(
            strategy: .linearLoad,
            prescription: prescription,
            performed: i.performed,
            currentWeight: 40,
            unit: .kilograms,
            availableIncrement: 2.5,
            loadability: .discreteIncrements,
            hasRecentSignificantDrop: true
        )
        let eval = try engine.evaluate(i)
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    // MARK: - repGoal

    @Test("repGoal avanza el objetivo de reps dentro del rango sin tocar el peso")
    func repGoalAdvancesReps() throws {
        let sets = [evidence(reps: 10)]
        let eval = try engine.evaluate(input(strategy: .repGoal, sets: sets, increment: 2.5))
        guard case .advanceRepTarget(let to, let weight) = eval.decision else {
            Issue.record("Debía avanzar reps"); return
        }
        #expect(to == 11)
        #expect(weight == 40)
    }

    @Test("repGoal sube carga y reinicia reps al rango inferior al completar el rango")
    func repGoalIncreasesAfterCompletingRange() throws {
        let sets = [evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .repGoal, sets: sets, increment: 2.5))
        guard case .repGoalLoadIncrease(let newWeight, let from, let reset) = eval.decision else {
            Issue.record("Debía incrementar el peso"); return
        }
        #expect(newWeight == 42.5)
        #expect(from == 40)
        #expect(reset == 8)
    }

    @Test("repGoal no sobrepasa el rango al avanzar reps")
    func repGoalClampsToRange() throws {
        let sets = [evidence(reps: 11)]
        let eval = try engine.evaluate(input(strategy: .repGoal, sets: sets, increment: 2.5))
        guard case .advanceRepTarget(let to, _) = eval.decision else {
            Issue.record("Debía avanzar reps"); return
        }
        #expect(to == 12)
    }

    // MARK: - topSetBackoff

    @Test("topSetBackoff sube el top set cuando alcanza su objetivo y modela back-off al % configurado")
    func topSetBackoffIncreasesAndModelsBackoff() throws {
        let sets = [evidence(isTopSet: true, weight: 40, reps: 12)]
        let eval = try engine.evaluate(input(strategy: .strengthTopSetBackoff, sets: sets, increment: 2.5))
        guard case .increaseLoad(let newWeight, _) = eval.decision else {
            Issue.record("Debía incrementar el top set"); return
        }
        #expect(newWeight == 42.5)
        // back-off = 85% del nuevo top set (config default 0.85).
        #expect(eval.reason.contains("85%"))
    }

    @Test("topSetBackoff mantiene si no hay top set en la sesión")
    func topSetBackoffHoldsWithoutTopSet() throws {
        let sets = [evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .strengthTopSetBackoff, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    @Test("topSetBackoff mantiene si el top set no alcanza su objetivo")
    func topSetBackoffHoldsWhenTopNotMet() throws {
        let sets = [evidence(isTopSet: true, reps: 10)]
        let eval = try engine.evaluate(input(strategy: .strengthTopSetBackoff, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    // MARK: - rirAutoregulated

    @Test("rirAutoregulated sube carga con RIR consistentemente bajo y en target")
    func rirAutoregulatedIncreasesOnLowRIR() throws {
        let sets = [evidence(reps: 12, rir: 1), evidence(reps: 12, rir: 0)]
        let eval = try engine.evaluate(input(strategy: .rirAutoregulated, sets: sets, increment: 2.5))
        guard case .increaseLoad(let newWeight, _) = eval.decision else {
            Issue.record("RIR bajo y en target debía incrementar"); return
        }
        #expect(newWeight == 42.5)
    }

    @Test("rirAutoregulated mantiene con RIR en zona")
    func rirAutoregulatedHoldsOnComfortableRIR() throws {
        let sets = [evidence(reps: 12, rir: 3), evidence(reps: 11, rir: 2)]
        let eval = try engine.evaluate(input(strategy: .rirAutoregulated, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    // MARK: - maintain / doubleProgression

    @Test("maintain siempre conserva la carga")
    func maintainKeepsLoad() throws {
        let sets = [evidence(reps: 12), evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .maintain, sets: sets, increment: 2.5))
        #expect(eval.decision == .holdLoad(weight: 40))
    }

    @Test("doubleProgression delega en el engine PR-1001 (sube bajo reglas del motor)")
    func doubleProgressionDelegates() throws {
        let sets = [evidence(reps: 12), evidence(reps: 12)]
        let eval = try engine.evaluate(input(strategy: .doubleProgression, sets: sets, increment: 2.5))
        guard case .increaseLoad(let newWeight, _) = eval.decision else {
            Issue.record("doubleProgression debía delegar la subida"); return
        }
        #expect(newWeight == 42.5)
    }

    // MARK: - Gate común

    @Test("dolor moderado/alto cancela la progresión en cualquier estrategia")
    func painCancelsAllStrategies() throws {
        let sets = [evidence(reps: 12, pain: .discomfort(muscleGroup: .shoulders, severity: 3))]
        for strategy in ProgressionStrategy.strengthStrategies {
            let eval = try engine.evaluate(input(strategy: strategy, sets: sets, increment: 2.5))
            #expect(eval.decision == .holdLoad(weight: 40), "\(strategy) no debía progresar con dolor moderado/alto")
        }
    }

    @Test("primera vez sin carga base mantiene (confidence low)")
    func firstTimeHolds() throws {
        let i = StrengthProgressionInput(
            strategy: .linearLoad,
            prescription: prescription,
            performed: [evidence(reps: 12)],
            currentWeight: nil,
            unit: .kilograms,
            availableIncrement: 2.5
        )
        let eval = try engine.evaluate(i)
        #expect(eval.decision == .holdLoad(weight: 0))
        #expect(eval.decisionRecord.ruleReferences.count == 1)
    }
}