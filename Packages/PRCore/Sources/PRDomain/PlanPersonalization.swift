//
//  PlanPersonalization.swift
//  PRDomain
//
//  SCRUM-205 (IA-4): personalización del plan propuesta por la IA tras el formulario.
//
//  Contrato:
//  - El motor genera el bloque con todo el perfil. La IA sólo PROPONE ajustes
//    estructurados: músculos a enfatizar y sustituciones de ejercicio.
//  - Cada ajuste pasa por reglas de forma (existe, está en el plan, es equivalente según la
//    regla del motor de sustitutos: mismo movimiento y puntaje mínimo, SCRUM-240; equipo
//    disponible y, si va en superset, sin músculos en común con su pareja: SCRUM-241) y por
//    `ActionPolicyValidator`
//    (`adjustVolume` / `replaceExercise`, que rechaza sustitutos prohibidos por una
//    restricción). Sólo lo aceptado cambia el plan; todo queda en `AgentAuditRecord`.
//  - El énfasis no fija números: el motor vuelve a repartir el volumen con la
//    prioridad `.emphasize`. La sustitución sólo cambia el ejercicio; la prescripción
//    (series, reps, RIR, descanso) la sigue decidiendo el motor. El LLM nunca calcula
//    carga, volumen ni RIR.
//  - La explicación de la IA sólo se acepta si cada número que menciona viene de los
//    hechos del motor; si no, se usa el texto local.
//

import Foundation

// MARK: - Propuesta (lo que manda la IA)

/// Sustitución propuesta: cambiar `replace` por `with` en todo el bloque.
public struct ProposedSubstitution: Codable, Sendable, Hashable {
    public var replace: ExerciseID
    public var with: ExerciseID

    public init(replace: ExerciseID, with: ExerciseID) {
        self.replace = replace
        self.with = with
    }
}

/// Ajustes que la IA propone sobre el bloque del motor. Campos ausentes = sin ajustes.
public struct PlanPersonalizationProposal: Codable, Sendable, Hashable {
    public var emphasis: [MuscleGroup]
    public var substitutions: [ProposedSubstitution]

    public init(emphasis: [MuscleGroup] = [], substitutions: [ProposedSubstitution] = []) {
        self.emphasis = emphasis
        self.substitutions = substitutions
    }

    public static let none = PlanPersonalizationProposal()

    public var isEmpty: Bool { emphasis.isEmpty && substitutions.isEmpty }

    private enum CodingKeys: String, CodingKey { case emphasis, substitutions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emphasis = try container.decodeIfPresent([MuscleGroup].self, forKey: .emphasis) ?? []
        substitutions = try container.decodeIfPresent([ProposedSubstitution].self, forKey: .substitutions) ?? []
    }
}

// MARK: - Política

/// Límites de la personalización (versionables; nada de números mágicos en la lógica).
public struct PlanPersonalizationPolicyConfig: Sendable, Hashable {
    /// Músculos que la IA puede enfatizar como máximo.
    public var maxEmphasizedMuscles: Int
    /// Sustituciones aceptadas como máximo.
    public var maxSubstitutions: Int
    /// Líneas de la explicación "Por qué tu plan es así".
    public var maxRationaleLines: Int
    /// Caracteres por línea de explicación.
    public var maxRationaleLineLength: Int
    /// Alternativas válidas que se le ofrecen a la IA por ejercicio del plan.
    public var maxAlternativesPerExercise: Int

    public init(
        maxEmphasizedMuscles: Int,
        maxSubstitutions: Int,
        maxRationaleLines: Int,
        maxRationaleLineLength: Int,
        maxAlternativesPerExercise: Int
    ) {
        self.maxEmphasizedMuscles = maxEmphasizedMuscles
        self.maxSubstitutions = maxSubstitutions
        self.maxRationaleLines = maxRationaleLines
        self.maxRationaleLineLength = maxRationaleLineLength
        self.maxAlternativesPerExercise = maxAlternativesPerExercise
    }

    public static let standard = PlanPersonalizationPolicyConfig(
        maxEmphasizedMuscles: 2, maxSubstitutions: 3, maxRationaleLines: 4, maxRationaleLineLength: 180,
        maxAlternativesPerExercise: 3
    )
}

// MARK: - Revisión

/// Un ajuste concreto (aceptado o rechazado).
public enum PersonalizationAdjustment: Codable, Sendable, Hashable {
    case emphasize(MuscleGroup)
    case substitute(ProposedSubstitution)
}

/// Por qué se rechazó un ajuste.
public enum PersonalizationRejection: String, Codable, Sendable, Hashable, CaseIterable {
    /// El músculo no es parte de las prioridades del bloque.
    case unknownMuscle
    /// El ejercicio no existe en el catálogo.
    case unknownExercise
    /// El ejercicio a cambiar no está en el plan.
    case exerciseNotInPlan
    /// El sustituto ya está en el plan (o es el mismo).
    case alreadyInPlan
    /// Repetido dentro de la misma propuesta.
    case duplicate
    /// Se alcanzó el máximo de la política.
    case limitReached
    /// El sustituto no trabaja el mismo músculo principal.
    case differentMuscle
    /// El sustituto hace otro movimiento: mismo músculo no es ejercicio equivalente (DE-3).
    case differentPattern
    /// El sustituto es de otra clase (compuesto/aislado): cambiaría la prescripción.
    case differentJointClass
    /// El equipo del sustituto no está disponible.
    case equipmentUnavailable
    /// No llega al puntaje mínimo de `safety.substitutionScoring` (DE-3).
    case belowMinimumScore
    /// El ejercicio va en superset y el sustituto comparte músculo con su pareja: el par se
    /// desharía y la sesión dejaría de caber en el tiempo (SCRUM-241).
    case breaksSuperset
    /// `ActionPolicyValidator` lo rechazó (p. ej. evade una restricción).
    case rejectedByPolicy
}

public enum PersonalizationOutcome: Codable, Sendable, Hashable {
    case accepted
    case rejected(PersonalizationRejection)
}

public struct PersonalizationDecision: Codable, Sendable, Hashable {
    public let adjustment: PersonalizationAdjustment
    public let outcome: PersonalizationOutcome

    public init(adjustment: PersonalizationAdjustment, outcome: PersonalizationOutcome) {
        self.adjustment = adjustment
        self.outcome = outcome
    }

    public var isAccepted: Bool {
        switch outcome {
        case .accepted: return true
        case .rejected: return false
        }
    }
}

/// Resultado de revisar una parte de la propuesta: decisiones y su bitácora.
public struct PersonalizationReview: Sendable, Equatable {
    public let decisions: [PersonalizationDecision]
    public let audit: [AgentAuditRecord]

    public init(decisions: [PersonalizationDecision], audit: [AgentAuditRecord]) {
        self.decisions = decisions
        self.audit = audit
    }

    public var acceptedEmphasis: [MuscleGroup] {
        decisions.compactMap {
            guard $0.isAccepted, case .emphasize(let muscle) = $0.adjustment else { return nil }
            return muscle
        }
    }

    public var acceptedSubstitutions: [ProposedSubstitution] {
        decisions.compactMap {
            guard $0.isAccepted, case .substitute(let substitution) = $0.adjustment else { return nil }
            return substitution
        }
    }
}

/// Revisa la propuesta de la IA. Determinista y sin acceso a persistencia.
public struct PlanPersonalizationValidator: Sendable {
    public let policy: ActionPolicyValidator
    public let restrictions: RestrictionPolicyEngine
    /// La regla de equivalencia de DE-3: la misma del motor de sustitutos (SCRUM-240).
    public let equivalence: SubstitutionScoringEngine
    public let config: PlanPersonalizationPolicyConfig

    public init(
        policy: ActionPolicyValidator,
        restrictions: RestrictionPolicyEngine,
        equivalence: SubstitutionScoringEngine,
        config: PlanPersonalizationPolicyConfig = .standard
    ) {
        self.policy = policy
        self.restrictions = restrictions
        self.equivalence = equivalence
        self.config = config
    }

    /// Validador con las reglas versionadas por defecto.
    public static func standard() throws -> PlanPersonalizationValidator {
        PlanPersonalizationValidator(
            policy: try ActionPolicyValidator(config: ActionPolicyConfig(rule: ActionPolicyDefaults.makeRule())),
            restrictions: try RestrictionPolicyEngine(config: RestrictionPolicyConfig(rule: RestrictionPolicyDefaults.makeRule())),
            equivalence: SubstitutionScoringEngine(config: try SubstitutionScoringConfig(rule: SubstitutionScoringDefaults.makeRule()))
        )
    }

    /// Énfasis: sólo músculos de las prioridades del bloque, sin repetir y hasta el máximo.
    /// En el formulario no hay reporte de dolor: el pain gate queda inactivo; las
    /// restricciones las sigue aplicando el motor al elegir ejercicios.
    public func reviewEmphasis(
        _ muscles: [MuscleGroup],
        priorities: [MusclePriority],
        conversationID: UUID,
        now: Date
    ) throws -> PersonalizationReview {
        let known = Set(priorities.map(\.muscleGroupID))
        var seen: Set<MuscleGroup> = []
        var accepted = 0
        var decisions: [PersonalizationDecision] = []
        var audit: [AgentAuditRecord] = []
        for muscle in muscles {
            let adjustment = PersonalizationAdjustment.emphasize(muscle)
            let intent = AgentIntent.requestPlanAdjustment(
                PlanAdjustmentRequest(scope: .volume, rationale: "emphasis:\(muscle.rawValue)")
            )
            audit.append(.intent(intent, conversationID: conversationID, date: now))
            let shapeProblem: PersonalizationRejection?
            if seen.contains(muscle) {
                shapeProblem = .duplicate
            } else if !known.contains(muscle) {
                shapeProblem = .unknownMuscle
            } else if accepted >= config.maxEmphasizedMuscles {
                shapeProblem = .limitReached
            } else {
                shapeProblem = nil
            }
            seen.insert(muscle)
            if let shapeProblem {
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .rejected(shapeProblem)))
                audit.append(try rejection(shapeProblem, action: .adjustVolume, conversationID: conversationID, now: now))
                continue
            }
            let verdict = try policy.validate(
                .adjustVolume,
                context: ActionPolicyContext(painGateActive: false, proposedProgressionIncrease: true)
            )
            audit.append(.validation(verdict, conversationID: conversationID, date: now))
            if case .allowed(let command) = verdict.outcome {
                accepted += 1
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .accepted))
                audit.append(.result(command: command, conversationID: conversationID, date: now))
            } else {
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .rejected(.rejectedByPolicy)))
            }
        }
        return PersonalizationReview(decisions: decisions, audit: audit)
    }

    /// Sustituciones contra el bloque final del motor. El sustituto debe existir, no estar
    /// ya en el plan, hacer el mismo movimiento (DE-3), tener equipo disponible, llegar al
    /// puntaje mínimo y, si el ejercicio va en superset, no compartir músculo con su pareja
    /// (ya cambiada si también se sustituyó); luego `ActionPolicyValidator` decide con el
    /// veredicto de restricciones (nunca se evade una restricción activa). El motivo es el
    /// primero que falla, en ese orden.
    public func reviewSubstitutions(
        _ substitutions: [ProposedSubstitution],
        block: TrainingBlock,
        catalog: [Exercise],
        activeRestrictions: [TrainingRestriction],
        equipment: EquipmentKnownness,
        conversationID: UUID,
        now: Date
    ) throws -> PersonalizationReview {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inPlan = Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) })
        let relevant = restrictions.relevantRestrictions(activeRestrictions, asOf: now)
        let partners = supersetPartners(in: block)
        // Original → sustituto de lo ya aceptado en esta propuesta.
        var accepted: [ExerciseID: ExerciseID] = [:]
        var decisions: [PersonalizationDecision] = []
        var audit: [AgentAuditRecord] = []
        for substitution in substitutions {
            let adjustment = PersonalizationAdjustment.substitute(substitution)
            audit.append(.intent(.requestExerciseSwap(substitution.replace), conversationID: conversationID, date: now))
            let shapeProblem = try shapeProblem(
                substitution, byID: byID, inPlan: inPlan, accepted: accepted, partners: partners, equipment: equipment
            )
            if let shapeProblem {
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .rejected(shapeProblem)))
                audit.append(try rejection(shapeProblem, action: .replaceExercise, conversationID: conversationID, now: now))
                continue
            }
            guard let substitute = byID[substitution.with] else { continue }
            let verdict = try restrictions.evaluate(
                RestrictionPolicyInput(exercise: substitute, activeRestrictions: relevant, asOf: now)
            ).verdict
            let policyVerdict = try policy.validate(
                .replaceExercise,
                context: ActionPolicyContext(proposedSubstituteIsForbidden: verdict != .allowed)
            )
            audit.append(.validation(policyVerdict, conversationID: conversationID, date: now))
            if case .allowed(let command) = policyVerdict.outcome {
                accepted[substitution.replace] = substitution.with
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .accepted))
                audit.append(.result(command: command, conversationID: conversationID, date: now))
            } else {
                decisions.append(PersonalizationDecision(adjustment: adjustment, outcome: .rejected(.rejectedByPolicy)))
            }
        }
        return PersonalizationReview(decisions: decisions, audit: audit)
    }

    /// Alternativas que pasarían la revisión para cada ejercicio del plan: las mejores del
    /// motor de sustitutos, en su orden. Se le ofrecen a la IA para que no proponga a ciegas;
    /// la revisión se repite igual al recibir la propuesta.
    public func alternatives(
        block: TrainingBlock,
        catalog: [Exercise],
        activeRestrictions: [TrainingRestriction],
        equipment: EquipmentKnownness,
        now: Date
    ) throws -> [ExerciseID: [ExerciseID]] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inPlan = Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) })
        let relevant = restrictions.relevantRestrictions(activeRestrictions, asOf: now)
        let partners = supersetPartners(in: block)
        let usable = catalog.filter { isAvailable($0, in: equipment) }
        var result: [ExerciseID: [ExerciseID]] = [:]
        for exerciseID in inPlan {
            guard let target = byID[exerciseID] else { continue }
            let candidates = usable.filter {
                keepsSupersets(replacing: exerciseID, with: $0, byID: byID, accepted: [:], partners: partners)
            }
            let options = try equivalence.substitutes(for: SubstitutionRequest(
                target: target, candidates: candidates, sessionExerciseIDs: inPlan,
                activeRestrictions: relevant, asOf: now, restrictionPolicyConfig: restrictions.config
            )).ranked.prefix(config.maxAlternativesPerExercise).map(\.exercise.id)
            if !options.isEmpty { result[exerciseID] = options }
        }
        return result
    }

    /// `accepted`: original → sustituto de lo ya aceptado en la misma propuesta.
    /// `partners`: parejas de superset de cada ejercicio en el bloque.
    private func shapeProblem(
        _ substitution: ProposedSubstitution,
        byID: [ExerciseID: Exercise],
        inPlan: Set<ExerciseID>,
        accepted: [ExerciseID: ExerciseID],
        partners: [ExerciseID: [ExerciseID]],
        equipment: EquipmentKnownness
    ) throws -> PersonalizationRejection? {
        guard let original = byID[substitution.replace], let substitute = byID[substitution.with] else {
            return .unknownExercise
        }
        if accepted[substitution.replace] != nil || accepted.values.contains(substitution.with) { return .duplicate }
        if !inPlan.contains(substitution.replace) { return .exerciseNotInPlan }
        if inPlan.contains(substitution.with) { return .alreadyInPlan }
        if accepted.count >= config.maxSubstitutions { return .limitReached }
        switch SubstitutionScoringEngine.movementMismatch(substitute, target: original) {
        case .differentMuscle: return .differentMuscle
        case .differentPattern: return .differentPattern
        case .differentJointClass: return .differentJointClass
        case nil: break
        }
        if !isAvailable(substitute, in: equipment) { return .equipmentUnavailable }
        // Sin restricciones ni disponibilidad aquí: lo único que puede dejarla fuera es el
        // mínimo. La personalización puntúa sin historial, preferencias ni gimnasio, para que
        // el mismo plan dé lo mismo al migrarlo.
        let verdict = try equivalence.substitutes(for: SubstitutionRequest(target: original, candidates: [substitute]))
        if verdict.ranked.isEmpty { return .belowMinimumScore }
        let keepsPairs = keepsSupersets(
            replacing: substitution.replace, with: substitute, byID: byID, accepted: accepted, partners: partners
        )
        return keepsPairs ? nil : .breaksSuperset
    }

    private func isAvailable(_ exercise: Exercise, in equipment: EquipmentKnownness) -> Bool {
        switch equipment {
        case .knownAvailable(let available): return available.contains(exercise.equipment)
        case .unknown: return true
        }
    }

    /// SCRUM-241: el par se queda con el sustituto sólo si no comparte músculo con la pareja
    /// de cada sesión (la pareja ya cambiada si la IA también la sustituyó).
    private func keepsSupersets(
        replacing exerciseID: ExerciseID,
        with substitute: Exercise,
        byID: [ExerciseID: Exercise],
        accepted: [ExerciseID: ExerciseID],
        partners: [ExerciseID: [ExerciseID]]
    ) -> Bool {
        (partners[exerciseID] ?? []).allSatisfy { partner in
            byID[accepted[partner] ?? partner].map { SupersetPairing.areCompatible(substitute, $0) } ?? false
        }
    }

    /// Parejas de superset de cada ejercicio, en todas las sesiones del bloque.
    private func supersetPartners(in block: TrainingBlock) -> [ExerciseID: [ExerciseID]] {
        var partners: [ExerciseID: [ExerciseID]] = [:]
        for pair in block.sessions.flatMap(\.supersetPairs) {
            partners[pair.first, default: []].append(pair.second)
            partners[pair.second, default: []].append(pair.first)
        }
        return partners
    }

    /// Los rechazos de la regla de equivalencia llevan su versión (RD-007).
    private func rejection(
        _ reason: PersonalizationRejection,
        action: AgentAction,
        conversationID: UUID,
        now: Date
    ) throws -> AgentAuditRecord {
        let equivalenceReasons: Set<PersonalizationRejection> = [
            .differentMuscle, .differentPattern, .differentJointClass, .belowMinimumScore,
        ]
        return AgentAuditRecord(
            date: now,
            conversationID: conversationID,
            stage: .actionValidation,
            actionName: action.displayName,
            outcome: "rejected",
            ruleReference: equivalenceReasons.contains(reason) ? try equivalence.config.reference() : nil,
            notes: [reason.rawValue]
        )
    }
}

// MARK: - Aplicación

public enum PlanPersonalizationApplier {
    /// Sube a `.emphasize` los músculos aceptados (nunca baja un tier ya mayor). El
    /// motor decide cuántas series implica.
    public static func priorities(_ base: [MusclePriority], emphasizing muscles: [MuscleGroup]) -> [MusclePriority] {
        let targets = Set(muscles)
        return base.map { priority in
            guard targets.contains(priority.muscleGroupID), priority.priority.rawValue < PriorityTier.emphasize.rawValue else { return priority }
            var raised = priority
            raised.priority = .emphasize
            return raised
        }
    }

    /// Cambia el ejercicio en cada serie planificada y en su par de superset (SCRUM-241: el
    /// validador ya comprobó que el sustituto es compatible con la pareja). La prescripción
    /// no se toca.
    public static func substituting(_ substitutions: [ProposedSubstitution], in block: TrainingBlock) -> TrainingBlock {
        let map = Dictionary(substitutions.map { ($0.replace, $0.with) }, uniquingKeysWith: { first, _ in first })
        guard !map.isEmpty else { return block }
        var result = block
        result.sessions = block.sessions.map { session in
            var session = session
            session.plannedSets = session.plannedSets.map { set in
                guard let replacement = map[set.exerciseID] else { return set }
                var set = set
                set.exerciseID = replacement
                return set
            }
            session.supersets = session.supersets?.compactMap { pair in
                SupersetPair(first: map[pair.first] ?? pair.first, second: map[pair.second] ?? pair.second)
            }
            return session
        }
        return result
    }

    /// Clave del hecho de cada par en superset ("A + B"), la misma que pone `BlockPlanner`.
    private static let supersetFactKey = "superset"

    /// Los hechos `superset` vuelven a nombrar los pares del bloque ya sustituido, en el
    /// lugar donde los dejó el motor (SCRUM-241): ningún hecho nombra un par que no está en
    /// el plan, tampoco lo que viaja a la IA. Sin sustituciones, los hechos no cambian.
    public static func supersetFacts(
        _ facts: [DecisionFact],
        after substitutions: [ProposedSubstitution],
        in block: TrainingBlock,
        names: [ExerciseID: String]
    ) -> [DecisionFact] {
        guard !substitutions.isEmpty else { return facts }
        var values: [String] = []
        for pair in block.sessions.flatMap(\.supersetPairs) {
            let value = [pair.first, pair.second].map { names[$0] ?? $0.rawValue.uuidString }.joined(separator: " + ")
            if !values.contains(value) { values.append(value) }
        }
        let rebuilt = values.map { DecisionFact(key: supersetFactKey, value: $0) }
        guard let position = facts.firstIndex(where: { $0.key == supersetFactKey }) else { return facts + rebuilt }
        var result = facts.filter { $0.key != supersetFactKey }
        result.insert(contentsOf: rebuilt, at: position)
        return result
    }
}

// MARK: - Explicación

/// Hechos del motor que sí le sirven al usuario para entender su plan. Es una lista
/// cerrada: un hecho nuevo del motor no viaja a la IA hasta que se agregue aquí. Los
/// internos (`priorityMuscles`, `orderPrecedence`) se quedan fuera porque la IA los
/// convertía en tecnicismos ("orden de precedencia", "8 músculos prioritarios").
public enum PlanRationaleFacts {
    public static let userFacingKeys: Set<String> = [
        "goal", "phase", "plannedWeeks", "split", "trainingDaysPerWeek", "totalWeeklySets",
        "restrictedRegions", "restrictedMuscles", "emphasizedMuscles", "substitution",
        "sessionsOverRange", "sessionsOverTime", "maintenanceLeftOut", "superset",
    ]

    /// Los hechos de la lista, en su orden original.
    public static func userFacing(_ facts: [DecisionFact]) -> [DecisionFact] {
        facts.filter { userFacingKeys.contains($0.key) }
    }
}

/// Por qué el filtro rechazó la explicación de la IA.
public enum PlanRationaleRejection: String, Sendable, Hashable, CaseIterable {
    case empty
    case tooManyLines
    case lineTooLong
    case unknownNumber
    /// Un identificador interno de un hecho ("pushPullLegs") llegó tal cual al texto.
    case technicalTerm
}

/// Veredicto del filtro sobre la explicación de la IA.
public enum PlanRationaleReview: Sendable, Hashable {
    case accepted([String])
    case rejected(PlanRationaleRejection)
}

/// Filtro de la explicación de la IA: sólo pasa si es corta, cada número que menciona
/// (con dígitos o con letras) aparece en los hechos del motor (la IA no inventa series,
/// semanas ni cargas) y no copia identificadores internos. Ante la duda, falla cerrado:
/// se usa el texto local.
public struct PlanRationaleGuard: Sendable {
    public let config: PlanPersonalizationPolicyConfig

    public init(config: PlanPersonalizationPolicyConfig = .standard) {
        self.config = config
    }

    /// Las líneas limpias si se aceptan; `nil` si hay que usar el texto local.
    public func accept(_ lines: [String], facts: [DecisionFact]) -> [String]? {
        switch review(lines, facts: facts) {
        case .accepted(let cleaned): return cleaned
        case .rejected: return nil
        }
    }

    /// Como `accept`, pero dice el motivo del rechazo.
    public func review(_ lines: [String], facts: [DecisionFact]) -> PlanRationaleReview {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return .rejected(.empty) }
        guard cleaned.count <= config.maxRationaleLines else { return .rejected(.tooManyLines) }
        guard cleaned.allSatisfy({ $0.count <= config.maxRationaleLineLength }) else { return .rejected(.lineTooLong) }
        let allowed = Set(facts.flatMap { Self.numbers(in: $0.value) })
        let words = cleaned.map(Self.words(in:))
        // Los escritos con letras ("seis", "sesenta y cuatro") se revisan igual que los dígitos.
        let mentioned = cleaned.flatMap { Self.numbers(in: $0) } + words.flatMap { Self.spelledNumbers(in: $0).map(String.init) }
        guard mentioned.allSatisfy(allowed.contains) else { return .rejected(.unknownNumber) }
        let identifiers = Set(facts.flatMap { Self.identifiers(in: $0.value) })
        guard words.allSatisfy({ identifiers.isDisjoint(with: $0) }) else { return .rejected(.technicalTerm) }
        return .accepted(cleaned)
    }

    /// Palabras en orden, en minúsculas y sin acentos.
    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split { !$0.isLetter }.map(String.init)
    }

    /// Cardinales de 2 a 29 en una palabra. "Un", "uno" y "una" sueltos no cuentan: casi
    /// siempre son artículos.
    private static let simpleNumbers: [String: Int] = [
        "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
        "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15, "dieciseis": 16,
        "diecisiete": 17, "dieciocho": 18, "diecinueve": 19, "veinte": 20, "veintiun": 21, "veintiuno": 21,
        "veintiuna": 21, "veintidos": 22, "veintitres": 23, "veinticuatro": 24, "veinticinco": 25,
        "veintiseis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
    ]
    private static let tens: [String: Int] = [
        "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90,
    ]
    /// Unidades tras "y" ("treinta y una").
    private static let units: [String: Int] = [
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
        "ocho": 8, "nueve": 9,
    ]
    private static let hundreds: [String: Int] = [
        "cien": 100, "ciento": 100, "doscientos": 200, "doscientas": 200, "trescientos": 300, "trescientas": 300,
        "cuatrocientos": 400, "cuatrocientas": 400, "quinientos": 500, "quinientas": 500, "seiscientos": 600,
        "seiscientas": 600, "setecientos": 700, "setecientas": 700, "ochocientos": 800, "ochocientas": 800,
        "novecientos": 900, "novecientas": 900, "mil": 1_000,
    ]

    /// Valores de los números escritos con letras, en orden ("sesenta y cuatro" → 64).
    static func spelledNumbers(in words: [String]) -> [Int] {
        var values: [Int] = []
        var index = words.startIndex
        while index < words.endIndex {
            var value = 0
            var next = index
            if let hundred = hundreds[words[next]] {
                value = hundred
                next += 1
            }
            if next < words.endIndex, let ten = tens[words[next]] {
                value += ten
                next += 1
                if next + 1 < words.endIndex, words[next] == "y", let unit = units[words[next + 1]] {
                    value += unit
                    next += 2
                }
            } else if next < words.endIndex, let simple = simpleNumbers[words[next]] {
                value += simple
                next += 1
            }
            if next > index {
                values.append(value)
                index = next
            } else {
                index += 1
            }
        }
        return values
    }

    /// Identificadores camelCase de un hecho ("pushPullLegs"), en minúsculas. Los valores
    /// de una sola palabra ("biceps") no cuentan: pueden coincidir con el nombre en español.
    private static func identifiers(in value: String) -> [String] {
        value.split(separator: ",").compactMap { piece in
            let token = piece.trimmingCharacters(in: .whitespaces)
            let isCamelCase = token.allSatisfy { $0.isASCII && $0.isLetter }
                && token.first?.isLowercase == true
                && token.contains { $0.isUppercase }
            return isCamelCase ? token.lowercased() : nil
        }
    }

    /// Renglones de la respuesta de la IA: uno por oración, sin viñetas ni numeración de
    /// lista. La IA suele contestar con un solo párrafo aunque se le pidan renglones; sin
    /// partirlo, el filtro lo rechazaba siempre por largo. Un punto pegado a un dígito
    /// ("74.2") no separa; uno seguido de espacio sí (abreviaturas incluidas).
    public static func lines(fromReply reply: String) -> [String] {
        reply
            .split(whereSeparator: \.isNewline)
            .flatMap { sentences(in: withoutListMarker(String($0))) }
    }

    private static func withoutListMarker(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespaces)
        while let first = line.first, "-*•".contains(first) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        // "1. " o "2) " al inicio: la numeración no es un número del plan.
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        let rest = line.dropFirst(digits.count)
        if !digits.isEmpty, let marker = rest.first, ".)".contains(marker), rest.dropFirst().first?.isWhitespace == true {
            line = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func sentences(in line: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in line {
            if character.isWhitespace, let last = current.last, ".!?".contains(last) {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Secuencias de dígitos (con decimales) de un texto.
    static func numbers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if character.isASCII && character.isNumber {
                current.append(character)
            } else if (character == "." || character == ","), !current.isEmpty {
                current.append(".")
            } else if !current.isEmpty {
                result.append(Self.trimmed(current))
                current = ""
            }
        }
        if !current.isEmpty { result.append(Self.trimmed(current)) }
        return result
    }

    private static func trimmed(_ number: String) -> String {
        var number = number
        while number.hasSuffix(".") { number.removeLast() }
        return number
    }
}

// MARK: - Registro guardado con el plan

/// De dónde salió la explicación "Por qué tu plan es así".
public enum PlanRationaleSource: String, Codable, Sendable, Hashable {
    case ai
    case local
}

/// Lo que la personalización dejó en el plan: decisiones, explicación y bitácora.
public struct PlanPersonalizationRecord: Codable, Sendable, Equatable {
    public var decisions: [PersonalizationDecision]
    public var rationale: [String]
    public var rationaleSource: PlanRationaleSource
    public var audit: [AgentAuditRecord]

    public init(
        decisions: [PersonalizationDecision],
        rationale: [String],
        rationaleSource: PlanRationaleSource,
        audit: [AgentAuditRecord]
    ) {
        self.decisions = decisions
        self.rationale = rationale
        self.rationaleSource = rationaleSource
        self.audit = audit
    }

    public var acceptedCount: Int { decisions.filter(\.isAccepted).count }
}
