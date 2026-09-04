//
//  CoachingCardDriver.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de tarjetas de educación contextual (plan §17.5, PR-1501).
//  Deriva UNA tarjeta (o ninguna) a partir de hechos de contexto del workout y del
//  nivel de detalle del usuario:
//  - guided  → máxima educación contextual (calentamiento + descanso + molestia).
//  - balanced→ educación breve y factual (ignora el racional salvo molestia).
//  - advanced→ reduce explicaciones: NO muestra tarjetas rutinarias; sólo la de
//              seguridad ante molestia (que sigue siendo sin diagnóstico).
//  Prioridad: molestia (safety) > calentamiento > descanso. Determinista; sin inventar.
//

import Foundation

/// Hechos de contexto del workout que alimentan la selección de tarjeta (PR-1501).
public struct CoachingContext: Equatable, Sendable {
    /// Nivel de detalle de coaching efectivo.
    public let level: CoachingDetailLevel
    /// ¿El set actual es de calentamiento?
    public let isWarmup: Bool
    /// ¿Está en curso el descanso (auto rest timer)?
    public let restActive: Bool
    /// Recomendación de molestia ya evaluada por `PainFeedbackEngine` (sin diagnóstico).
    public let painRecommendation: PainRecommendation
    /// Nombre canónico del ejercicio (sólo para personalizar copy, no determinismo).
    public let exerciseName: String?

    public init(
        level: CoachingDetailLevel,
        isWarmup: Bool = false,
        restActive: Bool = false,
        painRecommendation: PainRecommendation = .continueNormal,
        exerciseName: String? = nil
    ) {
        self.level = level
        self.isWarmup = isWarmup
        self.restActive = restActive
        self.painRecommendation = painRecommendation
        self.exerciseName = exerciseName
    }
}

/// Deriva, de forma determinista, la tarjeta de educación contextual (si procede).
public struct CoachingCardDriver: Sendable {

    public init() {}

    /// Id estable de la tarjeta de seguridad ante molestia.
    public static let painSafetyCardID = CoachingCardID(rawValue: "coaching.pain.safety")
    /// Id estable de la tarjeta de calentamiento.
    public static let warmupCardID = CoachingCardID(rawValue: "coaching.warmup")
    /// Id estable de la tarjeta de descanso.
    public static let restCardID = CoachingCardID(rawValue: "coaching.rest")

    /// Devuelve la tarjeta más relevante para el contexto, o `nil` si no procede.
    public func card(for context: CoachingContext) -> CoachingCard? {
        // 1. Molestia: siempre prioridad (seguridad), en cualquier nivel. Sin diagnóstico.
        if let product = painCard(context.painRecommendation, name: context.exerciseName) {
            return product
        }
        switch context.level {
        case .guided:
            // Máxima educación: calentamiento y descanso.
            if context.isWarmup {
                return warmupCard(context.exerciseName)
            }
            if context.restActive {
                return restCard
            }
            return nil
        case .balanced:
            // Educación breve y factual: sólo el calentamiento; el descanso es rutina.
            if context.isWarmup {
                return balancedWarmupCard(context.exerciseName)
            }
            return nil
        case .advanced:
            // Reduce explicaciones: ninguna tarjeta rutinaria (sólo la de molestia).
            return nil
        }
    }

    // MARK: - Molestia (safety, no diagnóstico)

    private func painCard(_ recommendation: PainRecommendation, name: String?) -> CoachingCard? {
        switch recommendation {
        case .continueNormal:
            return nil
        case .reduceIntensityAndMonitor:
            return CoachingCard(
                id: Self.painSafetyCardID,
                kind: .painSafety,
                title: "Moderar el esfuerzo",
                message: "Hay algo de molestia. Reduce la intensidad y monitorea cómo responde el \(name ?? "movimiento") en la siguiente serie. No estamos diagnosticando: si persiste, consulta a un profesional."
            )
        case .stopAndRest:
            return CoachingCard(
                id: Self.painSafetyCardID,
                kind: .painSafety,
                title: "Detener el movimiento",
                message: "La molestia es alta. Detén o modifica el \(name ?? "movimiento") y descansa. No estamos diagnosticando: ante dolor fuerte, consulta a un profesional."
            )
        }
    }

    // MARK: - Calentamiento

    private func warmupCard(_ name: String?) -> CoachingCard {
        CoachingCard(
            id: Self.warmupCardID,
            kind: .warmup,
            title: "Prepara el \(name ?? "movimiento")",
            message: "Este set es de calentamiento: ve subiendo de peso progresivamente y guarda energía para las series de trabajo."
        )
    }

    private func balancedWarmupCard(_ name: String?) -> CoachingCard {
        CoachingCard(
            id: Self.warmupCardID,
            kind: .warmup,
            title: "Calentamiento",
            message: "Aumenta de peso progresivo en el \(name ?? "ejercicio") antes de las series de trabajo."
        )
    }

    // MARK: - Descanso

    private var restCard: CoachingCard {
        CoachingCard(
            id: Self.restCardID,
            kind: .rest,
            title: "Descanso entre series",
            message: "El descanso permite recuperar algo de fuerza para mantener la calidad de la siguiente serie."
        )
    }
}