//
//  PlanPersonalizationTests.swift
//  PRCoreTests
//
//  SCRUM-205 (IA-4): la IA propone, el validador decide y el motor arma. Un ajuste
//  válido se aplica, uno inválido se rechaza con su motivo, la IA caída deja el plan
//  local igual y la explicación sólo pasa si usa hechos del motor. Sin red.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let conversation = UUID(uuidString: "00000000-0000-0000-0000-000000000205") ?? UUID()

/// Personalizador de prueba: responde lo que se le diga y cuenta las llamadas.
private final class StubPersonalizer: PlanPersonalizing, @unchecked Sendable {
    private let lock = NSLock()
    private let respond: @Sendable (PlanPersonalizationPrompt) -> PlanPersonalizationProposal?
    private let explanation: [String]?
    private var proposals = 0
    private var explanations = 0
    private var lastPrompt: PlanPersonalizationPrompt?
    private var lastFacts: [DecisionFact]?

    init(
        explanation: [String]? = nil,
        respond: @escaping @Sendable (PlanPersonalizationPrompt) -> PlanPersonalizationProposal? = { _ in nil }
    ) {
        self.respond = respond
        self.explanation = explanation
    }

    var calls: Int { lock.withLock { proposals + explanations } }
    var prompt: PlanPersonalizationPrompt? { lock.withLock { lastPrompt } }
    var explainedFacts: [DecisionFact]? { lock.withLock { lastFacts } }

    func propose(_ prompt: PlanPersonalizationPrompt) async -> PlanPersonalizationProposal? {
        lock.withLock {
            proposals += 1
            lastPrompt = prompt
        }
        return respond(prompt)
    }

    func explain(facts: [DecisionFact]) async -> [String]? {
        lock.withLock {
            explanations += 1
            lastFacts = facts
        }
        return explanation
    }
}

private func profile() throws -> OnboardingProfile {
    var profile = try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
    )
    profile.aboutYou = try AboutYou(name: nil, birthYear: 1994, sex: .female, heightCentimeters: 165, weight: 60, weightUnit: .kilograms)
    return profile
}

private func context(_ profile: OnboardingProfile) -> AgentProfileContext? {
    AgentProfileContextBuilder().context(profile: profile, consent: .granted(at: now), now: now, timeZone: .gmt)
}

private struct PersonalizationFixture {
    let catalog: ExerciseCatalog
    let builder = TodayPlanBuilder()
    let planner = TodayPlanBuilder.defaultPlanner()
    let profile: OnboardingProfile
    let flow: PlanPersonalizationFlow

    init() throws {
        catalog = try ExerciseCatalogLoader.loadBundled()
        profile = try PRCoreTests.profile()
        flow = PlanPersonalizationFlow(validator: try PlanPersonalizationValidator.standard())
    }

    func base(emphasis: [MuscleGroup] = []) throws -> BlockPlanningResult {
        try builder.generate(profile: profile, catalog: catalog, planner: planner, emphasis: emphasis)
    }

    func run(
        _ personalizer: (any PlanPersonalizing)?,
        context: AgentProfileContext?,
        restrictions: [TrainingRestriction] = []
    ) async throws -> (base: BlockPlanningResult, personalized: PersonalizedPlan) {
        let base = try base()
        let builder = builder, catalog = catalog, planner = planner, profile = profile
        let personalized = try await flow.personalize(
            base: base, context: context, personalizer: personalizer, catalog: catalog.exercises,
            restrictions: restrictions, equipment: builder.defaultEquipmentKnownness(),
            conversationID: conversation, now: now,
            regenerate: { emphasis in
                try builder.generate(profile: profile, catalog: catalog, planner: planner, blockID: base.block.id, emphasis: emphasis)
            }
        )
        return (base, personalized)
    }

    func alternatives(restrictions: [TrainingRestriction] = []) throws -> [ExerciseID: [ExerciseID]] {
        try flow.validator.alternatives(
            block: try base().block, catalog: catalog.exercises, activeRestrictions: restrictions,
            equipment: builder.defaultEquipmentKnownness(), now: now
        )
    }
}

private func exerciseIDs(_ block: TrainingBlock) -> Set<ExerciseID> {
    Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) })
}

private func priority(of muscle: MuscleGroup, in block: TrainingBlock) -> PriorityTier? {
    block.priorities.first { $0.muscleGroupID == muscle }?.priority
}

// Sin @MainActor en la suite: generar planes es trabajo pesado y no debe bloquear el hilo
// principal de otros tests en paralelo. Sólo los tests del coordinador lo necesitan.
@Suite("Plan personalizado por IA (SCRUM-205)")
struct PlanPersonalizationTests {

    @Test("Énfasis válido: el motor vuelve a repartir con prioridad alta y queda auditado")
    func validEmphasisIsApplied() async throws {
        let fixture = try PersonalizationFixture()
        let stub = StubPersonalizer { _ in PlanPersonalizationProposal(emphasis: [.glutes]) }
        let (base, personalized) = try await fixture.run(stub, context: context(fixture.profile))

        #expect(priority(of: .glutes, in: base.block) == .normal)
        #expect(priority(of: .glutes, in: personalized.result.block) == .emphasize)
        #expect(personalized.result.block.id == base.block.id, "Mismo bloque, regenerado")
        #expect(personalized.record.decisions == [PersonalizationDecision(adjustment: .emphasize(.glutes), outcome: .accepted)])
        let stages = personalized.record.audit.map(\.stage)
        #expect(stages == [.inboundIntent, .actionValidation, .result])
        #expect(personalized.result.explanation.facts.contains(DecisionFact(key: "emphasizedMuscles", value: "glutes")))
    }

    @Test("Sustitución válida: cambia el ejercicio y la prescripción del motor queda intacta")
    func validSubstitutionKeepsPrescription() async throws {
        let fixture = try PersonalizationFixture()
        let alternatives = try fixture.alternatives()
        let (original, option) = try #require(alternatives.sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
            .first.flatMap { entry in entry.value.first.map { (entry.key, $0) } })
        let stub = StubPersonalizer { _ in
            PlanPersonalizationProposal(substitutions: [ProposedSubstitution(replace: original, with: option)])
        }
        let (base, personalized) = try await fixture.run(stub, context: context(fixture.profile))
        let block = personalized.result.block

        #expect(!exerciseIDs(block).contains(original))
        #expect(exerciseIDs(block).contains(option))
        for (before, after) in zip(base.block.sessions, block.sessions) {
            #expect(before.plannedSets.map(\.prescription) == after.plannedSets.map(\.prescription))
            #expect(before.plannedSets.count == after.plannedSets.count)
        }
        #expect(personalized.record.acceptedCount == 1)
    }

    @Test("Inválidos se rechazan con su motivo y no tocan el plan")
    func invalidAdjustmentsAreRejected() async throws {
        let fixture = try PersonalizationFixture()
        let base = try fixture.base()
        // Se aceptan los énfasis en pecho y espalda, y el plan se regenera con ellos. Desde
        // SCRUM-219 el énfasis puede cambiar un aislamiento por otro (pecho cubre su apertura y
        // el tope de la sesión quita el aislamiento de un músculo no prioritario, SCRUM-218), así
        // que `planned` sale de lo que está en los dos planes, en orden fijo: un Set no tiene un
        // orden estable entre procesos (antes salía uno al azar y fallaba 1 de cada 25 veces).
        let emphasized = try fixture.base(emphasis: [.chest, .back])
        let planned = try #require(exerciseIDs(base.block).intersection(exerciseIDs(emphasized.block))
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.first)
        let plannedExercise = try #require(fixture.catalog.exercises.first { $0.id == planned })
        let otherMuscle = try #require(fixture.catalog.exercises.first { candidate in
            !exerciseIDs(base.block).contains(candidate.id)
                && Set(candidate.primaryMuscles.map(\.muscleGroupID))
                    .isDisjoint(with: plannedExercise.primaryMuscles.map(\.muscleGroupID))
        })
        let notInPlan = try #require(fixture.catalog.exercises.first { !exerciseIDs(base.block).contains($0.id) })
        let stub = StubPersonalizer { _ in
            PlanPersonalizationProposal(
                emphasis: [.forearms, .chest, .chest, .back, .quadriceps],
                substitutions: [
                    ProposedSubstitution(replace: planned, with: otherMuscle.id),
                    ProposedSubstitution(replace: notInPlan.id, with: planned),
                    ProposedSubstitution(replace: planned, with: ExerciseID()),
                ]
            )
        }
        let (_, personalized) = try await fixture.run(stub, context: context(fixture.profile))
        let outcomes = personalized.record.decisions.map(\.outcome)

        #expect(outcomes == [
            .rejected(.unknownMuscle),   // antebrazo no está en las prioridades del bloque
            .accepted,                   // pecho
            .rejected(.duplicate),       // pecho otra vez
            .accepted,                   // espalda
            .rejected(.limitReached),    // máximo 2 énfasis
            .rejected(.differentMuscle),
            .rejected(.exerciseNotInPlan),
            .rejected(.unknownExercise),
        ])
        #expect(exerciseIDs(personalized.result.block).contains(planned), "Ninguna sustitución inválida se aplicó")
        #expect(exerciseIDs(personalized.result.block) == exerciseIDs(emphasized.block),
                "El plan es el del énfasis aceptado, sin ninguna sustitución")
    }

    @Test("Un sustituto prohibido por una restricción lo rechaza ActionPolicyValidator")
    func forbiddenSubstituteIsRejectedByPolicy() async throws {
        let fixture = try PersonalizationFixture()
        let alternatives = try fixture.alternatives()
        let (original, option) = try #require(alternatives.sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }
            .first.flatMap { entry in entry.value.first.map { (entry.key, $0) } })
        let restriction = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [option])
        // La restricción no toca al original: el plan base es el mismo.
        let stub = StubPersonalizer { _ in
            PlanPersonalizationProposal(substitutions: [ProposedSubstitution(replace: original, with: option)])
        }
        let (_, personalized) = try await fixture.run(stub, context: context(fixture.profile), restrictions: [restriction])

        #expect(personalized.record.decisions.map(\.outcome) == [.rejected(.rejectedByPolicy)])
        #expect(!exerciseIDs(personalized.result.block).contains(option))
        let validation = try #require(personalized.record.audit.first { $0.stage == .actionValidation })
        #expect(validation.actionName == AgentAction.replaceExercise.displayName)
        #expect(validation.ruleReference != nil, "Queda la versión de la regla que lo rechazó")
        #expect(try fixture.alternatives(restrictions: [restriction])[original]?.contains(option) != true,
                "Tampoco se le ofrece a la IA")
    }

    @Test("IA caída o respuesta inválida: el plan es exactamente el del motor y la explicación es local")
    func aiDownKeepsLocalPlan() async throws {
        let fixture = try PersonalizationFixture()
        let stub = StubPersonalizer(explanation: nil) { _ in nil }
        let (base, personalized) = try await fixture.run(stub, context: context(fixture.profile))

        #expect(personalized.result.block == base.block)
        #expect(personalized.record.decisions.isEmpty)
        #expect(personalized.record.rationaleSource == .local)
        #expect(!personalized.record.rationale.isEmpty)
    }

    @Test("Sin consentimiento no se le pregunta nada a la IA")
    func noConsentNoCall() async throws {
        let fixture = try PersonalizationFixture()
        let stub = StubPersonalizer(explanation: ["Hola"]) { _ in PlanPersonalizationProposal(emphasis: [.chest]) }
        let (base, personalized) = try await fixture.run(stub, context: nil)

        #expect(stub.calls == 0)
        #expect(personalized.result.block == base.block)
        #expect(personalized.record.rationaleSource == .local)
    }

    @Test("La explicación de la IA sólo pasa si cada número viene de los hechos")
    func explanationUsesOnlyFacts() async throws {
        let fixture = try PersonalizationFixture()
        let facts = try fixture.base().explanation.facts
        let days = try #require(facts.first { $0.key == "trainingDaysPerWeek" }?.value)
        let guardrail = PlanRationaleGuard()

        #expect(guardrail.accept(["Entrenas \(days) días para ganar músculo."], facts: facts) != nil)
        #expect(guardrail.accept(["Haz sentadilla con 80 kg."], facts: facts) == nil, "Carga inventada")
        #expect(guardrail.accept([], facts: facts) == nil)
        #expect(guardrail.accept(Array(repeating: "Línea", count: 5), facts: facts) == nil)

        let honest = StubPersonalizer(explanation: ["- Entrenas \(days) días por semana.", "Tu plan prioriza lo básico."]) { _ in .none }
        let (_, accepted) = try await fixture.run(honest, context: context(fixture.profile))
        #expect(accepted.record.rationaleSource == .ai)
        #expect(accepted.record.rationale.first == "- Entrenas \(days) días por semana.")

        let inventor = StubPersonalizer(explanation: ["Harás 999 series."]) { _ in .none }
        let (_, rejected) = try await fixture.run(inventor, context: context(fixture.profile))
        #expect(rejected.record.rationaleSource == .local)
        #expect(!rejected.record.rationale.joined().contains("999"))
    }

    @Test("La IA ve claves cortas y listas cerradas; su JSON se traduce con tolerancia")
    func promptAndReplyParsing() async throws {
        let fixture = try PersonalizationFixture()
        let stub = StubPersonalizer { _ in .none }
        _ = try await fixture.run(stub, context: context(fixture.profile))
        let prompt = try #require(stub.prompt)

        let encoded = String(decoding: try JSONEncoder().encode(prompt), as: UTF8.self)
        #expect(!encoded.contains(try #require(exerciseIDs(fixture.base().block).first).rawValue.uuidString),
                "Los IDs internos no viajan")
        #expect(prompt.exercises.allSatisfy { $0.key.hasPrefix("e") })
        let alternative = try #require(prompt.alternatives.first)
        let option = try #require(alternative.options.first)

        let reply = """
        ```json
        {"emphasis":["chest","abs"],"substitutions":[{"replace":"\(alternative.replace)","with":"\(option)"},{"replace":"zz","with":"e1"}]}
        ```
        """
        let proposal = try #require(prompt.proposal(fromReply: reply))
        #expect(proposal.emphasis == [.chest], "Músculo desconocido descartado")
        #expect(proposal.substitutions.count == 1, "Clave desconocida descartada")
        #expect(prompt.proposal(fromReply: "no sé") == nil)
    }

    @Test("Una respuesta en un solo párrafo se parte en oraciones antes del filtro")
    func paragraphIsSplitIntoSentences() throws {
        let fixture = try PersonalizationFixture()
        let facts = PlanRationaleFacts.userFacing(try fixture.base().explanation.facts)
        let days = try #require(facts.first { $0.key == "trainingDaysPerWeek" }?.value)
        let weeks = try #require(facts.first { $0.key == "plannedWeeks" }?.value)
        let sets = try #require(facts.first { $0.key == "totalWeeklySets" }?.value)
        // Así contestaba la IA real: todo en un renglón, más largo de lo que acepta el filtro.
        let paragraph = "Entrenas \(days) días por semana durante \(weeks) semanas para ganar músculo con calma. "
            + "Tu semana suma \(sets) series repartidas entre empuje, jalón y pierna para que cada grupo descanse antes de volver. "
            + "El motor de Nucleus ordenó cada sesión para que empieces por lo más exigente."
        let guardrail = PlanRationaleGuard()
        #expect(guardrail.review([paragraph], facts: facts) == .rejected(.lineTooLong), "Sin partir, el filtro lo rechaza")

        let lines = PlanRationaleGuard.lines(fromReply: paragraph)
        #expect(lines.count == 3)
        #expect(lines.first == "Entrenas \(days) días por semana durante \(weeks) semanas para ganar músculo con calma.")
        #expect(guardrail.review(lines, facts: facts) == .accepted(lines))
    }

    @Test("Renglones: viñetas, numeración de lista, decimales y signos de pregunta")
    func replyLineEdgeCases() {
        let reply = """
        1. Entrenas 4 días.
        - Pesas 74.2 kg hoy. ¿Por qué así? ¡Porque encaja!
        2) Último renglón

        """
        #expect(PlanRationaleGuard.lines(fromReply: reply) == [
            "Entrenas 4 días.", "Pesas 74.2 kg hoy.", "¿Por qué así?", "¡Porque encaja!", "Último renglón",
        ])
        #expect(PlanRationaleGuard.lines(fromReply: "   \n\n").isEmpty)
        #expect(PlanRationaleGuard.lines(fromReply: "6 días por semana.") == ["6 días por semana."], "Un número al inicio no es numeración")
    }

    @Test("El filtro dice por qué rechaza")
    func guardRejectionReasons() throws {
        let fixture = try PersonalizationFixture()
        let facts = PlanRationaleFacts.userFacing(try fixture.base().explanation.facts)
        let days = try #require(facts.first { $0.key == "trainingDaysPerWeek" }?.value)
        let guardrail = PlanRationaleGuard()
        let limit = guardrail.config.maxRationaleLineLength
        let atLimit = String(repeating: "a", count: limit)

        #expect(guardrail.review([" ", ""], facts: facts) == .rejected(.empty))
        #expect(guardrail.review(Array(repeating: "Línea.", count: guardrail.config.maxRationaleLines + 1), facts: facts) == .rejected(.tooManyLines))
        #expect(guardrail.review([atLimit + "a"], facts: facts) == .rejected(.lineTooLong))
        #expect(guardrail.review([atLimit], facts: facts) == .accepted([atLimit]), "El límite exacto pasa")
        #expect(guardrail.review(["Haz 999 series."], facts: facts) == .rejected(.unknownNumber))
        #expect(guardrail.review(["Entrenas \(days) días."], facts: facts) == .accepted(["Entrenas \(days) días."]))

        // Los números con letras se revisan igual que los dígitos.
        let written = [DecisionFact(key: "trainingDaysPerWeek", value: "6"), DecisionFact(key: "totalWeeklySets", value: "64")]
        let honest = "Entrenas seis días con sesenta y cuatro series."
        #expect(guardrail.review([honest], facts: written) == .accepted([honest]))
        #expect(guardrail.review(["Entrenas siete días."], facts: written) == .rejected(.unknownNumber))
        #expect(guardrail.review(["Harás sesenta y cinco series."], facts: written) == .rejected(.unknownNumber), "Decena y unidad juntas")
        #expect(guardrail.review(["Harás sesenta series."], facts: written) == .rejected(.unknownNumber), "La decena sola no es 64")
        #expect(guardrail.review(["Entrenas dieciséis semanas."], facts: written) == .rejected(.unknownNumber), "Compuestos con acento")
        #expect(guardrail.review(["Son ciento veinte series."], facts: written) == .rejected(.unknownNumber), "Centenas")
        #expect(guardrail.review(["Una rutina para ti."], facts: written) == .accepted(["Una rutina para ti."]), "Los artículos no son números")

        // Identificadores internos tal cual: no pasan; un nombre igual en español sí.
        let split = DecisionFact(key: "split", value: "pushPullLegs")
        #expect(guardrail.review(["Tu rutina es PushPullLegs."], facts: [split]) == .rejected(.technicalTerm))
        let muscles = DecisionFact(key: "emphasizedMuscles", value: "biceps, chest")
        #expect(guardrail.review(["Más trabajo para tus bíceps."], facts: [muscles]) == .accepted(["Más trabajo para tus bíceps."]))
    }

    @Test("A la IA sólo viajan los hechos útiles para el usuario, y sólo esos se pueden citar")
    func explanationOnlySeesUserFacingFacts() async throws {
        let fixture = try PersonalizationFixture()
        let all = try fixture.base().explanation.facts
        let shared = PlanRationaleFacts.userFacing(all)
        #expect(shared.allSatisfy { PlanRationaleFacts.userFacingKeys.contains($0.key) })
        #expect(!shared.contains { $0.key == "orderPrecedence" || $0.key == "priorityMuscles" })
        #expect(Set(shared.map(\.key)).isSuperset(of: ["goal", "phase", "plannedWeeks", "trainingDaysPerWeek", "totalWeeklySets"]))
        #expect(PlanRationaleFacts.userFacing([DecisionFact(key: "nuevoHechoInterno", value: "1")]).isEmpty, "Lista cerrada")

        let spy = StubPersonalizer(explanation: ["Tu plan encaja contigo."]) { _ in .none }
        _ = try await fixture.run(spy, context: context(fixture.profile))
        let sent = try #require(spy.explainedFacts)
        #expect(!sent.contains { $0.key == "orderPrecedence" || $0.key == "priorityMuscles" })

        // Un número que sólo está en un hecho interno ya no se puede citar.
        let anchors = try #require(all.first { $0.key == "priorityMuscles" }?.value)
        let sharedNumbers = shared.map(\.value).joined(separator: " ").split { !$0.isNumber }.map(String.init)
        try #require(!sharedNumbers.contains(anchors), "El conteo interno no coincide con un hecho visible")
        let leaker = StubPersonalizer(explanation: ["Trabajas \(anchors) músculos prioritarios."]) { _ in .none }
        let (_, leaked) = try await fixture.run(leaker, context: context(fixture.profile))
        #expect(leaked.record.rationaleSource == .local)
        #expect(leaked.rationaleFallback == .rejected(.unknownNumber))
    }

    @Test("Motivo del texto local: sin consentimiento, IA caída o filtro")
    func fallbackReasons() async throws {
        let fixture = try PersonalizationFixture()
        let noConsent = try await fixture.run(StubPersonalizer(explanation: ["Hola."]) { _ in .none }, context: nil).personalized
        #expect(noConsent.rationaleFallback == .notRequested)

        let down = try await fixture.run(StubPersonalizer(explanation: nil) { _ in nil }, context: context(fixture.profile)).personalized
        #expect(down.rationaleFallback == .unavailable)

        let long = String(repeating: "a", count: PlanRationaleGuard().config.maxRationaleLineLength + 1)
        let tooLong = try await fixture.run(StubPersonalizer(explanation: [long]) { _ in .none }, context: context(fixture.profile)).personalized
        #expect(tooLong.rationaleFallback == .rejected(.lineTooLong))
        #expect(tooLong.record.rationaleSource == .local)

        let fine = try await fixture.run(StubPersonalizer(explanation: ["Tu plan encaja contigo."]) { _ in .none }, context: context(fixture.profile)).personalized
        #expect(fine.rationaleFallback == nil)
        #expect(fine.record.rationaleSource == .ai)

        let reasons = [PlanRationaleFallback.notRequested, .unavailable] + PlanRationaleRejection.allCases.map(PlanRationaleFallback.rejected)
        #expect(Set(reasons.map { "\($0.diagnosticCode)" }).count == reasons.count, "Cada motivo deja un código distinto en el log")
    }

    @Test("El prompt de la explicación pide renglones cortos con los límites del filtro")
    func explanationPromptUsesPolicyLimits() {
        let config = PlanPersonalizationPolicyConfig.standard
        let prompt = AIPlanPersonalizer.explanationSystemPrompt(config: config)
        #expect(prompt.contains("\(config.maxRationaleLines) renglones"))
        #expect(prompt.contains("\(config.maxRationaleLineLength) caracteres"))
        #expect(prompt.contains("con dígitos"))
    }

    @MainActor
    @Test("Coordinador: guarda la personalización con el plan y la recupera al reabrir")
    func coordinatorPersistsPersonalization() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let profile = try PRCoreTests.profile()
        let stub = StubPersonalizer(explanation: nil) { _ in PlanPersonalizationProposal(emphasis: [.glutes]) }
        let coordinator = TodayPlanCoordinator(
            catalog: catalog, planStore: store, clock: { now },
            personalizer: stub, profileContext: { context($0) }
        )
        #expect(await coordinator.activate(profile: profile, userID: "u1"))
        #expect(coordinator.personalization?.acceptedCount == 1)
        #expect(priority(of: .glutes, in: try #require(coordinator.plan?.block)) == .emphasize)

        guard case .loaded(let stored, let block) = await store.loadPlan(userID: "u1") else {
            Issue.record("El plan no se guardó"); return
        }
        #expect(stored.personalization == coordinator.personalization)
        #expect(priority(of: .glutes, in: block) == .emphasize)

        let reopened = TodayPlanCoordinator(catalog: catalog, planStore: store, clock: { now })
        #expect(await reopened.restore(userID: "u1") == .restored(profile))
        #expect(reopened.personalization == stored.personalization)
    }

    @MainActor
    @Test("Coordinador sin consentimiento: plan local con explicación local y sin llamar a la IA")
    func coordinatorWithoutConsent() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let stub = StubPersonalizer(explanation: ["Hola"]) { _ in PlanPersonalizationProposal(emphasis: [.glutes]) }
        let coordinator = TodayPlanCoordinator(
            catalog: catalog, planStore: store, clock: { now }, personalizer: stub, profileContext: { _ in nil }
        )
        #expect(await coordinator.activate(profile: try PRCoreTests.profile(), userID: "u1"))
        #expect(stub.calls == 0)
        #expect(coordinator.personalization?.rationaleSource == .local)
        #expect(coordinator.personalization?.rationale.isEmpty == false)
    }

    @Test("Un plan guardado antes de SCRUM-205 se sigue leyendo (sin personalización)")
    func legacyStoredPlanDecodes() throws {
        let profile = try PRCoreTests.profile()
        let stored = StoredPlan(
            userID: "u1", profile: profile, activeBlockID: TrainingBlockID(), blockHistory: [],
            explanation: BlockExplanation(facts: [], ruleReferences: [], sessionOrder: []), updatedAt: now
        )
        let encoder = JSONEncoder()
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(stored)) as? [String: Any])
        object.removeValue(forKey: "personalization")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(StoredPlan.self, from: legacy)
        #expect(decoded.personalization == nil)
        #expect(decoded.userID == "u1")
    }
}
