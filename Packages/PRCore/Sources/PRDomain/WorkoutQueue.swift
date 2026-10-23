//
//  WorkoutQueue.swift
//  PRDomain
//
//  SCRUM-212 (FB-5): dentro del entrenamiento la persona puede dejar un ejercicio para
//  después (la máquina está ocupada) o saltarlo.
//
//  Reglas (integridad de datos primero):
//  - Las series hechas nunca se tocan. Saltar NO crea series: el ejercicio queda marcado
//    como saltado en la sesión.
//  - "Dejar para después" manda el ejercicio al final de la cola; vuelve a aparecer.
//  - Un saltado se puede retomar mientras la sesión siga abierta: vuelve al final.
//  - La siguiente serie se calcula por ejercicio (cuántas series de ESE ejercicio ya se
//    hicieron), no por posición. Sin esperas ni saltos el resultado es idéntico al de
//    antes (`plannedSets[sets.count]`), así una sesión guardada antes se retoma igual.
//  - El estado vive en la sesión (`WorkoutSessionRecord.queue`) y se guarda con ella:
//    sobrevive a cerrar la app.
//

import Foundation

/// Esperas y saltos de una sesión en curso.
public struct ExerciseQueueState: Codable, Sendable, Hashable {
    /// Ejercicios dejados para después, en el orden en que se dejaron (van al final).
    public var deferred: [ExerciseID]
    /// Ejercicios saltados, en el orden en que se saltaron.
    public var skipped: [ExerciseID]

    public init(deferred: [ExerciseID] = [], skipped: [ExerciseID] = []) {
        self.deferred = deferred
        self.skipped = skipped
    }

    public static let empty = ExerciseQueueState()

    public var isEmpty: Bool { deferred.isEmpty && skipped.isEmpty }
}

public enum WorkoutQueue {
    /// Ejercicios de la plantilla en orden (sin repetir).
    public static func exerciseOrder(of template: SessionTemplate) -> [ExerciseID] {
        var seen: Set<ExerciseID> = []
        return template.plannedSets.compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
    }

    /// Orden efectivo: los no diferidos en el orden de la plantilla y, al final, los
    /// diferidos en el orden en que se dejaron. Incluye los saltados (no se pierden).
    public static func effectiveOrder(of template: SessionTemplate, state: ExerciseQueueState) -> [ExerciseID] {
        let order = exerciseOrder(of: template)
        let deferred = state.deferred.filter(order.contains)
        return order.filter { !deferred.contains($0) } + deferred
    }

    /// Índice en `plannedSets` de la siguiente serie a hacer, o `nil` si no queda ninguna
    /// (todo hecho o lo que falta está saltado).
    public static func nextPlannedIndex(
        template: SessionTemplate,
        sets: [SetRecord],
        state: ExerciseQueueState
    ) -> Int? {
        for exercise in effectiveOrder(of: template, state: state) where !state.skipped.contains(exercise) {
            let plannedIndices = template.plannedSets.indices.filter { template.plannedSets[$0].exerciseID == exercise }
            let done = sets.filter { $0.exerciseID == exercise }.count
            if done < plannedIndices.count {
                return plannedIndices[done]
            }
        }
        return nil
    }

    /// ¿Al ejercicio le faltan series?
    public static func hasPendingSets(_ exercise: ExerciseID, template: SessionTemplate, sets: [SetRecord]) -> Bool {
        let planned = template.plannedSets.filter { $0.exerciseID == exercise }.count
        return sets.filter { $0.exerciseID == exercise }.count < planned
    }

    /// Manda el ejercicio al final de la cola. Sólo si le faltan series.
    public static func deferring(
        _ exercise: ExerciseID,
        in state: ExerciseQueueState,
        template: SessionTemplate,
        sets: [SetRecord]
    ) -> ExerciseQueueState {
        guard hasPendingSets(exercise, template: template, sets: sets) else { return state }
        var next = state
        next.deferred.removeAll { $0 == exercise }
        next.deferred.append(exercise)
        return next
    }

    /// Marca el ejercicio como saltado (idempotente). Sólo si le faltan series.
    public static func skipping(
        _ exercise: ExerciseID,
        in state: ExerciseQueueState,
        template: SessionTemplate,
        sets: [SetRecord]
    ) -> ExerciseQueueState {
        guard hasPendingSets(exercise, template: template, sets: sets), !state.skipped.contains(exercise) else { return state }
        var next = state
        next.skipped.append(exercise)
        return next
    }

    /// Retoma un saltado: vuelve a la cola, al final (idempotente).
    public static func resuming(_ exercise: ExerciseID, in state: ExerciseQueueState) -> ExerciseQueueState {
        guard state.skipped.contains(exercise) else { return state }
        var next = state
        next.skipped.removeAll { $0 == exercise }
        next.deferred.removeAll { $0 == exercise }
        next.deferred.append(exercise)
        return next
    }
}
