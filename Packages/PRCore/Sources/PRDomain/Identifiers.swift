//
//  Identifiers.swift
//  PRDomain
//
//  Created by PR.
//
//  Identificadores tipados del dominio. Se prefieren tipos con identidad
//  frente a UUID/String crudos en APIs de dominio críticas (PR-0101).
//

import Foundation

/// Identificador de un `Exercise`.
public struct ExerciseID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de un `TrainingBlock`.
public struct TrainingBlockID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de un workout.
public struct WorkoutID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de un `SetRecord`.
public struct SetRecordID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de un gym.
public struct GymID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de una `TrainingRestriction`.
public struct RestrictionID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de un `DecisionRecord`.
public struct DecisionID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var id: UUID { rawValue }
}

/// Identificador de una `EvidenceRule`.
public struct EvidenceRuleID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: String { rawValue }
}
