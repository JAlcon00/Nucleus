//
//  PlanPersonalizationService.swift
//  PRCore
//
//  SCRUM-205 (IA-4): pide a la IA la personalización del bloque y la explicación
//  "Por qué tu plan es así", y orquesta motor → IA → validación → motor.
//
//  - Sin consentimiento (contexto `nil`) o sin conexión: no se manda nada y el plan es
//    el del motor con la explicación local.
//  - La IA sólo elige de listas cerradas: músculos de las prioridades y alternativas ya
//    filtradas por el motor (mismo músculo, misma clase, equipo y restricciones). Los
//    ejercicios viajan con claves cortas (`e1`, `e2`…), nunca con IDs ni nombres del
//    usuario, y la respuesta se revisa de nuevo con `PlanPersonalizationValidator`.
//  - Toda falla (red, JSON inválido, explicación con números inventados) cae al plan y
//    al texto locales; nunca bloquea. El motivo queda en el log de diagnóstico (categoría
//    `agent`) y en `PersonalizedPlan.rationaleFallback`.
//  - La explicación sólo recibe hechos útiles para el usuario (`PlanRationaleFacts`) y su
//    respuesta se parte en oraciones antes del filtro (`PlanRationaleGuard.lines`).
//

import Foundation
import PRDomain

// MARK: - Contrato con la IA

/// Lo que la IA ve para proponer ajustes.
public struct PlanPersonalizationPrompt: Encodable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public let key: String
        public let name: String
        public let muscles: [MuscleGroup]
        public let compound: Bool
    }

    public struct Session: Codable, Sendable, Equatable {
        public let title: String
        public let exercises: [String]
    }

    public struct Alternative: Codable, Sendable, Equatable {
        public let replace: String
        public let options: [String]
    }

    public let profile: AgentProfileContext
    public let exercises: [Line]
    public let sessions: [Session]
    public let emphasisOptions: [MuscleGroup]
    public let maxEmphasis: Int
    public let alternatives: [Alternative]
    public let maxSubstitutions: Int

    /// Clave corta → ejercicio (no viaja; sirve para traducir la respuesta).
    public let keys: [String: ExerciseID]

    private enum CodingKeys: String, CodingKey {
        case profile, exercises, sessions, emphasisOptions, maxEmphasis, alternatives, maxSubstitutions
    }

    public init(
        profile: AgentProfileContext,
        block: TrainingBlock,
        catalog: [Exercise],
        alternatives: [ExerciseID: [ExerciseID]],
        config: PlanPersonalizationPolicyConfig
    ) {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var order: [ExerciseID] = []
        var seen: Set<ExerciseID> = []
        func note(_ id: ExerciseID) {
            if seen.insert(id).inserted { order.append(id) }
        }
        for session in block.sessions {
            for set in session.plannedSets { note(set.exerciseID) }
        }
        let planned = order
        for id in planned {
            for option in alternatives[id] ?? [] { note(option) }
        }
        var keyOf: [ExerciseID: String] = [:]
        var keys: [String: ExerciseID] = [:]
        for (index, id) in order.enumerated() {
            let key = "e\(index + 1)"
            keyOf[id] = key
            keys[key] = id
        }
        self.profile = profile
        self.keys = keys
        self.exercises = order.compactMap { id in
            guard let exercise = byID[id], let key = keyOf[id] else { return nil }
            return Line(
                key: key,
                name: exercise.canonicalName,
                muscles: exercise.primaryMuscles.map(\.muscleGroupID),
                compound: exercise.jointClass == .multiJoint
            )
        }
        self.sessions = block.sessions.map { session in
            var lineKeys: [String] = []
            for set in session.plannedSets {
                if let key = keyOf[set.exerciseID], lineKeys.last != key, !lineKeys.contains(key) { lineKeys.append(key) }
            }
            return Session(title: session.title, exercises: lineKeys)
        }
        self.emphasisOptions = block.priorities.map(\.muscleGroupID)
        self.maxEmphasis = config.maxEmphasizedMuscles
        self.alternatives = planned.compactMap { id in
            guard let options = alternatives[id], !options.isEmpty, let key = keyOf[id] else { return nil }
            return Alternative(replace: key, options: options.compactMap { keyOf[$0] })
        }
        self.maxSubstitutions = config.maxSubstitutions
    }

    /// Traduce la respuesta JSON de la IA a una propuesta. Músculos o claves desconocidos
    /// se descartan aquí; lo demás lo decide el validador. `nil` si no es JSON válido.
    public func proposal(fromReply text: String) -> PlanPersonalizationProposal? {
        guard let data = Self.jsonObject(in: text),
              let raw = try? JSONDecoder().decode(RawProposal.self, from: data) else { return nil }
        let emphasis = (raw.emphasis ?? []).compactMap(MuscleGroup.init(rawValue:))
        let substitutions = (raw.substitutions ?? []).compactMap { item -> ProposedSubstitution? in
            guard let replace = keys[item.replace], let with = keys[item.with] else { return nil }
            return ProposedSubstitution(replace: replace, with: with)
        }
        return PlanPersonalizationProposal(emphasis: emphasis, substitutions: substitutions)
    }

    private struct RawProposal: Decodable {
        struct Item: Decodable { let replace: String; let with: String }
        let emphasis: [String]?
        let substitutions: [Item]?
    }

    /// Primer objeto JSON del texto (tolera ```json … ``` y texto alrededor).
    static func jsonObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }
}

/// Quien habla con la IA (real o de prueba).
public protocol PlanPersonalizing: Sendable {
    /// Ajustes propuestos; `nil` si la IA no está disponible o respondió algo inválido.
    func propose(_ prompt: PlanPersonalizationPrompt) async -> PlanPersonalizationProposal?
    /// Explicación en 1–4 líneas a partir de los hechos; `nil` si no está disponible.
    func explain(facts: [DecisionFact]) async -> [String]?
}

/// Personalizador con la IA real (vía `AICoach`, que nunca lanza). Si la IA no responde
/// o su JSON no se entiende lo deja en el log de diagnóstico, sin contenido.
public struct AIPlanPersonalizer: PlanPersonalizing {
    public let coach: AICoach
    public let config: PlanPersonalizationPolicyConfig
    private let logger: PRLogger

    public init(coach: AICoach, config: PlanPersonalizationPolicyConfig = .standard, logger: PRLogger = PRLogger(category: .agent)) {
        self.coach = coach
        self.config = config
        self.logger = logger
    }

    public func propose(_ prompt: PlanPersonalizationPrompt) async -> PlanPersonalizationProposal? {
        guard let payload = try? JSONEncoder().encode(prompt), let json = String(data: payload, encoding: .utf8) else {
            logger.diagnostic("plan.proposal no se pudo codificar", level: .error)
            return nil
        }
        let request = AgentRequest(
            messages: [
                AgentMessage(role: "system", content: Self.proposalSystemPrompt),
                AgentMessage(role: "user", content: json),
            ],
            output: .json
        )
        switch await coach.ask(request) {
        case .unavailable(let error):
            logger.diagnostic("plan.proposal IA no disponible", error.diagnosticCode)
            return nil
        case .answer(let response):
            guard let proposal = response.text.flatMap(prompt.proposal(fromReply:)) else {
                logger.diagnostic("plan.proposal respuesta sin JSON válido")
                return nil
            }
            return proposal
        }
    }

    public func explain(facts: [DecisionFact]) async -> [String]? {
        let lines = facts.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        let request = AgentRequest(
            messages: [
                AgentMessage(role: "system", content: Self.explanationSystemPrompt(config: config)),
                AgentMessage(role: "user", content: lines),
            ]
        )
        switch await coach.ask(request) {
        case .unavailable(let error):
            logger.diagnostic("plan.rationale IA no disponible", error.diagnosticCode)
            return nil
        case .answer(let response):
            return PlanRationaleGuard.lines(fromReply: response.text ?? "")
        }
    }

    static let proposalSystemPrompt = """
    Eres el asistente de personalización de Nucleus, una app de entrenamiento de fuerza. \
    El motor de entrenamiento YA armó el plan del usuario; tú sólo puedes proponer ajustes. \
    Puedes proponer: (1) hasta maxEmphasis músculos a enfatizar, elegidos SOLO de \
    emphasisOptions, cuando el perfil lo justifique (objetivo, experiencia, sexo, días); \
    (2) hasta maxSubstitutions sustituciones, eligiendo SOLO de alternatives (replace → una \
    de options), cuando otra opción encaje mejor con el perfil o sus restricciones. \
    Nunca propongas series, repeticiones, cargas, RIR ni ejercicios fuera de las listas. \
    Si el plan ya encaja, devuelve listas vacías. \
    Responde SOLO con JSON: {"emphasis":["chest"],"substitutions":[{"replace":"e1","with":"e7"}]}
    """

    /// Los límites de formato salen de la misma política que aplica `PlanRationaleGuard`.
    public static func explanationSystemPrompt(config: PlanPersonalizationPolicyConfig) -> String {
        """
        Explica en español por qué el plan del usuario es así. \
        Formato obligatorio: de 2 a \(config.maxRationaleLines) renglones EN TOTAL, separados por \
        salto de línea; cada renglón es UNA sola oración de menos de \(config.maxRationaleLineLength) \
        caracteres. Agrupa varios hechos en una oración en lugar de dedicar una a cada uno. \
        Nada de párrafos, viñetas, listas numeradas, títulos ni markdown. \
        Usa SOLO los hechos que recibes; no menciones ningún número que no aparezca en ellos, \
        ni cargas, ni RIR, ni promesas. Escribe los números siempre con dígitos (6, nunca \
        "seis"). Traduce los valores técnicos a palabras sencillas en \
        español (por ejemplo, hypertrophy es ganar músculo y pushPullLegs es empuje, jalón y \
        pierna) y nunca escribas los nombres de los hechos. Háblale de tú. Recuerda: el plan \
        lo arma el motor de Nucleus, no la IA; nunca digas que la IA creó la rutina.
        """
    }
}

/// Por qué "Por qué tu plan es así" quedó con el texto local en lugar del de la IA.
public enum PlanRationaleFallback: Sendable, Hashable {
    /// Sin consentimiento o sin IA conectada: no se le preguntó.
    case notRequested
    /// Se le preguntó y no respondió (red, llave, tiempo de espera…).
    case unavailable
    /// Respondió, pero el filtro la rechazó.
    case rejected(PlanRationaleRejection)

    /// Código fijo para el log de diagnóstico.
    public var diagnosticCode: StaticString {
        switch self {
        case .notRequested: return "sin consentimiento o sin IA"
        case .unavailable: return "la IA no respondió"
        case .rejected(.empty): return "rechazada: vacía"
        case .rejected(.tooManyLines): return "rechazada: demasiados renglones"
        case .rejected(.lineTooLong): return "rechazada: renglón demasiado largo"
        case .rejected(.unknownNumber): return "rechazada: número que no viene del motor"
        case .rejected(.technicalTerm): return "rechazada: término interno del motor"
        }
    }
}

// MARK: - Explicación local

/// Explicación "Por qué tu plan es así" sin IA, sólo con hechos del motor.
public struct PlanRationalePresenter: Sendable {
    private let locale: Locale
    private let vocabulary: TrainingVocabularyPresenter

    public init(locale: Locale = .current) {
        self.locale = locale
        self.vocabulary = TrainingVocabularyPresenter(locale: locale)
    }

    public func lines(
        facts: [DecisionFact],
        emphasis: [MuscleGroup],
        substitutions: [(from: String, to: String)]
    ) -> [String] {
        let value = Dictionary(facts.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        if let days = value["trainingDaysPerWeek"].flatMap(Int.init), let weeks = value["plannedWeeks"].flatMap(Int.init) {
            lines.append(resource("Entrenas \(days) días por semana en un bloque de \(weeks) semanas.", "Por qué tu plan: días y semanas"))
        }
        if let sets = value["totalWeeklySets"].flatMap(Int.init) {
            lines.append(resource("Tu semana suma \(sets) series, repartidas según tu objetivo.", "Por qué tu plan: series por semana"))
        }
        if !emphasis.isEmpty {
            let names = emphasis.map(vocabulary.muscleName).formatted(.list(type: .and).locale(locale))
            lines.append(resource("Más volumen para \(names).", "Por qué tu plan: músculos con énfasis"))
        }
        for substitution in substitutions {
            lines.append(resource("\(substitution.to) en lugar de \(substitution.from).", "Por qué tu plan: ejercicio cambiado"))
        }
        // SCRUM-209: zonas cuidadas y músculos omitidos por una restricción.
        let regions = Self.list(value["restrictedRegions"], BodyRegion.init(rawValue:)).map(vocabulary.bodyRegionName)
        if !regions.isEmpty {
            let names = regions.formatted(.list(type: .and).locale(locale))
            lines.append(resource("Cuidamos tu \(names): evitamos los movimientos de más riesgo para esa zona.", "Por qué tu plan: zonas con restricción"))
        }
        let skipped = Self.list(value["restrictedMuscles"], MuscleGroup.init(rawValue:)).map(vocabulary.muscleName)
        if !skipped.isEmpty {
            let names = skipped.formatted(.list(type: .and).locale(locale))
            lines.append(resource("Por tu restricción no programamos \(names) por ahora.", "Por qué tu plan: músculos omitidos por una restricción"))
        }
        // SCRUM-218: lo protegido (los ejercicios básicos) no se recorta para cumplir el tope o el tiempo.
        if value["sessionsOverRange"] != nil {
            lines.append(resource("En algunas sesiones dejamos más ejercicios de lo habitual para tu tiempo: los básicos no se quitan.", "Por qué tu plan: sesiones con más ejercicios que el rango"))
        }
        if value["sessionsOverTime"] != nil {
            lines.append(resource("Algunas sesiones pasan de tu tiempo: no quitamos los ejercicios básicos ni les dejamos menos series de su mínimo.", "Por qué tu plan: sesiones que no caben en el tiempo"))
        }
        return lines
    }

    /// Valores separados por coma de un hecho ("shoulder, knee").
    private static func list<Value>(_ raw: String?, _ make: (String) -> Value?) -> [Value] {
        (raw ?? "").split(separator: ",").compactMap { make($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}

// MARK: - Orquestación

/// Resultado de personalizar: el bloque final (del motor), su explicación y el registro.
public struct PersonalizedPlan: Sendable {
    public let result: BlockPlanningResult
    public let record: PlanPersonalizationRecord
    /// Por qué la explicación es la local; `nil` cuando es la de la IA.
    public let rationaleFallback: PlanRationaleFallback?

    public init(result: BlockPlanningResult, record: PlanPersonalizationRecord, rationaleFallback: PlanRationaleFallback?) {
        self.result = result
        self.record = record
        self.rationaleFallback = rationaleFallback
    }
}

/// Motor → IA → validación → motor. Sin estado; el reloj y los IDs se inyectan.
public struct PlanPersonalizationFlow: Sendable {
    public let validator: PlanPersonalizationValidator
    public let guardrail: PlanRationaleGuard
    public let presenter: PlanRationalePresenter
    private let logger: PRLogger

    public init(
        validator: PlanPersonalizationValidator,
        guardrail: PlanRationaleGuard = PlanRationaleGuard(),
        presenter: PlanRationalePresenter = PlanRationalePresenter(),
        logger: PRLogger = PRLogger(category: .agent)
    ) {
        self.validator = validator
        self.guardrail = guardrail
        self.presenter = presenter
        self.logger = logger
    }

    /// Sin IA: el plan del motor tal cual con la explicación local.
    public func local(_ base: BlockPlanningResult) -> PersonalizedPlan {
        PersonalizedPlan(
            result: base,
            record: PlanPersonalizationRecord(
                decisions: [],
                rationale: presenter.lines(facts: base.explanation.facts, emphasis: [], substitutions: []),
                rationaleSource: .local,
                audit: []
            ),
            rationaleFallback: .notRequested
        )
    }

    /// `regenerate`: el motor vuelve a armar el bloque con los músculos enfatizados.
    public func personalize(
        base: BlockPlanningResult,
        context: AgentProfileContext?,
        personalizer: (any PlanPersonalizing)?,
        catalog: [Exercise],
        restrictions: [TrainingRestriction],
        equipment: EquipmentKnownness,
        conversationID: UUID,
        now: Date,
        regenerate: @Sendable ([MuscleGroup]) throws -> BlockPlanningResult
    ) async throws -> PersonalizedPlan {
        guard let context, let personalizer else {
            logger.diagnostic("plan.rationale texto local", PlanRationaleFallback.notRequested.diagnosticCode, level: .info)
            return local(base)
        }
        let alternatives = try validator.alternatives(
            block: base.block, catalog: catalog, activeRestrictions: restrictions, equipment: equipment, now: now
        )
        let prompt = PlanPersonalizationPrompt(
            profile: context, block: base.block, catalog: catalog, alternatives: alternatives, config: validator.config
        )
        let proposal = await personalizer.propose(prompt) ?? .none

        let emphasisReview = try validator.reviewEmphasis(
            proposal.emphasis, priorities: base.block.priorities, conversationID: conversationID, now: now
        )
        var result = base
        if !emphasisReview.acceptedEmphasis.isEmpty {
            result = try regenerate(emphasisReview.acceptedEmphasis)
        }
        let substitutionReview = try validator.reviewSubstitutions(
            proposal.substitutions, block: result.block, catalog: catalog, activeRestrictions: restrictions,
            equipment: equipment, conversationID: conversationID, now: now
        )
        let accepted = substitutionReview.acceptedSubstitutions
        let block = PlanPersonalizationApplier.substituting(accepted, in: result.block)
        let names = Dictionary(catalog.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
        let swaps = accepted.compactMap { substitution -> (from: String, to: String)? in
            guard let from = names[substitution.replace], let to = names[substitution.with] else { return nil }
            return (from, to)
        }
        var facts = result.explanation.facts
        let emphasis = emphasisReview.acceptedEmphasis
        if !emphasis.isEmpty {
            facts.append(DecisionFact(key: "emphasizedMuscles", value: emphasis.map(\.rawValue).joined(separator: ", ")))
        }
        for swap in swaps {
            facts.append(DecisionFact(key: "substitution", value: "\(swap.from) → \(swap.to)"))
        }
        let explanation = BlockExplanation(
            facts: facts, ruleReferences: result.explanation.ruleReferences, sessionOrder: result.explanation.sessionOrder
        )
        // La IA sólo ve los hechos útiles para el usuario y el filtro revisa los números
        // contra esos mismos hechos: lo que no viaja tampoco se puede citar.
        let shared = PlanRationaleFacts.userFacing(facts)
        let rationale: [String]?
        let fallback: PlanRationaleFallback?
        switch await personalizer.explain(facts: shared).map({ guardrail.review($0, facts: shared) }) {
        case .accepted(let lines)?:
            rationale = lines
            fallback = nil
            logger.diagnostic("plan.rationale explicación de la IA aceptada", level: .info)
        case .rejected(let reason)?:
            rationale = nil
            fallback = .rejected(reason)
        case nil:
            rationale = nil
            fallback = .unavailable
        }
        if let fallback {
            logger.diagnostic("plan.rationale texto local", fallback.diagnosticCode)
        }
        return PersonalizedPlan(
            result: BlockPlanningResult(block: block, explanation: explanation, split: result.split),
            record: PlanPersonalizationRecord(
                decisions: emphasisReview.decisions + substitutionReview.decisions,
                rationale: rationale ?? presenter.lines(facts: facts, emphasis: emphasis, substitutions: swaps),
                rationaleSource: rationale == nil ? .local : .ai,
                audit: emphasisReview.audit + substitutionReview.audit
            ),
            rationaleFallback: fallback
        )
    }
}
