//
//  SessionTimeFit.swift
//  PRDomain
//
//  SCRUM-30 (PR-0108): cuánto dura de verdad la sesión de hoy y cómo se ajusta al tiempo
//  que la persona dice tener. Une piezas que ya existían: `DurationEstimator` (segundos por
//  serie), `HardTimeOptimizer` (recorte con anclas protegidas) y `ExtraTimeBehavior` (qué
//  sugerir si sobra tiempo).
//
//  - La duración cuenta series, descansos entre series y transiciones entre ejercicios,
//    con el descanso más largo del rango prescrito: mejor que sobre tiempo en el gimnasio
//    a que la sesión "quepa" sólo en papel.
//  - Si cabe, no cambia nada: más tiempo nunca es más volumen (RN-001). Como mucho se
//    sugiere movilidad o cardio, si encajan con el objetivo y la fase.
//  - Si no cabe: primero se quita lo opcional y después se reducen y quitan accesorios
//    desde el final de la sesión (lo menos importante). Un accesorio nunca baja de 2
//    series de trabajo: si ni así cabe, se quita (SCRUM-225). Anclas y prioritarios nunca
//    se tocan y el orden se conserva.
//  - Si ni recortada cabe, se dice cuánto necesita: nunca se quitan anclas en silencio.
//  Puro y determinista.
//

import Foundation

/// Tiempo que la persona dice tener hoy. Sólo vale el día en que lo eligió.
public struct SessionTimeChoice: Codable, Sendable, Hashable {
    /// Opciones rápidas que ofrece "Hoy" (PR-0108).
    public static let quickMinutes = [30, 45, 60, 90]

    public let minutes: Int
    /// Inicio del día (en la zona de la persona) en que se eligió.
    public let day: Date

    /// `nil` si los minutos están fuera de `TrainingWeek.allowedSessionMinutes`.
    public init?(minutes: Int, day: Date) {
        guard TrainingWeek.allowedSessionMinutes.contains(minutes) else { return nil }
        self.minutes = minutes
        self.day = day
    }

    /// ¿Aplica a `date`? Mismo día del calendario en `timeZone`. Un valor guardado fuera de
    /// rango nunca aplica (se lee sin fallar para no volver ilegible el plan).
    public func applies(on date: Date, timeZone: TimeZone) -> Bool {
        guard TrainingWeek.allowedSessionMinutes.contains(minutes) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(day, inSameDayAs: date)
    }
}

/// Un accesorio que se quedó con menos series de trabajo.
public struct SetReduction: Equatable, Sendable {
    public let exerciseID: ExerciseID
    public let from: Int
    public let to: Int

    public init(exerciseID: ExerciseID, from: Int, to: Int) {
        self.exerciseID = exerciseID
        self.from = from
        self.to = to
    }
}

/// Qué pasó al ajustar la sesión al tiempo elegido.
public enum SessionTimeFit: Equatable, Sendable {
    /// Ya cabía: no se tocó. `suggestions` dice qué hacer con lo que sobra (puede ir vacío).
    case fits(spareMinutes: Int, suggestions: [ExtraTimeActivity])
    /// Se recortó y ahora cabe.
    case trimmed(removed: [ExerciseID], reduced: [SetReduction])
    /// Ni recortada cabe: se conservan anclas y prioritarios y se dice cuánto necesita.
    case doesNotFit(neededMinutes: Int, removed: [ExerciseID], reduced: [SetReduction])
}

/// El ajuste de hoy: tiempo elegido, duración original y qué cambió.
public struct SessionTimeAdjustment: Equatable, Sendable {
    public let budgetMinutes: Int
    /// Duración de la sesión antes de ajustar.
    public let originalMinutes: Int
    public let fit: SessionTimeFit
    /// Pares que el ajuste juntó en superset para caber (SCRUM-224); los que la sesión ya
    /// traía no cuentan aquí.
    public let joined: [SupersetPair]

    public init(budgetMinutes: Int, originalMinutes: Int, fit: SessionTimeFit, joined: [SupersetPair] = []) {
        self.budgetMinutes = budgetMinutes
        self.originalMinutes = originalMinutes
        self.fit = fit
        self.joined = joined
    }

    /// ¿La sesión resultante cabe en el tiempo elegido?
    public var fitsBudget: Bool {
        switch fit {
        case .fits, .trimmed: return true
        case .doesNotFit: return false
        }
    }

    /// Ejercicios que salieron de la sesión.
    public var removed: [ExerciseID] {
        switch fit {
        case .fits: return []
        case .trimmed(let removed, _), .doesNotFit(_, let removed, _): return removed
        }
    }
}

/// Papel de cada ejercicio de la sesión al recortar. Lo que no está en ningún conjunto es
/// un accesorio.
public struct SessionTimeRoles: Sendable, Equatable {
    public var anchors: Set<ExerciseID>
    public var priority: Set<ExerciseID>
    public var optional: Set<ExerciseID>

    public init(anchors: Set<ExerciseID> = [], priority: Set<ExerciseID> = [], optional: Set<ExerciseID> = []) {
        self.anchors = anchors
        self.priority = priority
        self.optional = optional
    }
}

/// Calcula la duración real de una sesión y la ajusta a un tiempo (SCRUM-30).
public struct SessionTimeFitter: Sendable {
    public var estimator: DurationEstimator
    public var optimizer: HardTimeOptimizer
    public var extraTime: ExtraTimeBehavior

    public init(
        estimator: DurationEstimator = DurationEstimator(),
        optimizer: HardTimeOptimizer = HardTimeOptimizer(),
        extraTime: ExtraTimeBehavior = ExtraTimeBehavior()
    ) {
        self.estimator = estimator
        self.optimizer = optimizer
        self.extraTime = extraTime
    }

    /// Segundos de la sesión: series, descansos entre series y transiciones; con supersets,
    /// un solo descanso por ronda del par (SCRUM-224).
    public func seconds(of template: SessionTemplate) -> Int {
        optimizer.sessionSeconds(items(of: template, roles: SessionTimeRoles()), supersets: template.supersetPairs)
    }

    /// Minutos de la sesión, redondeados hacia arriba.
    public func minutes(of template: SessionTemplate) -> Int {
        Self.minutes(fromSeconds: seconds(of: template))
    }

    /// La sesión ajustada a `budgetMinutes` y qué cambió. Con el mismo ID de plantilla:
    /// el entrenamiento que se empiece con ella se retoma igual tras un cierre.
    /// `muscles` (SCRUM-224): los músculos de cada ejercicio, para juntar pares compatibles
    /// antes de bajar series, en el mismo orden de recorte que el plan. Un ejercicio sin
    /// músculos conocidos nunca se junta.
    public func fit(
        _ template: SessionTemplate,
        budgetMinutes: Int,
        roles: SessionTimeRoles,
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        muscles: [ExerciseID: Set<MuscleGroup.ID>] = [:]
    ) -> (template: SessionTemplate, adjustment: SessionTimeAdjustment) {
        let originalSeconds = seconds(of: template)
        let original = Self.minutes(fromSeconds: originalSeconds)
        let limit = budgetMinutes * 60
        guard originalSeconds > limit else {
            let spare = limit - originalSeconds
            let extra = extraTime.plan(extraSeconds: spare, goal: goal, phase: phase, hasOptionals: false)
            let fit = SessionTimeFit.fits(spareMinutes: spare / 60, suggestions: extra.activities)
            return (template, SessionTimeAdjustment(budgetMinutes: budgetMinutes, originalMinutes: original, fit: fit))
        }

        let existing = template.supersetPairs
        let result = optimizer.optimize(
            items: items(of: template, roles: roles, muscles: muscles), limitSeconds: limit,
            existingSupersets: existing, joinSupersets: true
        )
        let keptCounts = Dictionary(result.kept.map { ($0.exerciseID, $0.setCount) }, uniquingKeysWith: { first, _ in first })
        var trimmed = rebuild(template, keeping: keptCounts)
        trimmed.supersets = result.appliedSupersets.isEmpty ? nil : result.appliedSupersets
        let joined = result.appliedSupersets.filter { !existing.contains($0) }

        let removed = exerciseOrder(of: template).filter { keptCounts[$0] == nil }
        let reduced = exerciseOrder(of: trimmed).compactMap { id -> SetReduction? in
            let before = workSets(of: id, in: template)
            let after = workSets(of: id, in: trimmed)
            return after < before ? SetReduction(exerciseID: id, from: before, to: after) : nil
        }
        let trimmedSeconds = seconds(of: trimmed)
        let fit: SessionTimeFit = trimmedSeconds <= limit
            ? .trimmed(removed: removed, reduced: reduced)
            : .doesNotFit(neededMinutes: Self.minutes(fromSeconds: trimmedSeconds), removed: removed, reduced: reduced)
        return (trimmed, SessionTimeAdjustment(budgetMinutes: budgetMinutes, originalMinutes: original, fit: fit, joined: joined))
    }

    // MARK: - Privado

    private static func minutes(fromSeconds seconds: Int) -> Int {
        Int((Double(seconds) / 60).rounded(.up))
    }

    /// Ejercicios en orden de aparición.
    private func exerciseOrder(of template: SessionTemplate) -> [ExerciseID] {
        var seen: Set<ExerciseID> = []
        return template.plannedSets.map(\.exerciseID).filter { seen.insert($0).inserted }
    }

    private func workSets(of exercise: ExerciseID, in template: SessionTemplate) -> Int {
        template.plannedSets.filter { $0.exerciseID == exercise && !$0.prescription.isWarmup }.count
    }

    /// Un `SessionItem` por ejercicio. El calentamiento cuenta como serie completa (sobra
    /// tiempo antes que faltar) y el descanso es el más largo del rango prescrito.
    private func items(
        of template: SessionTemplate, roles: SessionTimeRoles, muscles: [ExerciseID: Set<MuscleGroup.ID>] = [:]
    ) -> [SessionItem] {
        let grouped = Dictionary(grouping: template.plannedSets, by: \.exerciseID)
        return exerciseOrder(of: template).compactMap { id in
            guard let sets = grouped[id], let first = sets.first else { return nil }
            let role: AssignmentRole
            if roles.anchors.contains(id) {
                role = .anchor
            } else if roles.optional.contains(id) {
                role = .optional
            } else {
                role = .rotatable
            }
            return SessionItem(
                id: id.rawValue,
                exerciseID: id,
                name: "",
                role: role,
                muscleGroups: muscles[id] ?? [],
                isPriorityMuscle: roles.priority.contains(id),
                setCount: sets.count,
                secondsPerSet: estimator.setDuration(for: id, profile: nil),
                restSeconds: Double(first.prescription.restSeconds.upperBound),
                warmupSets: sets.filter(\.prescription.isWarmup).count
            )
        }
    }

    /// La sesión con lo que quedó, en su orden. De cada ejercicio se conserva su
    /// calentamiento y las primeras series de trabajo que caben (al menos una).
    private func rebuild(_ template: SessionTemplate, keeping keptCounts: [ExerciseID: Int]) -> SessionTemplate {
        let warmups = Dictionary(grouping: template.plannedSets.filter(\.prescription.isWarmup), by: \.exerciseID)
            .mapValues(\.count)
        var workLeft = keptCounts.reduce(into: [ExerciseID: Int]()) { result, entry in
            result[entry.key] = max(1, entry.value - (warmups[entry.key] ?? 0))
        }
        var rebuilt = template
        rebuilt.plannedSets = template.plannedSets.filter { set in
            guard let left = workLeft[set.exerciseID] else { return false }
            if set.prescription.isWarmup { return true }
            guard left > 0 else { return false }
            workLeft[set.exerciseID] = left - 1
            return true
        }
        return rebuilt
    }
}
