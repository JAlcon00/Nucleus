//
//  WeeklyAdherence.swift
//  PRDomain
//
//  Created by PR.
//
//  Weekly adherence engine (plan §12, promptMaster RF-016, PR-1701). Calcula el
//  cumplimiento semanal del plan distinguiendo lo realizado (completed/adjusted/rest)
//  de lo perdido (missed), Y SIN penalizar el descanso programado.
//
//  INVARIANTES (promptMaster 2.2 "Consistency over perfection", plan "No daily streak
//  pressure"): un día/sesión de descanso planeado y confirmado NUNCA baja el cumplimiento;
//  una sesión reprogramada dentro de la semana se cuenta por templateID (no se pierde ni se
//  doble cuenta). Determinista: mismos inputs → misma adherence, sin reglas inventadas.
//

import Foundation

/// Cómo terminó una sesión planeada dentro de la ventana semanal.
public enum AdherenceRecordKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// La sesión planeada se ejecutó tal cual (esper acuerdo de working sets).
    case completed
    /// La sesión planeada se ejecutó pero con cambios (menos/más sets, abandono tras empezar).
    case adjusted
    /// La sesión planeada era descanso programado (no reduce cumplimiento).
    case rest
    /// La sesión planeada no se realizó en la ventana.
    case missed
}

/// Resultado individual de una sesión planeada dentro de la ventana.
public struct SessionAdherenceRecord: Equatable, Codable, Sendable {
    public let templateID: SessionTemplate.ID
    public let plannedDate: Date
    public let kind: AdherenceRecordKind

    public init(templateID: SessionTemplate.ID, plannedDate: Date, kind: AdherenceRecordKind) {
        self.templateID = templateID
        self.plannedDate = plannedDate
        self.kind = kind
    }
}

/// Una sesión planeada por el bloque para una ventana semanal. El `plannedWorkingSets`
/// es el nº de working sets esperado (del plan) para decidir `completed` vs `adjusted`.
public struct PlannedAdherenceSession: Equatable, Codable, Sendable {
    public let templateID: SessionTemplate.ID
    public let plannedDate: Date
    /// Si true, es descanso programado: exento de cumplimiento (RW: no rompe consistency).
    public let isRest: Bool
    /// Working sets esperados del plan. Se ignora si `isRest` es true.
    public let plannedWorkingSets: Int

    public init(templateID: SessionTemplate.ID, plannedDate: Date, isRest: Bool, plannedWorkingSets: Int) {
        self.templateID = templateID
        self.plannedDate = plannedDate
        self.isRest = isRest
        self.plannedWorkingSets = plannedWorkingSets
    }
}

/// Adherencia semanal del plan (PR-1701).
public struct WeeklyAdherenceResult: Equatable, Sendable {
    /// Primer día de la ventana (inicio de semana).
    public let weekStart: Date
    /// Sesiones planeadas NO descanso (las exigidas).
    public let planned: Int
    public let completed: Int
    public let adjusted: Int
    public let rest: Int
    public let missed: Int
    /// Proporción de cumplimiento 0...1. Si no hay sesiones exigidas (p. ej. semana de
    /// descanso/deload) es 1.0: el descanso programado no penaliza.
    public let adherence: Double
    public let records: [SessionAdherenceRecord]

    /// Sesiones cumplidas como plena intended (para streak/transparencia: completed + adjusted).
    public var fulfilledCount: Int { completed + adjusted }
    /// Total de sesiones exigidas no-descanso.
    public var expectedCount: Int { planned }

    public init(
        weekStart: Date,
        planned: Int,
        completed: Int,
        adjusted: Int,
        rest: Int,
        missed: Int,
        adherence: Double,
        records: [SessionAdherenceRecord]
    ) {
        self.weekStart = weekStart
        self.planned = planned
        self.completed = completed
        self.adjusted = adjusted
        self.rest = rest
        self.missed = missed
        self.adherence = adherence
        self.records = records
    }
}

/// Engine determinista de adherencia semanal (PR-1701).
public struct WeeklyAdherenceEngine: Sendable {

    public init() {}

    /// Calcula la adherencia de una ventana semanal.
    ///
    /// - Parameters:
    ///   - weekStart: inicio de la ventana. La ventana es `[weekStart, weekStart + 7 días)`.
    ///   - planned: sesiones planeadas por el bloque para la semana.
    ///   - executed: sesiones realmente registradas (por `templateID` y fecha de inicio).
    ///
    /// Reglas:
    /// 1. `planned vs completed/adjusted/rest`: cada sesión planeada se clasifica.
    /// 2. `planned rest no rompe consistency`: una entrada `isRest` NUNCA es `missed` y
    ///    queda fuera del denominador del cumplimiento.
    /// 3. `rescheduled se cuenta bien`: el match es por `templateID` dentro de la ventana
    ///    (no exige el mismo día); una ejecución cuenta UNA sola sesión planeada.
    public func adherence(
        weekStart: Date,
        planned: [PlannedAdherenceSession],
        executed: [WorkoutSessionRecord],
        calendar: Calendar = .current
    ) throws -> WeeklyAdherenceResult {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 24 * 3600)

        // Sesiones ejecutadas dentro de la ventana.
        let inWeek = executed.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }

        var completed = 0
        var adjusted = 0
        var rest = 0
        var missed = 0
        var plannedCount = 0
        var records: [SessionAdherenceRecord] = []
        var usedIndices = Set<Int>()

        // Iterar en orden estable (respetando el orden del plan).
        for session in planned {
            guard session.plannedDate >= weekStart, session.plannedDate < weekEnd, session.plannedWorkingSets >= 0 else {
                throw DomainValidationError.invalidAdherencePlannedSets
            }

            if session.isRest {
                rest += 1
                records.append(SessionAdherenceRecord(templateID: session.templateID, plannedDate: session.plannedDate, kind: .rest))
                continue
            }

            plannedCount += 1
            // Match por templateID; primera ejecución no usada de la ventana.
            if let matchIndex = inWeek.indices.first(where: { !usedIndices.contains($0) && inWeek[$0].templateID == session.templateID }) {
                usedIndices.insert(matchIndex)
                let executedRecord = inWeek[matchIndex]
                let performedWorkingSets = executedRecord.sets.filter { $0.lifecycle == .completed }.count
                if (executedRecord.lifecycle == .completed || executedRecord.lifecycle == .finishing),
                   performedWorkingSets >= session.plannedWorkingSets {
                    completed += 1
                    records.append(SessionAdherenceRecord(templateID: session.templateID, plannedDate: session.plannedDate, kind: .completed))
                } else {
                    adjusted += 1
                    records.append(SessionAdherenceRecord(templateID: session.templateID, plannedDate: session.plannedDate, kind: .adjusted))
                }
            } else {
                missed += 1
                records.append(SessionAdherenceRecord(templateID: session.templateID, plannedDate: session.plannedDate, kind: .missed))
            }
        }

        let adherence: Double = plannedCount > 0 ? Double(completed + adjusted) / Double(plannedCount) : 1.0

        return WeeklyAdherenceResult(
            weekStart: weekStart,
            planned: plannedCount,
            completed: completed,
            adjusted: adjusted,
            rest: rest,
            missed: missed,
            adherence: adherence,
            records: records
        )
    }
}