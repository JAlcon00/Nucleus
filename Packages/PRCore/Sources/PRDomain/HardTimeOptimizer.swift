//
//  HardTimeOptimizer.swift
//  PRDomain
//
//  Created by PR.
//
//  Hard time optimizer (plan §8, RF-006, PR-0802). Recorta una sesión planeada a un
//  límite duro de tiempo de forma determinista: preserva anchors y prioridades,
//  elimina opcionales primero, reduce accesorios, y NUNCA agrega supersets
//  incompatibles (sólo agrupa grupos musculares disjuntos). Siempre documenta
//  tolerancia y explica lo que se eliminó/redujo.
//

import Foundation

/// Un set/ejercicio planeado listo para optimizar por tiempo.
public struct SessionItem: Equatable, Sendable {
    public let id: UUID
    public let exerciseID: ExerciseID
    public let name: String
    public let role: AssignmentRole
    public let muscleGroups: Set<MuscleGroup>
    public let isPriorityMuscle: Bool
    public var setCount: Int
    public let secondsPerSet: Double
    public let restSeconds: Double

    public init(
        id: UUID = UUID(),
        exerciseID: ExerciseID,
        name: String,
        role: AssignmentRole,
        muscleGroups: Set<MuscleGroup>,
        isPriorityMuscle: Bool = false,
        setCount: Int,
        secondsPerSet: Double,
        restSeconds: Double
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.role = role
        self.muscleGroups = muscleGroups
        self.isPriorityMuscle = isPriorityMuscle
        self.setCount = setCount
        self.secondsPerSet = secondsPerSet
        self.restSeconds = restSeconds
    }
}

/// Un superset compatible: NUNCA agrupa grupos musculares solapados.
public struct CompatibleSuperset: Equatable, Sendable {
    public let first: SessionItem
    public let second: SessionItem

    /// Sólo es compatible si los grupos musculares son disjuntos (no se penaliza).
    public init?(first: SessionItem, second: SessionItem) {
        guard first.muscleGroups.isDisjoint(with: second.muscleGroups) else { return nil }
        self.first = first
        self.second = second
    }
}

/// Resultado de la optimización dura por tiempo.
public struct TimeOptimizerResult: Equatable, Sendable {
    public let kept: [SessionItem]
    /// Supersets compatibles que se añaden (nunca incompatibles).
    public let supersets: [CompatibleSuperset]
    public let estimatedSeconds: Int
    public let limitSeconds: Int
    public let toleranceSeconds: Int
    /// ¿Se alcanzó el límite dentro de la tolerancia documentada?
    public let withinLimit: Bool
    /// Notas explicativas de lo eliminado/reducido.
    public let notes: [String]

    public init(
        kept: [SessionItem],
        supersets: [CompatibleSuperset] = [],
        estimatedSeconds: Int,
        limitSeconds: Int,
        toleranceSeconds: Int,
        withinLimit: Bool,
        notes: [String]
    ) {
        self.kept = kept
        self.supersets = supersets
        self.estimatedSeconds = estimatedSeconds
        self.limitSeconds = limitSeconds
        self.toleranceSeconds = toleranceSeconds
        self.withinLimit = withinLimit
        self.notes = notes
    }
}

/// Recorta una sesión a un límite duro de tiempo (PR-0802).
public struct HardTimeOptimizer: Sendable {
    /// Segundos de transición entre ejercicios.
    public var transitionSeconds: Double

    public init(transitionSeconds: Double = 30) {
        self.transitionSeconds = transitionSeconds
    }

    /// Duración (segundos) de un `SessionItem` en solitario.
    public func itemSeconds(_ item: SessionItem) -> Double {
        let sets = Double(max(1, item.setCount))
        let rest = item.restSeconds * (sets - 1)
        return item.secondsPerSet * sets + rest
    }

    /// Duración (segundos) de una lista, sumando transiciones entre ejercicios.
    public func sessionSeconds(_ items: [SessionItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + itemSeconds($1) }
        let transitions = Double(items.count - 1) * transitionSeconds
        return Int((total + transitions).rounded())
    }

    /// Optimiza respetando el límite duro.
    /// - `toleranceSeconds`: holgura documentada aceptada (>= 0).
    public func optimize(
        items: [SessionItem],
        limitSeconds: Int,
        toleranceSeconds: Int = 0
    ) -> TimeOptimizerResult {
        var notes: [String] = []

        // 1) Preservar anchors y prioridades (nunca se recortan).
        let protected = items.filter { $0.role == .anchor || $0.isPriorityMuscle }
        let unprotected = items.filter { !($0.role == .anchor || $0.isPriorityMuscle) }

        // 2) Eliminar opcionales primero.
        let optionals = unprotected.filter { $0.role == .optional }
        let reducible = unprotected.filter { $0.role != .optional }
        if !optionals.isEmpty {
            notes.append("Eliminados \(optionals.count) ejercicio(s) opcional(es).")
        }

        // 3) Reducir accesorios repetidamente hasta caber, luego descartarlos.
        var kept = protected + reducible
        while sessionSeconds(kept) > limitSeconds + toleranceSeconds, hasAccessory(kept) {
            if reduceAccessory(&kept) {
                notes.append("Reducido el set-count de un ejercicio accesorio.")
            } else if let dropped = dropAccessory(&kept) {
                notes.append("Descartado accesorio: \(dropped).")
            } else {
                break
            }
        }

        // 4) Supersets compatibles (sólo disjuntos). Se ofrecen como ahorro, no se
        //    fuerza ninguno incompatible.
        let supersetSource = kept.filter { $0.role != .anchor }
        var supersets: [CompatibleSuperset] = []
        for i in supersetSource.indices {
            for j in (i + 1)..<supersetSource.count {
                if let pair = CompatibleSuperset(first: supersetSource[i], second: supersetSource[j]) {
                    supersets.append(pair)
                }
            }
        }

        let estimated = sessionSeconds(kept)
        let within = estimated <= limitSeconds + toleranceSeconds
        if !within {
            notes.append("Límite no alcanzado aun conservando todos los anchors/prioridades.")
        }

        return TimeOptimizerResult(
            kept: kept,
            supersets: supersets,
            estimatedSeconds: estimated,
            limitSeconds: limitSeconds,
            toleranceSeconds: toleranceSeconds,
            withinLimit: within,
            notes: notes
        )
    }

    // MARK: - Helpers

    private func hasAccessory(_ items: [SessionItem]) -> Bool {
        items.contains { $0.role != .anchor && !$0.isPriorityMuscle }
    }

    /// Reduce a la mitad el set-count del primer accesorio con >1 set. Devuelve true.
    private func reduceAccessory(_ items: inout [SessionItem]) -> Bool {
        guard let idx = items.firstIndex(where: { $0.role != .anchor && !$0.isPriorityMuscle && $0.setCount > 1 }) else {
            return false
        }
        var item = items[idx]
        item.setCount = max(1, Int(ceil(Double(item.setCount) / 2)))
        items[idx] = item
        return true
    }

    /// Descartar un accesorio. Devuelve el nombre si se descartó uno.
    private func dropAccessory(_ items: inout [SessionItem]) -> String? {
        guard let idx = items.firstIndex(where: { $0.role != .anchor && !$0.isPriorityMuscle }) else {
            return nil
        }
        let dropped = items.remove(at: idx)
        return dropped.name
    }
}