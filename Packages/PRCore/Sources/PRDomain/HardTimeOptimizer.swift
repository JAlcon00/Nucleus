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
    /// Cuántas de `setCount` son de calentamiento: el mínimo al recortar es de series de
    /// trabajo (SCRUM-225).
    public let warmupSets: Int

    public init(
        id: UUID = UUID(),
        exerciseID: ExerciseID,
        name: String,
        role: AssignmentRole,
        muscleGroups: Set<MuscleGroup>,
        isPriorityMuscle: Bool = false,
        setCount: Int,
        secondsPerSet: Double,
        restSeconds: Double,
        warmupSets: Int = 0
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
        self.warmupSets = warmupSets
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
    /// Pares que la sesión hace en superset al terminar (los que traía y los que se
    /// juntaron para caber, SCRUM-224), con sus dos ejercicios en `kept`.
    public let appliedSupersets: [SupersetPair]

    public init(
        kept: [SessionItem],
        supersets: [CompatibleSuperset] = [],
        estimatedSeconds: Int,
        limitSeconds: Int,
        toleranceSeconds: Int,
        withinLimit: Bool,
        notes: [String],
        appliedSupersets: [SupersetPair] = []
    ) {
        self.kept = kept
        self.supersets = supersets
        self.appliedSupersets = appliedSupersets
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
    /// Un accesorio no baja de estas series de trabajo: si ni así cabe, se quita (SCRUM-225).
    /// Es el mismo mínimo que el plan semanal (SCRUM-218).
    public var minimumWorkSets: Int

    public init(
        transitionSeconds: Double = 30,
        minimumWorkSets: Int = SessionCompositionRule.standard.minimumWorkSets
    ) {
        self.transitionSeconds = transitionSeconds
        self.minimumWorkSets = minimumWorkSets
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

    /// Duración con supersets (SCRUM-224): en cada ronda del par se ahorra el descanso de
    /// `first`, como mucho los descansos que `itemSeconds` le cuenta. Las rondas son tantas
    /// como series de trabajo tenga el que menos tiene.
    public func sessionSeconds(_ items: [SessionItem], supersets: [SupersetPair]) -> Int {
        let base = sessionSeconds(items)
        guard !supersets.isEmpty else { return base }
        let byID = Dictionary(items.map { ($0.exerciseID, $0) }, uniquingKeysWith: { first, _ in first })
        let saved = supersets.reduce(0.0) { total, pair in
            guard let first = byID[pair.first], let second = byID[pair.second] else { return total }
            return total + first.restSeconds * Double(roundsSavingRest(first: first, second: second))
        }
        return max(0, Int((Double(base) - saved).rounded()))
    }

    /// Rondas del par en las que `first` no descansa.
    private func roundsSavingRest(first: SessionItem, second: SessionItem) -> Int {
        let rounds = min(first.setCount - first.warmupSets, second.setCount - second.warmupSets)
        return max(0, min(rounds, first.setCount - 1))
    }

    /// Optimiza respetando el límite duro.
    /// - `toleranceSeconds`: holgura documentada aceptada (>= 0).
    /// - `existingSupersets`: pares que la sesión ya trae (cuentan en el tiempo).
    /// - `joinSupersets` (SCRUM-224): tras quitar los opcionales y antes de bajar series,
    ///   junta pares compatibles (sin músculos en común, nunca un ancla) mientras no quepa.
    ///   Sin pedirlo, el recorte es el de siempre.
    public func optimize(
        items: [SessionItem],
        limitSeconds: Int,
        toleranceSeconds: Int = 0,
        existingSupersets: [SupersetPair] = [],
        joinSupersets: Bool = false
    ) -> TimeOptimizerResult {
        var notes: [String] = []

        // 1) Preservar anchors y prioridades (nunca se recortan).
        func isProtected(_ item: SessionItem) -> Bool { item.role == .anchor || item.isPriorityMuscle }

        // 2) Eliminar opcionales primero.
        let optionals = items.filter { !isProtected($0) && $0.role == .optional }
        if !optionals.isEmpty {
            notes.append("Eliminados \(optionals.count) ejercicio(s) opcional(es).")
        }

        // Lo que queda conserva el orden de la sesión (SCRUM-30): la persona no ve
        // ejercicios saltar.
        var kept = items.filter { isProtected($0) || $0.role != .optional }
        var applied = existingSupersets
        /// Los pares con sus dos ejercicios todavía en la sesión.
        func livePairs() -> [SupersetPair] {
            let present = Set(kept.map(\.exerciseID))
            return applied.filter { present.contains($0.first) && present.contains($0.second) }
        }
        func seconds() -> Int { sessionSeconds(kept, supersets: livePairs()) }

        // 3) SCRUM-224 (si se pide): juntar pares compatibles antes de bajar series. Sólo
        //    pares que ahorran algo; cada ejercicio, en un par como mucho.
        if joinSupersets {
            while seconds() > limitSeconds + toleranceSeconds {
                let paired = Set(applied.flatMap { [$0.first, $0.second] })
                let candidates = kept.filter { $0.role != .anchor && !paired.contains($0.exerciseID) }
                guard let match = SupersetPairing.firstPair(among: candidates, compatible: { first, second in
                    SupersetPairing.areCompatible(first.muscleGroups, second.muscleGroups)
                        && roundsSavingRest(first: first, second: second) > 0
                }), let pair = SupersetPair(
                    first: candidates[match.first].exerciseID, second: candidates[match.second].exerciseID
                ) else { break }
                applied.append(pair)
                notes.append("Juntados en superset: \(candidates[match.first].name) y \(candidates[match.second].name).")
            }
        }

        // 4) Reducir accesorios repetidamente hasta caber, luego descartarlos.
        while seconds() > limitSeconds + toleranceSeconds, hasAccessory(kept) {
            if reduceAccessory(&kept) {
                notes.append("Reducido el set-count de un ejercicio accesorio.")
            } else if let dropped = dropAccessory(&kept) {
                notes.append("Descartado accesorio: \(dropped).")
            } else {
                break
            }
        }

        // 5) Supersets compatibles (sólo disjuntos). Se ofrecen como ahorro, no se
        //    fuerza ninguno incompatible. Los que sí se hacen van en `appliedSupersets`.
        let supersetSource = kept.filter { $0.role != .anchor }
        var supersets: [CompatibleSuperset] = []
        for i in supersetSource.indices {
            for j in (i + 1)..<supersetSource.count {
                if let pair = CompatibleSuperset(first: supersetSource[i], second: supersetSource[j]) {
                    supersets.append(pair)
                }
            }
        }

        let estimated = seconds()
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
            notes: notes,
            appliedSupersets: livePairs()
        )
    }

    // MARK: - Helpers

    private func hasAccessory(_ items: [SessionItem]) -> Bool {
        items.contains { $0.role != .anchor && !$0.isPriorityMuscle }
    }

    /// Reduce a la mitad el set-count del último accesorio que todavía está por encima del
    /// mínimo (calentamiento + `minimumWorkSets` de trabajo), sin bajar de ese mínimo.
    /// Devuelve true. Se empieza por el final porque la sesión va de lo más a lo menos
    /// importante. Nunca deja una serie de trabajo suelta (SCRUM-225).
    private func reduceAccessory(_ items: inout [SessionItem]) -> Bool {
        func minimum(_ item: SessionItem) -> Int { item.warmupSets + minimumWorkSets }
        guard let idx = items.lastIndex(where: { $0.role != .anchor && !$0.isPriorityMuscle && $0.setCount > minimum($0) }) else {
            return false
        }
        var item = items[idx]
        item.setCount = max(minimum(item), Int(ceil(Double(item.setCount) / 2)))
        items[idx] = item
        return true
    }

    /// Descartar el último accesorio. Devuelve el nombre si se descartó uno.
    private func dropAccessory(_ items: inout [SessionItem]) -> String? {
        guard let idx = items.lastIndex(where: { $0.role != .anchor && !$0.isPriorityMuscle }) else {
            return nil
        }
        let dropped = items.remove(at: idx)
        return dropped.name
    }
}