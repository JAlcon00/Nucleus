//
//  ExplainableDecisions.swift
//  PRDomain
//
//  SCRUM-270 (PR-I001, RF-025, RNEG-004, RD-007): el `DecisionRecord` de cada decisión que
//  la persona ve, para contestar "¿Por qué?" con lo que de verdad usó el motor y nunca con
//  texto del LLM. Los registros se arman de lo que la app ya guarda (plan, tiempo elegido,
//  check-in de sueño, gimnasio, series), así que no hay nada nuevo que persistir.
//
//  - Cada registro lleva sólo hechos (`DecisionFact`) y la referencia versionada de su
//    regla cuando existe; el texto lo arma `DecisionExplanationPresenter` (PRCore).
//  - Funciones puras: la fecha se inyecta y el ID sale de los hechos (mismo estado, mismo
//    ID), así "¿Por qué?" encuentra la misma decisión aunque se vuelva a armar.
//

import Foundation

// MARK: - Tema

/// De qué trata una decisión que se puede explicar.
public enum ExplainableTopic: String, Codable, Sendable, Hashable, CaseIterable {
    /// El orden de los ejercicios de hoy (SCRUM-29, SCRUM-211).
    case sessionOrder
    /// El ajuste de hoy al tiempo elegido (SCRUM-30).
    case timeFit
    /// El día aligerado por el check-in de sueño (SCRUM-203).
    case readiness
    /// Un ejercicio que el gimnasio activo cambió o quitó (SCRUM-236).
    case gymChange
    /// El peso precargado de la serie actual (SCRUM-237).
    case suggestedLoad
    /// La recomendación tras reportar dolor (SCRUM-32, SCRUM-226).
    case pain
}

/// Una decisión que la persona puede preguntar, con su registro.
public struct ExplainableDecision: Sendable, Hashable, Identifiable {
    public let topic: ExplainableTopic
    public let record: DecisionRecord

    public var id: DecisionID { record.id }

    public init(topic: ExplainableTopic, record: DecisionRecord) {
        self.topic = topic
        self.record = record
    }

    /// Valores del hecho `key`, en orden.
    public func values(_ key: String) -> [String] {
        record.inputFacts.filter { $0.key == key }.map(\.value)
    }

    /// Primer valor del hecho `key`, si está.
    public func value(_ key: String) -> String? {
        record.inputFacts.first { $0.key == key }?.value
    }
}

// MARK: - Claves de los hechos

/// Claves estables de los hechos. Un hecho repetido (p. ej. varios ejercicios quitados) va
/// varias veces con la misma clave, en orden.
public enum ExplainableFactKey {
    // Orden
    public static let orderCustom = "order.custom"
    public static let orderReorderedByFatigue = "order.reorderedByFatigue"
    /// "rank|nombre" de cada ejercicio, en orden. Nombre vacío si ya no está en el catálogo.
    public static let orderEntry = "order.entry"
    /// "rank|motivo" (`functionalRole`, `musclePriority`, `technicalDemand`).
    public static let orderReason = "order.reason"

    // Tiempo
    public static let timeBudgetMinutes = "time.budgetMinutes"
    public static let timeOriginalMinutes = "time.originalMinutes"
    /// `fits`, `trimmed` o `doesNotFit`.
    public static let timeFit = "time.fit"
    public static let timeNeededMinutes = "time.neededMinutes"
    public static let timeRemoved = "time.removed"
    public static let timeReduced = "time.reduced"
    public static let timeJoinedFirst = "time.joinedFirst"
    public static let timeJoinedSecond = "time.joinedSecond"
    public static let timeSuggestion = "time.suggestion"
    /// RN-002: el tiempo nunca agrega series.
    public static let timeNoExtraVolume = "time.noExtraVolume"

    // Sueño
    public static let readinessReason = "readiness.reason"
    public static let readinessRIRIncrease = "readiness.rirIncrease"
    public static let readinessIsolationSetReduction = "readiness.isolationSetReduction"
    /// El ajuste no toca carga ni repeticiones (`ReadinessEngine.apply`).
    public static let readinessLoadUnchanged = "readiness.loadUnchanged"

    // Gimnasio
    /// `replaced` u `omitted`.
    public static let gymChange = "gym.change"
    public static let gymOriginal = "gym.original"
    public static let gymReplacement = "gym.replacement"

    // Peso precargado
    /// `lastTime`, `prescription` o `none`.
    public static let loadSource = "load.source"
    public static let loadExercise = "load.exercise"
    public static let loadWeight = "load.weight"
    public static let loadUnit = "load.unit"
    public static let loadPerMachine = "load.perMachine"
    public static let loadWarmup = "load.warmup"
    /// La app no sube el peso por su cuenta: precarga lo que hay.
    public static let loadProgressionApplied = "load.progressionApplied"

    // Dolor: las del registro de `PainFeedbackEngine`.
    public static let painLevel = "level"
    public static let painRecommendation = "recommendation"
    public static let painSuspendsLoadProgression = "suspendsLoadProgression"
    public static let painExercise = "exercise"
}

/// De dónde salió el peso precargado (`SetCompleter.preload`).
public enum SuggestedLoadSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// El último peso que se levantó en este ejercicio (o en esta máquina).
    case lastTime
    /// El peso que trae la prescripción del plan.
    case prescription
    /// No hay dato: se precarga 0 para que la persona lo escriba.
    case none
}

// MARK: - Constructor

/// Arma el registro de cada decisión visible. Puro y determinista.
public struct ExplainableDecisionBuilder: Sendable {
    public init() {}

    /// El orden de hoy. `nil` sin explicación del motor.
    public func sessionOrder(
        _ explanation: SessionOrderExplanation?,
        isCustom: Bool,
        name: (ExerciseID) -> String?,
        ruleReferences: [EvidenceRuleReference],
        date: Date
    ) -> ExplainableDecision? {
        guard let explanation, !explanation.entries.isEmpty else { return nil }
        var facts: [DecisionFact] = []
        if isCustom {
            facts.append(DecisionFact(key: ExplainableFactKey.orderCustom, value: "true"))
        }
        facts.append(DecisionFact(key: ExplainableFactKey.orderReorderedByFatigue, value: String(explanation.reorderedByFatigue)))
        for entry in explanation.entries.sorted(by: { $0.rank < $1.rank }) {
            facts.append(DecisionFact(key: ExplainableFactKey.orderEntry, value: "\(entry.rank)|\(name(entry.exerciseID) ?? "")"))
            for fact in entry.facts {
                guard let reason = Self.orderReason(forFactKey: fact.key) else { continue }
                facts.append(DecisionFact(key: ExplainableFactKey.orderReason, value: "\(entry.rank)|\(reason)"))
            }
        }
        return make(
            topic: .sessionOrder, type: .reorder, title: "Orden de la sesión",
            facts: facts, ruleReferences: ruleReferences, date: date
        )
    }

    /// El ajuste de hoy al tiempo elegido. `nil` sin tiempo elegido.
    public func timeFit(
        _ adjustment: SessionTimeAdjustment?,
        name: (ExerciseID) -> String?,
        date: Date
    ) -> ExplainableDecision? {
        guard let adjustment else { return nil }
        var facts = [
            DecisionFact(key: ExplainableFactKey.timeBudgetMinutes, value: String(adjustment.budgetMinutes)),
            DecisionFact(key: ExplainableFactKey.timeOriginalMinutes, value: String(adjustment.originalMinutes)),
        ]
        switch adjustment.fit {
        case .fits(_, let suggestions):
            facts.append(DecisionFact(key: ExplainableFactKey.timeFit, value: "fits"))
            facts.append(contentsOf: suggestions.map { DecisionFact(key: ExplainableFactKey.timeSuggestion, value: $0.rawValue) })
        case .trimmed(let removed, let reduced):
            facts.append(DecisionFact(key: ExplainableFactKey.timeFit, value: "trimmed"))
            facts.append(contentsOf: removed.map { DecisionFact(key: ExplainableFactKey.timeRemoved, value: name($0) ?? "") })
            facts.append(contentsOf: reduced.map { DecisionFact(key: ExplainableFactKey.timeReduced, value: name($0.exerciseID) ?? "") })
        case .doesNotFit(let needed, let removed, let reduced):
            facts.append(DecisionFact(key: ExplainableFactKey.timeFit, value: "doesNotFit"))
            facts.append(DecisionFact(key: ExplainableFactKey.timeNeededMinutes, value: String(needed)))
            facts.append(contentsOf: removed.map { DecisionFact(key: ExplainableFactKey.timeRemoved, value: name($0) ?? "") })
            facts.append(contentsOf: reduced.map { DecisionFact(key: ExplainableFactKey.timeReduced, value: name($0.exerciseID) ?? "") })
        }
        for pair in adjustment.joined {
            facts.append(DecisionFact(key: ExplainableFactKey.timeJoinedFirst, value: name(pair.first) ?? ""))
            facts.append(DecisionFact(key: ExplainableFactKey.timeJoinedSecond, value: name(pair.second) ?? ""))
        }
        facts.append(DecisionFact(key: ExplainableFactKey.timeNoExtraVolume, value: "true"))
        return make(
            topic: .timeFit, type: .setVolumeChange, title: "Sesión ajustada al tiempo",
            facts: facts, ruleReferences: [], date: date
        )
    }

    /// El día aligerado por el sueño. `nil` si no se aligeró.
    public func readiness(_ adjustment: ReadinessAdjustment, date: Date) -> ExplainableDecision? {
        switch adjustment {
        case .none:
            return nil
        case .lighter(let reason, let rirIncrease, let isolationSetReduction):
            let facts = [
                DecisionFact(key: ExplainableFactKey.readinessReason, value: reason.rawValue),
                DecisionFact(key: ExplainableFactKey.readinessRIRIncrease, value: String(rirIncrease)),
                DecisionFact(key: ExplainableFactKey.readinessIsolationSetReduction, value: String(isolationSetReduction)),
                DecisionFact(key: ExplainableFactKey.readinessLoadUnchanged, value: "true"),
            ]
            return make(
                topic: .readiness, type: .intensityChange, title: "Día aligerado por el sueño",
                facts: facts, ruleReferences: [], date: date
            )
        }
    }

    /// Un registro por cada cambio del gimnasio en la sesión de hoy.
    public func gymChanges(
        _ notes: [GymAdaptationNote],
        name: (ExerciseID) -> String?,
        ruleReferences: [EvidenceRuleReference],
        date: Date
    ) -> [ExplainableDecision] {
        notes.map { note in
            var facts: [DecisionFact]
            switch note {
            case .replaced(let original, let replacement):
                facts = [
                    DecisionFact(key: ExplainableFactKey.gymChange, value: "replaced"),
                    DecisionFact(key: ExplainableFactKey.gymOriginal, value: name(original) ?? ""),
                    DecisionFact(key: ExplainableFactKey.gymReplacement, value: name(replacement) ?? ""),
                ]
            case .omitted(let original):
                facts = [
                    DecisionFact(key: ExplainableFactKey.gymChange, value: "omitted"),
                    DecisionFact(key: ExplainableFactKey.gymOriginal, value: name(original) ?? ""),
                ]
            }
            return make(
                topic: .gymChange, type: .exerciseSubstitution, title: "Cambio por el gimnasio",
                facts: facts, ruleReferences: ruleReferences, date: date
            )
        }
    }

    /// De dónde sale el peso precargado de la serie actual.
    public func suggestedLoad(
        draft: SetCompletionDraft,
        exerciseName: String?,
        isWarmup: Bool,
        loadIsPerMachine: Bool,
        date: Date
    ) -> ExplainableDecision {
        let source: SuggestedLoadSource
        if draft.weightFromHistory {
            source = .lastTime
        } else if draft.targetWeight > 0 {
            source = .prescription
        } else {
            source = .none
        }
        var facts = [
            DecisionFact(key: ExplainableFactKey.loadSource, value: source.rawValue),
            DecisionFact(key: ExplainableFactKey.loadExercise, value: exerciseName ?? ""),
        ]
        switch source {
        case .lastTime, .prescription:
            facts.append(DecisionFact(key: ExplainableFactKey.loadWeight, value: Self.weightText(draft.targetWeight)))
            facts.append(DecisionFact(key: ExplainableFactKey.loadUnit, value: draft.targetUnit.rawValue))
        case .none:
            break
        }
        facts.append(DecisionFact(key: ExplainableFactKey.loadPerMachine, value: String(loadIsPerMachine)))
        facts.append(DecisionFact(key: ExplainableFactKey.loadWarmup, value: String(isWarmup)))
        facts.append(DecisionFact(key: ExplainableFactKey.loadProgressionApplied, value: "false"))
        return make(
            topic: .suggestedLoad, type: .loadChange, title: "Peso precargado",
            facts: facts, ruleReferences: [], date: date
        )
    }

    /// El registro de `PainFeedbackEngine`, con un ID estable y la fecha inyectada; los
    /// hechos, la acción y la regla son los del motor. "Sin dolor" no tiene registro.
    public func pain(_ evaluation: PainEvaluation, date: Date) -> ExplainableDecision? {
        let facts = evaluation.decisionRecord.inputFacts
        guard facts.first(where: { $0.key == ExplainableFactKey.painLevel })?.value != String(PainLevel.none.rawValue) else {
            return nil
        }
        let source = evaluation.decisionRecord
        let record = DecisionRecord(
            id: StableDecisionID.make(topic: .pain, facts: facts),
            date: date,
            type: source.type,
            inputFacts: facts,
            action: source.action,
            ruleReferences: source.ruleReferences,
            userOverrideAllowed: source.userOverrideAllowed
        )
        return ExplainableDecision(topic: .pain, record: record)
    }

    // MARK: - Helpers

    private func make(
        topic: ExplainableTopic,
        type: DecisionType,
        title: String,
        facts: [DecisionFact],
        ruleReferences: [EvidenceRuleReference],
        date: Date
    ) -> ExplainableDecision {
        ExplainableDecision(topic: topic, record: DecisionRecord(
            id: StableDecisionID.make(topic: topic, facts: facts),
            date: date,
            type: type,
            inputFacts: facts,
            action: DecisionActionSummary(title: title),
            ruleReferences: ruleReferences,
            userOverrideAllowed: true
        ))
    }

    private static func orderReason(forFactKey key: String) -> String? {
        switch key {
        case "exercise.order.role": return "functionalRole"
        case "exercise.order.musclePriority": return "musclePriority"
        case "exercise.order.skillDemand": return "technicalDemand"
        default: return nil
        }
    }

    /// "40" o "42.5": sin ceros de más ni notación científica.
    static func weightText(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(weight)
    }
}

// MARK: - ID estable

/// ID que sale del tema y los hechos: el mismo estado da el mismo ID en cualquier arranque
/// (el `Hasher` de Swift cambia en cada proceso, por eso FNV-1a).
public enum StableDecisionID {
    public static func make(topic: ExplainableTopic, facts: [DecisionFact]) -> DecisionID {
        let text = ([topic.rawValue] + facts.map { "\($0.key)=\($0.value)" }).joined(separator: "\u{1F}")
        let bytes = Array(text.utf8)
        let high = fnv1a(bytes, seed: 0xcbf2_9ce4_8422_2325)
        let low = fnv1a(bytes, seed: 0x8422_2325_cbf2_9ce4)
        var raw = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            raw[index] = UInt8(truncatingIfNeeded: high >> (UInt64(7 - index) * 8))
            raw[index + 8] = UInt8(truncatingIfNeeded: low >> (UInt64(7 - index) * 8))
        }
        // Versión 8 (personalizada) y variante RFC 4122, para que sea un UUID válido.
        raw[6] = (raw[6] & 0x0F) | 0x80
        raw[8] = (raw[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
        ))
        return DecisionID(rawValue: uuid)
    }

    private static func fnv1a(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
