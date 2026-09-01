//
//  SetCompleter.swift
//  PRDomain
//
//  Created by PR.
//
//  One-tap set completion service (plan §8, PR-0603). Precarga target
//  weight/reps desde la prescripción y registra un set con un tap si coinciden;
//  permite editar peso/reps de forma accesible, y siempre persiste el set en la
//  sesión activa ANTES de cualquier transición de UI final. Determinista y sin
//  lógica en Views.
//

import Foundation

/// Resumen de lo realizado en un set (datos editables del usuario).
public struct SetCompletionInput: Sendable, Hashable {
    public var weight: Double
    public var unit: LoadUnit
    public var reps: Int

    public init(weight: Double, unit: LoadUnit, reps: Int) {
        self.weight = weight
        self.unit = unit
        self.reps = reps
    }
}

/// Borrador con target precargados para un set planeado (PR-0603).
public struct SetCompletionDraft: Sendable, Hashable {
    /// Peso sugerido (target) para precargar.
    public var targetWeight: Double
    /// Unidad del peso sugerido.
    public var targetUnit: LoadUnit
    /// Repeticiones objetivo (rango inferior de la prescripción) para precargar.
    public var targetReps: Int
    /// Rango de reps de la prescripción (referencia para edición).
    public var targetRepRange: ClosedRange<Int>
    /// ¿Se derivó el peso de un set previo (progresión) y no de la prescripción?
    public var weightFromHistory: Bool

    /// Un tap registra sólo si el input coincide exactamente con el target.
    public func matches(_ input: SetCompletionInput) -> Bool {
        input.unit == targetUnit
            && input.weight == targetWeight
            && input.reps == targetReps
    }
}

/// Problemas del completado de sets.
public enum SetCompletionError: Error, Equatable, Sendable {
    case invalidWeight(Double)
    case invalidReps(Int)
    case noTargetRepRange
}

/// Servicio de completado de sets de una sesión (plan §8, PR-0603).
///
/// Reglas deterministas:
/// - `preload` construye el target desde la prescripción (`targetLoad`) y, si no
///   hay targetLoad, desde el último peso realizado del ejercicio; reps target desde
///   el rango inferior.
/// - `oneTap` registra el set sólo si el input coincide con el target; persiste en
///   la sesión activa ANTES de cualquier transición UI.
/// - `recordSet` permite editar peso/reps de forma accesible y registra un working
///   set completado.
/// - Ambas operaciones son append-only: nunca mutan sets previos ni el historial.
public struct SetCompleter: Sendable {

    public init() {}

    /// Precarga el target de peso/reps para un set planeado.
    public func preload(
        for planned: PlannedSet,
        lastPerformedWeight: Double? = nil
    ) -> SetCompletionDraft {
        let prescription = planned.prescription
        let unit = prescription.loadUnit
        let reps = prescription.targetRepRange.lowerBound

        // El diseño no inventa: si la prescripción trae targetLoad lo usa; si no,
        // usa el último peso realizado del ejercicio; y si no hay ninguno, 0 como
        // placeholder editable.
        let weight: Double
        let weightFromHistory: Bool
        if let targetLoad = prescription.targetLoad {
            weight = targetLoad
            weightFromHistory = false
        } else if let last = lastPerformedWeight, last.isFinite, last >= 0 {
            weight = last
            weightFromHistory = true
        } else {
            weight = 0
            weightFromHistory = false
        }

        return SetCompletionDraft(
            targetWeight: weight,
            targetUnit: unit,
            targetReps: reps,
            targetRepRange: prescription.targetRepRange,
            weightFromHistory: weightFromHistory
        )
    }

    /// Registra con un tap si el input coincide con el target. Si no coincide,
    /// lanza nil result para que la UI ofrezca edición (no fuerza un registro
    /// erróneo).
    public func oneTap(
        input: SetCompletionInput,
        matches draft: SetCompletionDraft,
        planned: PlannedSet,
        in session: WorkoutSessionRecord,
        performedAt: Date = Date()
    ) throws -> WorkoutSessionRecord? {
        guard draft.matches(input) else { return nil }
        let record = try makeCompletedSet(
            from: input,
            exerciseID: planned.exerciseID,
            performedAt: performedAt
        )
        return session.performedSet(record)
    }

    /// Edición accesible: el usuario introduce peso/reps y se registra un working
    /// set completado (persistido antes de cualquier transición UI).
    public func recordSet(
        input: SetCompletionInput,
        planned: PlannedSet,
        in session: WorkoutSessionRecord,
        performedAt: Date = Date()
    ) throws -> WorkoutSessionRecord {
        let record = try makeCompletedSet(
            from: input,
            exerciseID: planned.exerciseID,
            performedAt: performedAt
        )
        return session.performedSet(record)
    }

    // MARK: - Helpers

    private func makeCompletedSet(
        from input: SetCompletionInput,
        exerciseID: ExerciseID,
        performedAt: Date
    ) throws -> SetRecord {
        try SetRecord(
            exerciseID: exerciseID,
            performedAt: performedAt,
            weight: input.weight,
            unit: input.unit,
            reps: input.reps,
            lifecycle: .completed
        )
    }
}