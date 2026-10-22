//
//  ExerciseAssignment.swift
//  PRDomain
//
//  Created by PR.
//
//  Exercise assignment (plan §4C, PR-0503). Dado un objetivo de volumen por
//  músculo, asigna un exercise `anchor` (estable para medir progreso) y un pool
//  de `rotatable` dentro de la misma familia. Respeta equipment disponible,
//  restricciones y variedad, sin depender de strings ni de LLM. Determinista.
//

import Foundation

/// Dispositivo de ejercicio seleccionado por el assigner.
public struct AssignedExercise: Codable, Sendable, Hashable, Identifiable {
    public let exercise: ExerciseID
    /// Rol dentro del bloque: anchor se mantiene para medir progreso; los
    /// rotatables pueden rotar dentro de una familia compatible.
    public let role: AssignmentRole

    public var id: ExerciseID { exercise }

    public init(exercise: ExerciseID, role: AssignmentRole) {
        self.exercise = exercise
        self.role = role
    }
}

/// Rol de asignación de un ejercicio dentro del bloque.
public enum AssignmentRole: String, Codable, Sendable, CaseIterable, Hashable {
    case anchor
    case rotatable
    case optional
}

/// Regla de evidencia por defecto que documenta la política de anchors/rotatables.
public enum ExerciseAssignmentDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "assignment.anchorRotatable")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        try EvidenceRule(
            id: ruleID,
            name: "Anchor/rotatable assignment policy",
            category: .ordering,
            confidence: .emerging,
            version: version,
            parameters: [
                "stableRotatables": 1,
                "balancedRotatables": 2,
                "variedRotatables": 3,
            ]
        )
    }
}

/// Resultado de la asignación para un grupo muscular: su familia + assignments.
public struct MuscleExerciseAssignment: Codable, Sendable, Hashable {
    public let muscleGroupID: MuscleGroup.ID
    public let familyID: ExerciseFamily.ID
    public let assignments: [AssignedExercise]

    public init(
        muscleGroupID: MuscleGroup.ID,
        familyID: ExerciseFamily.ID,
        assignments: [AssignedExercise]
    ) {
        self.muscleGroupID = muscleGroupID
        self.familyID = familyID
        self.assignments = assignments
    }

    public var anchor: ExerciseID? {
        assignments.first { $0.role == .anchor }?.exercise
    }
}

/// Problemas del assigner.
public enum ExerciseAssignmentError: Error, Equatable, Sendable {
    case noAvailableExercise(muscle: MuscleGroup.ID, familyPatterns: [String])
    case missingRestriction
}

/// Criterios de disponibilidad de equipment.
public enum EquipmentKnownness: Sendable, Hashable {
    /// Sólo se asignan ejercicios con equipment declarado disponible.
    case knownAvailable(Set<EquipmentType>)
    /// No se conoce el equipment; cualquier ejercicio se deja como sugerencia
    /// (la UI pregunta en lugar de programar ciegamente).
    case unknown
}

/// Datos de entrada del assigner.
public struct ExerciseAssignmentInput: Sendable {
    public let muscleGroupID: MuscleGroup.ID
    public let catalog: [Exercise]
    /// Nivel de variedad consultada del perfil (guía para rotar rotatables).
    public let varietyPreference: VarietyPreference
    /// Restricciones activas que blindan la asignación.
    public let restrictions: [TrainingRestriction]
    /// Disponibilidad de equipment (conocido o unknown).
    public let equipmentKnownness: EquipmentKnownness

    public init(
        muscleGroupID: MuscleGroup.ID,
        catalog: [Exercise],
        varietyPreference: VarietyPreference,
        restrictions: [TrainingRestriction],
        equipmentKnownness: EquipmentKnownness
    ) {
        self.muscleGroupID = muscleGroupID
        self.catalog = catalog
        self.varietyPreference = varietyPreference
        self.restrictions = restrictions
        self.equipmentKnownness = equipmentKnownness
    }
}

/// Asigna anchors y rotatables por grupo muscular (PR-0503).
///
/// Reglas deterministas:
/// - Sólo ejercicios del catálogo que trabajen el grupo objetivo.
/// - Equipment: si la disponibilidad es conocida, se excluyen los que usan
///   equipment no disponible; si es unknown, no se descarta nada (la UI pregunta).
/// - Restricciones: se excluyen ejercicios con patrón prohibido o ID prohibido;
///   si un ejercicio está en la lista explícitamente permitida, se respeta.
/// - Con ejercicios de referencia disponibles (lista curada, `Exercise.staple`), el primero
///   por orden de preferencia es el `anchor` y los siguientes los `rotatable` (tantos como
///   indique la variedad). Sin ellos, el mejor candidato por familia es el `anchor` y el resto
///   de la familia los `rotatable`, prefiriendo los que trabajan el músculo como principal.
public struct ExerciseAssigner: Sendable {
    public init() {}

    public func assign(input: ExerciseAssignmentInput) throws -> MuscleExerciseAssignment {
        let working = input.catalog.filter { works($0, muscleGroupID: input.muscleGroupID) }

        let permitted = working.filter { isPermitted($0, input: input) }
        guard !permitted.isEmpty else {
            throw ExerciseAssignmentError.noAvailableExercise(
                muscle: input.muscleGroupID,
                familyPatterns: working.map(\.movementPattern.rawValue)
            )
        }

        // Nº de rotatables según variedad (configurable, respeta anchors).
        let rotatableCount = Self.rotatableCount(for: input.varietyPreference)

        // 1) Ejercicios de referencia del músculo (lista curada, en orden de preferencia).
        //    El primero permitido es el anchor; los siguientes rotan entre días. La lista está
        //    ordenada para que lo consecutivo sea complementario (sentadilla → prensa →
        //    extensión), por eso los rotatables NO se limitan a la familia del anchor.
        let staples = permitted
            .filter { $0.staple?.muscle == input.muscleGroupID }
            .sorted { ($0.staple?.rank ?? .max) < ($1.staple?.rank ?? .max) }
        if let anchor = staples.first {
            var assignments = [AssignedExercise(exercise: anchor.id, role: .anchor)]
            for rotatable in staples.dropFirst().prefix(rotatableCount) {
                assignments.append(AssignedExercise(exercise: rotatable.id, role: .rotatable))
            }
            return MuscleExerciseAssignment(
                muscleGroupID: input.muscleGroupID,
                familyID: anchor.substitutionFamilyID,
                assignments: assignments
            )
        }

        // 2) Sin ejercicios de referencia disponibles (equipo limitado, restricciones o un
        //    catálogo sin lista curada): selección genérica. Se prefieren los que trabajan el
        //    músculo como PRINCIPAL antes que los que lo trabajan de rebote.
        let primaryFirst = permitted.filter { exercise in
            exercise.primaryMuscles.contains { $0.muscleGroupID == input.muscleGroupID }
        }
        let candidates = primaryFirst.isEmpty ? permitted : primaryFirst

        // Preferimos el ejercicio más representativo como anchor: el de menor
        // estabilidad demandada y menor coste sistémico (más programable).
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.stabilityDemand.score != rhs.stabilityDemand.score {
                return lhs.stabilityDemand.score < rhs.stabilityDemand.score
            }
            return lhs.systemicFatigueCost.normalized < rhs.systemicFatigueCost.normalized
        }

        let families = orderedFamilies(sorted)
        guard let anchorFamily = families.first, let anchorExercise = anchorExercise(in: sorted, family: anchorFamily) else {
            throw ExerciseAssignmentError.noAvailableExercise(
                muscle: input.muscleGroupID,
                familyPatterns: permitted.map(\.movementPattern.rawValue)
            )
        }

        var assignments: [AssignedExercise] = [AssignedExercise(exercise: anchorExercise.id, role: .anchor)]
        let rotatables = candidates
            .filter { $0.substitutionFamilyID == anchorFamily && $0.id != anchorExercise.id }
            .prefix(rotatableCount)
        for rotatable in rotatables {
            assignments.append(AssignedExercise(exercise: rotatable.id, role: .rotatable))
        }

        return MuscleExerciseAssignment(
            muscleGroupID: input.muscleGroupID,
            familyID: anchorFamily,
            assignments: assignments
        )
    }

    // MARK: - Helpers

    private func works(_ exercise: Exercise, muscleGroupID: MuscleGroup.ID) -> Bool {
        exercise.primaryMuscles.contains { $0.muscleGroupID == muscleGroupID }
            || exercise.secondaryMuscles.contains { $0.muscleGroupID == muscleGroupID }
    }

    private func isPermitted(_ exercise: Exercise, input: ExerciseAssignmentInput) -> Bool {
        // Equipment conocido → excluir los no disponibles.
        if case .knownAvailable(let available) = input.equipmentKnownness,
           !available.contains(exercise.equipment) {
            return false
        }
        // Restricciones: exciven patrón/ID prohibido; lista permitida prevalecida.
        for restriction in input.restrictions {
            if restriction.allowedExerciseIDs.contains(exercise.id) { return true }
            if restriction.forbids(exercise: exercise.id) { return false }
            if restriction.forbids(exercise.movementPattern) { return false }
        }
        return true
    }

    /// Familias ordenadas deterministamente (por nombre) presentes en los candidatos.
    private func orderedFamilies(_ exercises: [Exercise]) -> [ExerciseFamily.ID] {
        var seen: [ExerciseFamily.ID: Bool] = [:]
        return exercises.compactMap { ex in
            guard seen[ex.substitutionFamilyID] == nil else { return nil }
            seen[ex.substitutionFamilyID] = true
            return ex.substitutionFamilyID
        }
    }

    /// El mejor candidato de la familia como anchor (el más estable).
    private func anchorExercise(in exercises: [Exercise], family: ExerciseFamily.ID) -> Exercise? {
        exercises
            .filter { $0.substitutionFamilyID == family }
            .max { $0.systemicFatigueCost.normalized < $1.systemicFatigueCost.normalized }
    }

    /// Nº de rotatables según variedad (configurable, respeta anchors).
    private static func rotatableCount(for variety: VarietyPreference) -> Int {
        switch variety {
        case .stable: return 1
        case .balanced: return 2
        case .varied: return 3
        }
    }
}

private extension DemandLevel {
    var score: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }
}