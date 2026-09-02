//
//  RestrictionPolicyEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de política de restricciones (plan §15 Fase 12, promptMaster
//  §16.2, PR-1402). Decide si un ejercicio (o un sustituto) queda excluido por las
//  restricciones activas. Reglas:
//   - patrón de movimiento prohibido ⇒ el ejercicio no se programa;
//   - la lista explícita `allowedExerciseIDs` refina (permite) pese a un patrón
//     prohibido;
//   - un sustituto prohibido por la política NUNCA se adopta (no evade restricciones);
//   - nunca diagnostica: la política sólo aplica restricciones declaradas.
// Determinista y auditable vía `DecisionRecord`.
//

import Foundation

/// Verdicto de la política de restricciones sobre un ejercicio.
public enum RestrictionVerdict: Equatable, Sendable {
    case allowed
    /// Ejercicio prohibido explícitamente por ID.
    case forbiddenExplicit
    /// Patrón de movimiento prohibido por una restricción (lista de patrones).
    case forbiddenPattern([MovementPattern])
    /// Solape de tags de contraindicación con una restricción (gate de sustitución).
    case forbiddenByTag([RestrictionTag])
}

/// Entrada de la política de restricciones.
public struct RestrictionPolicyInput: Sendable {
    /// El ejercicio a evaluar (o sustituto candidato).
    public let exercise: Exercise
    /// Restricciones activas/reviewNeeded a aplicar. `resolved` se ignora.
    public let activeRestrictions: [TrainingRestriction]
    /// Fecha respecto a la que refrescar estados (para no asumir recuperación por paso
    /// del tiempo; un `active` vencido pasa a `reviewNeeded` pero SIGUE aplicando).
    public let asOf: Date

    public init(exercise: Exercise, activeRestrictions: [TrainingRestriction], asOf: Date = Date()) {
        self.exercise = exercise
        self.activeRestrictions = activeRestrictions
        self.asOf = asOf
    }
}

/// Configuración de la engine con un booleano para toggles aplicables.
public struct RestrictionPolicyScope: Sendable {
    public var enforceForbiddenPatterns: Bool
    public var enforceExplicitForbid: Bool
    public var explicitAllowRefines: Bool
    public var enforceRestrictionTags: Bool

    public init(
        enforceForbiddenPatterns: Bool = true,
        enforceExplicitForbid: Bool = true,
        explicitAllowRefines: Bool = true,
        enforceRestrictionTags: Bool = true
    ) {
        self.enforceForbiddenPatterns = enforceForbiddenPatterns
        self.enforceExplicitForbid = enforceExplicitForbid
        self.explicitAllowRefines = explicitAllowRefines
        self.enforceRestrictionTags = enforceRestrictionTags
    }
}

/// Claves canónicas de la policy de restricciones (versión rule).
public enum RestrictionPolicyKeys {
    /// 1 = aplicar prohibición por patrón de movimiento.
    public static let enforceForbiddenPatterns = "enforceForbiddenPatterns"
    /// 1 = aplicar prohibición explícita por ID.
    public static let enforceExplicitForbid = "enforceExplicitForbid"
    /// 1 = la lista explícita de permitidos refina un patrón prohibido.
    public static let explicitAllowRefines = "explicitAllowRefines"
    /// 1 = aplicar gate por tags de contraindicación (sustitución).
    public static let enforceRestrictionTags = "enforceRestrictionTags"

    public static let allRequired: Set<String> = [
        enforceForbiddenPatterns, enforceExplicitForbid, explicitAllowRefines, enforceRestrictionTags,
    ]

    public static func defaults() -> [String: Double] {
        [
            enforceForbiddenPatterns: 1,
            enforceExplicitForbid: 1,
            explicitAllowRefines: 1,
            enforceRestrictionTags: 1,
        ]
    }
}

/// Regla de evidencia por defecto (categoría `.safety`).
public enum RestrictionPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "safety.restrictionPolicy")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Restriction policy: forbidden pattern excludes, explicit allow refines, substitution never bypasses",
            source: "Plan §15 / promptMaster §16.2"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Restriction policy engine",
            category: .safety,
            confidence: .established,
            version: version,
            parameters: RestrictionPolicyKeys.defaults(),
            references: [reference]
        )
    }
}

/// Problemas de entrada del motor.
public enum RestrictionPolicyEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case wrongCategory
}

/// Configuración versionada de la policy de restricciones.
public struct RestrictionPolicyConfig: Sendable {
    public let rule: EvidenceRule

    public var enforceForbiddenPatterns: Bool { (rule.parameters[RestrictionPolicyKeys.enforceForbiddenPatterns] ?? 1) > 0 }
    public var enforceExplicitForbid: Bool { (rule.parameters[RestrictionPolicyKeys.enforceExplicitForbid] ?? 1) > 0 }
    public var explicitAllowRefines: Bool { (rule.parameters[RestrictionPolicyKeys.explicitAllowRefines] ?? 1) > 0 }
    public var enforceRestrictionTags: Bool { (rule.parameters[RestrictionPolicyKeys.enforceRestrictionTags] ?? 1) > 0 }

    public var scope: RestrictionPolicyScope {
        RestrictionPolicyScope(
            enforceForbiddenPatterns: enforceForbiddenPatterns,
            enforceExplicitForbid: enforceExplicitForbid,
            explicitAllowRefines: explicitAllowRefines,
            enforceRestrictionTags: enforceRestrictionTags
        )
    }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .safety else {
            throw RestrictionPolicyEngineError.wrongCategory
        }
        let missing = RestrictionPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw RestrictionPolicyEngineError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Resultado auditable de la evaluación de restricciones.
public struct RestrictionPolicyResult: Equatable, Sendable {
    public let verdict: RestrictionVerdict
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    public let decisionRecord: DecisionRecord

    public init(
        verdict: RestrictionVerdict,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.verdict = verdict
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }

    public var isAllowed: Bool { verdict == .allowed }
}

/// Motor determinista de política de restricciones (PR-1402).
///
/// Precedencia:
/// 1. prohibición explícita por ID (`forbiddenExerciseIDs`) — la más fuerte;
/// 2. permiso explícito (`allowedExerciseIDs`) que refina un patrón prohibido;
/// 3. patrón de movimiento prohibido (`forbiddenPatterns`);
/// 4. solape de tags de contraindicación con `restrictionTags` (gate sustitución);
/// 5. permitido.
public struct RestrictionPolicyEngine: Sendable {
    public let config: RestrictionPolicyConfig

    public init(config: RestrictionPolicyConfig) throws {
        self.config = config
    }

    /// Restricciones que siguen en vigor (active o reviewNeeded, nunca resolved).
    public func relevantRestrictions(_ restrictions: [TrainingRestriction], asOf: Date) -> [TrainingRestriction] {
        restrictions.map { $0.refreshed(asOf: asOf) }
            .filter { $0.status == .active || $0.status == .reviewNeeded }
    }

    public func evaluate(_ input: RestrictionPolicyInput) throws -> RestrictionPolicyResult {
        let reference = try config.reference()
        let scope = config.scope
        let reason = "exercise '\(input.exercise.canonicalName)' (pattern \(input.exercise.movementPattern.rawValue))"

        let applicable = relevantRestrictions(input.activeRestrictions, asOf: input.asOf)

        // 1. Prohibición explícita por ID.
        if scope.enforceExplicitForbid,
           applicable.contains(where: { $0.forbiddenExerciseIDs.contains(input.exercise.id) }) {
            return makeResult(.forbiddenExplicit, reasons: [reason + " → prohibido explícitamente"], reference: reference)
        }

        // 2. Permiso explícito refina.
        if scope.explicitAllowRefines,
           applicable.contains(where: { $0.allowedExerciseIDs.contains(input.exercise.id) }) {
            return makeResult(.allowed, reasons: [reason + " → permitido explícitamente (refina)"], reference: reference)
        }

        // 3. Patrón de movimiento prohibido.
        if scope.enforceForbiddenPatterns {
            let patterns = applicable.flatMap(\.forbiddenPatterns)
            if patterns.contains(input.exercise.movementPattern) {
                return makeResult(.forbiddenPattern(patterns), reasons: [reason + " → patrón \(input.exercise.movementPattern.rawValue) prohibido"], reference: reference)
            }
        }

        // 4. Solape de tags de contraindicación (gate de sustitución).
        if scope.enforceRestrictionTags {
            let overlap = applicable.flatMap(\.restrictionTags).filter { input.exercise.contraindicationTags.contains($0) }
            if !overlap.isEmpty {
                return makeResult(.forbiddenByTag(overlap), reasons: [reason + " → tags contraindicados: \(overlap.map(\.rawValue).joined(separator: ","))"], reference: reference)
            }
        }

        // 5. Permitido.
        return makeResult(.allowed, reasons: [reason + " → permitido"], reference: reference)
    }

    /// Filtra candidatos de sustitución: un sustituto prohibido por la política NUNCA
    /// se adopta (no evade restricciones §16.2).
    public func safeSubstitutes(
        among candidates: [Exercise],
        restrictions: [TrainingRestriction],
        asOf: Date = Date()
    ) throws -> [Exercise] {
        var safe: [Exercise] = []
        for candidate in candidates {
            let result = try evaluate(
                RestrictionPolicyInput(exercise: candidate, activeRestrictions: restrictions, asOf: asOf)
            )
            if result.isAllowed {
                safe.append(candidate)
            }
        }
        return safe
    }

    // MARK: - Helpers

    private func makeResult(_ verdict: RestrictionVerdict, reasons: [String], reference: EvidenceRuleReference) -> RestrictionPolicyResult {
        let record = DecisionRecord(
            type: .exerciseSubstitution,
            inputFacts: [
                DecisionFact(key: "verdict", value: verdictDescription(verdict)),
                DecisionFact(key: "reasons", value: reasons.joined(separator: "; ")),
            ],
            action: DecisionActionSummary(title: "Verdicto restricción", detail: reasons.joined(separator: "; ")),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )
        return RestrictionPolicyResult(verdict: verdict, reasons: reasons, ruleReference: reference, decisionRecord: record)
    }

    private func verdictDescription(_ verdict: RestrictionVerdict) -> String {
        switch verdict {
        case .allowed: return "allowed"
        case .forbiddenExplicit: return "forbiddenExplicit"
        case .forbiddenPattern: return "forbiddenPattern"
        case .forbiddenByTag: return "forbiddenByTag"
        }
    }
}