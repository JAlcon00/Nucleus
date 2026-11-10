//
//  ExplainableDecisionsTests.swift
//  PRDomainTests
//
//  SCRUM-270 (PR-I001): el registro de cada decisión visible lleva los hechos que usó el
//  motor y su regla; el mismo estado da el mismo registro (ID incluido).
//

import Foundation
import Testing
@testable import PRDomain

@Suite("SCRUM-270 · Registros de las decisiones visibles")
struct ExplainableDecisionsTests {
    private let builder = ExplainableDecisionBuilder()
    private let date = Date(timeIntervalSince1970: 1_792_000_000)
    private let squat = ExerciseID()
    private let curl = ExerciseID()
    private let raise = ExerciseID()

    private func name(_ id: ExerciseID) -> String? {
        switch id {
        case squat: return "Sentadilla"
        case curl: return "Curl"
        default: return nil
        }
    }

    private func entry(_ id: ExerciseID, rank: Int, keys: [String]) -> SessionOrderExplanation.Entry {
        SessionOrderExplanation.Entry(exerciseID: id, rank: rank, facts: keys.map { DecisionFact(key: $0, value: "x") })
    }

    private func order(reorderedByFatigue: Bool) -> SessionOrderExplanation {
        SessionOrderExplanation(
            sessionTitle: "Torso A",
            entries: [
                entry(squat, rank: 1, keys: ["exercise.order.role", "exercise.order.skillDemand"]),
                entry(curl, rank: 2, keys: ["exercise.order.musclePriority", "otra.cosa"]),
            ],
            reorderedByFatigue: reorderedByFatigue,
            residualInterference: 0
        )
    }

    // MARK: - Orden

    @Test("El orden lleva cada ejercicio con sus motivos del motor, la fatiga y las reglas del bloque")
    func sessionOrderFacts() throws {
        let rule = try EvidenceRuleReference(ruleID: EvidenceRuleID(rawValue: "ordering.fatigueInterference"), version: 1)
        let decision = try #require(builder.sessionOrder(
            order(reorderedByFatigue: true), isCustom: false, name: name, ruleReferences: [rule], date: date
        ))
        #expect(decision.topic == .sessionOrder)
        #expect(decision.record.type == .reorder)
        #expect(decision.values(ExplainableFactKey.orderEntry) == ["1|Sentadilla", "2|Curl"])
        #expect(decision.values(ExplainableFactKey.orderReason) == ["1|functionalRole", "1|technicalDemand", "2|musclePriority"],
                "Un hecho que no es motivo de orden no entra")
        #expect(decision.value(ExplainableFactKey.orderReorderedByFatigue) == "true")
        #expect(decision.value(ExplainableFactKey.orderCustom) == nil)
        #expect(decision.record.ruleReferences == [rule])
        #expect(decision.record.date == date)
    }

    @Test("Un orden elegido por la persona lo dice; sin explicación del motor no hay registro")
    func customOrder() throws {
        let decision = try #require(builder.sessionOrder(order(reorderedByFatigue: false), isCustom: true, name: name, ruleReferences: [], date: date))
        #expect(decision.value(ExplainableFactKey.orderCustom) == "true")
        #expect(builder.sessionOrder(nil, isCustom: true, name: name, ruleReferences: [], date: date) == nil)
    }

    // MARK: - Tiempo

    @Test("El recorte por tiempo lleva minutos, quitados, reducidos y pares, sin nombres inventados")
    func trimmedTimeFacts() throws {
        let pair = try #require(SupersetPair(first: squat, second: curl))
        let adjustment = SessionTimeAdjustment(
            budgetMinutes: 30, originalMinutes: 52,
            fit: .trimmed(removed: [raise], reduced: [SetReduction(exerciseID: curl, from: 3, to: 2)]),
            joined: [pair]
        )
        let decision = try #require(builder.timeFit(adjustment, name: name, date: date))
        #expect(decision.record.type == .setVolumeChange)
        #expect(decision.value(ExplainableFactKey.timeBudgetMinutes) == "30")
        #expect(decision.value(ExplainableFactKey.timeOriginalMinutes) == "52")
        #expect(decision.value(ExplainableFactKey.timeFit) == "trimmed")
        #expect(decision.values(ExplainableFactKey.timeRemoved) == [""], "Un ejercicio fuera del catálogo queda sin nombre")
        #expect(decision.values(ExplainableFactKey.timeReduced) == ["Curl"])
        #expect(decision.values(ExplainableFactKey.timeJoinedFirst) == ["Sentadilla"])
        #expect(decision.values(ExplainableFactKey.timeJoinedSecond) == ["Curl"])
        #expect(decision.value(ExplainableFactKey.timeNoExtraVolume) == "true")
    }

    @Test("Si no cabe ni recortada, el registro dice cuánto necesita; sin tiempo elegido no hay registro")
    func doesNotFitAndNone() throws {
        let adjustment = SessionTimeAdjustment(budgetMinutes: 30, originalMinutes: 70, fit: .doesNotFit(neededMinutes: 45, removed: [], reduced: []))
        let decision = try #require(builder.timeFit(adjustment, name: name, date: date))
        #expect(decision.value(ExplainableFactKey.timeFit) == "doesNotFit")
        #expect(decision.value(ExplainableFactKey.timeNeededMinutes) == "45")
        #expect(builder.timeFit(nil, name: name, date: date) == nil)
    }

    // MARK: - Sueño y gimnasio

    @Test("El día aligerado lleva el motivo y lo que cambió; sin ajuste no hay registro")
    func readinessFacts() throws {
        let decision = try #require(builder.readiness(.lighter(reason: .shortSleep, rirIncrease: 1, isolationSetReduction: 1), date: date))
        #expect(decision.record.type == .intensityChange)
        #expect(decision.value(ExplainableFactKey.readinessReason) == "shortSleep")
        #expect(decision.value(ExplainableFactKey.readinessRIRIncrease) == "1")
        #expect(decision.value(ExplainableFactKey.readinessIsolationSetReduction) == "1")
        #expect(decision.value(ExplainableFactKey.readinessLoadUnchanged) == "true")
        #expect(builder.readiness(.none, date: date) == nil)
    }

    @Test("Un registro por cada cambio del gimnasio, con la regla del sustituto")
    func gymChanges() throws {
        let rule = try EvidenceRuleReference(ruleID: SubstitutionScoringDefaults.ruleID, version: 1)
        let decisions = builder.gymChanges(
            [.replaced(original: squat, replacement: curl), .omitted(original: raise)],
            name: name, ruleReferences: [rule], date: date
        )
        #expect(decisions.count == 2)
        #expect(decisions[0].value(ExplainableFactKey.gymChange) == "replaced")
        #expect(decisions[0].value(ExplainableFactKey.gymOriginal) == "Sentadilla")
        #expect(decisions[0].value(ExplainableFactKey.gymReplacement) == "Curl")
        #expect(decisions[1].value(ExplainableFactKey.gymChange) == "omitted")
        #expect(decisions[1].value(ExplainableFactKey.gymReplacement) == nil)
        #expect(decisions.allSatisfy { $0.record.ruleReferences == [rule] })
        #expect(decisions[0].id != decisions[1].id)
    }

    // MARK: - Peso precargado

    @Test("El peso precargado dice de dónde salió: la última vez, la prescripción o sin dato",
          arguments: [
            (Double?.some(40), Double?.none, SuggestedLoadSource.lastTime, "40"),
            (nil, 42.5, .prescription, "42.5"),
            (nil, nil, SuggestedLoadSource.none, ""),
          ])
    func suggestedLoad(last: Double?, target: Double?, source: SuggestedLoadSource, weight: String) throws {
        let prescription = try SetPrescription(targetRepRange: 8...12, targetLoad: target, loadUnit: .kilograms, restSeconds: 90...120)
        let planned = PlannedSet(exerciseID: squat, prescription: prescription)
        let draft = SetCompleter().preload(for: planned, lastPerformedWeight: last)
        let decision = builder.suggestedLoad(draft: draft, exerciseName: "Sentadilla", isWarmup: false, loadIsPerMachine: true, date: date)
        #expect(decision.record.type == .loadChange)
        #expect(decision.value(ExplainableFactKey.loadSource) == source.rawValue)
        #expect((decision.value(ExplainableFactKey.loadWeight) ?? "") == weight)
        #expect(decision.value(ExplainableFactKey.loadPerMachine) == "true")
        #expect(decision.value(ExplainableFactKey.loadProgressionApplied) == "false", "Precargar no es progresar")
    }

    // MARK: - Dolor

    @Test("El dolor conserva hechos, acción y regla del motor; sin dolor no hay registro")
    func painKeepsEngineRecord() throws {
        let engine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
        let moderate = try engine.evaluate(PainFeedbackInput(level: .moderate, exerciseName: "Sentadilla"))
        let decision = try #require(builder.pain(moderate, date: date))
        #expect(decision.topic == .pain)
        #expect(decision.record.inputFacts == moderate.decisionRecord.inputFacts)
        #expect(decision.record.action == moderate.decisionRecord.action)
        #expect(decision.record.ruleReferences == moderate.decisionRecord.ruleReferences)
        #expect(decision.value(ExplainableFactKey.painSuspendsLoadProgression) == "true")

        let none = try engine.evaluate(PainFeedbackInput(level: .none, exerciseName: "Sentadilla"))
        #expect(builder.pain(none, date: date) == nil)
    }

    // MARK: - Determinismo

    @Test("Mismo estado, mismo registro con el mismo ID; otro estado, otro ID")
    func deterministic() throws {
        let adjustment = SessionTimeAdjustment(budgetMinutes: 30, originalMinutes: 52, fit: .trimmed(removed: [squat], reduced: []))
        let first = try #require(builder.timeFit(adjustment, name: name, date: date))
        let second = try #require(builder.timeFit(adjustment, name: name, date: date))
        #expect(first == second)
        let other = SessionTimeAdjustment(budgetMinutes: 45, originalMinutes: 52, fit: .trimmed(removed: [squat], reduced: []))
        #expect(try #require(builder.timeFit(other, name: name, date: date)).id != first.id)
        #expect(StableDecisionID.make(topic: .timeFit, facts: first.record.inputFacts) == first.id)
        #expect(StableDecisionID.make(topic: .readiness, facts: first.record.inputFacts) != first.id, "El tema entra en el ID")
    }
}
