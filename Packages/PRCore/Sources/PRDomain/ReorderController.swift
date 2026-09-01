//
//  ReorderController.swift
//  PRDomain
//
//  Created by PR.
//
//  Reorder-before-replace (plan §9, RF-010, PR-0905). Cuando un equipo está ocupado
//  durante la sesión, el sistema intenta reordenar la sesión restante a un ejercicio
//  compatible libre de equipamiento SIN perjudicar movimientos prioritarios; si no
//  hay reorder seguro, deja sitio a la sustitución (PR-0904). Determinista y auditable.
//

import Foundation

/// Vínculo ejercicio → equipamiento que usa, para el reorder de sesión.
/// `EquipmentUse` mapea un ejercicio ya ordenado al conjunto de equipos que requiere.
public struct ReorderItemUse: Equatable, Sendable {
    public let exerciseID: ExerciseID
    public let equipmentTypes: Set<EquipmentType>

    public init(exerciseID: ExerciseID, equipmentTypes: Set<EquipmentType>) {
        self.exerciseID = exerciseID
        self.equipmentTypes = equipmentTypes
    }
}

/// Resultado de intentar reordenar antes de sustituir.
public enum ReorderBeforeReplaceDecision: Equatable, Sendable {
    /// Se encontró un reorder seguro; `plan` es el nuevo orden de ejercicio.
    case reordered(plan: [OrderedExercise])
    /// No hay reorder seguro → debe ofrecerse sustitución para el ejercicio bloqueado.
    case substitute(blocked: OrderedExercise)
    /// No hay ninguna ocupación relevante en la sesión restante.
    case unchanged
}

/// Salida auditable del intento de reorder.
public struct ReorderBeforeReplaceOutcome: Equatable, Sendable {
    public let decision: ReorderBeforeReplaceDecision
    /// Hechos de entrada que explican la decisión (newMaster §21, RC-010).
    public let facts: [DecisionFact]

    public init(decision: ReorderBeforeReplaceDecision, facts: [DecisionFact]) {
        self.decision = decision
        self.facts = facts
    }
}

/// Intentos de reorder fallidos (máximo por determinismo y transparencia).
public struct ReorderBeforeReplaceResult: Equatable, Sendable {
    public let outcome: ReorderBeforeReplaceOutcome
    /// Razones por las que cada candidato no fue seguro.
    public let rejectedReasons: [String]

    public init(outcome: ReorderBeforeReplaceOutcome, rejectedReasons: [String]) {
        self.outcome = outcome
        self.rejectedReasons = rejectedReasons
    }
}

/// Input del motor de reorder-before-replace.
public struct ReorderBeforeReplaceInput: Sendable {
    public let ordered: [OrderedExercise]
    public let equipmentUses: [ReorderItemUse]
    public let occupiedTypes: Set<EquipmentType>
    public let config: FatigueInterferenceConfig

    public init(
        ordered: [OrderedExercise],
        equipmentUses: [ReorderItemUse],
        occupiedTypes: Set<EquipmentType>,
        config: FatigueInterferenceConfig
    ) {
        self.ordered = ordered
        self.equipmentUses = equipmentUses
        self.occupiedTypes = occupiedTypes
        self.config = config
    }
}

/// Intenta reordenar la sesión restante a un ejercicio compatible libre ANTES de
/// sustituir (plan §9 flujo ocupado, PR-0905).
///
/// Reglas deterministas:
/// - Localiza el primer ejercicio de la sesión restante cuyo equipamiento está
///   ocupado (el "bloqueado").
/// - Busca el siguiente ejercicio compatible (equipamiento libre) y lo adelanta al
///   hueco, desplazando el bloqueado a su posición original.
/// - GATE de seguridad: el candidato sólo se adopta si el reorder NO aumenta la
///   interferencia por fatiga respecto al orden base (reusa FatigueInterferenceEngine).
///   Así NUNCA se mueve un ejercicio de prioridad baja (p.ej. triceps) antes de un
///   movimiento prioritario (p.ej. priority bench) si la interferencia lo excede.
/// - Si no hay reorder seguro → `.substitute` (la sustitución rankea candidatos).
public struct ReorderBeforeReplaceController: Sendable {

    public init() {}

    public func evaluate(_ input: ReorderBeforeReplaceInput) throws -> ReorderBeforeReplaceResult {
        let usesByExercise = Dictionary(
            uniqueKeysWithValues: input.equipmentUses.map { ($0.exerciseID, $0.equipmentTypes) }
        )

        guard let blockedIndex = firstBlockedIndex(input.ordered, usesByExercise: usesByExercise, occupied: input.occupiedTypes) else {
            return ReorderBeforeReplaceResult(
                outcome: ReorderBeforeReplaceOutcome(
                    decision: .unchanged,
                    facts: [DecisionFact(key: "occupiedTypes", value: Input.inputTypes(input.occupiedTypes))]
                ),
                rejectedReasons: []
            )
        }
        guard input.ordered.count >= 2 else {
            return substitute(input.ordered[blockedIndex], input: input, reasons: ["solo hay un ejercicio en la sesión restante"])
        }

        let basePenalty = Self.totalPenalty(input.ordered, config: input.config)
        var rejected: [String] = []

        for candidateIndex in (blockedIndex + 1)..<input.ordered.count {
            let candidate = input.ordered[candidateIndex]
            let usesCandidate = usesByExercise[candidate.id] ?? []
            if usesCandidate.contains(where: { input.occupiedTypes.contains($0) }) {
                continue // el candidato también está ocupado; no es compatible ahora.
            }

            let plan = Self.movedPlan(input.ordered, blockedIndex: blockedIndex, candidateIndex: candidateIndex)
            let candidatePenalty = Self.totalPenalty(plan, config: input.config)
            if candidatePenalty <= basePenalty {
                let facts = [
                    DecisionFact(key: "occupied", value: Input.inputTypes(input.occupiedTypes)),
                    DecisionFact(key: "moved", value: candidate.exercise.canonicalName),
                    DecisionFact(key: "blocked", value: input.ordered[blockedIndex].exercise.canonicalName),
                    DecisionFact(key: "penaltyBefore", value: String(format: "%.3f", basePenalty)),
                    DecisionFact(key: "penaltyAfter", value: String(format: "%.3f", candidatePenalty)),
                    DecisionFact(key: "rule", value: Self.ruleFact(input.config)),
                ]
                return ReorderBeforeReplaceResult(
                    outcome: ReorderBeforeReplaceOutcome(decision: .reordered(plan: plan), facts: facts),
                    rejectedReasons: rejected
                )
            }
            rejected.append("\(candidate.exercise.canonicalName) aumentaría la interferencia de \(basePenalty) a \(candidatePenalty)")
        }

        return substitute(input.ordered[blockedIndex], input: input, reasons: rejected)
    }

    // MARK: - Helpers

    private func firstBlockedIndex(
        _ ordered: [OrderedExercise],
        usesByExercise: [ExerciseID: Set<EquipmentType>],
        occupied: Set<EquipmentType>
    ) -> Int? {
        ordered.firstIndex { item in
            let uses = usesByExercise[item.id] ?? []
            return uses.contains(where: { occupied.contains($0) })
        }
    }

    private func substitute(_ blocked: OrderedExercise, input: ReorderBeforeReplaceInput, reasons: [String]) -> ReorderBeforeReplaceResult {
        let facts = [
            DecisionFact(key: "occupied", value: Input.inputTypes(input.occupiedTypes)),
            DecisionFact(key: "blocked", value: blocked.exercise.canonicalName),
            DecisionFact(key: "decision", value: "substitute"),
        ]
        return ReorderBeforeReplaceResult(
            outcome: ReorderBeforeReplaceOutcome(decision: .substitute(blocked: blocked), facts: facts),
            rejectedReasons: reasons
        )
    }

    /// Mueve el candidato al hueco del bloqueado (lo adelanta) preservando el resto.
    private static func movedPlan(
        _ ordered: [OrderedExercise],
        blockedIndex: Int,
        candidateIndex: Int
    ) -> [OrderedExercise] {
        var plan = ordered
        let candidate = plan.remove(at: candidateIndex)
        plan.insert(candidate, at: blockedIndex)
        return plan
    }

    private static func totalPenalty(_ ordered: [OrderedExercise], config: FatigueInterferenceConfig) -> Double {
        guard ordered.count >= 2 else { return 0 }
        let exercises = ordered.map(\.exercise)
        guard let assessment = try? FatigueInterferenceEngine().assess(input: exercises, config: config) else { return 0 }
        return assessment.totalPenalty
    }

    private static func ruleFact(_ config: FatigueInterferenceConfig) -> String {
        guard let reference = try? config.reference() else { return "ordering.fatigueInterference" }
        return "\(reference.ruleID.rawValue)#v\(reference.version)"
    }
}

/// Codificación legible de un set de equipos para los facts auditables.
private enum Input {
    static func inputTypes(_ types: Set<EquipmentType>) -> String {
        types.map { $0.rawValue }.sorted().joined(separator: ",")
    }
}