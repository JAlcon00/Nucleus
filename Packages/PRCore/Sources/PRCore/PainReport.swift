//
//  PainReport.swift
//  PRCore
//
//  SCRUM-226: lo que muestra la hoja "¿Te dolió?" del descanso. La lógica del dolor es de
//  SCRUM-32 (`WorkoutSessionCoordinator.reportPain`, `PainFeedbackEngine`); aquí sólo se
//  describe la última serie hecha para que la pantalla no decida nada.
//

import Foundation
import PRDomain

/// La última serie hecha, vista desde el reporte de dolor. La UI sólo la presenta.
public struct PainReportUI: Equatable, Sendable {
    /// Nombre del ejercicio de la última serie.
    public let exerciseName: String
    /// Nivel ya reportado para esa serie; `nil` si todavía no se dijo nada. Si se cambió,
    /// es el último elegido.
    public let level: PainLevel?
    /// Músculo indicado, si se indicó (es opcional).
    public let muscleGroup: MuscleGroup.ID?
    /// Músculos que trabaja el ejercicio, para decir dónde se sintió. Vacío si no se sabe.
    public let muscleOptions: [MuscleGroup.ID]
    /// Lo que recomienda `PainFeedbackEngine` para el nivel reportado.
    public let recommendation: PainRecommendation
    /// ¿Se puede saltar ese ejercicio? Sólo si le faltan series y no está saltado ya.
    public let canSkipExercise: Bool

    public init(
        exerciseName: String,
        level: PainLevel?,
        muscleGroup: MuscleGroup.ID?,
        muscleOptions: [MuscleGroup.ID],
        recommendation: PainRecommendation,
        canSkipExercise: Bool
    ) {
        self.exerciseName = exerciseName
        self.level = level
        self.muscleGroup = muscleGroup
        self.muscleOptions = muscleOptions
        self.recommendation = recommendation
        self.canSkipExercise = canSkipExercise
    }
}

/// Músculos que se ofrecen para decir dónde dolió: primero los principales del ejercicio y
/// luego los secundarios, sin repetir. Sale del catálogo, no de la pantalla.
public enum PainMuscleOptions {
    public static func byExercise(_ exercises: [Exercise]) -> [ExerciseID: [MuscleGroup.ID]] {
        var result: [ExerciseID: [MuscleGroup.ID]] = [:]
        for exercise in exercises where result[exercise.id] == nil {
            var seen: Set<MuscleGroup.ID> = []
            result[exercise.id] = (exercise.primaryMuscles + exercise.secondaryMuscles)
                .map(\.muscleGroupID)
                .filter { seen.insert($0).inserted }
        }
        return result
    }
}
