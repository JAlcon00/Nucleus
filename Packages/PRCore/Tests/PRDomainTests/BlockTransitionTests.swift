//
//  BlockTransitionTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de la transición de bloque (PR-0505, RF-033): cerrar el bloque actual sin
//  tocar historial, abrir uno nuevo con el objetivo/fase destino, y conservar la
//  continuidad de ejercicio "cuando conviene" (su músculo sigue siendo prioritario).
//

import Foundation
import Testing
import PRDomain

@Suite("Block transition (PR-0505)")
struct BlockTransitionTests {

    private func makeExercise(
        name: String,
        pattern: MovementPattern = .horizontalPress,
        primary: MuscleGroup.ID
    ) throws -> Exercise {
        let family = ExerciseFamily(name: name + " family", movementPatterns: [pattern])
        return Exercise(
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: [try MuscleContribution(muscleGroupID: primary, activation: 1.0)],
            equipment: .barbell,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: Set(ExerciseRole.allCases),
            contraindicationTags: [],
            substitutionFamilyID: family.id
        )
    }

    /// Construye un bloque activo con plantillas que incluyen cada ejercicio dado.
    private func makeBlock(
        goal: TrainingGoal = .hypertrophy,
        phase: BodyCompositionPhase = .maintenance,
        status: BlockStatus = .active,
        exercises: [Exercise]
    ) throws -> TrainingBlock {
        var plannedSets: [PlannedSet] = []
        for exercise in exercises {
            plannedSets.append(PlannedSet(exerciseID: exercise.id, prescription: try prescription()))
        }
        let muscleIDs = exercises.compactMap { $0.primaryMuscles.first?.muscleGroupID }
        return try TrainingBlock(
            id: TrainingBlockID(),
            name: "Current",
            goal: goal,
            phase: phase,
            startDate: Date(timeIntervalSince1970: 1000),
            plannedWeeks: 6,
            sessions: [SessionTemplate(title: "Day 1", plannedSets: plannedSets)],
            muscleTargets: muscleIDs.map { try MuscleVolumeTarget(muscleGroupID: $0, targetSetsPerWeek: 4) },
            priorities: muscleIDs.map { MusclePriority(muscleGroupID: $0, priority: .normal) },
            progressionPolicy: .doubleProgression,
            deloadPolicy: .afterSixWeeks,
            varietyPolicy: try VarietyPolicy(percentStable: 0.65),
            status: status
        )
    }

    private func prescription() throws -> SetPrescription {
        try SetPrescription(targetRepRange: 8...12, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...90)
    }

    private func resolver(exercises: [Exercise]) -> CatalogExercisePrimaryResolver {
        CatalogExercisePrimaryResolver(catalog: exercises)
    }

    // MARK: - Cierra el bloque actual y abre uno nuevo

    @Test("Un nuevo goal/phase cierra el bloque actual (completed) y abre uno nuevo")
    func transitionClosesAndOpens() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let squat = try makeExercise(name: "Squat", primary: .quadriceps)
        let block = try makeBlock(exercises: [bench, squat])

        let outcome = try BlockTransitionEngine(resolver: resolver(exercises: [bench, squat]))
            .transition(
                current: block,
                toGoal: .strength,
                phase: .deficit,
                priorityMuscles: [.chest, .quadriceps],
                plannedWeeks: 6,
                varietyPreference: .balanced
            )

        #expect(outcome.closedBlock.status == .completed, "El bloque actual se cierra.")
        #expect(outcome.closedBlock.id == block.id, "Se cierra el MISMO bloque (mismo ID).")
        #expect(outcome.closedBlock.sessions == block.sessions, "El historial del bloque cerrado permanece intacto.")
        #expect(outcome.newBlock.id != block.id, "El nuevo bloque tiene un ID distinto.")
        #expect(outcome.newBlock.goal == .strength)
        #expect(outcome.newBlock.phase == .deficit)
    }

    @Test("Registros históricos permanecen intactos tras la transición")
    func historyIntact() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let block = try makeBlock(exercises: [bench])
        let originalSessions = block.sessions
        let originalSets = block.sessions.flatMap(\.plannedSets).count

        let outcome = try BlockTransitionEngine(resolver: resolver(exercises: [bench]))
            .transition(
                current: block,
                toGoal: .hypertrophy,
                phase: .maintenance,
                priorityMuscles: [.chest],
                plannedWeeks: 6,
                varietyPreference: .balanced
            )

        #expect(outcome.closedBlock.sessions == originalSessions)
        #expect(outcome.closedBlock.sessions.flatMap(\.plannedSets).count == originalSets)
        #expect(block.sessions.flatMap(\.plannedSets).count == originalSets, "El input original no muta.")
    }

    // MARK: - Continuidad de ejercicio

    @Test("Un ejercicio cuya prioridad se mantiene se conserva en el nuevo bloque")
    func continuityPreservedWhenMuscleStays() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let squat = try makeExercise(name: "Squat", primary: .quadriceps)
        let block = try makeBlock(exercises: [bench, squat])

        // Sólo el pecho sigue siendo prioritario; el cuadriceps se deja fuera.
        let outcome = try BlockTransitionEngine(resolver: resolver(exercises: [bench, squat]))
            .transition(
                current: block,
                toGoal: .hypertrophy,
                phase: .maintenance,
                priorityMuscles: [.chest],
                plannedWeeks: 6,
                varietyPreference: .balanced
            )

        #expect(outcome.carriedOverExercises.contains(bench.id), "El pecho se conserva.")
        #expect(!outcome.carriedOverExercises.contains(squat.id), "El cuadriceps no se conserva.")
        #expect(outcome.droppedExercises.contains(squat.id))
        let newSets = outcome.newBlock.sessions.flatMap(\.plannedSets)
        #expect(newSets.contains { $0.exerciseID == bench.id })
        #expect(!newSets.contains { $0.exerciseID == squat.id })
        #expect(outcome.newBlock.priorities.contains { $0.muscleGroupID == .chest })
        #expect(!outcome.newBlock.priorities.contains { $0.muscleGroupID == .quadriceps })
    }

    @Test("Continuidad se conserva 'cuando conviene': músculo deja de priorizarse ⇒ se descarta")
    func droppedWhenMuscleNoLongerPrioritized() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let block = try makeBlock(exercises: [bench])

        let outcome = try BlockTransitionEngine(resolver: resolver(exercises: [bench]))
            .transition(
                current: block,
                toGoal: .strength,
                phase: .maintenance,
                priorityMuscles: [.back], // el pecho dejó de priorizarse
                plannedWeeks: 6,
                varietyPreference: .balanced
            )

        #expect(outcome.carriedOverExercises.isEmpty)
        #expect(outcome.droppedExercises.contains(bench.id))
        #expect(outcome.newBlock.sessions.isEmpty, "Sin ejercicios de continuidad, el nuevo bloque arranca sin plantillas.")
    }

    // MARK: - Guardas

    @Test("Un bloque ya completado no es transicionable")
    func terminalBlockNotTransitionable() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let completed = try makeBlock(status: .completed, exercises: [bench])

        #expect(throws: BlockTransitionError.notTransitionable(.completed)) {
            _ = try BlockTransitionEngine(resolver: resolver(exercises: [bench]))
                .transition(
                    current: completed,
                    toGoal: .strength,
                    phase: .maintenance,
                    priorityMuscles: [.chest],
                    plannedWeeks: 6,
                    varietyPreference: .balanced
                )
        }
    }

    @Test("La transición produce hechos explicables (facts)")
    func emitsExplainableFacts() throws {
        let bench = try makeExercise(name: "Bench Press", primary: .chest)
        let block = try makeBlock(exercises: [bench])
        let outcome = try BlockTransitionEngine(resolver: resolver(exercises: [bench]))
            .transition(
                current: block,
                toGoal: .strength,
                phase: .maintenance,
                priorityMuscles: [.chest],
                plannedWeeks: 6,
                varietyPreference: .balanced
            )

        let keys = Set(outcome.facts.map(\.key))
        #expect(keys.contains("transition.fromGoal"))
        #expect(keys.contains("transition.toGoal"))
        #expect(keys.contains("transition.carriedExercises"))
        #expect(keys.contains("transition.closedStatus"))
        #expect(outcome.facts.first { $0.key == "transition.toGoal" }?.value == "strength")
    }
}