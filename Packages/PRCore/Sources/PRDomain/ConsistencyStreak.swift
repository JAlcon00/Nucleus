//
//  ConsistencyStreak.swift
//  PRDomain
//
//  Created by PR.
//
//  Consistency streak (plan §12, promptMaster RF-016, PR-1702). Racha POR SEMANAS
//  de cumplimiento del plan — NUNCA un streak de entrenar todos los días como métrica
//  principal ("No daily streak pressure", plan §12). El descanso programado no rompe la
//  consistency ("Descanso programado no rompe consistency").
//
//  INVARIANTES: es determinista sobre la secuencia semanal; una semana de descanso
//  programado (fulfillment 1.0) extiende o mantiene la racha y NO la reinicia; una semana
//  bloqueada por dolor/restricción grave ("pain blocks progression") PAUSA la racha (no la
//  rompe ni la extiende); una semana no cumplida REINICIA. Este módulo NO expone ningún
//  streak diario de entrenamiento como métrica.
//

import Foundation

/// Una semana del histórico para el cálculo de consistency (PR-1702).
public struct StreakWeek: Equatable, Codable, Sendable {
    /// Inicio de la ventana semanal.
    public let weekStart: Date
    /// Ratio de cumplimiento de la semana (0...1), de `WeeklyAdherenceResult.adherence`.
    public let fulfillmentRatio: Double
    /// Semana bloqueada por dolor/restricción grave: PAUSA la racha (no la rompe ni extiende).
    public let isPainBlocked: Bool

    public init(weekStart: Date, fulfillmentRatio: Double, isPainBlocked: Bool = false) {
        self.weekStart = weekStart
        self.fulfillmentRatio = fulfillmentRatio
        self.isPainBlocked = isPainBlocked
    }
}

/// Estado de cada semana dentro del cálculo de racha.
public enum StreakWeekState: Equatable, Sendable, Codable {
    /// Semana cumplida (extiende/mantiene la racha).
    case fulfilled
    /// Semana bloqueada por dolor (pausa la racha, no la rompe).
    case paused
    /// Semana no cumplida (reinicia la racha).
    case missed
}

/// Resultado de consistency (PR-1702).
public struct ConsistencyStreakResult: Equatable, Sendable {
    /// Racha actual en semanas: semanas cumplidas consecutivas hasta la última semana
    /// del histórico (las pareadas/pausadas se ignoran, no rompen).
    public let currentStreakWeeks: Int
    /// Racha máxima en semanas alcanzada en el histórico.
    public let longestStreakWeeks: Int
    /// ¿La semana más reciente está cumplida?
    public let isFulfilledThisWeek: Bool
    /// Estado de cada semana (orden cronológico, de la más antigua a la más reciente).
    public let weeks: [StreakWeekState]

    public init(
        currentStreakWeeks: Int,
        longestStreakWeeks: Int,
        isFulfilledThisWeek: Bool,
        weeks: [StreakWeekState]
    ) {
        self.currentStreakWeeks = currentStreakWeeks
        self.longestStreakWeeks = longestStreakWeeks
        self.isFulfilledThisWeek = isFulfilledThisWeek
        self.weeks = weeks
    }
}

/// Motor determinista de consistency (PR-1702).
public struct ConsistencyStreakEngine: Sendable {

    public init() {}

    /// Calcula la racha semanal a partir de un histórico ORDENADO (cronológico) de semanas.
    ///
    /// - Parameters:
    ///   - weeks: semanas del histórico, de la más antigua a la más reciente.
    ///   - requiredAdherence: ratio mínimo de cumplimiento para considerar una semana
    ///     cumplida (default 1.0). Una semana de descanso programado tiene fulfillment 1.0
    ///     y por tanto no rompe la racha.
    ///
    /// Reglas:
    /// 1. `fulfilled`: `fulfillmentRatio >= requiredAdherence` y NO bloqueada por dolor.
    /// 2. `paused`: semana bloqueada por dolor/restricción grave (ni rompe ni extiende).
    /// 3. `missed`: no cumplida y no bloqueada → reinicia la racha.
    public func streak(
        weeks: [StreakWeek],
        requiredAdherence: Double = 1.0
    ) throws -> ConsistencyStreakResult {
        let threshold = requiredAdherence
        guard threshold >= 0, threshold <= 1 else {
            throw DomainValidationError.invalidStreakWeek
        }

        var states: [StreakWeekState] = []
        states.reserveCapacity(weeks.count)

        var run = 0
        var longest = 0
        for week in weeks {
            guard week.fulfillmentRatio.isFinite, week.fulfillmentRatio >= 0, week.fulfillmentRatio <= 1 else {
                throw DomainValidationError.invalidStreakWeek
            }
            let state: StreakWeekState
            if week.isPainBlocked {
                state = .paused
            } else if week.fulfillmentRatio >= threshold {
                state = .fulfilled
                run += 1
            } else {
                state = .missed
                run = 0
            }
            longest = max(longest, run)
            states.append(state)
        }

        let isFulfilledThisWeek = states.last == .fulfilled
        return ConsistencyStreakResult(
            currentStreakWeeks: states.last.map { _ in run } ?? 0,
            longestStreakWeeks: longest,
            isFulfilledThisWeek: isFulfilledThisWeek,
            weeks: states
        )
    }
}