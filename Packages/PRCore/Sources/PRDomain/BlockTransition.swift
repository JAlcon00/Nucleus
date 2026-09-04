//
//  BlockTransition.swift
//  PRDomain
//
//  Created by PR.
//
//  Transición de bloque (plan §4, PR-0505, RF-033). Un cambio de goal/phase CIEERRA
//  el bloque actual (lo marca completado SIN tocar su historial) y abre un NUEVO
//  bloque con el objetivo/fase destino. La continuidad de ejercicio se conserva
//  "cuando conviene": un ejercicio del bloque anterior pasa al nuevo sólo si su
//  músculo primario sigue siendo prioritario en el nuevo bloque. Determinista y
//  explicable (facts). INVARIANTE: nunca muta ni borra registros históricos; el
//  `closedBlock` es una copia inmutable con el mismo ID y los mismos sessions.
//

import Foundation

/// Errores de transición de bloque (PR-0505).
public enum BlockTransitionError: Error, Equatable, Sendable {
    /// El bloque actual ya es terminal (completed/abandoned): no se puede transicionar.
    case notTransitionable(BlockStatus)
}

/// Resultado de transicionar de un bloque a otro (PR-0505).
public struct BlockTransitionOutcome: Equatable, Sendable {
    /// El bloque anterior CERRADO (status .completed, historial intacto).
    public let closedBlock: TrainingBlock
    /// El NUEVO bloque (ID distinto) con objetivo/fase destino y ejercicios de continuidad.
    public let newBlock: TrainingBlock
    /// Ejercicios conservados del bloque anterior (continuidad) en el nuevo.
    public let carriedOverExercises: [ExerciseID]
    /// Ejercicios del bloque anterior NO conservados (su músculo dejó de ser prioritario).
    public let droppedExercises: [ExerciseID]
    /// Hechos explicativos de la transición.
    public let facts: [DecisionFact]

    public init(
        closedBlock: TrainingBlock,
        newBlock: TrainingBlock,
        carriedOverExercises: [ExerciseID],
        droppedExercises: [ExerciseID],
        facts: [DecisionFact]
    ) {
        self.closedBlock = closedBlock
        self.newBlock = newBlock
        self.carriedOverExercises = carriedOverExercises
        self.droppedExercises = droppedExercises
        self.facts = facts
    }
}

/// Registrar cierta un bloque consultando qué músculo entrena cada ejercicio.
public protocol ExercisePrimaryResolver: Sendable {
    /// Músculo primario de un ejercicio (mayor activación en `primaryMuscles`).
    func primaryMuscle(of exerciseID: ExerciseID) -> MuscleGroup.ID?
}

/// Resolvedor por defecto a partir del catálogo de ejercicios.
public struct CatalogExercisePrimaryResolver: ExercisePrimaryResolver {
    private let byID: [ExerciseID: Exercise]

    public init(catalog: [Exercise]) {
        var map: [ExerciseID: Exercise] = [:]
        for exercise in catalog {
            map[exercise.id] = exercise
        }
        self.byID = map
    }

    public func primaryMuscle(of exerciseID: ExerciseID) -> MuscleGroup.ID? {
        guard let exercise = byID[exerciseID] else { return nil }
        return exercise.primaryMuscles.max(by: { $0.activation < $1.activation })?.muscleGroupID
    }
}

/// Motor determinista de transición de bloque (PR-0505, RF-033).
public struct BlockTransitionEngine: Sendable {

    private let resolver: any ExercisePrimaryResolver

    public init(resolver: some ExercisePrimaryResolver) {
        self.resolver = resolver
    }

    /// Transiciona desde `current` hacia un nuevo goal/phase, cerrando el actual.
    public func transition(
        current: TrainingBlock,
        toGoal newGoal: TrainingGoal,
        phase newPhase: BodyCompositionPhase,
        priorityMuscles: [MuscleGroup.ID],
        plannedWeeks: Int,
        varietyPreference: VarietyPreference
    ) throws -> BlockTransitionOutcome {
        guard current.status == .active || current.status == .planned || current.status == .deloading else {
            throw BlockTransitionError.notTransitionable(current.status)
        }
        guard (4...8).contains(plannedWeeks) else {
            throw DomainValidationError.invalidMinutes(value: plannedWeeks)
        }

        // 1) Cerrar el bloque actual: copia inmutable con status .completed.
        var closed = current
        closed.status = .completed

        // 2) Resolver continuidad por músculo primario que siga siendo prioritario.
        let prioritySet = Set(priorityMuscles)
        var carried: [ExerciseID] = []
        var dropped: [ExerciseID] = []
        for exerciseID in current.distinctPlannedExercises {
            guard let muscle = resolver.primaryMuscle(of: exerciseID) else {
                dropped.append(exerciseID)
                continue
            }
            if prioritySet.contains(muscle) {
                if !carried.contains(exerciseID) { carried.append(exerciseID) }
            } else if !dropped.contains(exerciseID) {
                dropped.append(exerciseID)
            }
        }

        // 3) Nuevo bloque: ID nuevo, goal/fase destino, ejercicios de continuidad.
        let newBlock = try buildNewBlock(
            from: current,
            goal: newGoal,
            phase: newPhase,
            priorityMuscles: prioritySet,
            plannedWeeks: plannedWeeks,
            varietyPreference: varietyPreference,
            carriedExercises: Set(carried)
        )

        let facts = buildFacts(
            fromGoal: current.goal,
            toGoal: newGoal,
            carried: carried.count,
            dropped: dropped.count,
            status: closed.status
        )

        return BlockTransitionOutcome(
            closedBlock: closed,
            newBlock: newBlock,
            carriedOverExercises: carried,
            droppedExercises: dropped,
            facts: facts
        )
    }

    // MARK: - New block

    private func buildNewBlock(
        from current: TrainingBlock,
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        priorityMuscles: Set<MuscleGroup.ID>,
        plannedWeeks: Int,
        varietyPreference: VarietyPreference,
        carriedExercises: Set<ExerciseID>
    ) throws -> TrainingBlock {
        // Continuidad estructural: conservamos las plantillas de sesión llevando sólo
        // los ejercicios que se mantienen, preservando la prescripción original.
        var sessions: [SessionTemplate] = []
        for session in current.sessions {
            var keptSets: [PlannedSet] = []
            for planned in session.plannedSets where carriedExercises.contains(planned.exerciseID) {
                keptSets.append(planned)
            }
            guard !keptSets.isEmpty else { continue }
            sessions.append(SessionTemplate(title: session.title, plannedSets: keptSets))
        }

        let muscleTargets = try priorityMuscles.map { muscle in
            try MuscleVolumeTarget(muscleGroupID: muscle, targetSetsPerWeek: 1)
        }
        let priorities = priorityMuscles.map { MusclePriority(muscleGroupID: $0, priority: .normal) }

        return try TrainingBlock(
            id: TrainingBlockID(),
            name: goal.rawValue.capitalized + " block",
            goal: goal,
            phase: phase,
            plannedWeeks: plannedWeeks,
            sessions: sessions,
            muscleTargets: muscleTargets,
            priorities: priorities,
            progressionPolicy: .doubleProgression,
            deloadPolicy: plannedWeeks == 8 ? .afterEightWeeks : (plannedWeeks >= 6 ? .afterSixWeeks : .none),
            varietyPolicy: try VarietyPolicy(percentStable: Self.stablePercent(for: varietyPreference)),
            status: .planned
        )
    }

    private static func stablePercent(for variety: VarietyPreference) -> Double {
        switch variety {
        case .stable: return 0.8
        case .balanced: return 0.65
        case .varied: return 0.55
        }
    }

    private func buildFacts(
        fromGoal: TrainingGoal,
        toGoal: TrainingGoal,
        carried: Int,
        dropped: Int,
        status: BlockStatus
    ) -> [DecisionFact] {
        [
            DecisionFact(key: "transition.fromGoal", value: fromGoal.rawValue),
            DecisionFact(key: "transition.toGoal", value: toGoal.rawValue),
            DecisionFact(key: "transition.carriedExercises", value: String(carried)),
            DecisionFact(key: "transition.droppedExercises", value: String(dropped)),
            DecisionFact(key: "transition.closedStatus", value: status.rawValue),
        ]
    }
}

private extension TrainingBlock {
    /// Ejercicios planeados (sin duplicados) a lo largo del bloque, en orden de aparición.
    var distinctPlannedExercises: [ExerciseID] {
        var seen: Set<ExerciseID> = []
        var ordered: [ExerciseID] = []
        for session in sessions {
            for planned in session.plannedSets where !seen.contains(planned.exerciseID) {
                seen.insert(planned.exerciseID)
                ordered.append(planned.exerciseID)
            }
        }
        return ordered
    }
}