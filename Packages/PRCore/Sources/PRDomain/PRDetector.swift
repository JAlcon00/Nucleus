//
//  PRDetector.swift
//  PRDomain
//
//  Created by PR.
//
//  PR detector (plan §12 Fase 9, RF-015, §12.x, PR-1003). Detecta récords personales
//  de carga (load), reps y e1RM estimado contra baselines históricos. La fórmula de
//  e1RM está versionada via EvidenceRule (Epley por defecto) y la política decide si
//  los warmups cuentan o no. Determinista: nunca inventa un récord sin baseline.
//

import Foundation

/// Tipos de récord personal (§19.1).
public enum PRKind: String, Codable, Sendable, CaseIterable, Hashable {
    case load
    case rep
    case e1RM
}

/// Claves canónicas de la regla del detector de PRs.
public enum PRConfigKeys {
    /// Denominador de la fórmula de e1RM (Epley: weight × (1 + reps / n)).
    public static let e1RMRepsDenominator = "e1RMRepsDenominator"
    /// Política: ¿excluir los warmups de la detección de PR? (1 = excluir).
    public static let warmupExcluded = "warmupExcluded"

    public static let allRequired: Set<String> = [e1RMRepsDenominator, warmupExcluded]

    public static func defaults() -> [String: Double] {
        [e1RMRepsDenominator: 30, warmupExcluded: 1]
    }
}

/// Regla versionada por defecto del detector de PRs (categoría progression).
public enum PRDetectorDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "progression.prDetector")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Personal record detection with versioned e1RM formula",
            source: "Plan §12 Fase 9 / promptMaster §19.1"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "PR detection rule",
            category: .progression,
            confidence: .emerging,
            version: version,
            parameters: PRConfigKeys.defaults(),
            references: [reference]
        )
    }
}

/// Configuración versionada del detector de PRs.
public struct PRDetectorConfig: Sendable {
    public let rule: EvidenceRule

    /// Denominador de la fórmula de e1RM (Epley). Mayor ⇒ estimado más conservador.
    public var e1RMRepsDenominator: Double {
        rule.parameters[PRConfigKeys.e1RMRepsDenominator] ?? 30
    }

    /// ¿Excluir warmups de la detección de PR por política?
    public var warmupExcluded: Bool {
        (rule.parameters[PRConfigKeys.warmupExcluded] ?? 1) > 0
    }

    public init(rule: EvidenceRule) throws {
        let missing = PRConfigKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw PRDetectorError.missingConfig(keys: Array(missing).sorted())
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Problemas de entrada del detector de PRs.
public enum PRDetectorError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
}

/// Un récord personal detectado (específico de un tipo).
public struct PersonalRecordDetection: Equatable, Sendable {
    public let kind: PRKind
    public let exerciseID: ExerciseID
    public let weight: Double
    public let unit: LoadUnit
    public let reps: Int
    public let e1RM: Double?
    public let achievedAt: Date

    public init(
        kind: PRKind,
        exerciseID: ExerciseID,
        weight: Double,
        unit: LoadUnit,
        reps: Int,
        e1RM: Double? = nil,
        achievedAt: Date
    ) {
        self.kind = kind
        self.exerciseID = exerciseID
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.e1RM = e1RM
        self.achievedAt = achievedAt
    }
}

/// Baselines históricos contra los que se comparan los récords.
public struct PRBaselines: Sendable {
    public let previousBestWeight: [ExerciseID: Double]
    public let previousBestReps: [ExerciseID: Int]
    public let previousBestE1RM: [ExerciseID: Double]

    public init(
        previousBestWeight: [ExerciseID: Double] = [:],
        previousBestReps: [ExerciseID: Int] = [:],
        previousBestE1RM: [ExerciseID: Double] = [:]
    ) {
        self.previousBestWeight = previousBestWeight
        self.previousBestReps = previousBestReps
        self.previousBestE1RM = previousBestE1RM
    }
}

/// Detecta récords personales (plan §12 Fase 9, RF-015, PR-1003).
///
/// Reglas deterministas:
/// - load PR: un set supera el mejor peso histórico del ejercicio.
/// - rep PR: un set supera el máximo de reps histórico del ejercicio.
/// - e1RM PR: el e1RM estimado (fórmula versionada) supera el mejor e1RM histórico.
/// - Nunca se inventa un récord sin baseline previo para ese ejercicio.
/// - Según política, los warmups no cuentan como PR (`warmupSetIDs` + `warmupExcluded`).
public struct PRDetector: Sendable {
    public let baselines: PRBaselines

    public init(baselines: PRBaselines = PRBaselines()) {
        self.baselines = baselines
    }

    /// Estima el e1RM con la fórmula versionada (Epley por defecto).
    public func estimatedOneRM(weight: Double, reps: Int, config: PRDetectorConfig) -> Double {
        weight * (1 + Double(reps) / config.e1RMRepsDenominator)
    }

    /// Evalúa los sets completados y devuelve los PRs detectados.
    /// `warmupSetIDs` identifica los sets que fueron planeados como warmup.
    public func evaluate(
        sets: [SetRecord],
        config: PRDetectorConfig,
        warmupSetIDs: Set<SetRecord.ID> = []
    ) -> [PersonalRecordDetection] {
        var result: [PersonalRecordDetection] = []
        for set in sets where set.lifecycle == .completed {
            if config.warmupExcluded, warmupSetIDs.contains(set.id) {
                continue // warmup no cuenta como PR por política.
            }

            // Load PR
            if let best = baselines.previousBestWeight[set.exerciseID], set.weight > best {
                result.append(PersonalRecordDetection(
                    kind: .load,
                    exerciseID: set.exerciseID,
                    weight: set.weight,
                    unit: set.unit,
                    reps: set.reps,
                    achievedAt: set.performedAt
                ))
            }

            // Rep PR
            if let best = baselines.previousBestReps[set.exerciseID], set.reps > best {
                result.append(PersonalRecordDetection(
                    kind: .rep,
                    exerciseID: set.exerciseID,
                    weight: set.weight,
                    unit: set.unit,
                    reps: set.reps,
                    achievedAt: set.performedAt
                ))
            }

            // e1RM PR
            if let best = baselines.previousBestE1RM[set.exerciseID] {
                let e1rm = estimatedOneRM(weight: set.weight, reps: set.reps, config: config)
                if e1rm > best {
                    result.append(PersonalRecordDetection(
                        kind: .e1RM,
                        exerciseID: set.exerciseID,
                        weight: set.weight,
                        unit: set.unit,
                        reps: set.reps,
                        e1RM: e1rm,
                        achievedAt: set.performedAt
                    ))
                }
            }
        }
        return result
    }

    /// Devuelve la referencia de la regla versionada usada (auditable).
    public func ruleReference(_ config: PRDetectorConfig) -> EvidenceRuleReference? {
        try? config.reference()
    }
}