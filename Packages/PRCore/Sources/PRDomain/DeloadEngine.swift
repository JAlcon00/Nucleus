//
//  DeloadEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de deload (plan §15 Fase 12, promptMaster §13.4, PR-1303).
//  Soporta deload PLANEADO (por bloque, según `DeloadPolicy`) y TRIGGERED (por
//  señales de fatiga del RecoveryDecisionEngine, PR-1302). Reduce variable(s) según
//  la policy versionada (carga, RIR, volumen). El deload cumplido cuenta como
//  adherencia (`countsTowardAdherence`). Determinista, sin Views y auditable vía
//  `DecisionRecord`. No inventa reducciones: los parámetros centralizan los imports.
//

import Foundation

/// Variable que el deload reduce, según policy (promptMaster §13.4).
public enum DeloadReductionVariable: String, Codable, Sendable, CaseIterable, Hashable {
    /// Bajar `targetLoad` de las prescripciones.
    case load
    /// Aumentar RIR (dejar más reps en reserva → menos intensidad).
    case intensity
    /// Reducir volumen: quitar sets de trabajo.
    case volume
}

/// Origen del deload (§13.4): planeado por bloque o disparado por fatiga.
public enum DeloadKind: String, Codable, Sendable, Hashable {
    case planned
    case triggered
}

/// Reducciones concretas aplicadas a una sesión (valores ya validados).
public struct DeloadReduction: Equatable, Sendable {
    public let variable: DeloadReductionVariable
    /// Fracción de carga a quitar (load), RIR añadido (intensity) o sets a quitar (volume).
    public let amount: Double

    public init(variable: DeloadReductionVariable, amount: Double) {
        self.variable = variable
        self.amount = amount
    }
}

/// Prescripción de deload resultante de aplicar la policy a una sesión.
public struct DeloadPrescription: Equatable, Sendable {
    public let session: SessionTemplate
    public let reductions: [DeloadReduction]

    public init(session: SessionTemplate, reductions: [DeloadReduction]) {
        self.session = session
        self.reductions = reductions
    }
}

/// Entrada del motor de deload (PR-1303).
public struct DeloadInput: Sendable {
    /// Política de deload del bloque (`.none` = nunca planeado).
    public let policy: DeloadPolicy
    /// Semanas transcurridas desde el inicio del bloque (0-indexado).
    public let weeksElapsed: Int
    /// Sesión candidata a deload (lo planeado).
    public let session: SessionTemplate
    /// Estado de recuperación del RecoveryDecisionEngine (PR-1302) como señal de
    /// fatiga para el deload triggered. nil si no se evalúa recovery hoy.
    public let recoveryState: RecoveryState?

    public init(
        policy: DeloadPolicy,
        weeksElapsed: Int,
        session: SessionTemplate,
        recoveryState: RecoveryState? = nil
    ) {
        self.policy = policy
        self.weeksElapsed = weeksElapsed
        self.session = session
        self.recoveryState = recoveryState
    }
}

/// Resultado auditable del motor de deload.
public struct DeloadEvaluation: Equatable, Sendable {
    /// nil = ningún deload aplica esta semana.
    public let prescription: DeloadPrescription?
    public let kind: DeloadKind?
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    /// El deload cumplido cuenta como adherencia (§13.4).
    public let countsTowardAdherence: Bool
    public let decisionRecord: DecisionRecord

    public init(
        prescription: DeloadPrescription?,
        kind: DeloadKind?,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.prescription = prescription
        self.kind = kind
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.countsTowardAdherence = prescription != nil
        self.decisionRecord = decisionRecord
    }
}

/// Claves canónicas de la policy de deload.
public enum DeloadPolicyKeys {
    /// ¿Reducir carga? (1 = sí)
    public static let reductionLoad = "reductionLoad"
    public static let loadReductionFraction = "loadReductionFraction"
    /// ¿Añadir RIR? (1 = sí)
    public static let reductionIntensity = "reductionIntensity"
    public static let rirIncrease = "rirIncrease"
    /// ¿Reducir sets de trabajo? (1 = sí)
    public static let reductionVolume = "reductionVolume"
    public static let volumeReductionSets = "volumeReductionSets"
    /// Semana (0-indexado) en la que programar el deload de 6 semanas.
    public static let scheduledWeekSix = "scheduledWeekSix"
    /// Semana (0-indexado) en la que programar el deload de 8 semanas.
    public static let scheduledWeekEight = "scheduledWeekEight"
    /// ¿Permitir deload triggered por fatiga (PR-1302) fuera de plan? (1 = sí)
    public static let allowTriggered = "allowTriggered"

    public static let allRequired: Set<String> = [
        reductionLoad, loadReductionFraction,
        reductionIntensity, rirIncrease,
        reductionVolume, volumeReductionSets,
        scheduledWeekSix, scheduledWeekEight,
        allowTriggered,
    ]

    public static func defaults() -> [String: Double] {
        [
            reductionLoad: 1,
            loadReductionFraction: 0.4,
            reductionIntensity: 1,
            rirIncrease: 2,
            reductionVolume: 1,
            volumeReductionSets: 0,
            scheduledWeekSix: 5,
            scheduledWeekEight: 7,
            allowTriggered: 1,
        ]
    }
}

/// Regla de evidencia por defecto del deload (categoría `.recovery`).
public enum DeloadPolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "recovery.deload")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Deload: planned & triggered, reduce variables conservatively, counts as adherence",
            source: "Plan §15 / promptMaster §13.4"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Deload policy",
            category: .recovery,
            confidence: .expertConsensus,
            version: version,
            parameters: DeloadPolicyKeys.defaults(),
            references: [reference]
        )
    }
}

/// Problemas de entrada del motor de deload.
public enum DeloadEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    case invalidLoadFraction
    case invalidRIRIncrease
    case invalidVolumeReduction
}

/// Configuración versionada de la policy de deload.
public struct DeloadPolicyConfig: Sendable {
    public let rule: EvidenceRule

    public var reductionLoad: Bool { (rule.parameters[DeloadPolicyKeys.reductionLoad] ?? 0) > 0 }
    public var loadReductionFraction: Double { rule.parameters[DeloadPolicyKeys.loadReductionFraction] ?? 0.4 }
    public var reductionIntensity: Bool { (rule.parameters[DeloadPolicyKeys.reductionIntensity] ?? 0) > 0 }
    public var rirIncrease: Int { Int(rule.parameters[DeloadPolicyKeys.rirIncrease] ?? 2) }
    public var reductionVolume: Bool { (rule.parameters[DeloadPolicyKeys.reductionVolume] ?? 0) > 0 }
    public var volumeReductionSets: Int { Int(rule.parameters[DeloadPolicyKeys.volumeReductionSets] ?? 0) }
    public var scheduledWeekSix: Int { Int(rule.parameters[DeloadPolicyKeys.scheduledWeekSix] ?? 5) }
    public var scheduledWeekEight: Int { Int(rule.parameters[DeloadPolicyKeys.scheduledWeekEight] ?? 7) }
    public var allowTriggered: Bool { (rule.parameters[DeloadPolicyKeys.allowTriggered] ?? 0) > 0 }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .recovery else {
            throw DeloadEngineError.missingConfig(keys: ["category=.recovery"])
        }
        let missing = DeloadPolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw DeloadEngineError.missingConfig(keys: Array(missing).sorted())
        }
        let fraction = rule.parameters[DeloadPolicyKeys.loadReductionFraction] ?? 0.4
        guard fraction.isFinite, (0...1).contains(fraction) else {
            throw DeloadEngineError.invalidLoadFraction
        }
        guard (rule.parameters[DeloadPolicyKeys.rirIncrease] ?? 2) >= 0 else {
            throw DeloadEngineError.invalidRIRIncrease
        }
        guard (rule.parameters[DeloadPolicyKeys.volumeReductionSets] ?? 0) >= 0 else {
            throw DeloadEngineError.invalidVolumeReduction
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Motor determinista de deload (PR-1303).
///
/// Reglas:
/// - Planificado: `weeksElapsed >= semanaProgramada` según `DeloadPolicy`
///   (`afterSixWeeks` ⇒ `scheduledWeekSix`; `afterEightWeeks` ⇒ `scheduledWeekEight`;
///   `.none` nunca). Precedencia: `afterSixWeeks`/`afterEightWeeks` son excluyentes.
/// - Triggered: fatiga elevada (`recoveryState == .highFatigue/.restRecommended`)
///   con `allowTriggered` ⇒ deload, aunque no toque por agenda.
/// - Reduce variable(s) según policy: carga (fracción), RIR (añade), volumen (quita
///   sets) con guardas conservadoras (nunca elimina todos los sets de trabajo de un
///   ejercicio, carga no negativa, RIR no negativo). El deload cumplido cuenta adherencia.
public struct DeloadEngine: Sendable {
    public let config: DeloadPolicyConfig

    public init(config: DeloadPolicyConfig) throws {
        self.config = config
    }

    public func evaluate(_ input: DeloadInput) throws -> DeloadEvaluation {
        let reference = try config.reference()

        let scheduledWeek = scheduleWeek(for: input.policy)
        let isPlannedDue = input.policy != .none && scheduledWeek != nil && input.weeksElapsed >= scheduledWeek!
        let isTriggered = config.allowTriggered && isFatigueSignaled(input.recoveryState)

        guard isPlannedDue || isTriggered else {
            let record = DecisionRecord(
                type: .deload,
                inputFacts: [DecisionFact(key: "decision", value: "no-deload")],
                action: DecisionActionSummary(title: "No deload esta semana", detail: "sin agenda cumplida ni señal de fatiga"),
                ruleReferences: [reference],
                userOverrideAllowed: true
            )
            return DeloadEvaluation(
                prescription: nil,
                kind: nil,
                reasons: ["sin deload programado ni señal de fatiga"],
                ruleReference: reference,
                decisionRecord: record
            )
        }

        let kind: DeloadKind = isTriggered ? .triggered : .planned
        var reasons: [String] = []
        if isPlannedDue {
            reasons.append("deload programado por bloque (\(input.policy.rawValue), semana \(input.weeksElapsed))")
        }
        if isTriggered {
            reasons.append("deload triggered por señal de fatiga (\(String(describing: input.recoveryState)))")
        }

        var reductions: [DeloadReduction] = []
        if config.reductionLoad && input.session.plannedSets.contains(where: { $0.prescription.targetLoad != nil }) {
            reductions.append(.init(variable: .load, amount: config.loadReductionFraction))
        }
        if config.reductionIntensity {
            reductions.append(.init(variable: .intensity, amount: Double(config.rirIncrease)))
        }
        if config.reductionVolume && config.volumeReductionSets > 0 {
            reductions.append(.init(variable: .volume, amount: Double(config.volumeReductionSets)))
        }

        let session = Self.apply(reductions, to: input.session)
        let prescription = DeloadPrescription(session: session, reductions: reductions)

        let record = DecisionRecord(
            type: .deload,
            inputFacts: [
                DecisionFact(key: "kind", value: kind.rawValue),
                DecisionFact(key: "reductions", value: reductions.map { "\($0.variable.rawValue)=\($0.amount)" }.joined(separator: ", ")),
                DecisionFact(key: "countsTowardAdherence", value: "true"),
            ],
            action: DecisionActionSummary(
                title: "Sesión de deload (\(kind.rawValue))",
                detail: reductions.map { "\($0.variable.rawValue) \($0.amount)" }.joined(separator: ", ")
            ),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )

        return DeloadEvaluation(
            prescription: prescription,
            kind: kind,
            reasons: reasons,
            ruleReference: reference,
            decisionRecord: record
        )
    }

    // MARK: - Helpers

    private func scheduleWeek(for policy: DeloadPolicy) -> Int? {
        switch policy {
        case .none: return nil
        case .afterSixWeeks: return config.scheduledWeekSix
        case .afterEightWeeks: return config.scheduledWeekEight
        }
    }

    private func isFatigueSignaled(_ state: RecoveryState?) -> Bool {
        guard let state else { return false }
        return state == .highFatigue || state == .restRecommended
    }

    /// Aplicar reducciones con guardas conservadoras. Nunca deja un ejercicio sin
    /// sets de trabajo; carga no negativa; RIR no negativo.
    static func apply(_ reductions: [DeloadReduction], to session: SessionTemplate) -> SessionTemplate {
        let loadFraction = reductions.first { $0.variable == .load }?.amount ?? 0
        let rirIncrease = Int(reductions.first { $0.variable == .intensity }?.amount ?? 0)
        let volumeReduction = Int(reductions.first { $0.variable == .volume }?.amount ?? 0)

        var plannedSets = session.plannedSets

        // Volumen: quitar sets de trabajo por el final, manteniendo >=1 por ejercicio.
        if volumeReduction > 0 {
            var keptByExercise: [ExerciseID: Int] = [:]
            for set in plannedSets where !set.prescription.isWarmup {
                keptByExercise[set.exerciseID, default: 0] += 1
            }
            var toRemove = volumeReduction
            var kept: [PlannedSet] = []
            for set in plannedSets {
                if toRemove > 0 && !set.prescription.isWarmup {
                    let count = keptByExercise[set.exerciseID] ?? 0
                    if count > 1 {
                        keptByExercise[set.exerciseID] = count - 1
                        toRemove -= 1
                        continue // drop este set de trabajo
                    }
                }
                kept.append(set)
            }
            plannedSets = kept
        }

        // Carga y RIR por set.
        var mutated: [PlannedSet] = []
        for set in plannedSets {
            var prescription = set.prescription
            if let load = prescription.targetLoad, loadFraction > 0 {
                prescription.targetLoad = max(0, load * (1 - loadFraction))
            }
            if rirIncrease > 0, let rir = prescription.targetRIR {
                prescription.targetRIR = (rir.lowerBound + rirIncrease)...(rir.upperBound + rirIncrease)
            }
            mutated.append(PlannedSet(exerciseID: set.exerciseID, prescription: prescription))
        }

        return SessionTemplate(
            id: session.id,
            title: session.title,
            plannedSets: mutated,
            estimatedMinutes: session.estimatedMinutes
        )
    }
}