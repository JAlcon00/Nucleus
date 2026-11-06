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
    /// Orden propio de esta sesión, si "Máquina ocupada" adelantó algo (SCRUM-233). Campo
    /// opcional (ADR-0003): sin él manda el orden de la plantilla.
    public var order: [ExerciseID]?
    /// Ejercicios marcados "Máquina ocupada" en esta sesión (SCRUM-233). Sólo vive aquí: la
    /// ocupación no se guarda en el gimnasio ni en el plan (RN-005). Campo opcional.
    public var occupied: [ExerciseID]?

    public init(
        deferred: [ExerciseID] = [],
        skipped: [ExerciseID] = [],
        order: [ExerciseID]? = nil,
        occupied: [ExerciseID]? = nil
    ) {
        self.deferred = deferred
        self.skipped = skipped
        self.order = order
        self.occupied = occupied
    }

    public static let empty = ExerciseQueueState()

    public var isEmpty: Bool { deferred.isEmpty && skipped.isEmpty && order == nil && occupied == nil }
}

public enum WorkoutQueue {
    /// Ejercicios de la plantilla en orden (sin repetir).
    public static func exerciseOrder(of template: SessionTemplate) -> [ExerciseID] {
        var seen: Set<ExerciseID> = []
        return template.plannedSets.compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
    }

    /// Orden efectivo: los no diferidos en el orden de la sesión (el propio, si lo hay, o el
    /// de la plantilla) y, al final, los diferidos en el orden en que se dejaron. Incluye los
    /// saltados (no se pierden).
    public static func effectiveOrder(of template: SessionTemplate, state: ExerciseQueueState) -> [ExerciseID] {
        let planned = exerciseOrder(of: template)
        let custom = (state.order ?? []).filter(planned.contains)
        let order = custom + planned.filter { !custom.contains($0) }
        let deferred = state.deferred.filter(planned.contains)
        return order.filter { !deferred.contains($0) } + deferred
    }

    /// Índice en `plannedSets` de la siguiente serie a hacer, o `nil` si no queda ninguna
    /// (todo hecho o lo que falta está saltado).
    /// SCRUM-224: al llegar a un ejercicio en superset se alterna con su pareja (ver
    /// `supersetTurn`) mientras los dos sigan juntos en la cola.
    public static func nextPlannedIndex(
        template: SessionTemplate,
        sets: [SetRecord],
        state: ExerciseQueueState
    ) -> Int? {
        for exercise in effectiveOrder(of: template, state: state) where !state.skipped.contains(exercise) {
            let turn = supersetTurn(for: exercise, template: template, sets: sets, state: state)
            if let index = nextIndex(of: turn, template: template, sets: sets) {
                return index
            }
            if turn != exercise, let index = nextIndex(of: exercise, template: template, sets: sets) {
                return index
            }
            // El par va completo en el lugar del primero de los dos que aparece: si éste ya
            // terminó, sigue su pareja aunque en la plantilla vaya más adelante.
            if let pair = template.superset(containing: exercise), isTogether(pair, state: state),
               let partner = pair.partner(of: exercise),
               let index = nextIndex(of: partner, template: template, sets: sets) {
                return index
            }
        }
        return nil
    }

    /// Índice de la siguiente serie de `exercise`, por cuántas suyas se hicieron.
    private static func nextIndex(of exercise: ExerciseID, template: SessionTemplate, sets: [SetRecord]) -> Int? {
        let plannedIndices = template.plannedSets.indices.filter { template.plannedSets[$0].exerciseID == exercise }
        let done = sets.filter { $0.exerciseID == exercise }.count
        return done < plannedIndices.count ? plannedIndices[done] : nil
    }

    /// ¿Los dos ejercicios del par siguen juntos en la cola? Ninguno saltado ni ocupado, y
    /// los dos diferidos o ninguno: dejar uno para después, marcarlo ocupado o saltarlo lo
    /// separa y su pareja sigue sola (decisión de Jesús, 2026-10-30).
    public static func isTogether(_ pair: SupersetPair, state: ExerciseQueueState) -> Bool {
        let occupied = state.occupied ?? []
        return !state.skipped.contains(pair.first) && !state.skipped.contains(pair.second)
            && !occupied.contains(pair.first) && !occupied.contains(pair.second)
            && state.deferred.contains(pair.first) == state.deferred.contains(pair.second)
    }

    /// A quién le toca dentro del superset de `exercise`: el que tenga calentamiento
    /// pendiente; si no, el que lleve menos series de trabajo; empatados, el primero del par.
    /// Sin superset (o con la pareja separada o sin series pendientes), `exercise`.
    public static func supersetTurn(
        for exercise: ExerciseID,
        template: SessionTemplate,
        sets: [SetRecord],
        state: ExerciseQueueState
    ) -> ExerciseID {
        guard let pair = template.superset(containing: exercise), isTogether(pair, state: state),
              hasPendingSets(pair.first, template: template, sets: sets),
              hasPendingSets(pair.second, template: template, sets: sets) else { return exercise }
        let members = [pair.first, pair.second]
        if let warmingUp = members.first(where: { member in
            nextIndex(of: member, template: template, sets: sets).map { template.plannedSets[$0].prescription.isWarmup } ?? false
        }) {
            return warmingUp
        }
        let firstDone = workSetsDone(pair.first, template: template, sets: sets)
        let secondDone = workSetsDone(pair.second, template: template, sets: sets)
        return secondDone < firstDone ? pair.second : pair.first
    }

    /// ¿Después de la serie que se acaba de completar (de `completed`) se sigue con la
    /// pareja sin descansar? Sí cuando la siguiente es una serie de trabajo de la pareja y
    /// la pareja va una ronda atrás: A → B → descanso (SCRUM-224).
    public static func continuesSupersetRound(
        after completed: ExerciseID,
        template: SessionTemplate,
        sets: [SetRecord],
        state: ExerciseQueueState
    ) -> Bool {
        guard let pair = template.superset(containing: completed), isTogether(pair, state: state),
              let partner = pair.partner(of: completed),
              let next = nextPlannedIndex(template: template, sets: sets, state: state),
              template.plannedSets[next].exerciseID == partner,
              !template.plannedSets[next].prescription.isWarmup else { return false }
        return workSetsDone(partner, template: template, sets: sets) < workSetsDone(completed, template: template, sets: sets)
    }

    /// Series de trabajo (sin calentamiento) ya hechas del ejercicio, por el orden de la plantilla.
    private static func workSetsDone(_ exercise: ExerciseID, template: SessionTemplate, sets: [SetRecord]) -> Int {
        let planned = template.plannedSets.filter { $0.exerciseID == exercise }
        let done = min(sets.filter { $0.exerciseID == exercise }.count, planned.count)
        return planned.prefix(done).filter { !$0.prescription.isWarmup }.count
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

    /// Lo que queda por hacer además de `exercise`, en el orden efectivo. Un saltado no cuenta.
    public static func pendingOthers(
        than exercise: ExerciseID,
        template: SessionTemplate,
        sets: [SetRecord],
        state: ExerciseQueueState
    ) -> [ExerciseID] {
        effectiveOrder(of: template, state: state).filter { other in
            other != exercise && !state.skipped.contains(other)
                && hasPendingSets(other, template: template, sets: sets)
        }
    }

    /// Marca el ejercicio como ocupado en esta sesión (idempotente).
    public static func markingOccupied(_ exercise: ExerciseID, in state: ExerciseQueueState) -> ExerciseQueueState {
        guard !(state.occupied ?? []).contains(exercise) else { return state }
        var next = state
        next.occupied = (state.occupied ?? []) + [exercise]
        return next
    }

    /// "Máquina ocupada" con adelanto seguro: `candidate` pasa a ser el actual y `exercise`
    /// queda justo después. Los dos dejan de estar diferidos: los coloca este orden.
    public static func advancing(
        _ candidate: ExerciseID,
        before exercise: ExerciseID,
        in state: ExerciseQueueState,
        template: SessionTemplate
    ) -> ExerciseQueueState {
        let rest = effectiveOrder(of: template, state: state).filter { $0 != candidate && $0 != exercise }
        var next = markingOccupied(exercise, in: state)
        next.deferred.removeAll { $0 == candidate || $0 == exercise }
        next.order = [candidate, exercise] + rest
        return next
    }

    /// SCRUM-234: las series pendientes de `exercise` pasan a `replacement`; las hechas se
    /// quedan como están y el total no cambia. La carga planeada no se hereda: nunca se
    /// transfiere entre ejercicios (RN-007). Los calentamientos pendientes siguen siéndolo.
    public static func substituting(
        _ exercise: ExerciseID,
        with replacement: ExerciseID,
        in template: SessionTemplate,
        sets: [SetRecord]
    ) -> SessionTemplate {
        var pendingFrom = sets.filter { $0.exerciseID == exercise }.count
        var result = template
        result.plannedSets = template.plannedSets.map { planned in
            guard planned.exerciseID == exercise else { return planned }
            guard pendingFrom == 0 else {
                pendingFrom -= 1
                return planned
            }
            var moved = planned
            moved.exerciseID = replacement
            moved.prescription.targetLoad = nil
            return moved
        }
        return result
    }

    /// La cola tras sustituir: `replacement` toma el lugar de `exercise`, que queda ocupado.
    public static func replacing(
        _ exercise: ExerciseID,
        with replacement: ExerciseID,
        in state: ExerciseQueueState,
        template: SessionTemplate
    ) -> ExerciseQueueState {
        let order = effectiveOrder(of: template, state: state).flatMap { $0 == exercise ? [replacement, exercise] : [$0] }
        var next = markingOccupied(exercise, in: state)
        next.deferred.removeAll { $0 == exercise }
        next.order = order
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
