//
//  AutoRescheduleEngine.swift
//  PRDomain
//
//  Created by PR.
//
//  Motor determinista de auto-reprogramación tras descanso (plan §15 Fase 12,
//  promptMaster §20.3 `rescheduleWorkout`, PR-1304). Cuando un día de descanso
//  recomendado (p.ej. `RecoveryDecision.restRecommended` de PR-1302) bloquea una
//  sesión programada, propone moverla a la primera ranura compatible libre, evitando
//  crear conflictos de sesiones consecutivas incompatibles (mismos grupos musculares
//  en días seguidos) y exigiendo confirmación del usuario ante cambios importantes de
//  calendario. Determinista, sin Views y auditable vía `DecisionRecord`.
//

import Foundation

/// Una sesión programada con su foco muscular (para compatibilidad de días seguidos).
public struct ScheduledSession: Equatable, Sendable {
    public let sessionID: UUID
    public let title: String
    /// Grupos musculares primarios de la sesión. Dos sesiones consecutivas con foco
    /// compartido se consideran incompatibles (recuperación insuficiente).
    public let focus: Set<MuscleGroup.ID>

    public init(sessionID: UUID = UUID(), title: String, focus: Set<MuscleGroup.ID>) {
        self.sessionID = sessionID
        self.title = title
        self.focus = focus
    }
}

/// Un día dentro de la ventana de calendario.
public struct ScheduleDay: Equatable, Sendable {
    public let dayIndex: Int
    /// nil = día libre/descanso (sin sesión).
    public let session: ScheduledSession?
    /// Día bloqueado como descanso recomendado (la causa del movimiento).
    public let isBlockedRest: Bool

    public init(dayIndex: Int, session: ScheduledSession?, isBlockedRest: Bool = false) {
        self.dayIndex = dayIndex
        self.session = session
        self.isBlockedRest = isBlockedRest
    }
}

/// Entrada del motor de auto-reprogramación (PR-1304).
public struct AutoRescheduleInput: Sendable {
    /// Ventana completa de calendario, ordenada por `dayIndex`.
    public let schedule: [ScheduleDay]
    /// Índice del día de la sesión afectada (que queda bloqueado por el descanso).
    public let affectedDayIndex: Int

    public init(schedule: [ScheduleDay], affectedDayIndex: Int) {
        self.schedule = schedule
        self.affectedDayIndex = affectedDayIndex
    }
}

/// Propuesta de movimiento de sesión.
public struct RescheduleProposal: Equatable, Sendable {
    public let originalDayIndex: Int
    public let proposedDayIndex: Int
    public let session: ScheduledSession
    /// true = requiere confirmación explícita del usuario (cambio importante).
    public let requiresUserConfirmation: Bool
    /// Pares consecutivos verificados (nuevo slot y sus vecinos) que resultan compatibles.
    public let checkedNeighbors: [NeighborCompatibility]

    public init(
        originalDayIndex: Int,
        proposedDayIndex: Int,
        session: ScheduledSession,
        requiresUserConfirmation: Bool,
        checkedNeighbors: [NeighborCompatibility]
    ) {
        self.originalDayIndex = originalDayIndex
        self.proposedDayIndex = proposedDayIndex
        self.session = session
        self.requiresUserConfirmation = requiresUserConfirmation
        self.checkedNeighbors = checkedNeighbors
    }
}

/// Compatibilidad de un par de sesiones consecutivas alrededor del nuevo slot.
public struct NeighborCompatibility: Equatable, Sendable {
    public let withDayIndex: Int
    public let session: ScheduledSession?
    public let compatible: Bool

    public init(withDayIndex: Int, session: ScheduledSession?, compatible: Bool) {
        self.withDayIndex = withDayIndex
        self.session = session
        self.compatible = compatible
    }
}

/// Resultado auditable del motor.
public struct AutoRescheduleEvaluation: Equatable, Sendable {
    public let proposal: RescheduleProposal?
    public let reasons: [String]
    public let ruleReference: EvidenceRuleReference
    public let decisionRecord: DecisionRecord

    public init(
        proposal: RescheduleProposal?,
        reasons: [String],
        ruleReference: EvidenceRuleReference,
        decisionRecord: DecisionRecord
    ) {
        self.proposal = proposal
        self.reasons = reasons
        self.ruleReference = ruleReference
        self.decisionRecord = decisionRecord
    }
}

/// Claves canónicas de la policy de auto-reprogramación.
public enum AutoReschedulePolicyKeys {
    /// Máximo de días que se mueve una sesión sin requerir confirmación.
    public static let maxRecommendedShiftDays = "maxRecommendedShiftDays"
    /// ¿Foco compartido entre días seguidos se trata como conflicto? (1 = sí).
    public static let conflictOnSharedFocus = "conflictOnSharedFocus"

    public static let allRequired: Set<String> = [
        maxRecommendedShiftDays, conflictOnSharedFocus,
    ]

    public static func defaults() -> [String: Double] {
        [
            maxRecommendedShiftDays: 2,
            conflictOnSharedFocus: 1,
        ]
    }
}

/// Regla de evidencia por defecto (categoría `.rest`, por ser descanso dirigido).
public enum AutoReschedulePolicyDefaults {
    public static let ruleID = EvidenceRuleID(rawValue: "rest.autoReschedule")

    public static func makeRule(version: Int = 1) throws -> EvidenceRule {
        let reference = try EvidenceReference(
            title: "Auto-reschedule after rest: move to earliest compatible free slot, confirm important changes",
            source: "Plan §15 / promptMaster §20.3"
        )
        return try EvidenceRule(
            id: ruleID,
            name: "Auto-reschedule policy",
            category: .rest,
            confidence: .expertConsensus,
            version: version,
            parameters: AutoReschedulePolicyKeys.defaults(),
            references: [reference]
        )
    }
}

/// Problemas de entrada del motor.
public enum AutoRescheduleEngineError: Error, Equatable, Sendable {
    case missingConfig(keys: [String])
    /// Día afectado fuera de la ventana.
    case affectedDayOutOfRange
    /// `affectedDayIndex` apunta a un día sin sesión (nada que mover).
    case affectedDayHasNoSession
    /// La sesión afectada no está bloqueada por descanso (nada que reprogramar).
    case affectedDayNotBlocked
}

/// Configuración versionada de la policy.
public struct AutoRescheduleConfig: Sendable {
    public let rule: EvidenceRule

    public var maxRecommendedShiftDays: Int { Int(rule.parameters[AutoReschedulePolicyKeys.maxRecommendedShiftDays] ?? 2) }
    public var conflictOnSharedFocus: Bool { (rule.parameters[AutoReschedulePolicyKeys.conflictOnSharedFocus] ?? 1) > 0 }

    public init(rule: EvidenceRule) throws {
        guard rule.category == .rest else {
            throw AutoRescheduleEngineError.missingConfig(keys: ["category=.rest"])
        }
        let missing = AutoReschedulePolicyKeys.allRequired.filter { rule.parameters[$0] == nil }
        guard missing.isEmpty else {
            throw AutoRescheduleEngineError.missingConfig(keys: Array(missing).sorted())
        }
        guard (rule.parameters[AutoReschedulePolicyKeys.maxRecommendedShiftDays] ?? 2) >= 0 else {
            throw AutoRescheduleEngineError.missingConfig(keys: ["maxRecommendedShiftDays negative"])
        }
        self.rule = rule
    }

    public func reference() throws -> EvidenceRuleReference {
        try EvidenceRuleReference(rule)
    }
}

/// Motor determinista de auto-reprogramación tras descanso (PR-1304).
///
/// Reglas:
/// - Si el día afectado está `isBlockedRest` y tiene sesión, se propone moverla a la
///   primera ranura libre/no-bloqueada dentro de la ventana.
/// - Se evita crear sesiones consecutivas incompatibles: el nuevo slot debe ser
///   compatible con su día anterior (si lo hay) y con el día siguiente si tendría
///   sesión. Dos sesiones comparten foco ⇒ incompatible (recuperación insuficiente).
/// - Se prefiere mover dentro de `maxRecommendedShiftDays`; si sólo hay una ranura
///   compatible más allá de ese límite, se propone con `requiresUserConfirmation=true`
///   (cambio importante). Si no hay ninguna ranura compatible, no se inventa un
///   movimiento (respuesta conservadora): `proposal == nil`.
public struct AutoRescheduleEngine: Sendable {
    public let config: AutoRescheduleConfig

    public init(config: AutoRescheduleConfig) throws {
        self.config = config
    }

    public func evaluate(_ input: AutoRescheduleInput) throws -> AutoRescheduleEvaluation {
        let reference = try config.reference()

        guard (0..<input.schedule.count).contains(input.affectedDayIndex) else {
            throw AutoRescheduleEngineError.affectedDayOutOfRange
        }
        let affectedDay = input.schedule[input.affectedDayIndex]
        guard let movedSession = affectedDay.session else {
            throw AutoRescheduleEngineError.affectedDayHasNoSession
        }
        guard affectedDay.isBlockedRest else {
            throw AutoRescheduleEngineError.affectedDayNotBlocked
        }

        var reasons: [String] = ["día \(input.affectedDayIndex) bloqueado como descanso recomendado; se mueve la sesión"]

        // Buscar la primera ranura compatible libre/no-bloqueada.
        for candidateIndex in (input.affectedDayIndex + 1)..<input.schedule.count {
            let day = input.schedule[candidateIndex]
            if day.session != nil { continue }
            if day.isBlockedRest { continue }

            let neighbors = neighborChecks(input: input, slot: candidateIndex, session: movedSession, vacatedDay: input.affectedDayIndex)
            guard neighbors.allSatisfy(\.compatible) else {
                reasons.append("ranura día \(candidateIndex) descartada: crearía sesiones consecutivas incompatibles")
                continue
            }

            let shift = candidateIndex - input.affectedDayIndex
            let important = shift > config.maxRecommendedShiftDays
            let proposal = RescheduleProposal(
                originalDayIndex: input.affectedDayIndex,
                proposedDayIndex: candidateIndex,
                session: movedSession,
                requiresUserConfirmation: important,
                checkedNeighbors: neighbors
            )
            if important {
                reasons.append("la única ranura compatible requiere mover \(shift) días (> máx \(config.maxRecommendedShiftDays)); se solicita confirmación")
            } else {
                reasons.append("se mueve \(shift) día(s) a la ranura compatible día \(candidateIndex)")
            }

            let record = DecisionRecord(
                type: .reorder,
                inputFacts: [
                    DecisionFact(key: "fromDay", value: String(input.affectedDayIndex)),
                    DecisionFact(key: "toDay", value: String(candidateIndex)),
                    DecisionFact(key: "session", value: movedSession.title),
                    DecisionFact(key: "requiresUserConfirmation", value: String(important)),
                ],
                action: DecisionActionSummary(title: "Mover sesión por descanso recomendado", detail: "día \(input.affectedDayIndex) → \(candidateIndex)"),
                ruleReferences: [reference],
                userOverrideAllowed: true
            )
            return AutoRescheduleEvaluation(
                proposal: proposal,
                reasons: reasons,
                ruleReference: reference,
                decisionRecord: record
            )
        }

        // Sin ranura compatible: respuesta conservadora, sin movimiento inventado.
        let record = DecisionRecord(
            type: .restChange,
            inputFacts: [DecisionFact(key: "decision", value: "no-move")],
            action: DecisionActionSummary(title: "No mover sesión", detail: "sin ranura compatible libre en la ventana"),
            ruleReferences: [reference],
            userOverrideAllowed: true
        )
        return AutoRescheduleEvaluation(
            proposal: nil,
            reasons: reasons + ["no se encontró ranura compatible; no se mueve (conservador)"],
            ruleReference: reference,
            decisionRecord: record
        )
    }

    // MARK: - Helpers

    private func neighborChecks(input: AutoRescheduleInput, slot: Int, session: ScheduledSession, vacatedDay: Int) -> [NeighborCompatibility] {
        var checks: [NeighborCompatibility] = []
        // Día anterior (si existe y tiene sesión). Se omite el día del que se vacía la
        // sesión, porque tras el movimiento ese día queda libre.
        if slot > 0, slot - 1 != vacatedDay, let prev = input.schedule[slot - 1].session {
            checks.append(.init(
                withDayIndex: slot - 1,
                session: prev,
                compatible: areCompatible(prev, session)
            ))
        }
        // Día siguiente (si existe y tiene sesión).
        if slot + 1 < input.schedule.count, let next = input.schedule[slot + 1].session {
            checks.append(.init(
                withDayIndex: slot + 1,
                session: next,
                compatible: areCompatible(session, next)
            ))
        }
        return checks
    }

    private func areCompatible(_ a: ScheduledSession, _ b: ScheduledSession) -> Bool {
        if config.conflictOnSharedFocus {
            return a.focus.isDisjoint(with: b.focus)
        }
        return true
    }
}