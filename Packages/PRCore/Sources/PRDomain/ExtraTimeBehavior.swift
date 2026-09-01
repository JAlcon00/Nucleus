//
//  ExtraTimeBehavior.swift
//  PRDomain
//
//  Created by PR.
//
//  Extra time behavior (plan §8, PR-0804). Qué hacer cuando hay tiempo sobrante:
//  NUNCA multiplicar volumen automáticamente (plan §388: no añadir volumen sin
//  límites), separar opcionales del plan núcleo, y añadir cardio/mobility/posing
//  SÓLO cuando corresponden al objetivo/fase. Determinista.
//

import Foundation

/// Actividad de extensión propuesta cuando hay tiempo extra.
public enum ExtraTimeActivity: String, Codable, Sendable, CaseIterable, Hashable {
    case mobility
    case cardio
    case posing
}

/// Respuesta del comportamiento con tiempo extra.
public struct ExtraTimePlan: Equatable, Sendable {
    /// Segundos extra disponibles.
    public var extraSeconds: Int
    /// Segundos realmente usados (<= extra; no se fuerza).
    public var usedSeconds: Int
    /// Actividades de extensión propuestas (en orden).
    public var activities: [ExtraTimeActivity]
    /// Los opcionales se presentan separados del plan núcleo.
    public var optionalsAreSeparate: Bool
    /// Notas explicativas (también si no se usó el tiempo o no correspondía cardio/
    /// posing).
    public var notes: [String]

    public init(extraSeconds: Int, usedSeconds: Int, activities: [ExtraTimeActivity], optionalsAreSeparate: Bool, notes: [String]) {
        self.extraSeconds = extraSeconds
        self.usedSeconds = usedSeconds
        self.activities = activities
        self.optionalsAreSeparate = optionalsAreSeparate
        self.notes = notes
    }
}

/// Decide el uso del tiempo extra (PR-0804).
///
/// Reglas deterministas:
/// - NUNCA multiplica volumen: no añade working sets; a lo sumo rellena con
///   actividades de extensión dentro del tiempo disponible.
/// - `optionalsAreSeparate` siempre true: los opcionales van separados del núcleo.
/// - `mobility` siempre correspondiente; `cardio` sólo según objetivo/fase; `posing`
///   sólo para `bodybuilding`.
public struct ExtraTimeBehavior: Sendable {
    /// Segundos de cada actividad de extensión.
    public var mobilitySeconds: Int
    public var cardioSeconds: Int
    public var posingSeconds: Int

    public init(mobilitySeconds: Int = 300, cardioSeconds: Int = 600, posingSeconds: Int = 480) {
        self.mobilitySeconds = mobilitySeconds
        self.cardioSeconds = cardioSeconds
        self.posingSeconds = posingSeconds
    }

    public func plan(
        extraSeconds: Int,
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        hasOptionals: Bool
    ) -> ExtraTimePlan {
        var notes: [String] = []
        notes.append("No se multiplica el volumen de trabajo automáticamente.")

        var used = 0
        var activities: [ExtraTimeActivity] = []

        let add = { (activity: ExtraTimeActivity, seconds: Int) -> Bool in
            guard used + seconds <= extraSeconds else { return false }
            activities.append(activity)
            used += seconds
            return true
        }

        if add(.mobility, mobilitySeconds) {
            // Mobility siempre corresponde.
        }
        if cardioApplies(goal: goal, phase: phase) {
            _ = add(.cardio, cardioSeconds)
        } else {
            notes.append("Cardio no corresponde para este objetivo/fase.")
        }
        if goal == .bodybuilding {
            _ = add(.posing, posingSeconds)
        } else {
            notes.append("Posing sólo corresponde en objetivo bodybuilding.")
        }

        if extraSeconds - used > 0 && activities.isEmpty {
            notes.append("Tiempo sobrante sin actividad correspondiente; no se rellena con más volumen.")
        }

        return ExtraTimePlan(
            extraSeconds: extraSeconds,
            usedSeconds: used,
            activities: activities,
            optionalsAreSeparate: true,
            notes: notes
        )
    }

    /// ¿Corresponde cardio? Según objetivo/fase (no en volumen-céntricos puros).
    public func cardioApplies(goal: TrainingGoal, phase: BodyCompositionPhase) -> Bool {
        switch goal {
        case .generalHealth, .recomposition, .powerbuilding: return true
        case .hypertrophy, .strength, .bodybuilding:
            return phase == .deficit
        }
    }
}