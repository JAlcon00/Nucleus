//
//  AgentProfileContext.swift
//  PRDomain
//
//  SCRUM-202 (IA-1): qué datos del perfil puede usar la IA y cuándo.
//
//  Decisión de Jesús (2026-10-22): con consentimiento explícito, la IA recibe el perfil
//  completo (edad, sexo, estatura, peso, objetivo, fase, experiencia, lesiones, variedad,
//  días y minutos) para adaptar el plan al estilo de vida de la persona. Sin
//  consentimiento no sale nada: el motor local arma el plan igual.
//
//  Minimización: nunca van el nombre, el ID de Apple, los IDs internos ni las notas
//  libres de una restricción (pueden contener datos sensibles). Estos datos tampoco van
//  a logs ni a analytics (guard de CI `check_privacy_logs.sh`).
//

import Foundation

/// Decisión de la persona sobre compartir sus datos con la IA.
public enum AIDataConsent: Codable, Sendable, Hashable {
    /// Aún no se le ha preguntado: no se comparte nada.
    case notAsked
    case granted(at: Date)
    /// Dijo que no o lo retiró en Perfil: no se comparte nada.
    case declined(at: Date)

    /// ¿Se pueden enviar datos a la IA?
    public var allowsSharing: Bool {
        switch self {
        case .granted: return true
        case .notAsked, .declined: return false
        }
    }

    /// ¿Falta que la persona decida?
    public var needsDecision: Bool {
        switch self {
        case .notAsked: return true
        case .granted, .declined: return false
        }
    }
}

/// Una restricción tal como la ve la IA: zona, lado y patrones a evitar. Sin notas ni IDs.
public struct AgentRestrictionSummary: Codable, Sendable, Hashable {
    public let bodyRegion: BodyRegion
    public let side: BodySide?
    public let forbiddenPatterns: [MovementPattern]

    public init(bodyRegion: BodyRegion, side: BodySide?, forbiddenPatterns: [MovementPattern]) {
        self.bodyRegion = bodyRegion
        self.side = side
        self.forbiddenPatterns = forbiddenPatterns
    }
}

/// Perfil que la IA puede usar para personalizar. Sólo existe con consentimiento.
public struct AgentProfileContext: Codable, Sendable, Hashable {
    public let ageYears: Int
    public let sex: DeclaredSex
    public let heightCentimeters: Int?
    public let weight: Double
    public let weightUnit: LoadUnit
    public let goal: TrainingGoal
    public let phase: BodyCompositionPhase
    public let experience: ExperienceLevel
    /// Días elegidos, de lunes a domingo.
    public let trainingDays: [WeekDay]
    public let sessionMinutes: Int
    public let variety: VarietyPreference
    /// Sólo las restricciones activas.
    public let restrictions: [AgentRestrictionSummary]
}

/// Arma el contexto para la IA. Puro: el reloj y la zona horaria se inyectan.
public struct AgentProfileContextBuilder: Sendable {
    public init() {}

    /// `nil` si no hay consentimiento o si falta "Sobre ti" (sin datos completos no se
    /// manda un perfil a medias).
    public func context(
        profile: OnboardingProfile,
        consent: AIDataConsent,
        now: Date,
        timeZone: TimeZone
    ) -> AgentProfileContext? {
        guard consent.allowsSharing, let aboutYou = profile.aboutYou else { return nil }
        let days = profile.trainingWeekdays ?? TrainingWeek.firstDays(profile.trainingDaysPerWeek) ?? []
        return AgentProfileContext(
            ageYears: aboutYou.age(on: now, timeZone: timeZone),
            sex: aboutYou.sex,
            heightCentimeters: aboutYou.heightCentimeters,
            weight: aboutYou.weight,
            weightUnit: aboutYou.weightUnit,
            goal: profile.goal,
            phase: profile.phase,
            experience: profile.experience,
            trainingDays: WeekDay.allCases.filter(days.contains),
            sessionMinutes: profile.usualSessionMinutes,
            variety: profile.varietyPreference,
            restrictions: profile.restrictions
                .filter { $0.status != .resolved }
                .map { restriction in
                    AgentRestrictionSummary(
                        bodyRegion: restriction.bodyRegion,
                        side: restriction.side,
                        forbiddenPatterns: MovementPattern.allCases.filter(restriction.forbiddenPatterns.contains)
                    )
                }
        )
    }
}
