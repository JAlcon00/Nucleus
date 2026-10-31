//
//  SupersetPairing.swift
//  PRDomain
//
//  SCRUM-224: qué dos ejercicios pueden ir en superset. Son compatibles si no comparten
//  ningún músculo, ni principal ni secundario: un remo y un curl no, porque el bíceps
//  trabaja en los dos. Quién no puede entrar nunca (un ancla compuesta) lo decide quien
//  arma la sesión. Puro y determinista.
//

import Foundation

public enum SupersetPairing {
    /// Todos los músculos que trabaja el ejercicio (principales y secundarios).
    public static func muscles(of exercise: Exercise) -> Set<MuscleGroup.ID> {
        Set((exercise.primaryMuscles + exercise.secondaryMuscles).map(\.muscleGroupID))
    }

    /// ¿Pueden ir en superset? Dos ejercicios distintos, con músculos conocidos y sin
    /// ninguno en común. Sin músculos conocidos nunca: no se junta a ciegas.
    public static func areCompatible(_ first: Set<MuscleGroup.ID>, _ second: Set<MuscleGroup.ID>) -> Bool {
        !first.isEmpty && !second.isEmpty && first.isDisjoint(with: second)
    }

    public static func areCompatible(_ first: Exercise, _ second: Exercise) -> Bool {
        first.id != second.id && areCompatible(muscles(of: first), muscles(of: second))
    }

    /// El primer par compatible entre `candidates`, en su orden: el primero que tenga
    /// pareja con el más próximo de los que le siguen. `nil` si no hay ninguno.
    public static func firstPair<Candidate>(
        among candidates: [Candidate],
        compatible: (Candidate, Candidate) -> Bool
    ) -> (first: Int, second: Int)? {
        for first in candidates.indices {
            for second in candidates.indices where second > first && compatible(candidates[first], candidates[second]) {
                return (first, second)
            }
        }
        return nil
    }
}
