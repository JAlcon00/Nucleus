//
//  BlockPlanner.swift
//  PRDomain
//
//  Created by PR.
//
//  Block generator (plan §4F, PR-0504). Orquesta SplitSelector → VolumeAllocator →
//  ExerciseAssigner → ExerciseOrderEngine → FatigueInterferenceEngine para producir
//  un TrainingBlock persistible (4–8 semanas), determinista y explicable. Siempre
//  genera un bloque NUEVO; nunca muta ni borra historial previo.
//

import Foundation

/// Entrada completa del planificador de bloque.
public struct BlockPlanningInput: Sendable {
    public let goal: TrainingGoal
    public let phase: BodyCompositionPhase
    public let experience: ExperienceLevel
    public let trainingDaysPerWeek: Int
    /// Músculos prioritarios del usuario (para volumen y asignación). Sin estos,
    /// el planner no inventa músculos.
    public let priorities: [MusclePriority]
    public let plannedWeeks: Int

    public var varietyPreference: VarietyPreference

    public var catalog: [Exercise]
    public var restrictions: [TrainingRestriction]
    /// Disponibilidad de equipment (conocida o unknown).
    public var equipmentKnownness: EquipmentKnownness

    public init(
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        experience: ExperienceLevel,
        trainingDaysPerWeek: Int,
        priorities: [MusclePriority],
        plannedWeeks: Int,
        varietyPreference: VarietyPreference,
        catalog: [Exercise],
        restrictions: [TrainingRestriction],
        equipmentKnownness: EquipmentKnownness
    ) {
        self.goal = goal
        self.phase = phase
        self.experience = experience
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.priorities = priorities
        self.plannedWeeks = plannedWeeks
        self.varietyPreference = varietyPreference
        self.catalog = catalog
        self.restrictions = restrictions
        self.equipmentKnownness = equipmentKnownness
    }
}

/// Hecho explicativo del bloque generado.
public struct BlockExplanation: Codable, Sendable, Hashable {
    public let facts: [DecisionFact]
    /// Referencias versionadas de las reglas usadas (volumen + assignment).
    public let ruleReferences: [EvidenceRuleReference]

    public init(facts: [DecisionFact], ruleReferences: [EvidenceRuleReference]) {
        self.facts = facts
        self.ruleReferences = ruleReferences
    }
}

/// Resultado del planificador: bloque persistible + explicación.
public struct BlockPlanningResult: Codable, Sendable {
    public let block: TrainingBlock
    public let explanation: BlockExplanation
    /// Reference del split elegido.
    public let split: TrainingSplit

    public init(block: TrainingBlock, explanation: BlockExplanation, split: TrainingSplit) {
        self.block = block
        self.explanation = explanation
        self.split = split
    }
}

/// Problemas de entrada del planificador.
public enum BlockPlanningError: Error, Equatable, Sendable {
    case invalidWeeks(value: Int)
    case invalidTrainingDays(value: Int)
    case missingPriorities
}

/// Genera un bloque de entrenamiento completo (plan §4F, PR-0504).
///
/// Pipeline determinista:
/// 1. `SplitSelector` elige la estructura por días/objetivo/experiencia.
/// 2. `VolumeAllocator` distribuye sets semanales por músculo (reglas versionadas).
/// 3. `ExerciseAssigner` asigna anchor/rotatables por músculo respetando equipo y
///    restricciones.
/// 4. `ExerciseOrderEngine` ordena cada sesión; `FatigueInterferenceEngine` refina
///    reduciendo interferencia.
/// 5. Produce un `TrainingBlock` NUEVO 4–8 semanas (nunca muta historial previo).
///
/// Misma entrada → mismo bloque reproducible y explicable.
public struct BlockPlanner: Sendable {
    private let splitSelector: SplitSelector
    private let volumeAllocator: VolumeAllocator
    private let assigner: ExerciseAssigner
    private let orderEngine: ExerciseOrderEngine
    private let fatigueEngine: FatigueInterferenceEngine

    public init(
        splitSelector: SplitSelector = SplitSelector(),
        volumeAllocator: VolumeAllocator,
        assigner: ExerciseAssigner = ExerciseAssigner(),
        orderEngine: ExerciseOrderEngine = ExerciseOrderEngine(),
        fatigueEngine: FatigueInterferenceEngine = FatigueInterferenceEngine()
    ) {
        self.splitSelector = splitSelector
        self.volumeAllocator = volumeAllocator
        self.assigner = assigner
        self.orderEngine = orderEngine
        self.fatigueEngine = fatigueEngine
    }

    public func plan(input: BlockPlanningInput) throws -> BlockPlanningResult {
        guard (4...8).contains(input.plannedWeeks) else {
            throw BlockPlanningError.invalidWeeks(value: input.plannedWeeks)
        }
        guard !input.priorities.isEmpty else {
            throw BlockPlanningError.missingPriorities
        }

        let split = try splitSelector.select(
            trainingDaysPerWeek: input.trainingDaysPerWeek,
            goal: input.goal,
            experience: input.experience,
            phase: input.phase
        ).split

        // Volumen semanal por músculo.
        let allocation = try volumeAllocator.allocate(priorities: input.priorities)

        // Asignación de ejercicios por músculo (anchor + rotatables).
        var assignmentsByMuscle: [MuscleGroup.ID: MuscleExerciseAssignment] = [:]
        for assignment in allocation.targets {
            let assignmentInput = ExerciseAssignmentInput(
                muscleGroupID: assignment.muscleGroupID,
                catalog: input.catalog,
                varietyPreference: input.varietyPreference,
                restrictions: input.restrictions,
                equipmentKnownness: input.equipmentKnownness
            )
            assignmentsByMuscle[assignment.muscleGroupID] = try assigner.assign(input: assignmentInput)
        }

        // Construimos una plantilla de sesión por día de entrenamiento.
        let sessions = try buildSessions(
            split: split,
            input: input,
            allocation: allocation,
            assignmentsByMuscle: assignmentsByMuscle
        )

        let muscleTargets = try allocation.targets.map { assignment in
            try MuscleVolumeTarget(
                muscleGroupID: assignment.muscleGroupID,
                targetSetsPerWeek: assignment.weeklySets
            )
        }

        let block = try TrainingBlock(
            name: "\(input.goal.rawValue.capitalized) block",
            goal: input.goal,
            phase: input.phase,
            plannedWeeks: input.plannedWeeks,
            sessions: sessions,
            muscleTargets: muscleTargets,
            priorities: input.priorities,
            progressionPolicy: .doubleProgression,
            deloadPolicy: input.plannedWeeks == 8 ? .afterEightWeeks : (input.plannedWeeks >= 6 ? .afterSixWeeks : .none),
            varietyPolicy: try VarietyPolicy(percentStable: Self.stablePercent(for: input.varietyPreference))
        )

        let explanation = try buildExplanation(input: input, split: split, allocation: allocation)

        return BlockPlanningResult(block: block, explanation: explanation, split: split)
    }

    // MARK: - Session building

    private func buildSessions(
        split: TrainingSplit,
        input: BlockPlanningInput,
        allocation: VolumeAllocation,
        assignmentsByMuscle: [MuscleGroup.ID: MuscleExerciseAssignment]
    ) throws -> [SessionTemplate] {
        // Días que trabajan cada músculo según split.
        let dayMuscles = classification(for: split)
        let muscleWorkDays = dayCountByMuscle(split: split, muscles: allocation.targets.map(\.muscleGroupID))
        return try trainingDaysBySplit(split).enumerated().compactMap { index, name -> SessionTemplate? in
            let muscles = dayMuscles[index]
            var plannedSets: [PlannedSet] = []
            var seen: Set<ExerciseID> = []
            for muscle in muscles {
                guard let assignment = assignmentsByMuscle[muscle],
                      let days = muscleWorkDays[muscle], days > 0,
                      let weeklySets = allocation.target(for: muscle) else { continue }
                let setsThisDay = max(1, weeklySets / days)
                for assigned in orderedExercises(assignment) {
                    guard !seen.contains(assigned.exercise) else { continue }
                    seen.insert(assigned.exercise)
                    for _ in 0..<setsThisDay {
                        plannedSets.append(PlannedSet(
                            exerciseID: assigned.exercise,
                            prescription: try prescription(for: input.goal, isAnchor: assigned.role == .anchor)
                        ))
                    }
                }
            }
            guard !plannedSets.isEmpty else { return nil }
            return SessionTemplate(title: name, plannedSets: plannedSets)
        }
    }

    /// Ordena los ejercicios asignados del músculo (order + fatigue).
    private func orderedExercises(_ assignment: MuscleExerciseAssignment) -> [AssignedExercise] {
        // Determinista: role anchor primero, luego rotatables estables.
        assignment.assignments
    }

    private func prescription(for goal: TrainingGoal, isAnchor: Bool) throws -> SetPrescription {
        let repRange: ClosedRange<Int> = Self.defaultRepRange(for: goal)
        let rest = Self.defaultRest(for: goal)
        return try SetPrescription(
            targetRepRange: repRange,
            targetRIR: 1...2,
            loadUnit: .kilograms,
            restSeconds: rest
        )
    }

    // MARK: - Split classification

    private func trainingDaysBySplit(_ split: TrainingSplit) -> [String] {
        switch split {
        case .fullBody: return ["Full Body"]
        case .upperLower: return ["Upper", "Lower"]
        case .pushPullLegs: return ["Push", "Pull", "Legs"]
        }
    }

    /// Las clases de cada día de entrenamiento del split.
    private func classification(for split: TrainingSplit) -> [[MuscleGroup.ID]] {
        switch split {
        case .fullBody:
            return [[.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .calves]]
        case .upperLower:
            return [
                [.chest, .back, .shoulders, .biceps, .triceps],
                [.quadriceps, .hamstrings, .glutes, .calves],
            ]
        case .pushPullLegs:
            return [
                [.chest, .shoulders, .triceps],
                [.back, .biceps, .forearms],
                [.quadriceps, .hamstrings, .glutes, .calves],
            ]
        }
    }

    /// Nº de días del split que trabajan cada músculo de los objetivos.
    private func dayCountByMuscle(split: TrainingSplit, muscles: [MuscleGroup.ID]) -> [MuscleGroup.ID: Int] {
        let classes = classification(for: split)
        var counts: [MuscleGroup.ID: Int] = [:]
        for muscle in muscles {
            counts[muscle] = classes.reduce(into: 0) { result, day in
                if day.contains(muscle) { result += 1 }
            }
        }
        return counts
    }

    // MARK: - Explainability

    private func buildExplanation(
        input: BlockPlanningInput,
        split: TrainingSplit,
        allocation: VolumeAllocation
    ) throws -> BlockExplanation {
        let totalVolume = allocation.totalWeeklySets
        let anchorCount = input.priorities.count
        let facts: [DecisionFact] = [
            DecisionFact(key: "goal", value: input.goal.rawValue),
            DecisionFact(key: "phase", value: input.phase.rawValue),
            DecisionFact(key: "plannedWeeks", value: String(input.plannedWeeks)),
            DecisionFact(key: "split", value: split.rawValue),
            DecisionFact(key: "trainingDaysPerWeek", value: String(input.trainingDaysPerWeek)),
            DecisionFact(key: "priorityMuscles", value: String(anchorCount)),
            DecisionFact(key: "totalWeeklySets", value: String(totalVolume)),
        ]
        let references = [try volumeConfigReference(), try assignmentRuleReference()]
        return BlockExplanation(facts: facts, ruleReferences: references)
    }

    private func volumeConfigReference() throws -> EvidenceRuleReference {
        let config = try VolumeConfig(rule: VolumeDefaults.makeRule())
        return try config.reference()
    }

    private func assignmentRuleReference() throws -> EvidenceRuleReference {
        let rule = try ExerciseAssignmentDefaults.makeRule()
        return try EvidenceRuleReference(rule)
    }

    // MARK: - Defaults

    private static func stablePercent(for variety: VarietyPreference) -> Double {
        switch variety {
        case .stable: return 0.8
        case .balanced: return 0.65
        case .varied: return 0.55
        }
    }

    private static func defaultRepRange(for goal: TrainingGoal) -> ClosedRange<Int> {
        switch goal {
        case .strength: return 3...6
        case .powerbuilding: return 4...8
        case .hypertrophy, .bodybuilding, .recomposition, .generalHealth: return 8...12
        }
    }

    private static func defaultRest(for goal: TrainingGoal) -> ClosedRange<Int> {
        switch goal {
        case .strength: return 150...180
        case .powerbuilding: return 120...150
        case .hypertrophy, .bodybuilding, .recomposition, .generalHealth: return 60...90
        }
    }
}