//
//  SupersetCompositionTests.swift
//  PRCoreTests
//
//  SCRUM-224 sobre el catálogo REAL: si una sesión no cabe en el tiempo, el motor junta
//  pares compatibles en superset antes de bajar series (paso 2 del recorte de SCRUM-218).
//  En cada par: sin músculos en común (ni secundarios), nunca un ancla compuesta, nunca 1
//  serie, y sólo cuando hace falta (sin el par la sesión no cabía). Con tiempo de sobra no
//  hay supersets.
//  Desde SCRUM-227 el techo de tiempo ya baja el volumen antes de componer, así que casi
//  siempre cabe; el superset aparece cuando lo protegido (anclas compuestas y músculos con
//  énfasis) no cabe. Por eso la muestra incluye perfiles con músculos enfatizados.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-224 · Supersets en la composición, catálogo real")
struct SupersetCompositionTests {

    private let builder = TodayPlanBuilder()

    private func plan(
        days: Int, minutes: Int?, goal: TrainingGoal, emphasis: [MuscleGroup] = [], experience: ExperienceLevel = .intermediate
    ) throws -> (result: BlockPlanningResult, input: BlockPlanningInput, catalog: [ExerciseID: Exercise]) {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let priorities = builder.defaultPriorities().map { priority in
            emphasis.contains(priority.muscleGroupID)
                ? MusclePriority(muscleGroupID: priority.muscleGroupID, priority: .emphasize) : priority
        }
        let input = BlockPlanningInput(
            goal: goal, phase: .maintenance, experience: experience,
            trainingDaysPerWeek: days, priorities: priorities, plannedWeeks: 6,
            varietyPreference: .balanced, catalog: catalog.exercises, restrictions: [],
            equipmentKnownness: builder.defaultEquipmentKnownness(), sessionMinutes: minutes
        )
        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (try TodayPlanBuilder.defaultPlanner().plan(input: input), input, exercises)
    }

    private struct Profile: CustomStringConvertible {
        let days: Int
        let minutes: Int
        let goal: TrainingGoal
        let emphasis: [MuscleGroup]
        var description: String { "\(days) días, \(minutes) min, \(goal.rawValue), énfasis \(emphasis.map(\.rawValue))" }
    }

    /// Sesiones cortas, sin énfasis y con dos músculos enfatizados (los que no se recortan).
    private static let shortSessions: [Profile] = [2, 3, 4, 5].flatMap { days in
        [30, 45].flatMap { minutes in
            [TrainingGoal.hypertrophy, .strength].flatMap { goal in
                [[], [MuscleGroup.biceps, .triceps], [.shoulders, .calves]].map {
                    Profile(days: days, minutes: minutes, goal: goal, emphasis: $0)
                }
            }
        }
    }

    @Test("Cada superset junta dos ejercicios sin músculos en común y nunca un ancla compuesta")
    func pairsAreCompatibleAndNeverACompoundAnchor() throws {
        var pairsSeen = 0
        for profile in Self.shortSessions {
            let (result, input, catalog) = try plan(days: profile.days, minutes: profile.minutes, goal: profile.goal, emphasis: profile.emphasis)
            let anchors = TodayPlanBuilder.defaultPlanner().anchorExercises(input: input)
            for session in result.block.sessions {
                for pair in session.supersetPairs {
                    pairsSeen += 1
                    let first = try #require(catalog[pair.first])
                    let second = try #require(catalog[pair.second])
                    #expect(SupersetPairing.areCompatible(first, second), "\(profile) \(session.title): \(first.canonicalName) + \(second.canonicalName) comparten músculos")
                    for exercise in [first, second] {
                        #expect(!(anchors.contains(exercise.id) && exercise.jointClass == .multiJoint),
                                "\(profile) \(session.title): \(exercise.canonicalName) es ancla compuesta")
                    }
                }
                // Nunca 1 serie de trabajo, con o sin superset (SCRUM-218).
                let counts = Dictionary(grouping: session.plannedSets.filter { !$0.prescription.isWarmup }, by: \.exerciseID).mapValues(\.count)
                #expect(counts.values.allSatisfy { $0 >= 2 }, "\(profile) \(session.title): \(counts.values.sorted())")
            }
        }
        #expect(pairsSeen > 0, "Con 30 y 45 min alguna sesión tiene que juntar pares: si no, el paso nuevo no hace nada")
    }

    @Test("Sólo se junta cuando hace falta: sin cualquiera de sus pares, la sesión no cabría")
    func pairsOnlyWhenNeeded() throws {
        let estimator = DurationEstimator()
        for profile in Self.shortSessions {
            let (result, _, _) = try plan(days: profile.days, minutes: profile.minutes, goal: profile.goal, emphasis: profile.emphasis)
            for session in result.block.sessions where !session.supersetPairs.isEmpty {
                let limit = profile.minutes * 60
                let pairs = session.supersetPairs
                guard estimator.estimate(plannedSets: session.plannedSets, supersets: pairs) <= limit else {
                    continue // Lo protegido no cupo ni así: todos los pares ayudan.
                }
                for pair in pairs {
                    let without = estimator.estimate(plannedSets: session.plannedSets, supersets: pairs.filter { $0 != pair })
                    #expect(without > limit, "\(profile) \(session.title): un par no hacía falta (\(without) s sin él, límite \(limit) s)")
                }
            }
        }
    }

    @Test("Con tiempo de sobra no hay supersets", arguments: [2, 3, 4])
    func noSupersetsWithPlentyOfTime(days: Int) throws {
        for goal in [TrainingGoal.hypertrophy, .strength] {
            let (result, _, _) = try plan(days: days, minutes: 120, goal: goal)
            #expect(result.block.sessions.allSatisfy { $0.supersetPairs.isEmpty }, "\(days) días, \(goal), 120 min")
        }
    }

    @Test("Sin minutos elegidos (sin componer) no hay supersets")
    func noSupersetsWithoutMinutes() throws {
        let (result, _, _) = try plan(days: 3, minutes: nil, goal: .hypertrophy)
        #expect(result.block.sessions.allSatisfy { $0.supersets == nil })
    }

    @Test("Cada par queda junto en la sesión y la explicación lo dice con los nombres")
    func pairIsAdjacentAndExplained() throws {
        var checked = false
        for profile in Self.shortSessions {
            let (result, _, catalog) = try plan(days: profile.days, minutes: profile.minutes, goal: profile.goal, emphasis: profile.emphasis)
            let facts = result.explanation.facts.filter { $0.key == "superset" }.map(\.value)
            for session in result.block.sessions {
                let order = WorkoutQueue.exerciseOrder(of: session)
                for pair in session.supersetPairs {
                    checked = true
                    let firstIndex = try #require(order.firstIndex(of: pair.first))
                    #expect(order.indices.contains(firstIndex + 1) && order[firstIndex + 1] == pair.second,
                            "\(profile) \(session.title): el segundo del par no va junto al primero")
                    let names = [pair.first, pair.second].compactMap { catalog[$0]?.canonicalName }.joined(separator: " + ")
                    #expect(facts.contains(names), "Falta el hecho \"\(names)\" en la explicación")
                }
            }
        }
        #expect(checked)
    }
}
