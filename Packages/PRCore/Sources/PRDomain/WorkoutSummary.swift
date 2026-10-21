//
//  WorkoutSummary.swift
//  PRDomain
//
//  Created by PR.
//
//  Workout completion summary (plan §8, PR-0605). Agrega una sesión completada en:
//  duration, working sets, volume, PRs detectados, energía (sólo si viene reconciliada
//  de otra fuente; nunca se inventa por RN-008) y próxima acción. Determinista; no
//  depende de una API.
//

import Foundation

/// Un set marcado como nuevo récord personal (detector determinista, PR-0605).
/// El detector no inventa récords: sólo compara contra un baseline previo real.
public struct PersonalRecord: Equatable, Codable, Sendable {
    public var exerciseID: ExerciseID
    public var weight: Double
    public var unit: LoadUnit
    public var reps: Int
    public var achievedAt: Date

    public init(exerciseID: ExerciseID, weight: Double, unit: LoadUnit, reps: Int, achievedAt: Date) {
        self.exerciseID = exerciseID
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.achievedAt = achievedAt
    }
}

/// Próxima acción sugerida tras resumir la sesión.
public enum SummaryNextAction: String, Codable, Sendable, Hashable {
    case inProgress
    case readyToFinish
    case completed
}

/// Resumen de una sesión completada (PR-0605).
public struct WorkoutSummary: Equatable, Codable, Sendable {
    /// Duración en segundos (endedAt - startedAt); 0 si no terminó.
    public var durationSeconds: Int
    /// Nº de working sets completados.
    public var workingSets: Int
    /// Volumen total (suma weight × reps de los sets completados).
    public var volume: Double
    /// Energía reconciliada en kcal, SÓLO si se suministra reconciliada (RN-008).
    public var energyKcal: Double?
    /// Récords personales detectados.
    public var records: [PersonalRecord]
    /// Próxima acción.
    public var nextAction: SummaryNextAction

    public init(
        durationSeconds: Int,
        workingSets: Int,
        volume: Double,
        energyKcal: Double? = nil,
        records: [PersonalRecord] = [],
        nextAction: SummaryNextAction
    ) {
        self.durationSeconds = durationSeconds
        self.workingSets = workingSets
        self.volume = volume
        self.energyKcal = energyKcal
        self.records = records
        self.nextAction = nextAction
    }
}

/// Contexto en el que se registró un baseline: unidad y máquina concreta. Las cargas
/// sólo son comparables dentro del mismo contexto (RN-007: máquinas distintas no se
/// comparan; kg y lb tampoco se comparan sin conversión explícita).
public struct PersonalRecordBaselineContext: Equatable, Codable, Sendable, Hashable {
    public var unit: LoadUnit
    public var machineProfileID: UUID?

    public init(unit: LoadUnit, machineProfileID: UUID? = nil) {
        self.unit = unit
        self.machineProfileID = machineProfileID
    }
}

/// Mejor carga histórica de un ejercicio dentro de un contexto comparable.
public struct PersonalRecordBaseline: Equatable, Codable, Sendable {
    public var bestWeight: Double
    public var context: PersonalRecordBaselineContext

    public init(bestWeight: Double, context: PersonalRecordBaselineContext) {
        self.bestWeight = bestWeight
        self.context = context
    }
}

/// Deriva baselines de PR desde el historial persistido (PR-1004 wiring). Puro y
/// determinista.
///
/// Reglas:
/// - sólo cuentan sets `.completed` (skipped/planned nunca son baseline);
/// - por ejercicio se agrupa por contexto (unidad + máquina); si el historial tiene
///   varios contextos se usa el del set más reciente (el que el usuario usa hoy). Así
///   nunca se compara una máquina con otra ni kg con lb;
/// - un ejercicio sin historial no tiene baseline → no se celebra un PR inventado.
public enum PersonalRecordBaselineBuilder {

    public static func baselines(from history: [WorkoutSessionRecord]) -> [ExerciseID: PersonalRecordBaseline] {
        var latest: [ExerciseID: SetRecord] = [:]
        var best: [ExerciseID: [PersonalRecordBaselineContext: Double]] = [:]
        for session in history {
            for set in session.sets where set.lifecycle == .completed {
                let context = PersonalRecordBaselineContext(unit: set.unit, machineProfileID: set.machineProfileID)
                let current = best[set.exerciseID]?[context] ?? 0
                best[set.exerciseID, default: [:]][context] = max(current, set.weight)
                if let previous = latest[set.exerciseID] {
                    // Empate de fecha → mayor id, para que el resultado no dependa del orden.
                    if set.performedAt > previous.performedAt
                        || (set.performedAt == previous.performedAt
                            && set.id.rawValue.uuidString > previous.id.rawValue.uuidString) {
                        latest[set.exerciseID] = set
                    }
                } else {
                    latest[set.exerciseID] = set
                }
            }
        }
        var result: [ExerciseID: PersonalRecordBaseline] = [:]
        for (exerciseID, recent) in latest {
            let context = PersonalRecordBaselineContext(unit: recent.unit, machineProfileID: recent.machineProfileID)
            guard let weight = best[exerciseID]?[context] else { continue }
            result[exerciseID] = PersonalRecordBaseline(bestWeight: weight, context: context)
        }
        return result
    }
}

/// Detecta récords personales comparando lo realizado contra un baseline histórico.
public struct PersonalRecordDetector: Sendable {
    /// Baseline: mejor peso histórico por ejercicio. Sólo se detecta un PR cuando
    /// hay baseline (nunca se inventa un récord sin referencia previa).
    public var previousBestWeight: [ExerciseID: Double]
    /// Contexto (unidad/máquina) de cada baseline. Si existe, un set en otro contexto
    /// no es comparable y no se marca como PR (RN-007).
    public var baselineContexts: [ExerciseID: PersonalRecordBaselineContext]

    public init(
        previousBestWeight: [ExerciseID: Double] = [:],
        baselineContexts: [ExerciseID: PersonalRecordBaselineContext] = [:]
    ) {
        self.previousBestWeight = previousBestWeight
        self.baselineContexts = baselineContexts
    }

    /// Construye el detector desde baselines con contexto (historial real).
    public init(baselines: [ExerciseID: PersonalRecordBaseline]) {
        self.previousBestWeight = baselines.mapValues(\.bestWeight)
        self.baselineContexts = baselines.mapValues(\.context)
    }

    /// Devuelve los sets completados que superan el mejor peso histórico de su
    /// ejercicio (mismo peso con más reps también cuenta como PR).
    public func detect(in session: WorkoutSessionRecord) -> [PersonalRecord] {
        var result: [PersonalRecord] = []
        for set in session.sets where set.lifecycle == .completed {
            guard let baseline = previousBestWeight[set.exerciseID] else { continue }
            if let context = baselineContexts[set.exerciseID],
               context != PersonalRecordBaselineContext(unit: set.unit, machineProfileID: set.machineProfileID) {
                continue // contexto no comparable: no inventar un récord.
            }
            if set.weight > baseline {
                result.append(
                    PersonalRecord(
                        exerciseID: set.exerciseID,
                        weight: set.weight,
                        unit: set.unit,
                        reps: set.reps,
                        achievedAt: set.performedAt
                    )
                )
            }
        }
        return result
    }
}

/// Construye el resumen de una sesión (PR-0605).
public struct WorkoutSummaryBuilder: Sendable {

    public init() {}

    /// Genera el resumen de una sesión completada.
    /// `now` permite concedúr el cálculo frente a lo realmente realizado.
    public func summarize(
        _ session: WorkoutSessionRecord,
        now: Date = Date(),
        energyKcal reconciledEnergy: Double? = nil,
        previousBestWeight: [ExerciseID: Double] = [:]
    ) -> WorkoutSummary {
        summarize(
            session,
            now: now,
            energyKcal: reconciledEnergy,
            detector: PersonalRecordDetector(previousBestWeight: previousBestWeight)
        )
    }

    /// Variante con baselines derivados del historial (unidad + máquina comparables).
    public func summarize(
        _ session: WorkoutSessionRecord,
        now: Date = Date(),
        energyKcal reconciledEnergy: Double? = nil,
        baselines: [ExerciseID: PersonalRecordBaseline]
    ) -> WorkoutSummary {
        summarize(
            session,
            now: now,
            energyKcal: reconciledEnergy,
            detector: PersonalRecordDetector(baselines: baselines)
        )
    }

    private func summarize(
        _ session: WorkoutSessionRecord,
        now: Date,
        energyKcal reconciledEnergy: Double?,
        detector: PersonalRecordDetector
    ) -> WorkoutSummary {
        let end = session.endedAt ?? now
        let duration = Int(max(0, end.timeIntervalSince(session.startedAt)))
        let workingSets = session.sets.filter { $0.lifecycle == .completed }.count
        let volume = session.sets.reduce(0.0) { $0 + ($1.lifecycle == .completed ? ($1.weight * Double($1.reps)) : 0) }

        let records = detector.detect(in: session)

        let nextAction: SummaryNextAction
        switch session.lifecycle {
        case .planned, .preparing, .active, .paused:
            nextAction = .inProgress
        case .finishing:
            nextAction = .readyToFinish
        case .completed, .abandoned:
            nextAction = .completed
        }

        return WorkoutSummary(
            durationSeconds: duration,
            workingSets: workingSets,
            volume: volume,
            energyKcal: validatedEnergy(reconciledEnergy),
            records: records,
            nextAction: nextAction
        )
    }

    /// Energía: NUNCA se computa/inventa aquí. Sólo se propaga si llega reconciliada
    /// de una fuente externa y es finita (RN-008: no doble contabilización).
    private func validatedEnergy(_ kcal: Double?) -> Double? {
        guard let kcal, kcal.isFinite, kcal >= 0 else { return nil }
        return kcal
    }
}