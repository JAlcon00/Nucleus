//
//  FatigueInterference.swift
//  PRDomain
//
//  Created by PR.
//
//  Fatigue interference model (plan §4D, PR-0702). Penaliza la pre-fatiga de
//  musculatura necesaria para un movimiento prioritario posterior, sin impedir
//  supersets compatibles (sin músculos prioritarios compartidos). La
//  configuración está versionada via `EvidenceRule` (categoría `.ordering`).
//

import Foundation

/// Configuración versionada del modelo de interferencia por fatiga, en forma de
/// regla de evidencia. Centraliza constantes ajustables (SKILL.md: no magic
/// numbers) y permite auditar la versión usada.
public struct FatigueInterferenceConfig: Sendable {
    public let rule: EvidenceRule

    /// Peso base de penalización por unidad de fatiga que pre-fatiga un músculo
    /// prioritario posterior.
    public var penaltyWeight: Double { rule.parameters[FatigueConfigKeys.penaltyWeight] ?? 1.0 }

    /// Umbral mínimo de solapamiento de fatiga para considerar interferencia
    /// significativa (0...1).
    public var minOverlapThreshold: Double { rule.parameters[FatigueConfigKeys.minOverlap] ?? 0.3 }

    /// Si un músculo prioritario compartido está por debajo de este umbral, el
    /// superset se considera compatible y NO se penaliza.
    public var compatibleSupersetThreshold: Double { rule.parameters[FatigueConfigKeys.compatibleThreshold] ?? 0.15 }

    public init(rule: EvidenceRule) throws {
        let missing = FatigueConfigKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw FatigueInterferenceError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Claves canónicas de los parámetros de la regla de interferencia.
public enum FatigueConfigKeys {
    public static let penaltyWeight = "penaltyWeight"
    public static let minOverlap = "minOverlap"
    public static let compatibleThreshold = "compatibleThreshold"

    public static let allRequired: Set<String> = [
        penaltyWeight, minOverlap, compatibleThreshold,
    ]

    /// Valores por defecto (producto; la UI/Evidence Registry los versiona).
    public static func defaults() -> [String: Double] {
        [
            penaltyWeight: 1.0,
            minOverlap: 0.3,
            compatibleThreshold: 0.15,
        ]
    }
}

/// Regla de evidencia por defecto del modelo de interferencia (categoría ordering).
public enum FatigueInterferenceDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "ordering.fatigueInterference")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        try EvidenceRule(
            id: ruleID,
            name: "Fatigue interference penalty",
            category: .ordering,
            confidence: .emerging,
            version: version,
            parameters: FatigueConfigKeys.defaults()
        )
    }
}

/// Problemas de entrada del modelo de interferencia.
public enum FatigueInterferenceError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case insufficientExercises
}

/// Penalización de interferencia entre dos ejercicios consecutivos.
public struct InterferencePenalty: Codable, Sendable, Hashable {
    public let fromExerciseID: ExerciseID
    public let toExerciseID: ExerciseID
    /// Fatiga acumulada sobre músculos necesarios por `to`.
    public let overFatiguedMuscles: [MuscleGroup.ID]
    /// Penalización normalizada (0...1) — 0 si es superset compatible.
    public let penalty: Double

    public init(
        fromExerciseID: ExerciseID,
        toExerciseID: ExerciseID,
        overFatiguedMuscles: [MuscleGroup.ID],
        penalty: Double
    ) {
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.overFatiguedMuscles = overFatiguedMuscles
        self.penalty = penalty
    }
}

/// Resultado de aplicar el modelo de interferencia a un orden propuesto.
public struct InterferenceAssessment: Codable, Sendable {
    /// Orden final (puede reordenarse para minimizar interferencia).
    public let orderedExercises: [Exercise]
    /// Penalizaciones de interferencia detectadas entre pares consecutivos.
    public let penalties: [InterferencePenalty]
    /// Penalización total (suma de penalizaciones).
    public let totalPenalty: Double
    /// Referencia de la regla versionada usada.
    public let ruleReference: EvidenceRuleReference

    public init(
        orderedExercises: [Exercise],
        penalties: [InterferencePenalty],
        totalPenalty: Double,
        ruleReference: EvidenceRuleReference
    ) {
        self.orderedExercises = orderedExercises
        self.penalties = penalties
        self.totalPenalty = totalPenalty
        self.ruleReference = ruleReference
    }
}

/// Modelo de interferencia por fatiga (plan §4D, PR-0702).
///
/// Reglas deterministas y versionadas via `FatigueInterferenceConfig`:
/// - Penaliza cuando un ejercicio anterior pre-fatiga musculatura necesaria para
///   un movimiento prioritario posterior.
/// - Un superset compatible (sin músculos prioritarios compartidos por encima del
///   umbral) NO se penaliza.
/// - `reorder` preserva el orden base del bloque salvo que reordenar reduzca la
///   interferencia; nunca mueve un ejercicio prioritario para acomodar a uno menor.
public struct FatigueInterferenceEngine: Sendable {
    public init() {}

    /// Evalúa la interferencia de un orden propuesto sin reordenar. Para cada
    /// movimiento prioritario posterior se acumula la fatiga de todos los
    /// ejercicios anteriores que pre-fatigan musculatura que necesita (§9.2).
    public func assess(input: [Exercise], config: FatigueInterferenceConfig) throws -> InterferenceAssessment {
        guard input.count >= 2 else {
            throw FatigueInterferenceError.insufficientExercises
        }
        let reference = try config.reference()
        var penalties: [InterferencePenalty] = []
        var total: Double = 0

        // Perfil de fatiga acumulada de todos los ejercicios precedentes.
        var accumulated: [MuscleGroup.ID: Double] = [:]
        for index in 0..<(input.count - 1) {
            // El ejercicio actual pre-fatiga a los posteriores.
            Self.accumulate(&accumulated, from: input[index], config: config)
            let to = input[index + 1]
            let penalty = Self.penalty(accumulatedFrom: accumulated, to: to, config: config)
            if penalty.penalty > 0 {
                penalties.append(penalty)
                total += penalty.penalty
            }
        }

        return InterferenceAssessment(
            orderedExercises: input,
            penalties: penalties,
            totalPenalty: total,
            ruleReference: reference
        )
    }

    /// Reordena el bloque para minimizar interferencia preservando prioridad base.
    public func reorder(input: [Exercise], config: FatigueInterferenceConfig) throws -> InterferenceAssessment {
        guard input.count >= 2 else {
            throw FatigueInterferenceError.insufficientExercises
        }
        let base = try assess(input: input, config: config)
        if base.totalPenalty == 0 { return base }

        // Candidato: orden por nivel de prioridad desc (estable). Si reducir la
        // interferencia, se adopta; si no, se preserva el orden base. Nunca se
        // mueve un movimiento prioritario después de uno menos prioritario.
        let candidate = input.sorted { lhs, rhs in
            Self.priorityLevel(lhs) > Self.priorityLevel(rhs)
        }
        if candidate != input, try assess(input: candidate, config: config).totalPenalty < base.totalPenalty {
            return try assess(input: candidate, config: config)
        }
        return base
    }

    // MARK: - Core interference

    /// Penalización de `accumulatedFrom` pre-fatigando musculatura que `to`
    /// (movimiento prioritario) necesita.
    public static func penalty(
        accumulatedFrom: [MuscleGroup.ID: Double],
        to: Exercise,
        config: FatigueInterferenceConfig
    ) -> InterferencePenalty {
        // Sólo se protege el "movimiento prioritario posterior" (§9.2): un
        // compuesto/anchor/priorityIsolation. Pre-fatigar un aislado accesorio
        // de baja prioridad no genera interferencia que reordenar.
        guard Self.isPriorityMovement(to) else {
            return InterferencePenalty(
                fromExerciseID: to.id,
                toExerciseID: to.id,
                overFatiguedMuscles: [],
                penalty: 0
            )
        }

        // Músculos que `to` necesita y están pre-fatigados por ejercicios previos.
        let required = requiredMuscles(to)
        var overFatigued: [MuscleGroup.ID] = []
        var maxOverlap: Double = 0

        for muscle in required {
            let priorFatigue = accumulatedFrom[muscle] ?? 0
            if priorFatigue >= config.minOverlapThreshold {
                overFatigued.append(muscle)
                maxOverlap = max(maxOverlap, priorFatigue)
            }
        }

        // Superset compatible: si el máximo solapamiento es bajo, no penalizamos.
        guard !overFatigued.isEmpty, maxOverlap >= config.compatibleSupersetThreshold else {
            return InterferencePenalty(
                fromExerciseID: to.id,
                toExerciseID: to.id,
                overFatiguedMuscles: [],
                penalty: 0
            )
        }

        let penalty = min(1.0, maxOverlap * config.penaltyWeight)
        return InterferencePenalty(
            fromExerciseID: to.id,
            toExerciseID: to.id,
            overFatiguedMuscles: overFatigued,
            penalty: penalty
        )
    }

    // MARK: - Helpers

    /// Acumula la fatiga local de un ejercicio al perfil previo (cap 0...1).
    private static func accumulate(
        _ profile: inout [MuscleGroup.ID: Double],
        from exercise: Exercise,
        config: FatigueInterferenceConfig
    ) {
        for (muscle, cost) in exercise.localFatigue {
            let prior = profile[muscle] ?? 0
            profile[muscle] = min(1.0, prior + cost.normalized)
        }
    }

    // MARK: - Helpers

    /// Músculos requeridos por un ejercicio (primarios, y secundarios relevantes).
    private static func requiredMuscles(_ exercise: Exercise) -> Set<MuscleGroup.ID> {
        Set(exercise.primaryMuscles.map(\.muscleGroupID) + exercise.secondaryMuscles.map(\.muscleGroupID))
    }

    /// Nivel de prioridad de rol para que el reorder no perjudique movimientos clave.
    private static func priorityLevel(_ exercise: Exercise) -> Int {
        let roles = exercise.defaultRoles
        if roles.contains(.primaryCompound) || roles.contains(.secondaryCompound) { return 3 }
        if roles.contains(.priorityIsolation) { return 2 }
        if roles.contains(.anchor) { return 2 }
        return 1
    }

    /// Indica si un ejercicio es un "movimiento prioritario" a proteger (§9.2).
    private static func isPriorityMovement(_ exercise: Exercise) -> Bool {
        let roles = exercise.defaultRoles
        return roles.contains(.primaryCompound)
            || roles.contains(.secondaryCompound)
            || roles.contains(.priorityIsolation)
            || roles.contains(.anchor)
    }
}