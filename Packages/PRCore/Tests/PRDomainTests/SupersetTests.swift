//
//  SupersetTests.swift
//  PRDomainTests
//
//  SCRUM-224: el par en superset y lo que lo usa, sin infraestructura.
//  - Modelo: dos ejercicios distintos; una plantilla guardada sin el campo se lee igual y
//    los pares inválidos se ignoran.
//  - Estimador: un solo descanso por ronda (A → B → descanso).
//  - Compatibilidad: sin músculos en común, ni secundarios; sin músculos conocidos, nunca.
//  - Cola: se alterna A, B, A, B; el descanso va tras la ronda; dejar para después o saltar
//    uno separa el par y su pareja sigue sola.
//  - Optimizador y "Ajustar a mi tiempo": juntan pares antes de bajar series sólo si se
//    pide, nunca con un ancla ni sin músculos conocidos.
//

import Foundation
import Testing
@testable import PRDomain

private let (a, b, c, d) = (ExerciseID(), ExerciseID(), ExerciseID(), ExerciseID())

private func work(rest: Int = 60) throws -> SetPrescription {
    try SetPrescription(targetRepRange: 10...12, targetLoad: 20, loadUnit: .kilograms, restSeconds: rest...rest, isWarmup: false)
}

private func warmup() throws -> SetPrescription {
    try SetPrescription(targetRepRange: 10...10, targetLoad: 10, loadUnit: .kilograms, restSeconds: 30...30, isWarmup: true)
}

/// `counts` series de trabajo por ejercicio, en ese orden y agrupadas por ejercicio.
private func template(_ counts: [(ExerciseID, Int)], warmups: [ExerciseID: Int] = [:], pairs: [SupersetPair] = []) throws -> SessionTemplate {
    var sets: [PlannedSet] = []
    for (exercise, count) in counts {
        for _ in 0..<(warmups[exercise] ?? 0) { sets.append(PlannedSet(exerciseID: exercise, prescription: try warmup())) }
        for _ in 0..<count { sets.append(PlannedSet(exerciseID: exercise, prescription: try work())) }
    }
    return SessionTemplate(title: "Brazos", plannedSets: sets, supersets: pairs.isEmpty ? nil : pairs)
}

private func pair(_ first: ExerciseID, _ second: ExerciseID) throws -> SupersetPair {
    try #require(SupersetPair(first: first, second: second))
}

/// Las series en el orden en que la cola las va dando, hasta terminar.
private func walk(_ plan: SessionTemplate, state: ExerciseQueueState = .empty) throws -> (order: [ExerciseID], restAfter: [Bool]) {
    var sets: [SetRecord] = []
    var order: [ExerciseID] = []
    var restAfter: [Bool] = []
    while let index = WorkoutQueue.nextPlannedIndex(template: plan, sets: sets, state: state) {
        let exercise = plan.plannedSets[index].exerciseID
        order.append(exercise)
        sets.append(try SetRecord(exerciseID: exercise, performedAt: Date(), weight: 20, unit: .kilograms, reps: 10))
        let midRound = WorkoutQueue.continuesSupersetRound(after: exercise, template: plan, sets: sets, state: state)
        restAfter.append(!midRound)
    }
    return (order, restAfter)
}

@Suite("SCRUM-224 · Superset: modelo, estimador, cola y recorte")
struct SupersetTests {

    // MARK: - Modelo

    @Test("Un superset es de dos ejercicios distintos; al leer uno inválido falla")
    func pairNeedsTwoExercises() throws {
        #expect(SupersetPair(first: a, second: a) == nil)
        let valid = try pair(a, b)
        #expect(valid.partner(of: a) == b && valid.partner(of: b) == a && valid.partner(of: c) == nil)
        let decoded = try JSONDecoder().decode(SupersetPair.self, from: JSONEncoder().encode(valid))
        #expect(decoded == valid)
        let same = Data(#"{"first":"\#(a.rawValue.uuidString)","second":"\#(a.rawValue.uuidString)"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SupersetPair.self, from: same) }
    }

    @Test("Una plantilla guardada sin supersets se lee igual y sin el campo se escribe igual")
    func legacyTemplateReadsTheSame() throws {
        let plan = try template([(a, 2), (b, 2)])
        let data = try JSONEncoder().encode(plan)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["supersets"] == nil, "Sin pares no se escribe el campo")
        let decoded = try JSONDecoder().decode(SessionTemplate.self, from: data)
        #expect(decoded == plan)
        #expect(decoded.supersetPairs.isEmpty)
        let ab = try pair(a, b)
        let paired = try template([(a, 2), (b, 2)], pairs: [ab])
        #expect(try JSONDecoder().decode(SessionTemplate.self, from: JSONEncoder().encode(paired)).supersetPairs == [ab])
    }

    @Test("Los pares inválidos se ignoran: un ejercicio que no está o repetido en otro par")
    func invalidPairsAreIgnored() throws {
        let ab = try pair(a, b)
        let plan = try template([(a, 2), (b, 2), (c, 2)], pairs: [ab, pair(b, c), pair(c, d)])
        #expect(plan.supersetPairs == [ab])
        #expect(plan.superset(containing: c) == nil)
    }

    // MARK: - Estimador

    @Test("El estimador cuenta un solo descanso por ronda: la serie de A no suma su descanso")
    func estimatorOneRestPerRound() throws {
        let estimator = DurationEstimator()
        let alone = try template([(a, 3), (b, 3)])
        let paired = try template([(a, 3), (b, 3)], pairs: [pair(a, b)])
        let saved = estimator.estimate(plannedSets: alone.plannedSets) - estimator.estimate(plannedSets: paired.plannedSets, supersets: paired.supersetPairs)
        #expect(saved == 3 * 60, "3 rondas, 60 s de descanso de A cada una")
        #expect(estimator.estimate(plannedSets: paired.plannedSets) == estimator.estimate(plannedSets: alone.plannedSets),
                "Sin pasarle los pares, igual que antes")
    }

    @Test("Con series distintas hay tantas rondas como series del que menos tiene; el calentamiento no cuenta")
    func estimatorRoundsAreTheSmallerCount() throws {
        let estimator = DurationEstimator()
        let alone = try template([(a, 3), (b, 2)], warmups: [a: 1])
        let paired = try template([(a, 3), (b, 2)], warmups: [a: 1], pairs: [pair(a, b)])
        let saved = estimator.estimate(plannedSets: alone.plannedSets) - estimator.estimate(plannedSets: paired.plannedSets, supersets: paired.supersetPairs)
        #expect(saved == 2 * 60)
    }

    // MARK: - Compatibilidad

    @Test("Compatibles: sin músculos en común; sin músculos conocidos, nunca")
    func compatibility() {
        #expect(SupersetPairing.areCompatible([.biceps], [.triceps]))
        #expect(!SupersetPairing.areCompatible([.back, .biceps], [.biceps, .forearms]), "Un remo y un curl comparten bíceps")
        #expect(!SupersetPairing.areCompatible([], [.triceps]))
        #expect(!SupersetPairing.areCompatible([], []), "Antes, dos conjuntos vacíos salían compatibles")
    }

    // MARK: - Cola

    @Test("Se alterna A, B, A, B, A, B y el descanso va sólo después de cada ronda")
    func queueAlternates() throws {
        let plan = try template([(a, 3), (b, 3), (c, 2)], pairs: [pair(a, b)])
        let (order, restAfter) = try walk(plan)
        #expect(order == [a, b, a, b, a, b, c, c])
        #expect(restAfter == [false, true, false, true, false, true, true, true])
    }

    @Test("Con series distintas, el que tiene más termina solo; el calentamiento va antes de las rondas")
    func queueUnequalAndWarmup() throws {
        let plan = try template([(a, 3), (b, 2)], warmups: [a: 1], pairs: [pair(a, b)])
        let (order, restAfter) = try walk(plan)
        #expect(order == [a, a, b, a, b, a])
        #expect(restAfter == [true, false, true, false, true, true])
    }

    @Test("Si la pareja va en otro lugar de la sesión, se alterna al llegar al primero")
    func queueAlternatesWhenNotAdjacent() throws {
        let plan = try template([(a, 2), (c, 2), (b, 2)], pairs: [pair(a, b)])
        let walked = try walk(plan)
        #expect(walked.order == [a, b, a, b, c, c])
    }

    @Test("Dejar uno para después separa el par: la pareja sigue sola y él vuelve al final")
    func deferSplitsThePair() throws {
        let plan = try template([(a, 3), (b, 3), (c, 2)], pairs: [pair(a, b)])
        let state = ExerciseQueueState(deferred: [a])
        let (order, restAfter) = try walk(plan, state: state)
        #expect(order == [b, b, b, c, c, a, a, a])
        #expect(restAfter.allSatisfy { $0 }, "Separados no hay rondas: descansa tras cada serie")
        #expect(try walk(plan, state: ExerciseQueueState(deferred: [a, b])).order == [c, c, a, b, a, b, a, b],
                "Los dos para después: vuelven juntos")
    }

    @Test("Saltar uno separa el par: la pareja sigue sola, sin series de más")
    func skipSplitsThePair() throws {
        let plan = try template([(a, 3), (b, 3)], pairs: [pair(a, b)])
        #expect(try walk(plan, state: ExerciseQueueState(skipped: [b])).order == [a, a, a])
    }

    @Test("Sin supersets la cola da lo mismo que antes")
    func noSupersetsUnchanged() throws {
        let plan = try template([(a, 2), (b, 2), (c, 2)])
        #expect(try walk(plan).order == [a, a, b, b, c, c])
        #expect(try walk(plan).restAfter.allSatisfy { $0 })
    }

    // MARK: - Optimizador y "Ajustar a mi tiempo"

    private func item(_ id: ExerciseID, _ name: String, role: AssignmentRole, muscles: Set<MuscleGroup>, sets: Int = 4) -> SessionItem {
        SessionItem(id: id.rawValue, exerciseID: id, name: name, role: role, muscleGroups: muscles,
                    setCount: sets, secondsPerSet: 60, restSeconds: 90)
    }

    @Test("Si se pide, el optimizador junta pares compatibles antes de bajar series")
    func optimizerJoinsBeforeReducing() {
        let optimizer = HardTimeOptimizer()
        let items = [
            item(a, "Curl", role: .rotatable, muscles: [.biceps]),
            item(c, "Press", role: .anchor, muscles: [.chest, .triceps]),
            item(b, "Extensión", role: .rotatable, muscles: [.triceps]),
        ]
        // 3 × 510 + 60 = 1 590. Curl + extensión comparten nada… salvo que el press usa tríceps;
        // el par es curl + extensión (bíceps y tríceps): ahorra 3 × 90 = 270 → 1 320.
        let joined = optimizer.optimize(items: items, limitSeconds: 1_400, joinSupersets: true)
        #expect(joined.appliedSupersets.count == 1)
        #expect(joined.kept.map(\.setCount) == [4, 4, 4], "Juntar bastó: no se bajan series")
        #expect(joined.withinLimit && joined.estimatedSeconds == 1_320)
        let plain = optimizer.optimize(items: items, limitSeconds: 1_400)
        #expect(plain.appliedSupersets.isEmpty && plain.kept.map(\.setCount) == [4, 4, 2], "Sin pedirlo, el recorte de siempre")
    }

    @Test("El optimizador nunca junta un ancla ni ejercicios sin músculos conocidos")
    func optimizerNeverJoinsAnchorsOrUnknown() {
        let optimizer = HardTimeOptimizer()
        let anchors = [item(a, "Sentadilla", role: .anchor, muscles: [.quadriceps]), item(b, "Press", role: .anchor, muscles: [.chest])]
        #expect(optimizer.optimize(items: anchors, limitSeconds: 600, joinSupersets: true).appliedSupersets.isEmpty)
        let unknown = [item(a, "?", role: .rotatable, muscles: []), item(b, "?", role: .rotatable, muscles: [])]
        #expect(optimizer.optimize(items: unknown, limitSeconds: 600, joinSupersets: true).appliedSupersets.isEmpty)
    }

    @Test("\"Ajustar a mi tiempo\" junta el par antes de bajar series, con el mismo ID y lo dice")
    func timeFitJoinsPairs() throws {
        let fitter = SessionTimeFitter()
        let plan = try template([(a, 3), (b, 3)])
        let minutes = fitter.minutes(of: plan)
        let muscles: [ExerciseID: Set<MuscleGroup>] = [a: [.biceps], b: [.triceps]]
        let ab = try pair(a, b)
        let fitted = fitter.fit(plan, budgetMinutes: minutes - 2, roles: SessionTimeRoles(), goal: .hypertrophy, phase: .maintenance, muscles: muscles)
        #expect(fitted.template.id == plan.id)
        #expect(fitted.template.supersetPairs == [ab])
        #expect(fitted.template.plannedSets == plan.plannedSets, "Juntar bastó: ninguna serie menos")
        #expect(fitted.adjustment.joined == [ab])
        #expect(fitted.adjustment.fitsBudget)
        #expect(fitter.seconds(of: fitted.template) < fitter.seconds(of: plan), "El tiempo cuenta el superset")
        let blind = fitter.fit(plan, budgetMinutes: minutes - 2, roles: SessionTimeRoles(), goal: .hypertrophy, phase: .maintenance)
        #expect(blind.template.supersetPairs.isEmpty, "Sin músculos conocidos no se junta nada")
    }
}
