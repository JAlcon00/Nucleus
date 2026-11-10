//
//  AgentInputSafety.swift
//  PRDomain
//
//  SCRUM-33 (PR-0111): lo que el agente entiende se revisa antes de actuar.
//  - `AgentIntentValidator`: datos imposibles (0 minutos, fatiga 9) piden aclarar en vez de
//    adivinar, y una nota que el usuario no dijo (p. ej. un diagnóstico inventado por el
//    modelo) se descarta.
//  - `MedicalBoundary`: una pregunta de diagnóstico ("me duele el hombro, ¿qué tengo?") no
//    se responde; nunca llega al modelo.
//  Funciones puras: sin red, sin reloj, sin estado.
//

import Foundation

// MARK: - Datos de la intención

/// Por qué una intención no se puede usar tal cual.
public enum AgentIntentProblem: Equatable, Sendable {
    /// Minutos que no pueden ser una sesión: 0 o menos, o más que el máximo permitido.
    case minutesOutOfRange
    /// Tolerancia negativa o tan grande como el objetivo.
    case invalidTolerance
    /// Fatiga fuera de 1…5.
    case fatigueSeverityOutOfRange
}

public enum AgentIntentValidator {

    /// El problema de la intención, o `nil` si sus datos son posibles. Pocos minutos (p. ej.
    /// 20) son posibles: los decide el motor; lo imposible es lo que no es una sesión.
    public static func problem(in intent: AgentIntent) -> AgentIntentProblem? {
        switch intent {
        case .setTimeConstraint(let constraint):
            return problem(in: constraint)
        case .reportFatigue(let feedback):
            return UserFatigueFeedback.validSeverity(feedback.severity) ? nil : .fatigueSeverityOutOfRange
        case .equipmentUnavailable, .requestExerciseSwap, .reportPain, .changeGoal, .changePhase,
             .changeGym, .askWhy, .updateRestriction, .requestPlanAdjustment:
            return nil
        }
    }

    private static func problem(in constraint: TimeConstraint) -> AgentIntentProblem? {
        let maximum = TrainingWeek.allowedSessionMinutes.upperBound
        switch constraint {
        case .hard(let minutes):
            return (1...maximum).contains(minutes) ? nil : .minutesOutOfRange
        case .flexible(let target, let tolerance):
            guard (1...maximum).contains(target) else { return .minutesOutOfRange }
            return (0..<target).contains(tolerance) ? nil : .invalidTolerance
        case .unconstrained:
            return nil
        }
    }

    /// Las notas son el reporte literal del usuario: una que no aparece en su mensaje (p. ej.
    /// "posible tendinitis", inventada por el modelo) se quita. Sin distinguir mayúsculas
    /// ni acentos.
    public static func keepingOnlyLiteralNotes(_ intent: AgentIntent, userText: String) -> AgentIntent {
        switch intent {
        case .reportPain(var report):
            report.notes = literal(report.notes, in: userText)
            return .reportPain(report)
        case .updateRestriction(var draft):
            draft.notes = literal(draft.notes, in: userText)
            return .updateRestriction(draft)
        case .setTimeConstraint, .equipmentUnavailable, .requestExerciseSwap, .reportFatigue,
             .changeGoal, .changePhase, .changeGym, .askWhy, .requestPlanAdjustment:
            return intent
        }
    }

    private static func literal(_ notes: String?, in userText: String) -> String? {
        guard let notes else { return nil }
        let needle = MedicalBoundary.folded(notes).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, MedicalBoundary.folded(userText).contains(needle) else { return nil }
        return notes
    }
}

// MARK: - Límite médico

public enum MedicalBoundary {
    /// Palabras de dolor o lesión (sin acentos).
    private static let painWords = ["duele", "dolor", "molesti", "lesion", "lastim", "punzad", "hinchad"]
    /// Formas de pedir un diagnóstico (sin acentos).
    private static let diagnosisAsks = [
        "que tengo", "que me pasa", "que me paso", "es grave", "sera grave", "que sera",
        "sera una lesion", "es una lesion", "me lesione", "diagnost", "que lesion",
        // SCRUM-271: preguntar la causa del dolor también es pedir un diagnóstico.
        "por que me duele", "por que duele", "por que me molesta", "por que tengo dolor",
    ]

    /// ¿Pide un diagnóstico? Sólo si habla de dolor y además pregunta qué tiene: "lo que
    /// tengo es 30 minutos" no es una pregunta médica.
    public static func asksForDiagnosis(_ text: String) -> Bool {
        let folded = folded(text)
        return painWords.contains { folded.contains($0) } && diagnosisAsks.contains { folded.contains($0) }
    }

    /// Minúsculas y sin acentos, para comparar como lo escribe la gente.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
