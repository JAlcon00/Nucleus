//
//  Evidence.swift
//  PRDomain
//
//  Created by PR.
//
//  Evidence Registry (promptMaster §22, PR-0303). Centraliza reglas científicas
//  versionadas y sirve de fuente única de parámetros ajustables (sin constantes
//  dispersas en Views / engines). Un `DecisionRecord` guarda la referencia
//  (id + versión) de la regla usada para hacer auditable el coaching (§22.2).
//

import Foundation

/// Categoría del dominio de entrenamiento al que aplica la regla.
public enum EvidenceCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case volume
    case progression
    case recovery
    case ordering
    case rest
    case safety
}

/// Confianza de la evidencia subyacente a la regla.
public enum EvidenceConfidence: String, Codable, Sendable, CaseIterable, Hashable {
    case established
    case emerging
    case expertConsensus
    case anecdotal
}

/// Referencia bibliográfica de una regla (título + opcional fuente/año/URL).
public struct EvidenceReference: Codable, Sendable, Hashable {
    public var title: String
    public var source: String?
    public var year: Int?
    public var url: String?

    public init(
        title: String,
        source: String? = nil,
        year: Int? = nil,
        url: String? = nil
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainValidationError.emptyEvidenceReferenceTitle
        }
        self.title = trimmed
        self.source = source
        self.year = year
        self.url = url
    }
}

/// Regla científica versionada (promptMaster §22.1).
public struct EvidenceRule: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = EvidenceRuleID

    public let id: EvidenceRuleID
    public var name: String
    public var category: EvidenceCategory
    public var confidence: EvidenceConfidence
    public var version: Int
    public var parameters: [String: Double]
    public var references: [EvidenceReference]
    public var active: Bool

    public init(
        id: EvidenceRuleID,
        name: String,
        category: EvidenceCategory,
        confidence: EvidenceConfidence,
        version: Int,
        parameters: [String: Double] = [:],
        references: [EvidenceReference] = [],
        active: Bool = true
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainValidationError.emptyRuleName
        }
        guard version >= 1 else {
            throw DomainValidationError.invalidRuleVersion(value: version)
        }
        for (key, value) in parameters where !value.isFinite {
            throw DomainValidationError.nonFiniteRuleParameter(name: key, value: value)
        }
        self.id = id
        self.name = trimmed
        self.category = category
        self.confidence = confidence
        self.version = version
        self.parameters = parameters
        self.references = references
        self.active = active
    }
}

/// Referencia a una versión concreta de una regla. Un `DecisionRecord` la guarda
/// para auditar qué versión de la regla se usó al decidir (§22.2).
public struct EvidenceRuleReference: Codable, Sendable, Hashable {
    public let ruleID: EvidenceRuleID
    public let version: Int

    public init(ruleID: EvidenceRuleID, version: Int) throws {
        guard version >= 1 else {
            throw DomainValidationError.invalidRuleVersion(value: version)
        }
        self.ruleID = ruleID
        self.version = version
    }

    public init(_ rule: EvidenceRule) throws {
        try self.init(ruleID: rule.id, version: rule.version)
    }
}

/// Registro centralizado y versionado de reglas de evidencia (PR-0303).
/// Registrar un cambio en una regla existente requiere incrementar su versión.
public struct EvidenceRegistry: Sendable {
    private var rulesByID: [EvidenceRuleID: EvidenceRule]

    public init(_ rules: [EvidenceRule] = []) throws {
        var store: [EvidenceRuleID: EvidenceRule] = [:]
        for rule in rules {
            if let existing = store[rule.id] {
                throw DomainValidationError.duplicateRuleID(id: rule.id.rawValue, existingVersion: existing.version, newVersion: rule.version)
            }
            store[rule.id] = rule
        }
        self.rulesByID = store
    }

    /// Reglas actuales ordenadas por id (orden estable para tests/UI).
    public func allRules() -> [EvidenceRule] {
        rulesByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func activeRules() -> [EvidenceRule] {
        allRules().filter(\.active)
    }

    public func rule(id: EvidenceRuleID) -> EvidenceRule? {
        rulesByID[id]
    }

    public func activeRule(id: EvidenceRuleID) -> EvidenceRule? {
        guard let rule = rulesByID[id], rule.active else { return nil }
        return rule
    }

    /// Parámetros centralizados de la regla activa (o nil si no existe/inactiva).
    public func parameters(id: EvidenceRuleID) -> [String: Double]? {
        activeRule(id: id)?.parameters
    }

    /// Referencia versionada de la regla activa vigente.
    public func reference(for id: EvidenceRuleID) -> EvidenceRuleReference? {
        guard let rule = activeRule(id: id) else { return nil }
        return try? EvidenceRuleReference(rule)
    }

    /// Registra una regla nueva o una versión superior de una existente.
    /// Un cambio sin incremento de versión es rechazado (reglas testeables).
    public mutating func register(_ rule: EvidenceRule) throws {
        if let existing = rulesByID[rule.id] {
            guard rule.id == existing.id else {
                throw DomainValidationError.ruleNotFound(id: rule.id.rawValue)
            }
            guard rule.version > existing.version else {
                throw DomainValidationError.ruleVersionNotAdvanced(
                    id: rule.id.rawValue,
                    current: existing.version,
                    proposed: rule.version
                )
            }
        }
        rulesByID[rule.id] = rule
    }

    /// Marca una regla como inactiva (no se usa para decisiones nuevas).
    public mutating func deactivate(id: EvidenceRuleID) throws {
        guard var rule = rulesByID[id] else {
            throw DomainValidationError.ruleNotFound(id: id.rawValue)
        }
        rule.active = false
        rulesByID[id] = rule
    }
}