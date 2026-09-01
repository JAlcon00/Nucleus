//
//  ExerciseOrder.swift
//  PRDomain
//
//  Created by PR.
//
//  Base ordering rules (plan §4D, PR-0701). Ordena los ejercicios de una sesión
//  de forma determinista por prioridad muscular, rol funcional, demanda de
//  técnica y carga, siguiendo el modelo de puntuación del promptMaster §9.
//  La interferencia por fatiga se modela en PR-0702; aquí sólo orden base.
//

import Foundation

/// Elemento ordenado del block: ejercicio + motivos ordenables.
public struct OrderedExercise: Codable, Sendable, Equatable, Identifiable {
    public let exercise: Exercise
    /// Puntuación de orden base (§9.3 conceptual). Mayor ⇒ va antes.
    public let orderScore: Int
    /// Orden final (1-based) asignado tras ordenar.
    public let rank: Int

    public var id: ExerciseID { exercise.id }

    public init(exercise: Exercise, orderScore: Int, rank: Int) {
        self.exercise = exercise
        self.orderScore = orderScore
        self.rank = rank
    }
}

/// Entradas para el ordenador.
public struct ExerciseOrderInput: Sendable {
    public let exercises: [Exercise]
    /// Prioridades musculares del perfil (para dar prioridad a quironeció del bloque).
    public let priorities: [MusclePriority]
    /// Orden base ya fijo? No: se calcula. Se mantiene el campo para futuros matices.
    public let goal: TrainingGoal

    public init(
        exercises: [Exercise],
        priorities: [MusclePriority],
        goal: TrainingGoal
    ) {
        self.exercises = exercises
        self.priorities = priorities
        self.goal = goal
    }
}

/// Errores del ordenador.
public enum ExerciseOrderError: Error, Equatable, Sendable {
    case emptyInput
}

/// Ordena una sesión de forma determinista (PR-0701, promptMaster §9).
///
/// Reglas de prioridad (alta → baja):
/// 1. restricción/seguridad (manejada por exclusión upstream);
/// 2. técnica/potencia del movimiento prioritario del bloque;
/// 3. músculo prioritario;
/// 4. compuestos principales del objetivo;
/// 5. compuestos secundarios;
/// 6. aislados prioritarios;
/// 7. aislados accesorios;
/// 8. opcionales / conditioning / posing.
///
/// Implementación: `exerciseOrderScore` combina rol y demanda; los empates se
/// resuelven establemente y por nombre canónico para determinismo.
public struct ExerciseOrderEngine: Sendable {
    public init() {}

    public func order(input: ExerciseOrderInput) throws -> [OrderedExercise] {
        guard !input.exercises.isEmpty else { throw ExerciseOrderError.emptyInput }

        let priorities = priorityBy(muscle: input.priorities)
        let scored = input.exercises.map { exercise in
            (exercise, Self.orderScore(for: exercise, priorities: priorities))
        }

        // Orden determinista: score desc, luego nombre canónico asc como tie-break.
        let sorted = scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.canonicalName < rhs.0.canonicalName
        }

        return sorted.enumerated().map { index, pair in
            OrderedExercise(exercise: pair.0, orderScore: pair.1, rank: index + 1)
        }
    }

    // MARK: - Scoring (§9.3 conceptual)

    /// Puntuación de orden base. Mayor ⇒ primero.
    private static func orderScore(for exercise: Exercise, priorities: [MuscleGroup.ID: PriorityTier]) -> Int {
        var score = 0
        score += rolePriority(exercise)
        score += priorityBonus(exercise, priorities: priorities)
        score += skillBonus(exercise)
        score += loadabilityBonus(exercise)
        return score
    }

    /// Rol funcional (prmMaster §9.1 4–8).
    private static func rolePriority(_ exercise: Exercise) -> Int {
        let roles = exercise.defaultRoles
        if roles.contains(.primaryCompound) { return 100 }
        if roles.contains(.secondaryCompound) { return 80 }
        if roles.contains(.priorityIsolation) { return 70 }
        if roles.contains(.accessoryIsolation) { return 50 }
        if roles.contains(.warmup) { return 10 }
        if roles.contains(.mobility) { return 5 }
        if roles.contains(.conditioning) || roles.contains(.posing) { return 1 }
        // Si el ejercicio es anchor pero sin rol compuesto, se trata según su función.
        return 40
    }

    /// Bonus muscular por prioridad del bloque (§9.1 3).
    private static func priorityBonus(_ exercise: Exercise, priorities: [MuscleGroup.ID: PriorityTier]) -> Int {
        let worked = exercise.primaryMuscles.map(\.muscleGroupID) + exercise.secondaryMuscles.map(\.muscleGroupID)
        let best = worked.compactMap { priorities[$0] }.map { bonus(for: $0) }.max() ?? 0
        return best
    }

    private static func bonus(for tier: PriorityTier) -> Int {
        switch tier {
        case .specialize: return 60
        case .emphasize: return 45
        case .normal: return 20
        case .maintain: return 0
        }
    }

    /// Demanda técnica/potencia (§9.1 2): los movimientos de mayor skill y que
    /// exigen potencia fresca van antes.
    private static func skillBonus(_ exercise: Exercise) -> Int {
        if exercise.skillDemand == .high { return 30 }
        if exercise.skillDemand == .moderate { return 15 }
        return 0
    }

    /// Carga (loadability): compuestos pesados antes aislados, pero ya cubierto
    /// por rol. Aquí matizamos por fatiga sistémica: menor fatiga ⇒ más adelante
    /// NO; el orden base favorece ejercicios clave. Devolvemos 0 como base neutral.
    private static func loadabilityBonus(_ exercise: Exercise) -> Int {
        0
    }

    // MARK: - Helpers

    private func priorityBy(muscle priorities: [MusclePriority]) -> [MuscleGroup.ID: PriorityTier] {
        Dictionary(uniqueKeysWithValues: priorities.map { ($0.muscleGroupID, $0.priority) })
    }
}