//
//  Decision.swift
//  PRDomain
//
//  Created by PR.
//
//  Registro de decisiones para explainability (promptMaster §21, RC-010).
//  Toda decisión automática de carga/volumen/ejercicio/descanso genera un
//  DecisionRecord consultable por el usuario.
//

import Foundation

/// Descripción del tipo de decisión automática.
public enum DecisionType: String, Codable, Sendable, CaseIterable, Hashable {
    case loadChange
    case setVolumeChange
    case exerciseSubstitution
    case deload
    case restChange
    case reorder
    case blockChange
    case intensityChange
}

/// Hecho de entrada usado por la regla para decidir.
public struct DecisionFact: Codable, Sendable, Hashable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Resumen legible de la acción decidida.
public struct DecisionActionSummary: Codable, Sendable, Hashable {
    public var title: String
    public var detail: String

    public init(title: String, detail: String = "") {
        self.title = title
        self.detail = detail
    }
}

/// Registro persistible de una decisión automática (promptMaster §21).
public struct DecisionRecord: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = DecisionID

    public let id: DecisionID
    public let date: Date
    public let type: DecisionType
    public let inputFacts: [DecisionFact]
    public let action: DecisionActionSummary
    public let ruleIDs: [EvidenceRuleID]
    public let userOverrideAllowed: Bool

    public init(
        id: DecisionID = DecisionID(),
        date: Date = Date(),
        type: DecisionType,
        inputFacts: [DecisionFact] = [],
        action: DecisionActionSummary,
        ruleIDs: [EvidenceRuleID] = [],
        userOverrideAllowed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.inputFacts = inputFacts
        self.action = action
        self.ruleIDs = ruleIDs
        self.userOverrideAllowed = userOverrideAllowed
    }
}
