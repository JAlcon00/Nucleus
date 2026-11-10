//
//  LocalPhraseInterpreterTests.swift
//  PRDomainTests
//
//  SCRUM-271 (PR-I002, RF-027): el intérprete local entiende las frases del gimnasio sin
//  red y, cuando pide aclarar, dice sobre qué. Nunca inventa IDs: salen del contexto. La
//  suite de SCRUM-33 sigue igual (`AgentUnderstandsTests.phraseSuite`).
//

import Foundation
import Testing
@testable import PRDomain

private let squat = ExerciseID()
private let office = GymID()
private let home = GymID()
private let loadDecision = DecisionID()
private let orderDecision = DecisionID()
private let timeDecision = DecisionID()
private let gymDecisionA = DecisionID()
private let gymDecisionB = DecisionID()

/// Dentro del entrenamiento, con la prensa como ejercicio actual.
private let inWorkout = AgentContext(
    todaySessionStarted: true,
    currentExercise: AgentExerciseContext(id: squat, equipment: .machine, name: "Prensa"),
    gyms: [AgentGymContext(id: office, name: "Oficina"), AgentGymContext(id: home, name: "Gimnasio de Casa")],
    explainableDecisions: [AgentDecisionContext(id: loadDecision, topic: .suggestedLoad)]
)

/// En Hoy, con orden, tiempo y dos cambios del gimnasio que explicar.
private let inToday = AgentContext(
    gyms: [AgentGymContext(id: office, name: "Oficina")],
    explainableDecisions: [
        AgentDecisionContext(id: orderDecision, topic: .sessionOrder),
        AgentDecisionContext(id: timeDecision, topic: .timeFit),
        AgentDecisionContext(id: gymDecisionA, topic: .gymChange),
        AgentDecisionContext(id: gymDecisionB, topic: .gymChange),
    ]
)

private let interpreter = LocalFallbackInterpreter()

private func intent(_ intent: AgentIntent) -> LocalInterpretation {
    LocalInterpretation(interpretation: .intent(intent), clarification: nil)
}

private func clarify(_ clarification: AgentClarification) -> LocalInterpretation {
    LocalInterpretation(interpretation: .needsClarification, clarification: clarification)
}

@Suite("SCRUM-271 · Intérprete local sin conexión")
struct LocalPhraseInterpreterTests {

    @Test("Tiempo con palabras y con número; poco tiempo, dos cantidades o fuera de rango piden minutos",
          arguments: [
            ("Tengo media hora", intent(.setTimeConstraint(.hard(minutes: 30)))),
            ("solo una hora", intent(.setTimeConstraint(.hard(minutes: 60)))),
            ("tengo una hora y media", intent(.setTimeConstraint(.hard(minutes: 90)))),
            ("hora y media", intent(.setTimeConstraint(.hard(minutes: 90)))),
            ("tengo 40 min", intent(.setTimeConstraint(.hard(minutes: 40)))),
            ("Tengo 2 horas", intent(.setTimeConstraint(.hard(minutes: 120)))),
            ("tengo poco tiempo", clarify(.minutes)),
            ("tengo 30 o 45 minutos", clarify(.minutes)),
            ("tengo 500 minutos", clarify(.minutes)),
          ])
    func time(text: String, expected: LocalInterpretation) {
        #expect(interpreter.analyze(text: text, context: inToday) == expected, "\"\(text)\"")
    }

    @Test("\"Está ocupada\" sin nombrar la máquina: en el entrenamiento es la del ejercicio actual; fuera pide cuál")
    func occupiedWithoutName() {
        #expect(interpreter.analyze(text: "Está ocupada", context: inWorkout)
                == intent(.equipmentUnavailable(EquipmentReference(equipmentType: .machine), .occupied)))
        #expect(interpreter.analyze(text: "está ocupada", context: inToday) == clarify(.equipment))
        #expect(interpreter.analyze(text: "estoy ocupado", context: inWorkout) == clarify(.general), "No habla de una máquina")
        #expect(interpreter.analyze(text: "no hay mancuernas", context: inWorkout)
                == intent(.equipmentUnavailable(EquipmentReference(equipmentType: .dumbbell), .doesNotExist)),
                "Con nombre de equipo manda el nombre")
    }

    @Test("\"¿Por qué?\" con tema pide el registro de ese tema",
          arguments: [
            ("¿Por qué este orden?", intent(.askWhy(orderDecision))),
            ("por que tan corta", intent(.askWhy(timeDecision))),
            ("¿Por qué quitaste ejercicios?", intent(.askWhy(timeDecision))),
            ("¿por qué cambió?", clarify(.whichDecision([
                AgentDecisionContext(id: gymDecisionA, topic: .gymChange), AgentDecisionContext(id: gymDecisionB, topic: .gymChange),
            ]))),
            ("¿Por qué este peso?", clarify(.nothingToExplain(.suggestedLoad))),
            ("¿por qué más ligero?", clarify(.nothingToExplain(.readiness))),
          ])
    func whyWithTopic(text: String, expected: LocalInterpretation) {
        #expect(interpreter.analyze(text: text, context: inToday) == expected, "\"\(text)\"")
    }

    @Test("\"¿Por qué?\" a secas: con un registro es ése; con varios pregunta cuál; sin ninguno lo dice")
    func bareWhy() {
        #expect(interpreter.analyze(text: "¿Por qué?", context: inWorkout) == intent(.askWhy(loadDecision)))
        #expect(interpreter.analyze(text: "¿por qué este peso?", context: inWorkout) == intent(.askWhy(loadDecision)))
        #expect(interpreter.analyze(text: "¿por qué?", context: inToday) == clarify(.whichDecision(inToday.explainableDecisions)))
        #expect(interpreter.analyze(text: "explícame", context: AgentContext()) == clarify(.nothingToExplain(nil)))
        #expect(interpreter.analyze(text: "porque estoy cansado", context: inToday)
                == intent(.reportFatigue(UserFatigueFeedback(severity: 3))), "\"Porque…\" sin pregunta no es \"¿por qué?\"")
    }

    @Test("Cambiar de ejercicio: en el entrenamiento, el actual; fuera pide entrar al entrenamiento")
    func swap() {
        #expect(interpreter.analyze(text: "Cámbiame este ejercicio", context: inWorkout) == intent(.requestExerciseSwap(squat)))
        #expect(interpreter.analyze(text: "quiero otro ejercicio", context: inWorkout) == intent(.requestExerciseSwap(squat)))
        #expect(interpreter.analyze(text: "cámbiame este ejercicio", context: inToday) == clarify(.exerciseSwapNeedsWorkout))
    }

    @Test("Gimnasio por su nombre, sin mayúsculas ni acentos; un nombre que no existe pide cuál y nunca se inventa")
    func gym() {
        #expect(interpreter.analyze(text: "Estoy en OFICINA", context: inWorkout) == intent(.changeGym(office)))
        #expect(interpreter.analyze(text: "cambia a gimnasio de casa", context: inWorkout) == intent(.changeGym(home)))
        #expect(interpreter.analyze(text: "cambia de gimnasio a Centro", context: inWorkout) == clarify(.whichGym(inWorkout.gyms)))
        #expect(interpreter.analyze(text: "cambiar de gym", context: AgentContext()) == clarify(.whichGym([])))
        #expect(interpreter.analyze(text: "estoy en déficit", context: inWorkout) == intent(.changePhase(.deficit)),
                "\"Estoy en\" con algo que no es un gimnasio no cambia de gimnasio")
    }

    @Test("Dolor con nivel y zona; sin nivel pregunta cuánto",
          arguments: [
            ("Me duele un poco el hombro", intent(.reportPain(PainReport(level: .mild, bodyRegion: .shoulder)))),
            ("me duele mucho la rodilla izquierda", intent(.reportPain(PainReport(level: .high, bodyRegion: .knee, side: .left)))),
            ("tengo una molestia moderada en la espalda baja", intent(.reportPain(PainReport(level: .moderate, bodyRegion: .lumbar)))),
            ("no me duele mucho el codo", intent(.reportPain(PainReport(level: .mild, bodyRegion: .elbow)))),
            ("me duele", clarify(.painLevel(region: nil))),
            ("me duele el pie", clarify(.painLevel(region: .foot))),
            ("me duele la pierna", clarify(.painLevel(region: nil))),
          ])
    func pain(text: String, expected: LocalInterpretation) {
        #expect(interpreter.analyze(text: text, context: inWorkout) == expected, "\"\(text)\"")
    }

    @Test("Fatiga con la tabla fija de 1 a 5",
          arguments: [
            ("estoy un poco cansado", 2), ("estoy cansada", 3), ("Estoy muy cansado", 4), ("ando agotado", 4), ("estoy exhausto", 5),
          ])
    func fatigue(text: String, severity: Int) {
        #expect(interpreter.analyze(text: text, context: inToday) == intent(.reportFatigue(UserFatigueFeedback(severity: severity))))
        #expect(UserFatigueFeedback.validSeverity(severity))
    }

    @Test("Objetivo y fase con sinónimos",
          arguments: [
            ("quiero ganar fuerza", intent(.changeGoal(.strength))),
            ("quiero ganar músculo", intent(.changeGoal(.hypertrophy))),
            ("estoy en definición", intent(.changePhase(.deficit))),
            ("ya estoy en mantenimiento", intent(.changePhase(.maintenance))),
            ("hipertrofia en déficit", clarify(.oneThingAtATime)),
          ])
    func goalAndPhase(text: String, expected: LocalInterpretation) {
        #expect(interpreter.analyze(text: text, context: AgentContext()) == expected, "\"\(text)\"")
    }

    @Test("Dos pedidos en un mensaje, texto vacío o sólo emojis piden aclarar sin ejecutar nada",
          arguments: [
            ("tengo 30 min y me duele el hombro", clarify(.oneThingAtATime)),
            ("la prensa está ocupada y tengo media hora", clarify(.oneThingAtATime)),
            ("", clarify(.general)),
            ("   ", clarify(.general)),
            ("💪🔥", clarify(.general)),
          ])
    func ambiguous(text: String, expected: LocalInterpretation) {
        #expect(interpreter.analyze(text: text, context: inWorkout) == expected, "\"\(text)\"")
    }

    @Test("Preguntar la causa del dolor es pedir un diagnóstico y no se responde")
    func causeOfPainIsDiagnosis() async throws {
        let gateway = AgentGateway(transport: nil, timing: try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 0, backoffSeconds: 0))
        #expect(await gateway.interpret(text: "¿Por qué me duele el hombro?", context: inWorkout) == .declinesDiagnosis)
        #expect(await gateway.interpret(text: "¿Por qué esta recomendación?", context: AgentContext(
            explainableDecisions: [AgentDecisionContext(id: loadDecision, topic: .pain)]
        )) == .intent(.askWhy(loadDecision)))
    }

    @Test("Integración sin transporte (Release): \"tengo media hora\" llega al comando con 30 min por la política real")
    func releasePipeline() async throws {
        let gateway = AgentGateway(transport: nil, timing: try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 0, backoffSeconds: 0))
        let reply = await gateway.interpretReply(text: "Tengo media hora", context: AgentContext())
        #expect(reply.fallback == .noBackend)
        guard case .intent(let understood) = reply.value else {
            Issue.record("Debía entender el tiempo")
            return
        }
        let writer = try AgentActionWriter(validator: ActionPolicyValidator(config: ActionPolicyConfig(rule: ActionPolicyDefaults.makeRule())))
        let result = try writer.execute(intent: understood, context: ActionPolicyContext())
        guard case .execute(let command, _, _) = result.decision else {
            Issue.record("Lo del día no pide confirmación")
            return
        }
        #expect(command == .recomputeSession(timeConstraint: .hard(minutes: 30)))
    }

    @Test("El vocabulario está versionado y el texto se normaliza sin acentos ni signos")
    func vocabulary() {
        #expect(LocalPhraseVocabulary.version == 1)
        #expect(LocalPhraseVocabulary.normalize("  ¿Por QUÉ   está ocupada?! ") == "por que esta ocupada")
    }
}
