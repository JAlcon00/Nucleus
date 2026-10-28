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
    /// Objetivo, experiencia y fase de la persona (SCRUM-219).
    public let selectionProfile: ExerciseSelectionProfile
    /// Lugar del bloque en el historial de la persona (0 = el primero). Los rotables giran con
    /// él; las anclas no.
    public let blockSequence: Int

    public init(
        muscleGroupID: MuscleGroup.ID,
        catalog: [Exercise],
        varietyPreference: VarietyPreference,
        restrictions: [TrainingRestriction],
        equipmentKnownness: EquipmentKnownness,
        selectionProfile: ExerciseSelectionProfile = .neutral,
        blockSequence: Int = 0
    ) {
        self.muscleGroupID = muscleGroupID
        self.catalog = catalog
        self.varietyPreference = varietyPreference
        self.restrictions = restrictions
        self.equipmentKnownness = equipmentKnownness
        self.selectionProfile = selectionProfile
        self.blockSequence = blockSequence
    }
}

/// Asigna anchors y rotatables por grupo muscular (PR-0503).
///
/// Reglas deterministas:
/// - Sólo ejercicios del catálogo que trabajen el grupo objetivo.
/// - Equipment: si la disponibilidad es conocida, se excluyen los que usan
///   equipment no disponible; si es unknown, no se descarta nada (la UI pregunta).
/// - Restricciones: `RestrictionPolicyEngine.verdict`, la misma evaluación que sustituciones,
///   IA y dropset (SCRUM-31): se excluye lo que cualquier restricción en vigor prohíbe; el
///   permiso de una restricción sólo refina esa restricción.
/// - Con ejercicios de referencia disponibles (lista curada, `Exercise.staple`), se reparten
///   por slot funcional del músculo (`ExerciseSelectionRule`, SCRUM-219): el `anchor` es el
///   mejor del primer slot para el objetivo y la experiencia; los `rotatable` (tantos como
///   indique la variedad) cubren los demás slots antes de repetir uno y giran con el bloque.
///   Sin ellos, el mejor candidato por familia es el `anchor` y el resto de la familia los
///   `rotatable`, prefiriendo los que trabajan el músculo como principal.
public struct ExerciseAssigner: Sendable {
    public let selectionRule: ExerciseSelectionRule

    public init(selectionRule: ExerciseSelectionRule = .standard) {
        self.selectionRule = selectionRule
    }

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

        // 1) Ejercicios de referencia del músculo (lista curada), por slot funcional. Los
        //    rotatables NO se limitan a la familia del anchor: cubren los otros slots
        //    (sentadilla → zancada → extensión).
        let staples = permitted.filter { $0.staple?.muscle == input.muscleGroupID }
        if let assignment = slotAssignment(staples, input: input, rotatableCount: rotatableCount) {
            return assignment
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

    // MARK: - Slots (SCRUM-219)

    /// Ancla y rotatables de los ejercicios de referencia, por slot del músculo. `nil` si
    /// ninguno cumple un slot (se usa la selección genérica).
    /// - El ancla es el mejor del primer slot con ejercicios para el objetivo y la experiencia.
    /// - Cada slot ordena sus rotatables por experiencia y fase, y los mejores
    ///   `rotationPool` giran según `blockSequence`: el mismo bloque da lo mismo, el siguiente
    ///   cambia.
    /// - Ronda a ronda: primero uno de cada slot que el ancla no cubre, luego segundas opciones.
    private func slotAssignment(
        _ staples: [Exercise],
        input: ExerciseAssignmentInput,
        rotatableCount: Int
    ) -> MuscleExerciseAssignment? {
        let muscle = input.muscleGroupID
        let profile = input.selectionProfile
        let slots = selectionRule.slots(for: muscle).map { slot in
            staples.filter { selectionRule.slot(of: $0, for: muscle) == slot }
        }.filter { !$0.isEmpty }
        guard let anchorSlot = slots.first,
              let anchor = ranked(anchorSlot, by: { selectionRule.anchorScore($0, profile: profile) }).first
        else { return nil }

        let queues = slots.map { candidates in
            rotated(
                ranked(candidates.filter { $0.id != anchor.id }, by: { selectionRule.rotationScore($0, profile: profile) }),
                by: input.blockSequence
            )
        }
        var rotatables: [Exercise] = []
        let rounds = (queues.map(\.count).max() ?? 0) + 1
        for round in 0..<rounds {
            for (index, queue) in queues.enumerated() {
                // El slot del ancla ya está cubierto en la primera ronda.
                let position = index == 0 ? round - 1 : round
                guard rotatables.count < rotatableCount, queue.indices.contains(position) else { continue }
                rotatables.append(queue[position])
            }
        }

        let assignments = [AssignedExercise(exercise: anchor.id, role: .anchor)]
            + rotatables.map { AssignedExercise(exercise: $0.id, role: .rotatable) }
        return MuscleExerciseAssignment(
            muscleGroupID: muscle,
            familyID: anchor.substitutionFamilyID,
            assignments: assignments
        )
    }

    /// De mayor a menor puntaje; empata el orden de la lista curada y, al final, el ID.
    private func ranked(_ exercises: [Exercise], by score: (Exercise) -> Double) -> [Exercise] {
        exercises
            .map { (exercise: $0, score: score($0)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let lhsRank = lhs.exercise.staple?.rank ?? .max
                let rhsRank = rhs.exercise.staple?.rank ?? .max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.exercise.id.rawValue.uuidString < rhs.exercise.id.rawValue.uuidString
            }
            .map(\.exercise)
    }

    /// Gira los mejores `rotationPool` según el bloque; el resto queda detrás, en su orden.
    private func rotated(_ exercises: [Exercise], by blockSequence: Int) -> [Exercise] {
        let pool = min(selectionRule.rotationPool, exercises.count)
        guard pool > 1 else { return exercises }
        let offset = ((blockSequence % pool) + pool) % pool
        let head = Array(exercises.prefix(pool))
        return Array(head[offset...] + head[..<offset]) + exercises.dropFirst(pool)
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
        return RestrictionPolicyEngine.verdict(for: exercise, under: input.restrictions) == .allowed
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