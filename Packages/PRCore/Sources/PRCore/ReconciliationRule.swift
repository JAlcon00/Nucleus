//
//  ReconciliationRule.swift
//  PRCore
//
//  Created by PR.
//
//  Regla versionada de la reconciliación de energía (SCRUM-245, promptMaster §15.4).
//  El umbral, la tolerancia y la confianza por fuente viven aquí, no en el motor: cambiar
//  cualquiera exige una versión nueva de la regla (`EvidenceRegistry`).
//

import Foundation
import PRDomain

/// Claves de los parámetros de la regla de reconciliación.
public enum WorkoutReconciliationKeys {
    /// Solapamiento mínimo, medido sobre el más corto, para que sean el mismo (§15.4).
    public static let overlapThreshold = "overlapThreshold"
    /// Diferencia máxima, en segundos, de inicio y de fin para que sean el mismo (§15.4).
    public static let endpointToleranceSeconds = "endpointToleranceSeconds"
    public static let confidenceOurHealthKitWorkout = "confidence.ourHealthKitWorkout"
    public static let confidenceExternalAppleWorkout = "confidence.externalAppleWorkout"
    public static let confidenceExternalHealthKitWorkout = "confidence.externalHealthKitWorkout"
    public static let confidenceFallbackEstimate = "confidence.fallbackEstimate"

    public static let allRequired: Set<String> = [
        overlapThreshold,
        endpointToleranceSeconds,
        confidenceOurHealthKitWorkout,
        confidenceExternalAppleWorkout,
        confidenceExternalHealthKitWorkout,
        confidenceFallbackEstimate,
    ]
}

/// Problemas al leer la regla de reconciliación.
public enum WorkoutReconciliationRuleError: Error, Equatable, Sendable {
    case wrongCategory
    case missingConfig(keys: [String])
    /// Proporción fuera de 0...1 o tolerancia negativa.
    case invalidValue(key: String)
}

/// Lo que decide la regla, ya validado. El motor sólo lee de aquí.
public struct WorkoutReconciliationConfiguration: Sendable, Hashable {
    public let overlapThreshold: Double
    public let endpointToleranceSeconds: TimeInterval
    public let ourHealthKitWorkoutConfidence: Double
    public let externalAppleWorkoutConfidence: Double
    public let externalHealthKitWorkoutConfidence: Double
    public let fallbackEstimateConfidence: Double

    /// Valores de la versión 1. La tolerancia de 10 minutos cubre la prueba 7 del gate
    /// (SCRUM-251) también en entrenamientos cortos, donde el umbral no alcanza.
    public static let standard = WorkoutReconciliationConfiguration(
        overlapThreshold: 0.80,
        endpointToleranceSeconds: 600,
        ourHealthKitWorkoutConfidence: 1.0,
        externalAppleWorkoutConfidence: 0.92,
        externalHealthKitWorkoutConfidence: 0.85,
        fallbackEstimateConfidence: 0.5
    )

    private init(
        overlapThreshold: Double,
        endpointToleranceSeconds: TimeInterval,
        ourHealthKitWorkoutConfidence: Double,
        externalAppleWorkoutConfidence: Double,
        externalHealthKitWorkoutConfidence: Double,
        fallbackEstimateConfidence: Double
    ) {
        self.overlapThreshold = overlapThreshold
        self.endpointToleranceSeconds = endpointToleranceSeconds
        self.ourHealthKitWorkoutConfidence = ourHealthKitWorkoutConfidence
        self.externalAppleWorkoutConfidence = externalAppleWorkoutConfidence
        self.externalHealthKitWorkoutConfidence = externalHealthKitWorkoutConfidence
        self.fallbackEstimateConfidence = fallbackEstimateConfidence
    }

    /// Lee y valida una regla. Falla si falta una clave o un valor no tiene sentido.
    public init(rule: EvidenceRule) throws {
        guard rule.category == .safety else {
            throw WorkoutReconciliationRuleError.wrongCategory
        }
        let missing = WorkoutReconciliationKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw WorkoutReconciliationRuleError.missingConfig(keys: missing.sorted())
        }
        func proportion(_ key: String) throws -> Double {
            let value = rule.parameters[key] ?? .nan
            guard (0...1).contains(value) else {
                throw WorkoutReconciliationRuleError.invalidValue(key: key)
            }
            return value
        }
        let toleranceKey = WorkoutReconciliationKeys.endpointToleranceSeconds
        let tolerance = rule.parameters[toleranceKey] ?? .nan
        guard tolerance >= 0 else {
            throw WorkoutReconciliationRuleError.invalidValue(key: toleranceKey)
        }
        self.init(
            overlapThreshold: try proportion(WorkoutReconciliationKeys.overlapThreshold),
            endpointToleranceSeconds: tolerance,
            ourHealthKitWorkoutConfidence: try proportion(WorkoutReconciliationKeys.confidenceOurHealthKitWorkout),
            externalAppleWorkoutConfidence: try proportion(WorkoutReconciliationKeys.confidenceExternalAppleWorkout),
            externalHealthKitWorkoutConfidence: try proportion(WorkoutReconciliationKeys.confidenceExternalHealthKitWorkout),
            fallbackEstimateConfidence: try proportion(WorkoutReconciliationKeys.confidenceFallbackEstimate)
        )
    }

    /// Confianza coherente con la fuente (no un score inventado).
    public func confidence(for source: EnergySource) -> Double {
        switch source {
        case .ourHealthKitWorkout: return ourHealthKitWorkoutConfidence
        case .externalAppleWorkout: return externalAppleWorkoutConfidence
        case .externalHealthKitWorkout: return externalHealthKitWorkoutConfidence
        case .fallbackEstimate: return fallbackEstimateConfidence
        }
    }

    fileprivate var parameters: [String: Double] {
        [
            WorkoutReconciliationKeys.overlapThreshold: overlapThreshold,
            WorkoutReconciliationKeys.endpointToleranceSeconds: endpointToleranceSeconds,
            WorkoutReconciliationKeys.confidenceOurHealthKitWorkout: ourHealthKitWorkoutConfidence,
            WorkoutReconciliationKeys.confidenceExternalAppleWorkout: externalAppleWorkoutConfidence,
            WorkoutReconciliationKeys.confidenceExternalHealthKitWorkout: externalHealthKitWorkoutConfidence,
            WorkoutReconciliationKeys.confidenceFallbackEstimate: fallbackEstimateConfidence,
        ]
    }
}

/// Regla de evidencia por defecto de la reconciliación (categoría `.safety`).
public enum WorkoutReconciliationDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "health.workoutReconciliation")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Reconciliación de energía (promptMaster §15)",
            source: "promptMaster §15.3 y §15.4 / SCRUM-245"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Workout energy reconciliation",
            category: .safety,
            confidence: .expertConsensus,
            version: version,
            parameters: WorkoutReconciliationConfiguration.standard.parameters,
            references: [reference]
        )
    }
}
