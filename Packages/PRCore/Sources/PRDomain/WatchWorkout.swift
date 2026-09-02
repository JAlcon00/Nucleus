//
//  WatchWorkout.swift
//  PRDomain
//
//  Created by PR.
//
//  Watch workout UI driver (plan §14 Fase 11, EPIC-12, PR-1201). Deriva, desde el
//  estado de la sesión activa y la plantilla, el set actual a mostrar en el Watch:
//  ejercicio, peso, reps, índice del set, fin de los sets del ejercicio y estado de
//  descanso. Lógica pura (sin Views). La shell SwiftUI del Watch renderiza este estado
//  con touch targets adecuados. Reutiliza SetCompleter (PR-0603) y RestTimer (PR-0604);
//  determinista.
//

import Foundation

/// Presentación del set actual para la UI del Watch (PR-1201).
public struct WatchSetPresentation: Equatable, Sendable {
    public var exerciseID: ExerciseID
    /// Peso target precargado (desde prescripción o último realizado).
    public var weight: Double
    public var unit: LoadUnit
    /// Reps objetivo (rango inferior de la prescripción).
    public var reps: Int
    /// Nº del set dentro del ejercicio (1-based).
    public var currentSetIndex: Int
    /// Total de sets planeados del ejercicio.
    public var totalSetsInExercise: Int
    public var isWarmup: Bool
    public var targetRepRange: ClosedRange<Int>

    public init(
        exerciseID: ExerciseID,
        weight: Double,
        unit: LoadUnit,
        reps: Int,
        currentSetIndex: Int,
        totalSetsInExercise: Int,
        isWarmup: Bool,
        targetRepRange: ClosedRange<Int>
    ) {
        self.exerciseID = exerciseID
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.currentSetIndex = currentSetIndex
        self.totalSetsInExercise = totalSetsInExercise
        self.isWarmup = isWarmup
        self.targetRepRange = targetRepRange
    }
}

/// Indica si aún quedan sets por completar en la sesión.
public enum WatchWorkoutProgress: Equatable, Sendable {
    /// Texto del ejercicio actual + datos. totalSets restantes > 0.
    case inProgress(WatchSetPresentation)
    /// La sesión planeada está completa: todos los sets realizados.
    case complete
    /// No hay plantilla / nada que mostrar.
    case idle
}

/// Driver determinista del workout en el Watch (PR-1201).
///
/// Reglas:
/// - el set actual es el primer set planeado (en orden) cuyo ejercicio aún no ha
///   completado todos sus sets — los `SetRecord` completados se mapean por orden de
///   desempeño dentro de cada ejercicio;
/// - peso/reps target se precargan con `SetCompleter.preload` (prescripción o último
///   peso realizado); nunca se inventa un peso;
/// - el descanso sugerido usa `RestTimer` (PR-0604) y sobrevive background vía wall-clock.
public struct WatchWorkoutDriver: Sendable {

    public init() {}

    /// Devuelve el set actual a mostrar, o `.complete` cuando no quedan sets.
    public func current(
        template: SessionTemplate,
        performedSets: [SetRecord],
        lastPerformedWeightByExercise: [ExerciseID: Double] = [:],
        now: Date = Date()
    ) -> WatchWorkoutProgress {
        guard !template.plannedSets.isEmpty else { return .idle }

        let completedCount = Self.countCompletedByExercise(performedSets)
        var slotByExercise: [ExerciseID: Int] = [:]
        let completer = SetCompleter()

        for planned in template.plannedSets {
            let slot = slotByExercise[planned.exerciseID] ?? 0
            slotByExercise[planned.exerciseID] = slot + 1
            let done = completedCount[planned.exerciseID] ?? 0
            guard done <= slot else { continue }

            let prescription = planned.prescription
            let draft = completer.preload(
                for: planned,
                lastPerformedWeight: lastPerformedWeightByExercise[planned.exerciseID]
            )
            let totalInExercise = template.plannedSets.filter { $0.exerciseID == planned.exerciseID }.count
            let presentation = WatchSetPresentation(
                exerciseID: planned.exerciseID,
                weight: draft.targetWeight,
                unit: draft.targetUnit,
                reps: draft.targetReps,
                currentSetIndex: slot + 1,
                totalSetsInExercise: totalInExercise,
                isWarmup: prescription.isWarmup,
                targetRepRange: prescription.targetRepRange
            )
            return .inProgress(presentation)
        }
        return .complete
    }

    /// Estado de descanso sugerido tras completar un set (usando RestTimer, PR-0604).
    public func restSuggested(
        afterCompleted planned: PlannedSet,
        now: Date = Date()
    ) -> RestTimerState {
        RestTimer().autoStart(
            afterCompletedWarmup: planned.prescription.isWarmup,
            prescription: planned.prescription,
            now: now
        )
    }

    /// Conteo de sets completados por ejercicio.
    private static func countCompletedByExercise(_ sets: [SetRecord]) -> [ExerciseID: Int] {
        sets.reduce(into: [:]) { result, set in
            guard set.lifecycle == .completed else { return }
            result[set.exerciseID, default: 0] += 1
        }
    }
}