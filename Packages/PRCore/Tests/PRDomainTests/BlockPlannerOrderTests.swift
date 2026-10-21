//
//  BlockPlannerOrderTests.swift
//  PRDomainTests
//
//  SCRUM-29: el planificador invoca de verdad el motor de orden y el de fatiga.
//  Compuestos antes que aislamientos, ningún aislamiento antes del compuesto que
//  necesita ese músculo fresco (tríceps/press, bíceps/remo), prioridad muscular que
//  adelanta, determinismo y explicación con la precedencia documentada.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("SCRUM-29 · Orden de ejercicios en el bloque")
struct BlockPlannerOrderTests {

    private let chestFamily = ExerciseFamilyID()
    private let backFamily = ExerciseFamilyID()
    private let tricepsFamily = ExerciseFamilyID()
    private let bicepsFamily = ExerciseFamilyID()

    private func exercise(
        _ name: String, pattern: MovementPattern, role: ExerciseRole,
        primary: MuscleGroup.ID, secondary: MuscleGroup.ID? = nil, family: ExerciseFamilyID
    ) -> Exercise {
        var fatigue: [MuscleGroup.ID: FatigueCost] = [primary: try! FatigueCost(normalized: 0.7)]
        if let secondary { fatigue[secondary] = try! FatigueCost(normalized: 0.5) }
        return Exercise(
            id: ExerciseID(),
            canonicalName: name,
            movementPattern: pattern,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: primary, activation: 1.0)],
            secondaryMuscles: secondary.map { [try! MuscleContribution(muscleGroupID: $0, activation: 0.4)] } ?? [],
            equipment: .barbell,
            jointClass: role == .primaryCompound ? .multiJoint : .singleJoint,
            stabilityDemand: role == .primaryCompound ? .high : .moderate,
            skillDemand: role == .primaryCompound ? .high : .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            localFatigue: fatigue,
            loadability: .discreteIncrements,
            defaultRoles: [role],
            substitutionFamilyID: family
        )
    }

    private var bench: Exercise { exercise("Press banca", pattern: .horizontalPress, role: .primaryCompound, primary: .chest, secondary: .triceps, family: chestFamily) }
    private var pushdown: Exercise { exercise("Extensión de tríceps", pattern: .elbowExtension, role: .accessoryIsolation, primary: .triceps, family: tricepsFamily) }
    private var row: Exercise { exercise("Remo con barra", pattern: .horizontalPull, role: .primaryCompound, primary: .back, secondary: .biceps, family: backFamily) }
    private var curl: Exercise { exercise("Curl de bíceps", pattern: .elbowFlexion, role: .accessoryIsolation, primary: .biceps, family: bicepsFamily) }

    private func plan(
        catalog: [Exercise],
        priorities: [MusclePriority],
        days: Int = 3
    ) throws -> BlockPlanningResult {
        let planner = BlockPlanner(volumeAllocator: VolumeAllocator(config: try VolumeConfig(rule: VolumeDefaults.makeRule())))
        return try planner.plan(input: BlockPlanningInput(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: days, priorities: priorities, plannedWeeks: 6,
            varietyPreference: .balanced, catalog: catalog, restrictions: [],
            equipmentKnownness: .knownAvailable([.barbell])
        ))
    }

    private func names(of session: SessionTemplate, in catalog: [Exercise]) -> [String] {
        var seen: [ExerciseID] = []
        for set in session.plannedSets where !seen.contains(set.exerciseID) { seen.append(set.exerciseID) }
        return seen.compactMap { id in catalog.first { $0.id == id }?.canonicalName }
    }

    private var normalPriorities: [MusclePriority] {
        [.chest, .triceps, .back, .biceps].map { MusclePriority(muscleGroupID: $0, priority: .normal) }
    }

    @Test("Los compuestos van antes que los aislamientos; tríceps después del press y bíceps después del remo")
    func compoundsBeforeIsolations() throws {
        let catalog = [pushdown, curl, bench, row] // orden de entrada adverso a propósito
        let result = try plan(catalog: catalog, priorities: normalPriorities)
        for session in result.block.sessions {
            let order = names(of: session, in: catalog)
            let index = { (name: String) in order.firstIndex(of: name) }
            let bench = try #require(index("Press banca")), triceps = try #require(index("Extensión de tríceps"))
            let row = try #require(index("Remo con barra")), biceps = try #require(index("Curl de bíceps"))
            #expect(bench < triceps, "El press debe ir antes que el tríceps: \(order)")
            #expect(row < biceps, "El remo debe ir antes que el bíceps: \(order)")
        }
    }

    @Test("Un músculo prioritario adelanta a otro aislamiento del mismo rol")
    func priorityMovesForward() throws {
        let priorities = [
            MusclePriority(muscleGroupID: .chest, priority: .normal),
            MusclePriority(muscleGroupID: .triceps, priority: .normal),
            MusclePriority(muscleGroupID: .back, priority: .normal),
            MusclePriority(muscleGroupID: .biceps, priority: .specialize),
        ]
        let catalog = [pushdown, curl, bench, row]
        let session = try #require(try plan(catalog: catalog, priorities: priorities).block.sessions.first)
        let order = names(of: session, in: catalog)
        #expect(try #require(order.firstIndex(of: "Curl de bíceps")) < (try #require(order.firstIndex(of: "Extensión de tríceps"))),
                "El bíceps especializado debe ir antes que el tríceps normal: \(order)")
    }

    @Test("Misma entrada, mismo orden (determinismo)")
    func deterministic() throws {
        let catalog = [bench, pushdown, row, curl]
        let a = try plan(catalog: catalog, priorities: normalPriorities)
        let b = try plan(catalog: catalog, priorities: normalPriorities)
        #expect(a.block.sessions.map { $0.plannedSets.map(\.exerciseID) } == b.block.sessions.map { $0.plannedSets.map(\.exerciseID) })
    }

    @Test("La explicación guarda el orden de cada sesión, sus razones y la precedencia")
    func explanationRecordsOrder() throws {
        let catalog = [bench, pushdown, row, curl]
        let result = try plan(catalog: catalog, priorities: normalPriorities)
        let explanation = result.explanation
        #expect(explanation.sessionOrder.count == result.block.sessions.count)
        #expect(explanation.facts.contains { $0.key == "orderPrecedence" && $0.value == SessionOrderExplanation.precedence })
        #expect(explanation.ruleReferences.contains { $0.ruleID == FatigueInterferenceDefaults.ruleID })
        for (session, order) in zip(result.block.sessions, explanation.sessionOrder) {
            var seen: [ExerciseID] = []
            for set in session.plannedSets where !seen.contains(set.exerciseID) { seen.append(set.exerciseID) }
            #expect(order.entries.map(\.exerciseID) == seen, "La explicación debe seguir el orden real de la sesión")
            #expect(order.entries.map(\.rank) == Array(1...seen.count))
            #expect(order.entries.allSatisfy { !$0.facts.isEmpty })
        }
    }
}
