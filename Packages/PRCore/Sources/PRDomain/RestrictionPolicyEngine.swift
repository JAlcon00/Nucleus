//
//  RestrictionPolicyEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de política de restricciones (plan §15 Fase 12, promptMaster
//  §16.2, PR-1402). Decide si un ejercicio (o un sustituto) queda excluido por las
//  restricciones activas. Es la única evaluación de restricciones (SCRUM-31): la usan el
//  plan, las sustituciones, la IA y el dropset. Reglas:
//   - patrón de movimiento prohibido ⇒ el ejercicio no se programa;
//   - la lista explícita `allowedExerciseIDs` refina (permite) pese a un patrón
//     prohibido de ESA MISMA restricción; nunca anula otra restricción;
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

/// Configuración de la engine con un booleano para toggles aplicables. Sus valores por
/// defecto son los de `RestrictionPolicyDefaults.makeRule()` (un test lo comprueba): los usan
/// el plan y el dropset, que no cargan la regla versionada.
public struct RestrictionPolicyScope: Equatable, Sendable {
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
/// Un ejercicio vale sólo si NINGUNA restricción en vigor lo prohíbe; el orden de las
/// restricciones no importa (SCRUM-31). Cada restricción, por separado:
/// 1. prohibición explícita por ID (`forbiddenExerciseIDs`) — la más fuerte: ni el permiso
///    de la misma restricción la anula;
/// 2. permiso explícito (`allowedExerciseIDs`): refina los patrones y tags de ESA
///    restricción, nunca los de otra;
/// 3. patrón de movimiento prohibido (`forbiddenPatterns`);
/// 4. solape de tags de contraindicación con `restrictionTags`;
/// 5. permitido.
/// Las resueltas no cuentan; una fecha de revisión vencida no es curación (RN-004). El
/// veredicto combinado dice la causa más fuerte: ID, después patrón, después tags.
public struct RestrictionPolicyEngine: Sendable {
    public let config: RestrictionPolicyConfig

    public init(config: RestrictionPolicyConfig) throws {
        self.config = config
    }

    /// Restricciones que siguen en vigor (active o reviewNeeded, nunca resolved).
    public func relevantRestrictions(_ restrictions: [TrainingRestriction], asOf: Date) -> [TrainingRestriction] {
        restrictions.map { $0.refreshed(asOf: asOf) }.filter(\.isInForce)
    }

    public func evaluate(_ input: RestrictionPolicyInput) throws -> RestrictionPolicyResult {
        let reference = try config.reference()
        let reason = "exercise '\(input.exercise.canonicalName)' (pattern \(input.exercise.movementPattern.rawValue))"
        let applicable = relevantRestrictions(input.activeRestrictions, asOf: input.asOf)
        let verdict = Self.verdict(for: input.exercise, under: applicable, scope: config.scope)
        return makeResult(verdict, reasons: [reason + " → " + outcome(of: verdict, for: input.exercise, under: applicable)], reference: reference)
    }

    /// Veredicto de todas las restricciones juntas: la única evaluación de restricciones de la
    /// app (SCRUM-31). Plan (`ExerciseAssigner`), sustituciones, IA y dropset
    /// (`IntensityAdvisor`) la usan. No depende de la fecha: `active` y `reviewNeeded`
    /// aplican igual.
    public static func verdict(
        for exercise: Exercise,
        under restrictions: [TrainingRestriction],
        scope: RestrictionPolicyScope = RestrictionPolicyScope()
    ) -> RestrictionVerdict {
        var patternForbidden = false
        var tags: Set<RestrictionTag> = []
        for restriction in restrictions where restriction.isInForce {
            switch verdict(of: restriction, for: exercise, scope: scope) {
            case .forbiddenExplicit: return .forbiddenExplicit
            case .forbiddenPattern: patternForbidden = true
            case .forbiddenByTag(let overlap): tags.formUnion(overlap)
            case .allowed: break
            }
        }
        if patternForbidden { return .forbiddenPattern([exercise.movementPattern]) }
        if !tags.isEmpty { return .forbiddenByTag(tags.sorted { $0.rawValue < $1.rawValue }) }
        return .allowed
    }

    /// Veredicto de UNA restricción: su permiso sólo refina sus propios patrones y tags.
    private static func verdict(
        of restriction: TrainingRestriction,
        for exercise: Exercise,
        scope: RestrictionPolicyScope
    ) -> RestrictionVerdict {
        if scope.enforceExplicitForbid, restriction.forbids(exercise: exercise.id) {
            return .forbiddenExplicit
        }
        if scope.explicitAllowRefines, restriction.allowedExerciseIDs.contains(exercise.id) {
            return .allowed
        }
        if scope.enforceForbiddenPatterns, restriction.forbids(exercise.movementPattern) {
            return .forbiddenPattern([exercise.movementPattern])
        }
        if scope.enforceRestrictionTags {
            let overlap = restriction.restrictionTags.intersection(exercise.contraindicationTags)
            if !overlap.isEmpty { return .forbiddenByTag(overlap.sorted { $0.rawValue < $1.rawValue }) }
        }
        return .allowed
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

    /// La razón auditable del veredicto.
    private func outcome(of verdict: RestrictionVerdict, for exercise: Exercise, under applicable: [TrainingRestriction]) -> String {
        switch verdict {
        case .forbiddenExplicit:
            return "prohibido explícitamente"
        case .forbiddenPattern:
            return "patrón \(exercise.movementPattern.rawValue) prohibido"
        case .forbiddenByTag(let tags):
            return "tags contraindicados: \(tags.map(\.rawValue).joined(separator: ","))"
        case .allowed:
            let refined = config.scope.explicitAllowRefines && applicable.contains { $0.allowedExerciseIDs.contains(exercise.id) }
            return refined ? "permitido explícitamente (refina)" : "permitido"
        }
    }

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