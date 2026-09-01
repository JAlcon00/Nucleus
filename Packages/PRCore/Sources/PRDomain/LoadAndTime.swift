//
//  LoadAndTime.swift
//  PRDomain
//
//  Created by PR.
//
//  Value objects de carga y tiempo (PR-0101). Validan valores no negativos.
//

import Foundation

/// Unidad de carga usada en el dominio.
public enum LoadUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case kilograms
    case pounds
}

/// Carga con unidad. Validada: nunca negativa.
public struct Load: Codable, Sendable, Hashable {
    public let value: Double
    public let unit: LoadUnit

    public init(value: Double, unit: LoadUnit) throws {
        guard value.isFinite, value >= 0 else {
            throw DomainValidationError.invalidLoad(value: value)
        }
        self.value = value
        self.unit = unit
    }
}

/// Restricción temporal de una sesión (promptMaster §11.1).
public enum TimeConstraint: Codable, Sendable, Hashable, Equatable {
    case hard(minutes: Int)
    case flexible(targetMinutes: Int, toleranceMinutes: Int)
    case unconstrained

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self.parse(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .hard(let minutes):
            return "hard:\(minutes)"
        case .flexible(let target, let tolerance):
            return "flexible:\(target):\(tolerance)"
        case .unconstrained:
            return "unconstrained"
        }
    }

    private static func parse(_ raw: String) -> TimeConstraint {
        let parts = raw.split(separator: ":")
        guard let kind = parts.first else { return .unconstrained }
        switch kind {
        case "hard":
            if parts.count > 1, let m = Int(parts[1]) { return .hard(minutes: m) }
            return .unconstrained
        case "flexible":
            if parts.count > 2, let t = Int(parts[1]), let tol = Int(parts[2]) {
                return .flexible(targetMinutes: t, toleranceMinutes: tol)
            }
            return .unconstrained
        default:
            return .unconstrained
        }
    }

    /// Minutos mínimos garantizados (para planificación conservadora).
    public var guaranteedMinutes: Int? {
        switch self {
        case .hard(let minutes):
            return minutes
        case .flexible(let target, _):
            return target
        case .unconstrained:
            return nil
        }
    }
}

/// Error de validación del dominio.
public enum DomainValidationError: Error, Equatable, Sendable {
    case invalidLoad(value: Double)
    case invalidReps(value: Int)
    case invalidMinutes(value: Int)
}
