//
//  FitnessCheckIn.swift
//  PRDomain
//
//  Created by PR.
//
//  Pre-workout subjective check-in (plan §15 Fase 12, PR-1301). Captura cómo se
//  siente el usuario antes de entrenar (excellent/normal/tired/veryTired o que algo
//  le duele/malestar) y resuelve, mediante una policy versionada, si el check-in es
//  obligatorio hoy. NUNCA es un diagnóstico ni un score 0-100: es una señal subjetiva
//  que la capa de recovery (PR-1302) usará como contexto. Determinista y sin Views.
//

import Foundation

/// Cómo se siente el usuario justo antes de entrenar (PR-1301). Subjetivo; nunca un
/// diagnóstico. `somethingHurts` expresa malestar/dolor localizado (con región).
public enum CheckInFeeling: String, Codable, Sendable, CaseIterable, Hashable {
    case excellent
    case normal
    case tired
    case veryTired
    case somethingHurts
}

/// Check-in pre-workout capturado (PR-1301). Incluye la región cuando aplica (sólo
/// contexto; nunca diagnóstico). Persistible para auditar la decisión de recovery.
public struct PreWorkoutCheckIn: Codable, Sendable, Hashable {
    public var date: Date
    public var feeling: CheckInFeeling
    /// Región de malestar (sólo si `feeling == .somethingHurts`); nunca diagnóstico.
    public var region: MuscleGroup.ID?

    public init(
        date: Date = Date(),
        feeling: CheckInFeeling,
        region: MuscleGroup.ID? = nil
    ) {
        self.date = date
        self.feeling = feeling
        self.region = region
    }

    /// Coherencia básica: la región sólo se consigna si dice que algo le duele.
    public var isCoherent: Bool {
        if feeling == .somethingHurts { return region != nil }
        return region == nil
    }
}

/// Configuración versionada de la policy de check-in (PR-1301), en forma de regla de
/// evidencia para centralizar parámetros y auditar la versión usada.
public struct CheckInPolicy: Sendable {
    /// Regla de la que se lee `requiredEveryNDays` (0 = nunca obligatorio).
    public let rule: EvidenceRule

    /// Cada cuántos días es obligatorio el check-in; 0 = no obligatorio por días.
    public var requiredEveryNDays: Int { Int(rule.parameters[CheckInPolicyKeys.requiredEveryNDays] ?? 0) }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .recovery else {
            throw CheckInPolicyError.wrongCategory
        }
        let missing = CheckInPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw CheckInPolicyError.missingConfig(keys: Array(missing).sorted())
        }
        let interval = Int(rule.parameters[CheckInPolicyKeys.requiredEveryNDays] ?? 0)
        guard interval >= 0 else {
            throw CheckInPolicyError.invalidInterval
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Claves canónicas de la política de check-in.
public enum CheckInPolicyKeys {
    /// Obligatorio cada N días. 0 = nunca obligatorio por periodicidad.
    public static let requiredEveryNDays = "requiredEveryNDays"

    public static let allRequired: Set<String> = [requiredEveryNDays]

    /// Default de producto: no obligatorio todos los días (1 = a diario).
    public static func defaults() -> [String: Double] {
        [requiredEveryNDays: 0]
    }
}

/// Regla de evidencia por defecto de la policy de check-in (categoría recovery).
public enum CheckInPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "recovery.preWorkoutCheckIn")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        try EvidenceRule(
            id: ruleID,
            name: "Pre-workout check-in policy",
            category: .recovery,
            confidence: .expertConsensus,
            version: version,
            parameters: CheckInPolicyKeys.defaults()
        )
    }
}

/// Problemas de la política de check-in.
public enum CheckInPolicyError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case invalidInterval
    case wrongCategory
    /// Check-in incoherente (p. ej. malestar sin región, o región sin malestar).
    case invalidCheckIn
}

/// Resolución de si el check-in es requerido hoy (PR-1301).
public enum CheckInRequirement: Equatable, Sendable {
    /// Se requiere el check-in antes de empezar (con la periodicidad configurada).
    case required(reference: EvidenceRuleReference)
    /// Hoy no es obligatorio (policy no lo exige).
    case optional(reference: EvidenceRuleReference)
}

/// Motor determinista del check-in pre-workout (PR-1301).
///
/// Reglas:
/// - `evaluateRequirement(daysSinceLastWorkout:)` considera el intervalo configurado:
///   0 = nunca obligatorio por periodicidad ("no obligatorio todos los días");
///   N>0 = obligatorio cuando han pasado >= N días desde el último entrenamiento;
/// - `record` valida la coherencia del `PreWorkoutCheckIn` (región sólo con
///   `somethingHurts`) y devuelve el check-in normalizado.
public struct CheckInEngine: Sendable {
    public var policy: CheckInPolicy

    public init(policy: CheckInPolicy) throws {
        self.policy = policy
    }

    /// ¿Es obligatorio el check-in hoy? Usa la periodicidad de la policy.
    public func evaluateRequirement(daysSinceLastWorkout: Int) throws -> CheckInRequirement {
        let reference = try policy.reference()
        let interval = policy.requiredEveryNDays
        if interval > 0 && daysSinceLastWorkout >= interval {
            return .required(reference: reference)
        }
        return .optional(reference: reference)
    }

    /// Registra y normaliza el check-in, validando coherencia (malestar ⇔ región).
    public func record(_ checkIn: PreWorkoutCheckIn) throws -> PreWorkoutCheckIn {
        guard checkIn.isCoherent else {
            throw CheckInPolicyError.invalidCheckIn
        }
        return checkIn
    }
}