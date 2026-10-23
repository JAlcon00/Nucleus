//
//  SessionOrderOverride.swift
//  PRDomain
//
//  SCRUM-211 (FB-4): la persona puede cambiar el orden de los ejercicios de una sesión
//  aunque el motor (o la IA) haya recomendado otro.
//
//  Reglas:
//  - El orden propio es una permutación exacta de los ejercicios de la sesión: no agrega
//    ni quita ejercicios (`isPermutation`).
//  - Reordenar mueve cada ejercicio con TODAS sus series (calentamiento incluido) y en
//    su orden interno; la prescripción (series, reps, RIR, carga, descanso) no cambia.
//  - El bloque del motor no se toca: el orden propio se aplica encima y "restablecer"
//    sólo lo quita. Un orden de una sesión que ya no existe se ignora.
//

import Foundation

public enum SessionOrderOverride {
    /// Ejercicios de la sesión en el orden en que aparecen (sin repetir).
    public static func exerciseOrder(of template: SessionTemplate) -> [ExerciseID] {
        var seen: Set<ExerciseID> = []
        return template.plannedSets.compactMap { seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil }
    }

    /// ¿`order` tiene exactamente los mismos ejercicios de la sesión, sin repetir?
    public static func isPermutation(_ order: [ExerciseID], of template: SessionTemplate) -> Bool {
        let current = exerciseOrder(of: template)
        return order.count == current.count && Set(order) == Set(current) && Set(order).count == order.count
    }

    /// La sesión con sus ejercicios en `order`. Si `order` no es una permutación válida,
    /// la sesión queda como estaba (nunca se pierde ni se inventa un ejercicio).
    public static func apply(_ order: [ExerciseID], to template: SessionTemplate) -> SessionTemplate {
        guard isPermutation(order, of: template) else { return template }
        let groups = Dictionary(grouping: template.plannedSets, by: \.exerciseID)
        var reordered = template
        reordered.plannedSets = order.flatMap { groups[$0] ?? [] }
        return reordered
    }

    /// El bloque con los órdenes propios aplicados a sus sesiones.
    public static func apply(_ orders: [SessionTemplate.ID: [ExerciseID]], to block: TrainingBlock) -> TrainingBlock {
        guard !orders.isEmpty else { return block }
        var result = block
        result.sessions = block.sessions.map { session in
            orders[session.id].map { apply($0, to: session) } ?? session
        }
        return result
    }
}
