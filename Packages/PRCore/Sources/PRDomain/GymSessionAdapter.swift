//
//  GymSessionAdapter.swift
//  PRDomain
//
//  SCRUM-236 (PR-E005): lo que no hay en el gimnasio activo se aplica ENCIMA del plan al armar
//  el día. El bloque guardado no cambia, así marcar o quitar es reversible y cambiar de
//  gimnasio sólo cambia lo que se aplica. Nunca se programa una máquina que no existe
//  (RN-006). Sin azar: mismo gimnasio y mismo plan, mismo resultado.
//

import Foundation

/// "En este gimnasio no hay `exercise`; se hace `replacement`". Sin sustituto equivalente,
/// `replacement` es `nil` y el ejercicio se omite.
public struct MissingExercise: Codable, Sendable, Hashable {
    public let exercise: ExerciseID
    public var replacement: ExerciseID?

    public init(exercise: ExerciseID, replacement: ExerciseID?) {
        self.exercise = exercise
        self.replacement = replacement
    }
}

/// Qué cambió el gimnasio en una sesión, para explicarlo.
public enum GymAdaptationNote: Equatable, Sendable, Hashable {
    case replaced(original: ExerciseID, replacement: ExerciseID)
    /// No hay sustituto equivalente y seguro: el ejercicio no se programa.
    case omitted(original: ExerciseID)
}

public struct GymAdaptation: Equatable, Sendable {
    public let block: TrainingBlock
    public let notes: [SessionTemplate.ID: [GymAdaptationNote]]

    public init(block: TrainingBlock, notes: [SessionTemplate.ID: [GymAdaptationNote]]) {
        self.block = block
        self.notes = notes
    }
}

public struct GymSessionAdapter: Sendable {
    public let equivalence: SubstitutionScoringEngine

    public init(equivalence: SubstitutionScoringEngine) {
        self.equivalence = equivalence
    }

    public static func standard() throws -> GymSessionAdapter {
        GymSessionAdapter(equivalence: SubstitutionScoringEngine(
            config: try SubstitutionScoringConfig(rule: SubstitutionScoringDefaults.makeRule())
        ))
    }

    /// El bloque con lo que no hay ya cambiado. Sin marcas devuelve el mismo bloque.
    public func adapt(
        _ block: TrainingBlock,
        gym: GymProfile?,
        catalog: [Exercise],
        restrictions: [TrainingRestriction],
        now: Date
    ) throws -> GymAdaptation {
        let missing = gym?.missingExercises ?? []
        guard !missing.isEmpty else { return GymAdaptation(block: block, notes: [:]) }
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let unavailable = Set(missing.map(\.exercise))
        var result = block
        var notes: [SessionTemplate.ID: [GymAdaptationNote]] = [:]
        result.sessions = try block.sessions.map { session in
            var adapted = session
            for mark in missing where adapted.plannedSets.contains(where: { $0.exerciseID == mark.exercise }) {
                let chosen = try replacement(
                    for: mark, in: adapted, byID: byID, catalog: catalog,
                    unavailable: unavailable, restrictions: restrictions, now: now
                )
                adapted = applying(chosen, to: mark.exercise, in: adapted)
                notes[session.id, default: []].append(
                    chosen.map { .replaced(original: mark.exercise, replacement: $0) } ?? .omitted(original: mark.exercise)
                )
            }
            return adapted
        }
        return GymAdaptation(block: result, notes: notes)
    }

    /// El sustituto elegido si sigue valiendo (seguro y fuera de la sesión) y, si no, el mejor
    /// equivalente. `nil` si no hay ninguno.
    private func replacement(
        for mark: MissingExercise,
        in session: SessionTemplate,
        byID: [ExerciseID: Exercise],
        catalog: [Exercise],
        unavailable: Set<ExerciseID>,
        restrictions: [TrainingRestriction],
        now: Date
    ) throws -> ExerciseID? {
        guard let target = byID[mark.exercise] else { return nil }
        let inSession = Set(session.plannedSets.map(\.exerciseID))
        func best(among candidates: [Exercise]) throws -> ExerciseID? {
            try equivalence.substitutes(for: SubstitutionRequest(
                target: target, candidates: candidates, unavailableExerciseIDs: unavailable,
                sessionExerciseIDs: inSession, activeRestrictions: restrictions, asOf: now
            )).ranked.first?.exercise.id
        }
        if let chosen = mark.replacement.flatMap({ byID[$0] }), let valid = try best(among: [chosen]) {
            return valid
        }
        return try best(among: catalog)
    }

    /// Cambia (u omite) el ejercicio en la sesión. La carga no se hereda (RN-007) y el
    /// superset se deshace: el sustituto va solo.
    private func applying(_ replacement: ExerciseID?, to exercise: ExerciseID, in session: SessionTemplate) -> SessionTemplate {
        var adapted = session
        if let replacement {
            adapted.plannedSets = session.plannedSets.map { planned in
                guard planned.exerciseID == exercise else { return planned }
                var moved = planned
                moved.exerciseID = replacement
                moved.prescription.targetLoad = nil
                return moved
            }
        } else {
            adapted.plannedSets = session.plannedSets.filter { $0.exerciseID != exercise }
        }
        adapted.supersets = session.supersets?.filter { !$0.contains(exercise) }
        return adapted
    }
}
