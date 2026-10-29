//
//  ExerciseSelectionTests.swift
//  PRCoreTests
//
//  SCRUM-219 (PR-B005) con el catálogo real: el objetivo y la experiencia cambian las anclas,
//  el novato recibe lo guiado y el avanzado con fuerza la barra, en déficit baja la fatiga
//  sistémica, de un bloque al siguiente cambian los rotables (las anclas no) y nunca sale un
//  ejercicio prohibido ni con equipo ausente. La tabla de anclas queda en el log de `make ci`
//  con el prefijo `[PR-B005]`.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let muscles: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .calves, .core]
private let rule = ExerciseSelectionRule.standard

private struct Selection {
    let catalog: ExerciseCatalog
    let byID: [ExerciseID: Exercise]
    let builder = TodayPlanBuilder()
    let planner = TodayPlanBuilder.defaultPlanner()

    init() throws {
        catalog = try ExerciseCatalogLoader.loadBundled()
        byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func assignment(
        _ muscle: MuscleGroup,
        goal: TrainingGoal,
        experience: ExperienceLevel,
        phase: BodyCompositionPhase = .maintenance,
        variety: VarietyPreference = .balanced,
        sequence: Int = 0,
        restrictions: [TrainingRestriction] = [],
        equipment: EquipmentKnownness? = nil
    ) throws -> MuscleExerciseAssignment {
        try ExerciseAssigner().assign(input: ExerciseAssignmentInput(
            muscleGroupID: muscle, catalog: catalog.exercises, varietyPreference: variety,
            restrictions: restrictions, equipmentKnownness: equipment ?? builder.defaultEquipmentKnownness(),
            selectionProfile: ExerciseSelectionProfile(goal: goal, experience: experience, phase: phase),
            blockSequence: sequence
        ))
    }

    func anchor(_ muscle: MuscleGroup, goal: TrainingGoal, experience: ExperienceLevel) throws -> Exercise {
        let id = try #require(try assignment(muscle, goal: goal, experience: experience).anchor)
        return try #require(byID[id])
    }

    func block(
        goal: TrainingGoal,
        experience: ExperienceLevel,
        phase: BodyCompositionPhase = .maintenance,
        days: Int = 4,
        variety: VarietyPreference = .balanced,
        minutes: Int? = 60,
        sequence: Int = 0,
        restrictions: [TrainingRestriction] = [],
        equipment: EquipmentKnownness? = nil
    ) throws -> TrainingBlock {
        let input = BlockPlanningInput(
            goal: goal, phase: phase, experience: experience, trainingDaysPerWeek: days,
            priorities: builder.defaultPriorities(), plannedWeeks: 6, varietyPreference: variety,
            catalog: catalog.exercises, restrictions: restrictions,
            equipmentKnownness: equipment ?? builder.defaultEquipmentKnownness(),
            sessionMinutes: minutes, blockSequence: sequence
        )
        return try planner.plan(input: input).block
    }

    /// Nombre original del dataset (el canónico es el español).
    func english(_ id: ExerciseID) -> String {
        byID[id].map { $0.aliases.first ?? $0.canonicalName } ?? id.rawValue.uuidString
    }
}

/// Ejercicios de referencia de `muscle` que caben en el primer slot con ejercicios: de ahí sale
/// el ancla.
private func anchorSlotCandidates(_ muscle: MuscleGroup, in selection: Selection, equipment: Set<EquipmentType>) -> [Exercise] {
    let staples = selection.catalog.exercises.filter { $0.staple?.muscle == muscle && equipment.contains($0.equipment) }
    for slot in rule.slots(for: muscle) {
        let candidates = staples.filter { rule.slot(of: $0, for: muscle) == slot }
        if !candidates.isEmpty { return candidates }
    }
    return []
}

private let guided: Set<EquipmentType> = [.machine, .smithMachine, .plateLoaded]
/// Músculos cuyo primer slot es un básico compuesto.
private let basicLiftMuscles: Set<MuscleGroup> = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .glutes]
private let defaultEquipment: Set<EquipmentType> = [.barbell, .dumbbell, .machine, .smithMachine, .cable, .bodyweight]

@Suite("SCRUM-219 · Selección por objetivo, experiencia, fase y bloque (catálogo real)")
struct ExerciseSelectionTests {

    @Test("Tabla de anclas por objetivo y experiencia: fuerza e hipertrofia difieren en al menos 4 músculos en cada nivel")
    func goalChangesAnchors() throws {
        let selection = try Selection()
        for experience in ExperienceLevel.allCases {
            var differing: [MuscleGroup] = []
            for muscle in muscles {
                let strength = try selection.anchor(muscle, goal: .strength, experience: experience)
                let hypertrophy = try selection.anchor(muscle, goal: .hypertrophy, experience: experience)
                let health = try selection.anchor(muscle, goal: .generalHealth, experience: experience)
                print("[PR-B005] \(experience.rawValue) \(muscle.rawValue): fuerza \(selection.english(strength.id)) · hipertrofia \(selection.english(hypertrophy.id)) · salud \(selection.english(health.id))")
                if strength.id != hypertrophy.id { differing.append(muscle) }
            }
            #expect(differing.count >= 4, "\(experience): sólo \(differing.map(\.rawValue)) cambian de ancla")
        }
    }

    @Test("El novato ancla en lo guiado (máquina, Smith, prensa) y el avanzado con objetivo de fuerza, en la barra libre")
    func experienceChangesAnchors() throws {
        let selection = try Selection()
        for goal in TrainingGoal.allCases {
            for muscle in muscles {
                let candidates = anchorSlotCandidates(muscle, in: selection, equipment: defaultEquipment)
                let novice = try selection.anchor(muscle, goal: goal, experience: .novice)
                if candidates.contains(where: { guided.contains($0.equipment) }) {
                    #expect(guided.contains(novice.equipment), "novato, \(goal), \(muscle): \(selection.english(novice.id))")
                }
                // La fuerza pide la barra en los básicos (press, remo, sentadilla, bisagra), no en
                // core, pantorrilla ni aislamientos.
                guard goal == .strength || goal == .powerbuilding, basicLiftMuscles.contains(muscle) else { continue }
                for experience in [ExperienceLevel.advanced, .competitive] {
                    let anchor = try selection.anchor(muscle, goal: goal, experience: experience)
                    if candidates.contains(where: { $0.equipment == .barbell && $0.jointClass == .multiJoint }) {
                        #expect(anchor.equipment == .barbell, "\(experience), \(goal), \(muscle): \(selection.english(anchor.id))")
                        // Con las dos opciones en el slot, el novato y el avanzado no comparten ancla.
                        if candidates.contains(where: { guided.contains($0.equipment) }) {
                            #expect(anchor.id != novice.id, "\(goal), \(muscle): el novato y el \(experience) tienen la misma ancla")
                        }
                    }
                }
            }
        }
    }

    /// La sesión media (promedio de la fatiga por serie de cada sesión) cansa menos en déficit.
    /// Novato y principiante ya reciben lo guiado: ahí puede quedar igual, nunca más. Cada día
    /// rota distinto, así que se compara la sesión media, no sesión por sesión.
    @Test("En déficit la fatiga sistémica de la sesión media es menor que en superávit; las anclas no cambian")
    func deficitLowersSystemicFatigue() throws {
        let selection = try Selection()
        /// Media de la fatiga sistémica por serie de trabajo de cada sesión.
        func sessionMeans(_ block: TrainingBlock) -> [Double] {
            block.sessions.map { session in
                let costs = session.plannedSets.filter { !$0.prescription.isWarmup }
                    .compactMap { selection.byID[$0.exerciseID]?.systemicFatigueCost.normalized }
                return costs.reduce(0, +) / Double(max(1, costs.count))
            }
        }
        for goal in TrainingGoal.allCases {
            for experience in ExperienceLevel.allCases {
                for days in [3, 5] {
                    let deficit = sessionMeans(try selection.block(goal: goal, experience: experience, phase: .deficit, days: days))
                    let surplus = sessionMeans(try selection.block(goal: goal, experience: experience, phase: .surplus, days: days))
                    let mean = { (values: [Double]) in values.reduce(0, +) / Double(max(1, values.count)) }
                    print("[PR-B005] fatiga media \(goal.rawValue) \(experience.rawValue) \(days)d: déficit \(String(format: "%.3f", mean(deficit))) · superávit \(String(format: "%.3f", mean(surplus)))")
                    if experience == .novice || experience == .beginner {
                        #expect(mean(deficit) <= mean(surplus) + 1e-9, "\(goal), \(experience), \(days) días: el déficit sube la fatiga")
                    } else {
                        #expect(mean(deficit) < mean(surplus), "\(goal), \(experience), \(days) días: el déficit no baja la fatiga")
                    }
                    for muscle in muscles {
                        #expect(try selection.assignment(muscle, goal: goal, experience: experience, phase: .deficit).anchor
                                == selection.assignment(muscle, goal: goal, experience: experience, phase: .surplus).anchor)
                    }
                }
            }
        }
    }

    @Test("Bloques consecutivos: las anclas se quedan y al menos la mitad de los rotables cambia; el mismo bloque sale igual")
    func consecutiveBlocksRotate() throws {
        let selection = try Selection()
        func exercises(_ block: TrainingBlock) -> Set<ExerciseID> {
            Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) })
        }
        for goal in [TrainingGoal.strength, .hypertrophy, .generalHealth] {
            for experience in ExperienceLevel.allCases {
                for variety in VarietyPreference.allCases {
                    var anchors: Set<ExerciseID>?
                    for sequence in 0..<3 {
                        let blockAnchors = Set(try muscles.compactMap {
                            try selection.assignment($0, goal: goal, experience: experience, variety: variety, sequence: sequence).anchor
                        })
                        #expect(anchors == nil || anchors == blockAnchors, "\(goal), \(experience), \(variety): el bloque \(sequence) cambió un ancla")
                        anchors = blockAnchors
                        let block = try selection.block(goal: goal, experience: experience, variety: variety, sequence: sequence)
                        let again = try selection.block(goal: goal, experience: experience, variety: variety, sequence: sequence)
                        #expect(block.sessions.map { $0.plannedSets.map(\.exerciseID) } == again.sessions.map { $0.plannedSets.map(\.exerciseID) })
                        let next = try selection.block(goal: goal, experience: experience, variety: variety, sequence: sequence + 1)
                        let rotatables = exercises(block).subtracting(blockAnchors)
                        let changed = rotatables.subtracting(exercises(next)).count
                        #expect(changed * 2 >= rotatables.count,
                                "\(goal), \(experience), \(variety), bloque \(sequence) → \(sequence + 1): cambian \(changed) de \(rotatables.count) rotables")
                    }
                }
            }
        }
    }

    @Test("Con una restricción o con poco equipo nunca sale un ejercicio prohibido ni con equipo ausente",
          arguments: BodyRegionRestrictionRule.selectableRegions)
    func restrictionsAndEquipmentHold(region: BodyRegion) throws {
        let selection = try Selection()
        let restrictions = BodyRegionRestrictionRule.restrictions(for: RestrictionsAnswer(zones: [region]), now: now)
        let limited: Set<EquipmentType> = [.dumbbell, .cable, .bodyweight]
        for goal in [TrainingGoal.strength, .hypertrophy] {
            for experience in [ExperienceLevel.novice, .advanced] {
                for equipment in [defaultEquipment, limited] {
                    for sequence in 0..<2 {
                        let block = try selection.block(
                            goal: goal, experience: experience, days: 5, variety: .varied, sequence: sequence,
                            restrictions: restrictions, equipment: .knownAvailable(equipment)
                        )
                        for id in Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) }) {
                            let exercise = try #require(selection.byID[id])
                            #expect(RestrictionPolicyEngine.verdict(for: exercise, under: restrictions) == .allowed,
                                    "\(region), \(goal), \(experience), bloque \(sequence): \(selection.english(id))")
                            #expect(equipment.contains(exercise.equipment), "\(region), \(goal): \(selection.english(id)) sin su equipo")
                        }
                    }
                }
            }
        }
    }
}
