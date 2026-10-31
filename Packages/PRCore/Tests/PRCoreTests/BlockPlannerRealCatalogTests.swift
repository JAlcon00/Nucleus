//
//  BlockPlannerRealCatalogTests.swift
//  PRCoreTests
//
//  SCRUM-28 / SCRUM-29 sobre el catálogo REAL (678 ejercicios): N días ⇒ N sesiones,
//  el objetivo semanal por músculo se reparte (no se multiplica por ejercicio), cada
//  día tiene su propia plantilla, una sesión cabe en el tiempo del usuario y ningún
//  aislamiento precede a un compuesto de su músculo.
//  SCRUM-227 (ADR-0004) cambió a propósito `moreTimeDoesNotAddSets`: el volumen lo marca la
//  experiencia dentro del rango y el tiempo sólo lo limita. Ahora es
//  `moreTimeNeverExceedsTierMax` (nunca se pasa del máximo), más "con 90 min, al menos lo de
//  60" y "el novato sigue en el mínimo".
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-28/29 · Plan semanal sobre el catálogo real")
struct BlockPlannerRealCatalogTests {

    private let builder = TodayPlanBuilder()

    private func plan(days: Int, minutes: Int? = 60, goal: TrainingGoal = .hypertrophy,
                      variety: VarietyPreference = .balanced,
                      experience: ExperienceLevel = .intermediate,
                      planner: BlockPlanner = TodayPlanBuilder.defaultPlanner()) throws -> (BlockPlanningResult, ExerciseCatalog) {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let input = BlockPlanningInput(
            goal: goal, phase: .maintenance, experience: experience,
            trainingDaysPerWeek: days, priorities: builder.defaultPriorities(), plannedWeeks: 6,
            varietyPreference: variety, catalog: catalog.exercises, restrictions: [],
            equipmentKnownness: builder.defaultEquipmentKnownness(), sessionMinutes: minutes
        )
        return (try planner.plan(input: input), catalog)
    }

    /// Volumen fijo en el mínimo del rango para cualquier experiencia (como antes de
    /// SCRUM-227). Las pruebas del recorte de SCRUM-218 comparan un plan sin límite de tiempo
    /// con otro con poco tiempo: para medir sólo lo que recorta la sesión, los dos deben tener
    /// el mismo volumen. Con SCRUM-227 el volumen ya depende del tiempo (el techo), así que se
    /// fija aquí; la elección del volumen se prueba aparte (`noviceUnchangedOthersMore`, techo).
    private func fixedVolumePlanner() throws -> BlockPlanner {
        var parameters = try VolumeDefaults.makeRule().parameters
        for experience in ExperienceLevel.allCases { parameters[VolumeConfigKeys.positionKey(for: experience)] = 0 }
        let rule = try EvidenceRule(
            id: VolumeDefaults.ruleID, name: "Volumen fijo en el mínimo", category: .volume,
            confidence: .emerging, version: 2, parameters: parameters
        )
        return BlockPlanner(volumeAllocator: VolumeAllocator(config: try VolumeConfig(rule: rule)))
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

    /// Series de trabajo de la semana.
    private func weeklySets(_ result: BlockPlanningResult) -> Int {
        result.block.sessions.map { $0.plannedSets.filter { !$0.prescription.isWarmup }.count }.reduce(0, +)
    }

    @Test("SCRUM-227: con cualquier tiempo, ningún músculo pasa del máximo de su rango ni la semana del objetivo",
          arguments: ExperienceLevel.allCases)
    func moreTimeNeverExceedsTierMax(experience: ExperienceLevel) throws {
        let config = try VolumeConfig(rule: VolumeDefaults.makeRule())
        let tiers = Dictionary(builder.defaultPriorities().map { ($0.muscleGroupID, $0.priority) }, uniquingKeysWith: { first, _ in first })
        for days in [2, 3, 4, 6] {
            for minutes in [90, 180] {
                let (result, _) = try plan(days: days, minutes: minutes, experience: experience)
                for target in result.block.muscleTargets {
                    let tier = try #require(tiers[target.muscleGroupID])
                    #expect(target.targetSetsPerWeek <= config.range(for: tier).upperBound,
                            "\(experience), \(days) días, \(minutes) min, \(target.muscleGroupID)")
                }
                let target = result.block.muscleTargets.map(\.targetSetsPerWeek).reduce(0, +)
                #expect(weeklySets(result) <= target, "\(experience), \(days) días, \(minutes) min")
            }
            // Más tiempo nunca da menos; lo que sube lo frena el máximo del rango (arriba).
            let ninety = weeklySets(try plan(days: days, minutes: 90, experience: experience).0)
            let long = weeklySets(try plan(days: days, minutes: 180, experience: experience).0)
            #expect(long >= ninety, "\(experience), \(days) días: 180 min dio \(long) < 90 min \(ninety)")
        }
    }

    @Test("SCRUM-227: con 90 min nunca hay menos series por semana que con 60",
          arguments: ExperienceLevel.allCases)
    func ninetyNeverGivesLessThanSixty(experience: ExperienceLevel) throws {
        for goal in [TrainingGoal.hypertrophy, .strength] {
            for days in 2...6 {
                let sixty = weeklySets(try plan(days: days, minutes: 60, goal: goal, experience: experience).0)
                let ninety = weeklySets(try plan(days: days, minutes: 90, goal: goal, experience: experience).0)
                #expect(ninety >= sixty, "\(goal), \(experience), \(days) días: 90 min \(ninety) < 60 min \(sixty)")
            }
        }
    }

    @Test("SCRUM-227: el novato sigue en el mínimo del rango; intermedio y avanzado reciben más si el tiempo alcanza")
    func noviceUnchangedOthersMore() throws {
        let config = try VolumeConfig(rule: VolumeDefaults.makeRule())
        let (novice, _) = try plan(days: 4, minutes: nil, experience: .novice)
        let tiers = Dictionary(builder.defaultPriorities().map { ($0.muscleGroupID, $0.priority) }, uniquingKeysWith: { first, _ in first })
        for target in novice.block.muscleTargets {
            let tier = try #require(tiers[target.muscleGroupID])
            #expect(target.targetSetsPerWeek == config.range(for: tier).lowerBound, "\(target.muscleGroupID)")
        }
        let (intermediate, _) = try plan(days: 4, minutes: nil, experience: .intermediate)
        let (advanced, _) = try plan(days: 4, minutes: nil, experience: .advanced)
        #expect(weeklySets(novice) == 72)
        #expect(weeklySets(intermediate) == 90)
        #expect(weeklySets(advanced) == 108)
    }

    /// SCRUM-218 cambió esta prueba a propósito. Antes decía "recortar no quita ejercicios,
    /// sólo series", y por eso quedaban 8 ejercicios de 1 serie. Ahora, con poco tiempo,
    /// primero salen los aislamientos no protegidos, ningún ejercicio queda con menos de 2
    /// series y las anclas compuestas nunca se quitan.
    @Test("Con poco tiempo salen primero los aislamientos, nunca queda 1 serie y las anclas compuestas se quedan")
    func tightTimeDropsIsolationsKeepsCompoundAnchors() throws {
        let planner = try fixedVolumePlanner()
        let (roomy, catalog) = try plan(days: 3, minutes: nil, planner: planner)
        let (tight, _) = try plan(days: 3, minutes: TrainingWeek.allowedSessionMinutes.lowerBound, planner: planner)
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let anchors = try anchorExercises(days: 3)
        let roomySets = roomy.block.sessions.map { $0.plannedSets.count }.reduce(0, +)
        let tightSets = tight.block.sessions.map { $0.plannedSets.count }.reduce(0, +)
        #expect(tightSets < roomySets)
        for (a, b) in zip(roomy.block.sessions, tight.block.sessions) {
            let compoundAnchors = Set(a.plannedSets.map(\.exerciseID)).filter { anchors.contains($0) && byID[$0]?.jointClass == .multiJoint }
            #expect(compoundAnchors.isSubset(of: Set(b.plannedSets.map(\.exerciseID))), "\(b.title): se quitó un ancla compuesta")
            let counts = Dictionary(grouping: b.plannedSets, by: \.exerciseID).mapValues(\.count)
            #expect(counts.values.allSatisfy { $0 >= 2 }, "\(b.title): \(counts.values.sorted())")
        }
    }

    @Test("SCRUM-218: el número de ejercicios cae en el rango por duración y nunca queda 1 serie", arguments: [30, 45, 60, 90])
    func exercisesWithinRange(minutes: Int) throws {
        let range = SessionCompositionRule.standard.exerciseRange(forMinutes: minutes)
        for days in 2...6 {
            let (result, _) = try plan(days: days, minutes: minutes)
            let flagged = result.explanation.facts.first { $0.key == "sessionsOverRange" }?.value ?? ""
            for session in result.block.sessions {
                let counts = Dictionary(grouping: session.plannedSets, by: \.exerciseID).mapValues(\.count)
                #expect(counts.count <= range.upperBound || flagged.contains(session.title),
                        "\(days) días, \(minutes) min, \(session.title): \(counts.count) ejercicios sin aviso")
                #expect(counts.values.allSatisfy { $0 >= 2 }, "\(days) días, \(minutes) min, \(session.title): \(counts.values.sorted())")
            }
        }
    }

    @Test("SCRUM-218: con objetivo fuerza y 60 min, las anclas compuestas conservan al menos 3 series y se recortan accesorios")
    func strengthAnchorsKeepThreeSets() throws {
        let planner = try fixedVolumePlanner()
        let (roomy, catalog) = try plan(days: 3, minutes: nil, goal: .strength, planner: planner)
        let (sixty, _) = try plan(days: 3, minutes: 60, goal: .strength, planner: planner)
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let anchors = try anchorExercises(days: 3, goal: .strength)
        for (a, b) in zip(roomy.block.sessions, sixty.block.sessions) {
            let before = Dictionary(grouping: a.plannedSets, by: \.exerciseID).mapValues(\.count)
            let after = Dictionary(grouping: b.plannedSets, by: \.exerciseID).mapValues(\.count)
            for (id, sets) in after where anchors.contains(id) && byID[id]?.jointClass == .multiJoint {
                #expect(sets >= min(3, before[id] ?? sets), "\(b.title): ancla con \(sets) series")
            }
            #expect(after.values.reduce(0, +) <= before.values.reduce(0, +))
        }
        #expect(sixty.block.sessions.map(\.plannedSets.count).reduce(0, +) < roomy.block.sessions.map(\.plannedSets.count).reduce(0, +))
    }

    @Test("SCRUM-218: si lo protegido pasa del tope, la explicación lo dice en palabras simples")
    func overRangeIsExplained() throws {
        let (result, _) = try plan(days: 2, minutes: 30)
        let facts = result.explanation.facts
        #expect(facts.contains { $0.key == "sessionsOverRange" })
        let lines = PlanRationalePresenter(locale: Locale(identifier: "es")).lines(facts: PlanRationaleFacts.userFacing(facts), emphasis: [], substitutions: [])
        #expect(lines.contains("En algunas sesiones dejamos más ejercicios de lo habitual para tu tiempo: los básicos no se quitan."))
    }

    private func anchorExercises(days: Int, goal: TrainingGoal = .hypertrophy) throws -> Set<ExerciseID> {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let input = BlockPlanningInput(
            goal: goal, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: days, priorities: builder.defaultPriorities(), plannedWeeks: 6,
            varietyPreference: .balanced, catalog: catalog.exercises, restrictions: [],
            equipmentKnownness: builder.defaultEquipmentKnownness()
        )
        return TodayPlanBuilder.defaultPlanner().anchorExercises(input: input)
    }

    /// SCRUM-219: los ejercicios de un músculo cubren sus slots (pecho: plano, inclinado,
    /// apertura) antes de repetir uno, en la asignación y en la semana. Sin límite de tiempo: la
    /// composición por minutos puede quitar aislamientos (SCRUM-218).
    @Test("SCRUM-219: cada músculo cubre sus slots antes de repetir uno, en la asignación y en la semana",
          arguments: VarietyPreference.allCases)
    func slotsCoveredBeforeRepeating(variety: VarietyPreference) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rule = ExerciseSelectionRule.standard
        let equipment = builder.defaultEquipmentKnownness()
        let muscles = builder.defaultPriorities().map(\.muscleGroupID)
        /// Slots del músculo que tienen algún ejercicio de referencia con el equipo por defecto.
        func available(_ muscle: MuscleGroup) -> Set<ExerciseSlot> {
            Set(catalog.exercises.filter { exercise in
                guard exercise.staple?.muscle == muscle, case .knownAvailable(let owned) = equipment else { return false }
                return owned.contains(exercise.equipment)
            }.compactMap { rule.slot(of: $0, for: muscle) })
        }
        for goal in [TrainingGoal.strength, .hypertrophy] {
            for experience in [ExperienceLevel.novice, .intermediate, .advanced] {
                let profile = ExerciseSelectionProfile(goal: goal, experience: experience, phase: .maintenance)
                for muscle in muscles {
                    let assignment = try ExerciseAssigner().assign(input: ExerciseAssignmentInput(
                        muscleGroupID: muscle, catalog: catalog.exercises, varietyPreference: variety,
                        restrictions: [], equipmentKnownness: equipment, selectionProfile: profile
                    ))
                    let slots = assignment.assignments.compactMap { byID[$0.exercise].flatMap { rule.slot(of: $0, for: muscle) } }
                    let firstRound = Array(slots.prefix(available(muscle).count))
                    #expect(Set(firstRound).count == firstRound.count, "\(goal), \(experience), \(variety), \(muscle): \(slots)")
                }
                for days in 2...6 {
                    let input = BlockPlanningInput(
                        goal: goal, phase: .maintenance, experience: experience, trainingDaysPerWeek: days,
                        priorities: builder.defaultPriorities(), plannedWeeks: 6, varietyPreference: variety,
                        catalog: catalog.exercises, restrictions: [], equipmentKnownness: equipment
                    )
                    let block = try TodayPlanBuilder.defaultPlanner().plan(input: input).block
                    let used = Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) }).compactMap { byID[$0] }
                    for muscle in muscles {
                        let slots = used.filter { $0.staple?.muscle == muscle }.compactMap { rule.slot(of: $0, for: muscle) }
                        // Un slot se repite sólo cuando ya salieron todos los del músculo.
                        if Set(slots).count < slots.count {
                            #expect(Set(slots) == available(muscle), "\(goal), \(experience), \(variety), \(days) días, \(muscle): \(slots)")
                        }
                    }
                }
            }
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

@Suite("Calidad de la asignación de ejercicios (catálogo real)")
struct ExerciseSelectionQualityTests {

    private let builder = TodayPlanBuilder()

    private func result(days: Int) throws -> (BlockPlanningResult, [ExerciseID: Exercise]) {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let input = BlockPlanningInput(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: days, priorities: builder.defaultPriorities(), plannedWeeks: 6,
            varietyPreference: .balanced, catalog: catalog.exercises, restrictions: [],
            equipmentKnownness: builder.defaultEquipmentKnownness(), sessionMinutes: 60
        )
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (try TodayPlanBuilder.defaultPlanner().plan(input: input), byID)
    }

    @Test("Toda la lista curada existe en el dataset y cada músculo tiene referencias con el equipo por defecto",
          arguments: [MuscleGroup.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes])
    func everyMuscleHasStaples(muscle: MuscleGroup) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let staples = catalog.exercises.filter { $0.staple?.muscle == muscle }
        #expect(staples.count >= 4, "\(muscle): sólo \(staples.count) ejercicios de referencia")
        let defaultEquipment: Set<EquipmentType> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
        #expect(staples.contains { defaultEquipment.contains($0.equipment) })
        // Cada ejercicio de referencia trabaja de verdad ese músculo (como principal).
        #expect(staples.allSatisfy { exercise in
            exercise.primaryMuscles.contains { $0.muscleGroupID == muscle }
        }, "\(muscle): hay un ejercicio de referencia que no lo trabaja como principal")
    }

    @Test("Cada ejercicio de la lista curada del recurso se encuentra en el catálogo")
    func curatedIDsResolve() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let total = catalog.exercises.filter { $0.staple != nil }.count
        // 10 músculos curados, 78 ids en exercise-staples.json (SCRUM-219 sumó 15); ningún id de la lista quedó sin resolver.
        #expect(total == 78, "esperados 78 ejercicios de referencia, hay \(total)")
    }

    @Test("Los ejercicios nunca recomendados quedan fuera del plan (guillotina, vueltas al mundo, encogimientos)",
          arguments: [2, 3, 4, 6])
    func noBadExercises(days: Int) throws {
        let (plan, byID) = try result(days: days)
        let names = plan.block.sessions
            .flatMap { $0.plannedSets.map(\.exerciseID) }
            .compactMap { byID[$0]?.canonicalName.lowercased() }
        for forbidden in ["guillotina", "vueltas al mundo", "encogimiento", "aducción", "aductor"] {
            #expect(!names.contains { $0.contains(forbidden) }, "\(days) días incluye '\(forbidden)'")
        }
    }

    @Test("El plan trae los básicos: sentadilla/prensa, peso muerto rumano o curl femoral, press de banca, remo o jalón",
          arguments: [3, 4, 6])
    func hasTheBasics(days: Int) throws {
        let (plan, byID) = try result(days: days)
        let names = Set(plan.block.sessions
            .flatMap { $0.plannedSets.map(\.exerciseID) }
            .compactMap { byID[$0]?.canonicalName.lowercased() })
        func has(_ fragments: String...) -> Bool { names.contains { name in fragments.contains { name.contains($0) } } }
        #expect(has("sentadilla", "prensa"), "falta una pierna de cuádriceps")
        #expect(has("rumano", "curl femoral"), "falta cadena posterior")
        #expect(has("press de banca"), "falta press de pecho")
        #expect(has("remo", "jalón"), "falta espalda de verdad (remo/jalón)")
        #expect(has("press de hombro", "press militar"), "falta press de hombro")
    }

    @Test("Todo ejercicio programado para un músculo lo trabaja como principal")
    func plannedExercisesTargetTheirMuscle() throws {
        let (plan, byID) = try result(days: 4)
        let targeted = Set(plan.block.muscleTargets.map(\.muscleGroupID))
        for session in plan.block.sessions {
            let exercises = Set(session.plannedSets.map(\.exerciseID)).compactMap { byID[$0] }
            for exercise in exercises {
                let primaries = Set(exercise.primaryMuscles.map(\.muscleGroupID))
                #expect(!primaries.isDisjoint(with: targeted), "\(exercise.canonicalName) no trabaja un músculo objetivo")
            }
        }
    }

    @Test("Con un catálogo sin lista curada se usa la selección genérica (no falla)")
    func fallbackWithoutStaples() throws {
        let raw = Data("""
        [{"id":"Some_Press","name":"Some Press","force":"push","level":"beginner","mechanic":"compound",
          "equipment":"barbell","primaryMuscles":["chest"],"secondaryMuscles":["triceps"],"category":"strength"},
         {"id":"Some_Fly","name":"Some Fly","force":"push","level":"beginner","mechanic":"isolation",
          "equipment":"dumbbell","primaryMuscles":["chest"],"secondaryMuscles":[],"category":"strength"}]
        """.utf8)
        let catalog = try ExerciseCatalogLoader.load(from: raw)
        let assignment = try ExerciseAssigner().assign(input: ExerciseAssignmentInput(
            muscleGroupID: .chest, catalog: catalog.exercises, varietyPreference: .balanced,
            restrictions: [], equipmentKnownness: .knownAvailable([.barbell, .dumbbell])
        ))
        #expect(assignment.anchor != nil)
        #expect(catalog.exercises.allSatisfy { $0.staple == nil })
    }
}
