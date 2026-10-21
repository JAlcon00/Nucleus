//
//  BlockPlannerRealCatalogTests.swift
//  PRCoreTests
//
//  SCRUM-28 / SCRUM-29 sobre el catálogo REAL (678 ejercicios): N días ⇒ N sesiones,
//  el objetivo semanal por músculo se reparte (no se multiplica por ejercicio), cada
//  día tiene su propia plantilla, una sesión cabe en el tiempo del usuario, más
//  tiempo no agrega series y ningún aislamiento precede a un compuesto de su músculo.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-28/29 · Plan semanal sobre el catálogo real")
struct BlockPlannerRealCatalogTests {

    private let builder = TodayPlanBuilder()

    private func plan(days: Int, minutes: Int? = 60, goal: TrainingGoal = .hypertrophy,
                      variety: VarietyPreference = .balanced) throws -> (BlockPlanningResult, ExerciseCatalog) {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let input = BlockPlanningInput(
            goal: goal, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: days, priorities: builder.defaultPriorities(), plannedWeeks: 6,
            varietyPreference: variety, catalog: catalog.exercises, restrictions: [],
            equipmentKnownness: builder.defaultEquipmentKnownness(), sessionMinutes: minutes
        )
        return (try TodayPlanBuilder.defaultPlanner().plan(input: input), catalog)
    }

    @Test("N días ⇒ exactamente N sesiones, con título propio", arguments: Array(2...7))
    func oneSessionPerDay(days: Int) throws {
        let (result, _) = try plan(days: days)
        #expect(result.block.sessions.count == days)
        #expect(Set(result.block.sessions.map(\.title)).count == days, "Títulos repetidos: \(result.block.sessions.map(\.title))")
    }

    @Test("El objetivo semanal se reparte: la suma de la semana es el objetivo, no el objetivo por ejercicio",
          arguments: [2, 3, 4, 6])
    func weeklyVolumeEqualsTarget(days: Int) throws {
        let (result, _) = try plan(days: days, minutes: nil)
        let total = result.block.sessions.map { $0.plannedSets.count }.reduce(0, +)
        let target = result.block.muscleTargets.map(\.targetSetsPerWeek).reduce(0, +)
        #expect(total == target, "\(days) días: \(total) series en la semana contra un objetivo de \(target)")
    }

    @Test("Una sesión de 60 min cabe en 60 min según el estimador", arguments: [2, 3, 4, 6])
    func sessionFitsTheTime(days: Int) throws {
        let (result, _) = try plan(days: days, minutes: 60)
        let estimator = DurationEstimator()
        for session in result.block.sessions {
            #expect(estimator.estimate(plannedSets: session.plannedSets) <= 60 * 60, "\(session.title)")
        }
    }

    @Test("Con 180 minutos no hay más series que con 90")
    func moreTimeDoesNotAddSets() throws {
        let (ninety, _) = try plan(days: 3, minutes: 90)
        let (long, _) = try plan(days: 3, minutes: 180)
        let count = { (r: BlockPlanningResult) in r.block.sessions.map { $0.plannedSets.count }.reduce(0, +) }
        #expect(count(long) <= count(ninety))
        #expect(count(long) == count(ninety))
    }

    @Test("Con poco tiempo se recortan series pero el ancla de cada ejercicio conserva al menos una")
    func tightTimeTrimsButKeepsEachExercise() throws {
        let (roomy, _) = try plan(days: 3, minutes: nil)
        let (tight, _) = try plan(days: 3, minutes: TrainingWeek.allowedSessionMinutes.lowerBound)
        let roomySets = roomy.block.sessions.map { $0.plannedSets.count }.reduce(0, +)
        let tightSets = tight.block.sessions.map { $0.plannedSets.count }.reduce(0, +)
        #expect(tightSets < roomySets)
        for (a, b) in zip(roomy.block.sessions, tight.block.sessions) {
            #expect(Set(a.plannedSets.map(\.exerciseID)) == Set(b.plannedSets.map(\.exerciseID)),
                    "Recortar no debe quitar ejercicios, sólo series")
        }
    }

    @Test("Con 3 días y variedad equilibrada, cada día tiene su propia plantilla")
    func eachDayHasItsOwnTemplate() throws {
        let (result, _) = try plan(days: 3)
        let signatures = result.block.sessions.map { Set($0.plannedSets.map(\.exerciseID)) }
        #expect(Set(signatures).count == signatures.count, "Sesiones iguales entre sí")
    }

    @Test("Los ejercicios ancla de la semana son siempre los mismos entre bloques iguales (determinismo)")
    func deterministic() throws {
        let (a, _) = try plan(days: 4)
        let (b, _) = try plan(days: 4)
        #expect(a.block.sessions.map { $0.plannedSets.map(\.exerciseID) } == b.block.sessions.map { $0.plannedSets.map(\.exerciseID) })
    }

    @Test("Ningún aislamiento va antes de un compuesto que trabaja el mismo músculo",
          arguments: [2, 3, 4, 6])
    func isolationNeverBeforeItsCompound(days: Int) throws {
        let (result, catalog) = try plan(days: days)
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let compound: Set<ExerciseRole> = [.primaryCompound, .secondaryCompound]
        let isolation: Set<ExerciseRole> = [.accessoryIsolation, .priorityIsolation]
        for session in result.block.sessions {
            var order: [Exercise] = []
            for set in session.plannedSets {
                if let e = byID[set.exerciseID], !order.contains(where: { $0.id == e.id }) { order.append(e) }
            }
            for (i, early) in order.enumerated() where !early.defaultRoles.isDisjoint(with: isolation)
                && early.defaultRoles.isDisjoint(with: compound) {
                let muscles = Set(early.primaryMuscles.map(\.muscleGroupID))
                for late in order[(i + 1)...] where !late.defaultRoles.isDisjoint(with: compound) {
                    let involved = Set((late.primaryMuscles + late.secondaryMuscles).map(\.muscleGroupID))
                    #expect(muscles.isDisjoint(with: involved),
                            "\(session.title): '\(early.canonicalName)' va antes que '\(late.canonicalName)'")
                }
            }
        }
    }
}

@Suite("Catálogo real en español")
struct SpanishCatalogNamesTests {

    @Test("Todos los ejercicios tienen nombre en español y conservan el inglés como alias")
    func allExercisesTranslated() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        #expect(catalog.exercises.count == 678)
        // 4 nombres (p. ej. "Pushups") son iguales en ambos idiomas y quedan sin alias.
        let untranslated = catalog.exercises.filter { $0.aliases.isEmpty }
        #expect(untranslated.count <= 10, "Sin traducir: \(untranslated.map(\.canonicalName))")
    }

    @Test("Los IDs no cambian al traducir (los datos guardados siguen válidos) y la búsqueda sigue en inglés")
    func idsStableAcrossLanguages() throws {
        let raw = Data("""
        [{"id":"Barbell_Bench_Press","name":"Barbell Bench Press","force":"push","level":"intermediate",
          "mechanic":"compound","equipment":"barbell","primaryMuscles":["chest"],
          "secondaryMuscles":["triceps"],"category":"strength"}]
        """.utf8)
        let english = try ExerciseCatalogLoader.load(from: raw)
        let spanish = try ExerciseCatalogLoader.load(from: raw, spanishNames: ["Barbell_Bench_Press": "Press de banca con barra"])
        #expect(english.exercises.map(\.id) == spanish.exercises.map(\.id))
        #expect(spanish.exercises.first?.canonicalName == "Press de banca con barra")
        #expect(spanish.exercises.first?.aliases == ["Barbell Bench Press"])
        #expect(english.exercises.first?.canonicalName == "Barbell Bench Press")
    }
}
