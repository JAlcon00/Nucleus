//
//  MuscleCoverageTests.swift
//  PRCoreTests
//
//  SCRUM-215 (PR-B002) con el catálogo real: pantorrilla y core entran al plan en
//  mantenimiento; el core va en el día con más espacio y la pantorrilla con la pierna;
//  gana el tiempo (si no caben en la semana, "Por qué tu plan" lo dice); una restricción
//  que los deja fuera se explica como restricción; el énfasis sirve en cualquier nivel.
//  El orden de un músculo prioritario frente a otro aislamiento lo cubre
//  `BlockPlannerOrderTests`.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let maintenance: [MuscleGroup] = [.calves, .core]

private struct Engine {
    let catalog: ExerciseCatalog
    let byID: [ExerciseID: Exercise]

    init() throws {
        catalog = try ExerciseCatalogLoader.loadBundled()
        byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func plan(_ profile: OnboardingProfile) throws -> BlockPlanningResult {
        try TodayPlanBuilder().generate(
            profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner(), blockID: TrainingBlockID()
        )
    }

    /// Series de trabajo de cada ejercicio de `muscle` (su músculo principal), sesión por sesión.
    func workSets(of muscle: MuscleGroup, in result: BlockPlanningResult) -> [Int] {
        result.block.sessions.flatMap { session in
            Dictionary(grouping: session.plannedSets.filter { !$0.prescription.isWarmup }, by: \.exerciseID)
                .filter { byID[$0.key]?.primaryMuscles.first?.muscleGroupID == muscle }
                .map(\.value.count)
        }
    }

    /// Músculos principales de los ejercicios de una sesión.
    func muscles(of session: SessionTemplate) -> Set<MuscleGroup> {
        Set(session.plannedSets.compactMap { byID[$0.exerciseID]?.primaryMuscles.first?.muscleGroupID })
    }
}

private func profile(
    days: Int, minutes: Int, goal: TrainingGoal = .hypertrophy, experience: ExperienceLevel = .intermediate
) -> OnboardingProfile {
    OnboardingProfile(
        goal: goal, phase: .maintenance, experience: experience, trainingDaysPerWeek: days,
        usualSessionMinutes: minutes, varietyPreference: .balanced
    )
}

/// Valores de un hecho separados por coma ("calves, core").
private func listed(_ key: String, in result: BlockPlanningResult) -> Set<String> {
    let raw = result.explanation.facts.first { $0.key == key }?.value ?? ""
    return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
}

@Suite("SCRUM-215 · Pantorrilla y core en el plan, y prioridades en todos los niveles")
struct MuscleCoverageTests {

    @Test("Por defecto: los 8 grupos principales en normal; pantorrilla y core en mantener")
    func defaultPriorities() {
        let priorities = TodayPlanBuilder().defaultPriorities()
        let tiers = Dictionary(priorities.map { ($0.muscleGroupID, $0.priority) }, uniquingKeysWith: { first, _ in first })
        for muscle in OnboardingFlowPolicy.priorityMuscleOptions {
            #expect(tiers[muscle] == .normal, "\(muscle)")
        }
        #expect(tiers[.calves] == .maintain)
        #expect(tiers[.core] == .maintain)
        #expect(priorities.count == OnboardingFlowPolicy.priorityMuscleOptions.count + maintenance.count)
    }

    @Test("Con tiempo de sobra entran pantorrilla y core, cada ejercicio con al menos 2 series", arguments: 2...7)
    func presentWithTime(days: Int) throws {
        let engine = try Engine()
        for goal in [TrainingGoal.hypertrophy, .strength] {
            let result = try engine.plan(profile(days: days, minutes: 120, goal: goal))
            for muscle in maintenance {
                let sets = engine.workSets(of: muscle, in: result)
                #expect(!sets.isEmpty, "\(days) días, \(goal): falta \(muscle)")
                #expect(sets.allSatisfy { $0 >= 2 }, "\(days) días, \(goal), \(muscle): \(sets)")
            }
            #expect(listed("maintenanceLeftOut", in: result).isEmpty)
        }
    }

    @Test("El core va en el día con más espacio y la pantorrilla con la pierna")
    func placementBySplit() throws {
        let engine = try Engine()
        var splits: Set<TrainingSplit> = []
        for days in 2...7 {
            let result = try engine.plan(profile(days: days, minutes: 120))
            splits.insert(result.split)
            for session in result.block.sessions {
                let muscles = engine.muscles(of: session)
                switch result.split {
                case .fullBody:
                    break
                case .upperLower:
                    if muscles.contains(.core) { #expect(session.title.hasPrefix("Lower"), "\(session.title) trae core") }
                    if muscles.contains(.calves) { #expect(session.title.hasPrefix("Lower"), "\(session.title) trae pantorrilla") }
                case .pushPullLegs:
                    if muscles.contains(.core) { #expect(session.title.hasPrefix("Pull"), "\(session.title) trae core") }
                    if muscles.contains(.calves) { #expect(session.title.hasPrefix("Legs"), "\(session.title) trae pantorrilla") }
                }
            }
        }
        #expect(splits == [.fullBody, .upperLower, .pushPullLegs], "Se revisaron los tres splits")
    }

    @Test("Gana el tiempo: si pantorrilla o core no caben en la semana, la explicación lo dice")
    func timeWinsAndIsExplained() throws {
        let engine = try Engine()
        var explained: BlockPlanningResult?
        for days in 2...7 {
            for minutes in [30, 45, 60] {
                for goal in [TrainingGoal.hypertrophy, .strength] {
                    let result = try engine.plan(profile(days: days, minutes: minutes, goal: goal))
                    let leftOut = listed("maintenanceLeftOut", in: result)
                    for muscle in maintenance {
                        let present = !engine.workSets(of: muscle, in: result).isEmpty
                        #expect(present != leftOut.contains(muscle.rawValue), "\(days) días, \(minutes) min, \(goal), \(muscle)")
                    }
                    if !leftOut.isEmpty { explained = explained ?? result }
                    // Lo que pasa del tiempo es por lo protegido, nunca por pantorrilla o core.
                    let overTime = listed("sessionsOverTime", in: result)
                    for session in result.block.sessions where overTime.contains(session.title) {
                        #expect(engine.muscles(of: session).isDisjoint(with: maintenance), "\(session.title) pasa del tiempo con pantorrilla o core")
                    }
                }
            }
        }
        let result = try #require(explained, "Con 30–60 min hay semanas donde no caben")
        let lines = PlanRationalePresenter(locale: Locale(identifier: "es_MX"))
            .lines(facts: result.explanation.facts, emphasis: [], substitutions: [])
        #expect(lines.contains { $0.hasPrefix("Con tus minutos por sesión no hay espacio para") }, "\(lines)")
    }

    @Test("Una restricción que deja sin ejercicios a la pantorrilla se explica como restricción, no como falta de tiempo")
    func restrictedIsNotTime() throws {
        let engine = try Engine()
        // Restricción amplia (como la de bíceps de SCRUM-209): prohíbe todo patrón que trabaje
        // la pantorrilla. Con la de tobillo del formulario el motor no programa elevaciones y
        // pasa sus series a un ejercicio permitido que también la trabaja (sentadilla).
        let calvesPatterns = Set(engine.catalog.exercises
            .filter { $0.primaryMuscles.contains { $0.muscleGroupID == .calves } || $0.secondaryMuscles.contains { $0.muscleGroupID == .calves } }
            .map(\.movementPattern))
        var base = profile(days: 4, minutes: 120)
        base.restrictions = [TrainingRestriction(
            bodyRegion: .ankle, startDate: Date(timeIntervalSince1970: 1_792_670_400), forbiddenPatterns: calvesPatterns
        )]
        let result = try engine.plan(base)
        #expect(engine.workSets(of: .calves, in: result).isEmpty)
        #expect(listed("restrictedMuscles", in: result).contains("calves"))
        #expect(!listed("maintenanceLeftOut", in: result).contains("calves"))
        #expect(!engine.workSets(of: .core, in: result).isEmpty, "El core sigue")
    }

    @Test("El énfasis sirve en cualquier nivel: el músculo elegido recibe más series que uno normal", arguments: ExperienceLevel.allCases)
    func emphasisAtAnyLevel(level: ExperienceLevel) throws {
        var chosen = profile(days: 4, minutes: 120, experience: level)
        chosen.priorityMuscles = [.shoulders]
        let result = try Engine().plan(chosen)
        let tiers = Dictionary(result.block.priorities.map { ($0.muscleGroupID, $0.priority) }, uniquingKeysWith: { first, _ in first })
        #expect(tiers[.shoulders] == .emphasize)
        #expect(tiers[.calves] == .maintain)
        #expect(tiers[.core] == .maintain)
        let weekly = Dictionary(result.block.muscleTargets.map { ($0.muscleGroupID, $0.targetSetsPerWeek) }, uniquingKeysWith: { first, _ in first })
        let shoulders = try #require(weekly[.shoulders])
        let chest = try #require(weekly[.chest])
        let calves = try #require(weekly[.calves])
        #expect(shoulders > chest, "Énfasis: \(shoulders) series contra \(chest)")
        #expect(calves < chest, "Mantener: \(calves) series contra \(chest)")
    }
}
