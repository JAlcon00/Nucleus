//
//  SupersetPresentationTests.swift
//  PRCoreTests
//
//  SCRUM-224: lo que se dice de los supersets, en palabras simples y en los dos idiomas.
//  - "Por qué tu plan es así": qué va en superset y por qué (con los nombres del hecho del
//    motor); la clave viaja a la IA y su filtro no la toma por término interno.
//  - "Ajustar a mi tiempo": si sólo se juntaron ejercicios, la frase lo dice.
//  - Hoy: la nota de lo que hoy va en superset.
//  - Con el plan real y el catálogo real, "Ajustar a mi tiempo" junta pares compatibles,
//    nunca anclas, antes de bajar series, y la sesión que se va a hacer los trae.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let spanish = Locale(identifier: "es_MX")
private let english = Locale(identifier: "en_US")
private let (curl, pushdown) = (ExerciseID(), ExerciseID())
private let names = [curl: "Curl con barra", pushdown: "Extensión de tríceps"]

@Suite("SCRUM-224 · Textos de los supersets")
struct SupersetPresentationTests {

    @Test("\"Por qué tu plan es así\" dice qué va en superset y por qué, en español y en inglés")
    func rationaleLine() {
        let facts = [DecisionFact(key: "superset", value: "Curl con barra + Extensión de tríceps")]
        let es = PlanRationalePresenter(locale: spanish).lines(facts: facts, emphasis: [], substitutions: [])
        #expect(es.contains("Para que quepan en tu tiempo, haces en superset Curl con barra con Extensión de tríceps: una serie de cada uno y después descansas. No comparten músculos."))
        let en = PlanRationalePresenter(locale: english).lines(facts: facts, emphasis: [], substitutions: [])
        #expect(en.contains("To fit your time, you do Curl con barra with Extensión de tríceps as supersets: one set of each, then rest. They don't share muscles."))
        #expect(PlanRationalePresenter(locale: spanish).lines(facts: [], emphasis: [], substitutions: []).allSatisfy { !$0.contains("superset") })
    }

    @Test("La clave viaja a la IA y su filtro acepta una explicación que nombra el par")
    func factIsUserFacingAndPassesTheGuard() {
        let facts = [DecisionFact(key: "superset", value: "Curl con barra + Extensión de tríceps")]
        #expect(PlanRationaleFacts.userFacing(facts) == facts)
        let review = PlanRationaleGuard().review(["Haces el curl con barra y la extensión de tríceps alternados para ahorrar tiempo."], facts: facts)
        #expect(review == .accepted(["Haces el curl con barra y la extensión de tríceps alternados para ahorrar tiempo."]))
    }

    @Test("\"Ajustar a mi tiempo\": si sólo se juntaron ejercicios, la frase lo dice")
    func timeSentenceWhenOnlyJoined() throws {
        let pair = try #require(SupersetPair(first: curl, second: pushdown))
        let adjustment = SessionTimeAdjustment(budgetMinutes: 40, originalMinutes: 44, fit: .trimmed(removed: [], reduced: []), joined: [pair])
        #expect(SessionTimePresenter(locale: spanish).sentence(for: adjustment) { names[$0] }
            == "Para caber en 40 min haces Curl con barra con Extensión de tríceps en superset; no quitamos nada.")
        #expect(SessionTimePresenter(locale: english).sentence(for: adjustment) { names[$0] }
            == "To fit in 40 min you do Curl con barra with Extensión de tríceps as a superset; nothing was removed.")
        let plain = SessionTimeAdjustment(budgetMinutes: 40, originalMinutes: 44, fit: .trimmed(removed: [], reduced: []))
        #expect(SessionTimePresenter(locale: spanish).sentence(for: plain) { names[$0] }
            == "Ajustamos la sesión para caber en 40 min; los ejercicios principales se quedan.", "Sin pares, la frase de antes")
    }

    @Test("Hoy dice qué va en superset y por qué; sin pares no dice nada")
    func todayNote() throws {
        let work = try SetPrescription(targetRepRange: 10...12, loadUnit: .kilograms, restSeconds: 60...90, isWarmup: false)
        let sets = [curl, curl, pushdown, pushdown].map { PlannedSet(exerciseID: $0, prescription: work) }
        let paired = SessionTemplate(title: "Brazos", plannedSets: sets, supersets: [try #require(SupersetPair(first: curl, second: pushdown))])
        #expect(SupersetPresenter(locale: spanish).todayNote(for: paired) { names[$0] }
            == "Hoy va en superset Curl con barra con Extensión de tríceps: una serie de cada uno y luego descansas, para que tu sesión quepa en tu tiempo.")
        #expect(SupersetPresenter(locale: english).todayNote(for: paired) { names[$0] }
            == "Today Curl con barra with Extensión de tríceps go as a superset: one set of each, then rest, so your session fits your time.")
        #expect(SupersetPresenter(locale: spanish).todayNote(for: SessionTemplate(title: "Brazos", plannedSets: sets)) { names[$0] } == nil)
        #expect(SupersetPresenter(locale: spanish).todayNote(for: nil) { names[$0] } == nil)
    }

    @Test("Con el plan real, \"Ajustar a mi tiempo\" junta pares compatibles, nunca anclas, y nunca deja 1 serie")
    func realPlanTimeBudgetJoinsCompatiblePairs() throws {
        let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let builder = TodayPlanBuilder()
        let planner = TodayPlanBuilder.defaultPlanner()
        let profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
        )
        let generated = try builder.generate(profile: profile, catalog: catalog, planner: planner)
        var joinedSomewhere = false
        for budget in [30, 35, 40, 45, 50] {
            let plan = try builder.todayPlan(
                profile: profile, block: generated.block, explanation: generated.explanation, catalog: catalog,
                driver: TodayScreenDriver(), date: monday, timeZone: zone, timeBudget: budget, planner: planner
            )
            let template = try #require(plan.todayTemplate)
            let adjustment = try #require(plan.timeAdjustment)
            let roles = try builder.timeRoles(for: template, profile: profile, block: generated.block, catalog: catalog, planner: planner)
            for pair in adjustment.joined {
                joinedSomewhere = true
                let first = try #require(exercises[pair.first])
                let second = try #require(exercises[pair.second])
                #expect(SupersetPairing.areCompatible(first, second), "\(budget) min: \(first.canonicalName) + \(second.canonicalName)")
                #expect(!roles.anchors.contains(pair.first) && !roles.anchors.contains(pair.second), "\(budget) min: un ancla en superset")
                #expect(template.supersetPairs.contains(pair), "\(budget) min: la sesión que se hace trae el par")
            }
            let counts = Dictionary(grouping: template.plannedSets.filter { !$0.prescription.isWarmup }, by: \.exerciseID).mapValues(\.count)
            #expect(counts.values.allSatisfy { $0 >= 2 }, "\(budget) min: \(counts.values.sorted())")
        }
        #expect(joinedSomewhere, "Con poco tiempo, alguna vez tiene que juntar pares antes de bajar series")
    }
}
