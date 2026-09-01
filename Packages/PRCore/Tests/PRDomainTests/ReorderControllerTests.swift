//
//  ReorderControllerTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del reorder-before-replace (PR-0905): cuando un equipo está ocupado, intenta
//  adelantar un ejercicio compatible libre SIN perjudicar movimientos prioritarios;
//  si no hay reorder seguro, ofrece sustitución. Determinista y auditable.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Reorder-before-replace (PR-0905)")
struct ReorderControllerTests {

    let config = try! FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule())
    let controller = ReorderBeforeReplaceController()

    // Bench: priority compound usando barbell, pre-fatiga pecho y tríceps.
    private let benchPress = make(
        name: "Barbell Bench Press",
        equipment: .barbell,
        role: .primaryCompound,
        primary: [.chest: 1.0],
        secondary: [.triceps: 0.6],
        local: [.chest: 0.7, .triceps: 0.5]
    )
    // Chest machine libre y compatible: no pre-fatiga, no genera interferencia.
    private let chestMachinePress = make(
        name: "Chest Machine Press",
        equipment: .machine,
        role: .primaryCompound,
        primary: [.chest: 1.0],
        secondary: [.triceps: 0.6],
        local: [:]
    )
    // Triceps pushdown con cable: priFatigues triceps que bench necesita.
    private let tricepsPushdown = make(
        name: "Triceps Pushdown",
        equipment: .cable,
        role: .accessoryIsolation,
        primary: [.triceps: 0.8],
        secondary: [:],
        local: [.triceps: 0.8]
    )

    @Test("Ocupado intenta adelantar el siguiente ejercicio compatible libre")
    func occupiedReordersToCompatibleFreeExercise() throws {
        let ordered = [
            OrderedExercise(exercise: benchPress, orderScore: 100, rank: 1),
            OrderedExercise(exercise: chestMachinePress, orderScore: 90, rank: 2),
            OrderedExercise(exercise: tricepsPushdown, orderScore: 80, rank: 3),
        ]
        let uses = [
            ReorderItemUse(exerciseID: benchPress.id, equipmentTypes: [.barbell]),
            ReorderItemUse(exerciseID: chestMachinePress.id, equipmentTypes: [.machine]),
            ReorderItemUse(exerciseID: tricepsPushdown.id, equipmentTypes: [.cable]),
        ]
        let input = ReorderBeforeReplaceInput(
            ordered: ordered, equipmentUses: uses, occupiedTypes: [.barbell], config: config
        )

        let result = try controller.evaluate(input)

        guard case .reordered(let plan) = result.outcome.decision else {
            Issue.record("Se esperaba un reorder seguro")
            return
        }
        // El pecho compatible (libre) pasa a la primera posición; bench queda detrás.
        #expect(plan.first?.exercise.id == chestMachinePress.id)
        #expect(result.outcome.facts.contains { $0.key == "penaltyAfter" })
    }

    @Test("No adelanta triceps antes del priority bench si la interferencia excede el threshold")
    func noTricepsBeforePriorityBench() throws {
        let ordered = [
            OrderedExercise(exercise: benchPress, orderScore: 100, rank: 1),
            OrderedExercise(exercise: tricepsPushdown, orderScore: 80, rank: 2),
        ]
        let uses = [
            ReorderItemUse(exerciseID: benchPress.id, equipmentTypes: [.barbell]),
            ReorderItemUse(exerciseID: tricepsPushdown.id, equipmentTypes: [.cable]),
        ]
        let input = ReorderBeforeReplaceInput(
            ordered: ordered, equipmentUses: uses, occupiedTypes: [.barbell], config: config
        )

        let result = try controller.evaluate(input)

        guard case .substitute(let blocked) = result.outcome.decision else {
            Issue.record("Triceps antes de bench no es seguro; debe ofrecerse sustitución")
            return
        }
        #expect(blocked.exercise.id == benchPress.id)
        #expect(result.rejectedReasons.contains { $0.contains("Triceps Pushdown") })
    }

    @Test("Si no hay reorder seguro, ofrece sustitución")
    func noSafeReorderOffersSubstitution() throws {
        let ordered = [
            OrderedExercise(exercise: benchPress, orderScore: 100, rank: 1),
            OrderedExercise(exercise: tricepsPushdown, orderScore: 80, rank: 2),
        ]
        let uses = [
            ReorderItemUse(exerciseID: benchPress.id, equipmentTypes: [.barbell]),
            ReorderItemUse(exerciseID: tricepsPushdown.id, equipmentTypes: [.cable]),
        ]
        let input = ReorderBeforeReplaceInput(
            ordered: ordered, equipmentUses: uses, occupiedTypes: [.barbell], config: config
        )

        let result = try controller.evaluate(input)

        #expect(result.outcome.facts.contains { $0.key == "decision" && $0.value == "substitute" })
    }

    @Test("Sin equipos ocupados en la sesión no hay nada que reordenar")
    func unchangedWhenNoOccupiedEquipment() throws {
        let ordered = [
            OrderedExercise(exercise: benchPress, orderScore: 100, rank: 1),
            OrderedExercise(exercise: tricepsPushdown, orderScore: 80, rank: 2),
        ]
        let uses = [
            ReorderItemUse(exerciseID: benchPress.id, equipmentTypes: [.barbell]),
            ReorderItemUse(exerciseID: tricepsPushdown.id, equipmentTypes: [.cable]),
        ]
        let input = ReorderBeforeReplaceInput(
            ordered: ordered, equipmentUses: uses, occupiedTypes: [], config: config
        )

        let result = try controller.evaluate(input)

        #expect(result.outcome.decision == .unchanged)
    }

    @Test("Sesión restante con un solo ejercicio ocupado no puede reordenar → sustitución")
    func singleBlockedItemSubstitutes() throws {
        let ordered = [
            OrderedExercise(exercise: benchPress, orderScore: 100, rank: 1),
        ]
        let uses = [ReorderItemUse(exerciseID: benchPress.id, equipmentTypes: [.barbell])]
        let input = ReorderBeforeReplaceInput(
            ordered: ordered, equipmentUses: uses, occupiedTypes: [.barbell], config: config
        )

        let result = try controller.evaluate(input)

        guard case .substitute(let blocked) = result.outcome.decision else {
            Issue.record("Sin alternativa remanente debe ofrecerse sustitución")
            return
        }
        #expect(blocked.exercise.id == benchPress.id)
    }

    // MARK: - Fixtures

    private static func make(
        name: String,
        equipment: EquipmentType,
        role: ExerciseRole,
        primary: [MuscleGroup: Double],
        secondary: [MuscleGroup: Double],
        local: [MuscleGroup: Double]
    ) -> Exercise {
        Exercise(
            canonicalName: name,
            movementPattern: .horizontalPress,
            primaryMuscles: primary.map { try! MuscleContribution(muscleGroupID: $0.key, activation: $0.value) },
            secondaryMuscles: secondary.map { try! MuscleContribution(muscleGroupID: $0.key, activation: $0.value) },
            equipment: equipment,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            localFatigue: local.mapValues { try! FatigueCost(normalized: $0) },
            loadability: .discreteIncrements,
            defaultRoles: [role],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}