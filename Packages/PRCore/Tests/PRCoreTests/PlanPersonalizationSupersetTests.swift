//
//  PlanPersonalizationSupersetTests.swift
//  PRCoreTests
//
//  SCRUM-241 (PR-E009): si la IA cambia un ejercicio que va en superset, el par se queda
//  con el sustituto cuando es compatible con su pareja (ningún músculo en común) y, si no,
//  la sustitución se rechaza con `breaksSuperset`. Nunca queda un par roto ni un hecho
//  que nombre un par que no está en el plan. Sin red.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let conversation = UUID(uuidString: "00000000-0000-0000-0000-000000000241") ?? UUID()

private func exercise(
    _ name: String, pattern: MovementPattern, primary: MuscleGroup, secondary: [MuscleGroup] = [],
    equipment: EquipmentType = .dumbbell
) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: pattern,
        primaryMuscles: [try MuscleContribution(muscleGroupID: primary, activation: 1.0)],
        secondaryMuscles: try secondary.map { try MuscleContribution(muscleGroupID: $0, activation: 0.4) },
        equipment: equipment,
        jointClass: .singleJoint,
        stabilityDemand: .low,
        skillDemand: .low,
        systemicFatigueCost: try FatigueCost(normalized: 0.2),
        loadability: .discreteIncrements,
        defaultRoles: [.accessoryIsolation],
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [pattern]).id
    )
}

/// Brazos y hombro. Los secundarios marcan quién choca con quién en un superset.
private struct Arms {
    /// A: va en superset con la extensión en polea.
    let curl: Exercise
    /// B: pareja del curl; trabaja también antebrazo.
    let pushdown: Exercise
    /// C: compatible con B, pero comparte hombro con la elevación lateral.
    let inclineCurl: Exercise
    /// D: comparte antebrazo con B.
    let hammerCurl: Exercise
    /// Compatible con B y con la elevación lateral.
    let preacherCurl: Exercise
    /// Compatible con C.
    let ropePushdown: Exercise
    /// Compatible con el curl, pero comparte hombro con C.
    let overheadExtension: Exercise
    let lateralRaise: Exercise

    init() throws {
        curl = try exercise("Curl con barra", pattern: .elbowFlexion, primary: .biceps, equipment: .barbell)
        pushdown = try exercise(
            "Extensión de tríceps en polea", pattern: .elbowExtension, primary: .triceps, secondary: [.forearms], equipment: .cable
        )
        inclineCurl = try exercise("Curl inclinado con mancuernas", pattern: .elbowFlexion, primary: .biceps, secondary: [.shoulders])
        hammerCurl = try exercise("Curl martillo", pattern: .elbowFlexion, primary: .biceps, secondary: [.forearms])
        preacherCurl = try exercise("Curl en banco Scott", pattern: .elbowFlexion, primary: .biceps)
        ropePushdown = try exercise("Extensión con cuerda", pattern: .elbowExtension, primary: .triceps, equipment: .cable)
        overheadExtension = try exercise(
            "Extensión sobre la cabeza", pattern: .elbowExtension, primary: .triceps, secondary: [.shoulders]
        )
        lateralRaise = try exercise("Elevación lateral", pattern: .shoulderAbduction, primary: .shoulders)
    }

    var catalog: [Exercise] {
        [curl, pushdown, inclineCurl, hammerCurl, preacherCurl, ropePushdown, overheadExtension, lateralRaise]
    }

    var names: [ExerciseID: String] {
        Dictionary(catalog.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
    }
}

private struct Session {
    let title: String
    let exercises: [Exercise]
    let pairs: [(Exercise, Exercise)]
}

private func block(_ sessions: [Session]) throws -> TrainingBlock {
    let work = try SetPrescription(targetRepRange: 10...12, loadUnit: .kilograms, restSeconds: 60...90)
    let templates = try sessions.map { session in
        SessionTemplate(
            title: session.title,
            plannedSets: session.exercises.flatMap { exercise in
                Array(repeating: PlannedSet(exerciseID: exercise.id, prescription: work), count: 3)
            },
            supersets: try session.pairs.map { pair in try #require(SupersetPair(first: pair.0.id, second: pair.1.id)) }
        )
    }
    let muscles = Array(Set(sessions.flatMap(\.exercises).compactMap { $0.primaryMuscles.first?.muscleGroupID }))
        .sorted { $0.rawValue < $1.rawValue }
    return try TrainingBlock(
        name: "Brazos",
        goal: .hypertrophy,
        phase: .maintenance,
        startDate: now,
        plannedWeeks: 6,
        sessions: templates,
        muscleTargets: try muscles.map { try MuscleVolumeTarget(muscleGroupID: $0, targetSetsPerWeek: 6) },
        priorities: muscles.map { MusclePriority(muscleGroupID: $0, priority: .normal) },
        progressionPolicy: .doubleProgression,
        deloadPolicy: .afterSixWeeks,
        varietyPolicy: try VarietyPolicy(percentStable: 0.65)
    )
}

/// Un solo día: curl con barra en superset con la extensión en polea, más una elevación lateral.
private func singleSession(_ arms: Arms) throws -> TrainingBlock {
    try block([Session(title: "Brazos", exercises: [arms.curl, arms.pushdown, arms.lateralRaise], pairs: [(arms.curl, arms.pushdown)])])
}

private func review(
    _ substitutions: [ProposedSubstitution], in block: TrainingBlock, arms: Arms, restrictions: [TrainingRestriction] = []
) throws -> PersonalizationReview {
    try PlanPersonalizationValidator.standard().reviewSubstitutions(
        substitutions, block: block, catalog: arms.catalog, activeRestrictions: restrictions,
        equipment: .unknown, conversationID: conversation, now: now
    )
}

private func swap(_ replace: Exercise, _ with: Exercise) -> ProposedSubstitution {
    ProposedSubstitution(replace: replace.id, with: with.id)
}

private func pairs(_ session: SessionTemplate) -> [SupersetPair] {
    session.supersetPairs
}

/// Personalizador de prueba: propone lo que se le diga y guarda los hechos que recibió.
private final class StubPersonalizer: PlanPersonalizing, @unchecked Sendable {
    private let lock = NSLock()
    private let proposal: PlanPersonalizationProposal?
    private var lastFacts: [DecisionFact]?

    init(_ proposal: PlanPersonalizationProposal?) {
        self.proposal = proposal
    }

    var explainedFacts: [DecisionFact]? { lock.withLock { lastFacts } }

    func propose(_ prompt: PlanPersonalizationPrompt) async -> PlanPersonalizationProposal? {
        proposal
    }

    func explain(facts: [DecisionFact]) async -> [String]? {
        lock.withLock { lastFacts = facts }
        return nil
    }
}

private func context() throws -> AgentProfileContext {
    var profile = try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 30, varietyPreference: .balanced
    )
    profile.aboutYou = try AboutYou(name: nil, birthYear: 1994, sex: .female, heightCentimeters: 165, weight: 60, weightUnit: .kilograms)
    return try #require(AgentProfileContextBuilder().context(profile: profile, consent: .granted(at: now), now: now, timeZone: .gmt))
}

/// Corre la personalización completa sobre `base` con un hecho `superset` como el que deja el motor.
private func personalize(
    _ base: TrainingBlock, arms: Arms, proposal: PlanPersonalizationProposal?
) async throws -> (result: PersonalizedPlan, personalizer: StubPersonalizer) {
    let names = arms.names
    let supersetFacts = base.sessions.flatMap(\.supersetPairs).map { pair in
        DecisionFact(key: "superset", value: "\(names[pair.first] ?? "") + \(names[pair.second] ?? "")")
    }
    let explanation = BlockExplanation(
        facts: [DecisionFact(key: "goal", value: "hypertrophy")] + supersetFacts + [DecisionFact(key: "trainingDaysPerWeek", value: "3")],
        ruleReferences: []
    )
    let planning = BlockPlanningResult(block: base, explanation: explanation, split: .fullBody)
    let personalizer = StubPersonalizer(proposal)
    let result = try await PlanPersonalizationFlow(validator: try PlanPersonalizationValidator.standard()).personalize(
        base: planning, context: try context(), personalizer: personalizer, catalog: arms.catalog, restrictions: [],
        equipment: .unknown, conversationID: conversation, now: now, regenerate: { _ in planning }
    )
    return (result, personalizer)
}

@Suite("SCRUM-241 · La sustitución de la IA no deshace el superset")
struct PlanPersonalizationSupersetTests {

    @Test("Un sustituto compatible con la pareja se queda con el par y la sesión sigue cabiendo igual")
    func compatibleSubstituteKeepsThePair() throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let review = try review([swap(arms.curl, arms.inclineCurl)], in: base, arms: arms)

        #expect(review.decisions.map(\.outcome) == [.accepted])
        let substituted = PlanPersonalizationApplier.substituting(review.acceptedSubstitutions, in: base)
        let session = try #require(substituted.sessions.first)
        #expect(pairs(session) == [try #require(SupersetPair(first: arms.inclineCurl.id, second: arms.pushdown.id))])
        #expect(session.supersets?.count == pairs(session).count, "Ningún par roto")
        let estimator = DurationEstimator()
        let baseSession = try #require(base.sessions.first)
        #expect(
            estimator.estimate(plannedSets: session.plannedSets, supersets: pairs(session))
                == estimator.estimate(plannedSets: baseSession.plannedSets, supersets: pairs(baseSession)),
            "El superset sigue ahorrando el mismo descanso"
        )
    }

    @Test("Un sustituto que comparte músculo con la pareja se rechaza, no cambia el plan y no se le ofrece a la IA")
    func incompatibleSubstituteIsRejected() throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let review = try review([swap(arms.curl, arms.hammerCurl)], in: base, arms: arms)

        #expect(review.decisions.map(\.outcome) == [.rejected(.breaksSuperset)])
        #expect(review.acceptedSubstitutions.isEmpty)
        let rejection = try #require(review.audit.last)
        #expect(rejection.stage == .actionValidation)
        #expect(rejection.notes == [PersonalizationRejection.breaksSuperset.rawValue])

        let alternatives = try PlanPersonalizationValidator.standard().alternatives(
            block: base, catalog: arms.catalog, activeRestrictions: [], equipment: .unknown, now: now
        )
        let offered = try #require(alternatives[arms.curl.id])
        #expect(!offered.contains(arms.hammerCurl.id), "El curl martillo rompería el par: no se ofrece")
        #expect(offered.contains(arms.inclineCurl.id))
        #expect(offered.contains(arms.preacherCurl.id))
    }

    @Test("En varias sesiones el sustituto tiene que ser compatible con su pareja en cada una")
    func everyPairInTheBlockMustStayCompatible() throws {
        let arms = try Arms()
        let base = try block([
            Session(title: "Lunes", exercises: [arms.curl, arms.pushdown], pairs: [(arms.curl, arms.pushdown)]),
            Session(title: "Miércoles", exercises: [arms.curl, arms.lateralRaise], pairs: [(arms.curl, arms.lateralRaise)]),
            Session(title: "Viernes", exercises: [arms.curl], pairs: []),
        ])

        // El curl inclinado va bien con la extensión, pero comparte hombro con la elevación.
        #expect(try review([swap(arms.curl, arms.inclineCurl)], in: base, arms: arms).decisions.map(\.outcome)
            == [.rejected(.breaksSuperset)])

        let accepted = try review([swap(arms.curl, arms.preacherCurl)], in: base, arms: arms)
        #expect(accepted.decisions.map(\.outcome) == [.accepted])
        let substituted = PlanPersonalizationApplier.substituting(accepted.acceptedSubstitutions, in: base)
        #expect(substituted.sessions.map { pairs($0).count } == [1, 1, 0])
        #expect(substituted.sessions.allSatisfy { $0.supersets?.count ?? 0 == pairs($0).count }, "Ningún par roto")
        #expect(!substituted.sessions.flatMap(\.plannedSets).contains { $0.exerciseID == arms.curl.id })
    }

    @Test("Si se cambian los dos del par, el segundo se mide contra la pareja ya cambiada")
    func secondSubstitutionUsesTheSubstitutedPartner() throws {
        let arms = try Arms()
        let base = try singleSession(arms)

        // La extensión sobre la cabeza va bien con el curl con barra, no con el inclinado.
        let clash = try review([swap(arms.curl, arms.inclineCurl), swap(arms.pushdown, arms.overheadExtension)], in: base, arms: arms)
        #expect(clash.decisions.map(\.outcome) == [.accepted, .rejected(.breaksSuperset)])

        let both = try review([swap(arms.curl, arms.inclineCurl), swap(arms.pushdown, arms.ropePushdown)], in: base, arms: arms)
        #expect(both.decisions.map(\.outcome) == [.accepted, .accepted])
        let session = try #require(PlanPersonalizationApplier.substituting(both.acceptedSubstitutions, in: base).sessions.first)
        #expect(pairs(session) == [try #require(SupersetPair(first: arms.inclineCurl.id, second: arms.ropePushdown.id))])
    }

    @Test("Prohibido por una restricción: rejectedByPolicy; si además rompe el par, gana breaksSuperset")
    func restrictionAndSupersetOrder() throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [arms.inclineCurl.id, arms.hammerCurl.id]
        )

        #expect(try review([swap(arms.curl, arms.inclineCurl)], in: base, arms: arms, restrictions: [restriction])
            .decisions.map(\.outcome) == [.rejected(.rejectedByPolicy)])
        #expect(try review([swap(arms.curl, arms.hammerCurl)], in: base, arms: arms, restrictions: [restriction])
            .decisions.map(\.outcome) == [.rejected(.breaksSuperset)])
    }

    @Test("La explicación y la nota de Hoy nombran el par con el sustituto, también lo que recibe la IA")
    func factsNameTheSubstitutedPair() async throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let (personalized, personalizer) = try await personalize(
            base, arms: arms, proposal: PlanPersonalizationProposal(substitutions: [swap(arms.curl, arms.inclineCurl)])
        )

        let expected = DecisionFact(key: "superset", value: "Curl inclinado con mancuernas + Extensión de tríceps en polea")
        let facts = personalized.result.explanation.facts
        #expect(facts.filter { $0.key == "superset" } == [expected])
        #expect(facts.map(\.key).prefix(3) == ["goal", "superset", "trainingDaysPerWeek"], "El hecho queda en su lugar")
        #expect(personalizer.explainedFacts?.filter { $0.key == "superset" } == [expected])

        let session = try #require(personalized.result.block.sessions.first)
        let names = arms.names
        #expect(SupersetPresenter(locale: Locale(identifier: "es_MX")).todayNote(for: session) { names[$0] }
            == "Hoy va en superset Curl inclinado con mancuernas con Extensión de tríceps en polea: una serie de cada uno y luego descansas, para que tu sesión quepa en tu tiempo.")
    }

    @Test("Sin sustituciones aceptadas los hechos y los pares quedan exactamente como los dejó el motor")
    func rejectedSubstitutionLeavesFactsAlone() async throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let (personalized, _) = try await personalize(
            base, arms: arms, proposal: PlanPersonalizationProposal(substitutions: [swap(arms.curl, arms.hammerCurl)])
        )

        #expect(personalized.result.block == base)
        #expect(personalized.result.explanation.facts.filter { $0.key == "superset" }
            == [DecisionFact(key: "superset", value: "Curl con barra + Extensión de tríceps en polea")])
    }

    @Test("IA caída (sin red): el plan es el del motor con sus pares intactos")
    func aiDownKeepsEnginePairs() async throws {
        let arms = try Arms()
        let base = try singleSession(arms)
        let (personalized, _) = try await personalize(base, arms: arms, proposal: nil)

        #expect(personalized.result.block == base)
        #expect(personalized.result.block.sessions.map { pairs($0) } == base.sessions.map { pairs($0) })
        #expect(personalized.record.decisions.isEmpty)
    }

    @Test("Catálogo real: cualquier alternativa ofrecida conserva los pares de cada sesión", arguments: [30, 45])
    func realCatalogAlternativesKeepPairs(minutes: Int) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        var profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: 3,
            usualSessionMinutes: minutes, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
        )
        profile.priorityMuscles = [.biceps, .triceps]
        let builder = TodayPlanBuilder()
        let base = try builder.generate(profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()).block
        let paired = Set(base.sessions.flatMap(\.supersetPairs).flatMap { [$0.first, $0.second] })
        try #require(!paired.isEmpty, "Con \(minutes) min y brazos con énfasis hay supersets")

        let alternatives = try PlanPersonalizationValidator.standard().alternatives(
            block: base, catalog: catalog.exercises, activeRestrictions: [], equipment: builder.defaultEquipmentKnownness(), now: now
        )
        for exercise in paired.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            for option in alternatives[exercise] ?? [] {
                let substituted = PlanPersonalizationApplier.substituting([ProposedSubstitution(replace: exercise, with: option)], in: base)
                #expect(substituted.sessions.map { $0.supersetPairs.count } == base.sessions.map { $0.supersetPairs.count },
                        "Cambiar \(exercise) por \(option) deshace un par")
            }
        }
    }
}
