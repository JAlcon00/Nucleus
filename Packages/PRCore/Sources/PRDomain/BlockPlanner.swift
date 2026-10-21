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
    /// Minutos que el usuario dedica a una sesión. Si una sesión no cabe, se recortan
    /// series de los ejercicios de menor prioridad; `nil` = sin límite de tiempo.
    public var sessionMinutes: Int?
    /// ID del bloque a generar. `nil` = ID nuevo. Para regenerar un bloque guardado
    /// conservando su identidad (SCRUM-26).
    public var blockID: TrainingBlockID?

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
        equipmentKnownness: EquipmentKnownness,
        sessionMinutes: Int? = nil,
        blockID: TrainingBlockID? = nil
    ) {
        self.sessionMinutes = sessionMinutes
        self.blockID = blockID
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
    /// Referencias versionadas de las reglas usadas (volumen + assignment + orden/fatiga).
    public let ruleReferences: [EvidenceRuleReference]
    /// Por qué cada ejercicio va en su posición, por sesión (SCRUM-29).
    public let sessionOrder: [SessionOrderExplanation]

    public init(
        facts: [DecisionFact],
        ruleReferences: [EvidenceRuleReference],
        sessionOrder: [SessionOrderExplanation] = []
    ) {
        self.facts = facts
        self.ruleReferences = ruleReferences
        self.sessionOrder = sessionOrder
    }
}

/// Orden final de una sesión con sus razones (rol funcional, prioridad muscular, demanda
/// técnica y, si aplicó, reordenamiento por fatiga).
public struct SessionOrderExplanation: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public let exerciseID: ExerciseID
        /// Posición final 1…N dentro de la sesión.
        public let rank: Int
        public let facts: [DecisionFact]
    }

    public let sessionTitle: String
    public let entries: [Entry]
    /// ¿La fatiga cambió el orden por rol/prioridad?
    public let reorderedByFatigue: Bool
    /// Interferencia residual del orden final (0 = ningún ejercicio pre-fatiga a otro prioritario).
    public let residualInterference: Double
    /// Precedencia aplicada, documentada para auditar (promptMaster §9.1).
    public static let precedence = "restricciones > rol funcional > prioridad muscular > demanda técnica > interferencia por fatiga"
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
    private let durationEstimator: DurationEstimator

    public init(
        splitSelector: SplitSelector = SplitSelector(),
        volumeAllocator: VolumeAllocator,
        assigner: ExerciseAssigner = ExerciseAssigner(),
        orderEngine: ExerciseOrderEngine = ExerciseOrderEngine(),
        fatigueEngine: FatigueInterferenceEngine = FatigueInterferenceEngine(),
        durationEstimator: DurationEstimator = DurationEstimator()
    ) {
        self.durationEstimator = durationEstimator
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
        let built = try buildSessions(
            split: split,
            input: input,
            allocation: allocation,
            assignmentsByMuscle: assignmentsByMuscle
        )
        let sessions = built.sessions

        let muscleTargets = try allocation.targets.map { assignment in
            try MuscleVolumeTarget(
                muscleGroupID: assignment.muscleGroupID,
                targetSetsPerWeek: assignment.weeklySets
            )
        }

        let block = try TrainingBlock(
            id: input.blockID ?? TrainingBlockID(),
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

        let explanation = try buildExplanation(
            input: input, split: split, allocation: allocation, sessionOrder: built.order
        )

        return BlockPlanningResult(block: block, explanation: explanation, split: split)
    }

    // MARK: - Session building (SCRUM-28 / SCRUM-29)

    /// Un día de entrenamiento de la semana con los músculos que trabaja.
    private struct DayPlan {
        let title: String
        let muscles: [MuscleGroup.ID]
    }

    /// Un ejercicio de una sesión con las series que le tocan ese día.
    private struct DayExercise {
        let exercise: Exercise
        var sets: Int
    }

    /// Construye UNA plantilla por día de entrenamiento (N días ⇒ N sesiones):
    /// - el objetivo semanal de cada músculo se reparte entre los días en que se entrena
    ///   (suma exacta) y luego entre pocos ejercicios (≈3 series cada uno), no por ejercicio;
    /// - el ancla se conserva todos los días; los rotables cambian de un día a otro;
    /// - cada sesión se ordena (rol/prioridad, luego fatiga) y se recorta si no cabe en
    ///   el tiempo del usuario.
    private func buildSessions(
        split: TrainingSplit,
        input: BlockPlanningInput,
        allocation: VolumeAllocation,
        assignmentsByMuscle: [MuscleGroup.ID: MuscleExerciseAssignment]
    ) throws -> (sessions: [SessionTemplate], order: [SessionOrderExplanation]) {
        let days = dayPlans(split: split, trainingDays: input.trainingDaysPerWeek)
        let catalog = Dictionary(input.catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fatigueConfig = try FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule())

        // Días (índices) en que se entrena cada músculo.
        var daysByMuscle: [MuscleGroup.ID: [Int]] = [:]
        for (index, day) in days.enumerated() {
            for muscle in day.muscles { daysByMuscle[muscle, default: []].append(index) }
        }

        var sessions: [SessionTemplate] = []
        var orderExplanations: [SessionOrderExplanation] = []
        for (dayIndex, day) in days.enumerated() {
            var chosen: [DayExercise] = []
            for muscle in day.muscles {
                guard let assignment = assignmentsByMuscle[muscle],
                      let weeklySets = allocation.target(for: muscle),
                      let muscleDays = daysByMuscle[muscle],
                      let position = muscleDays.firstIndex(of: dayIndex) else { continue }
                // Reparto exacto del objetivo semanal entre los días del músculo.
                let setsToday = weeklySets / muscleDays.count + (position < weeklySets % muscleDays.count ? 1 : 0)
                guard setsToday > 0 else { continue }
                for (exerciseID, sets) in distribute(setsToday, among: assignment, occurrence: position) {
                    guard let exercise = catalog[exerciseID] else { continue }
                    if let existing = chosen.firstIndex(where: { $0.exercise.id == exerciseID }) {
                        chosen[existing].sets += sets
                    } else {
                        chosen.append(DayExercise(exercise: exercise, sets: sets))
                    }
                }
            }
            guard !chosen.isEmpty else { continue }

            let (ordered, explanation) = try order(
                chosen, title: day.title, input: input, fatigueConfig: fatigueConfig
            )
            var exercises = ordered
            let rx = try prescription(for: input.goal, isAnchor: false)
            if let minutes = input.sessionMinutes {
                trimToFit(&exercises, minutes: minutes, prescription: rx)
            }
            var plannedSets: [PlannedSet] = []
            for item in exercises {
                for _ in 0..<item.sets {
                    plannedSets.append(PlannedSet(exerciseID: item.exercise.id, prescription: rx))
                }
            }
            sessions.append(SessionTemplate(title: day.title, plannedSets: plannedSets))
            orderExplanations.append(explanation)
        }
        return (sessions, orderExplanations)
    }

    /// Reparte las series del día entre pocos ejercicios del músculo: el ancla (el primer
    /// día, o junto a rotables si hay series de sobra) y rotables que cambian según
    /// cuántas veces se entrenó ya ese músculo en la semana.
    private func distribute(
        _ sets: Int,
        among assignment: MuscleExerciseAssignment,
        occurrence: Int
    ) -> [(ExerciseID, Int)] {
        let anchor = assignment.assignments.first { $0.role == .anchor } ?? assignment.assignments.first
        guard let anchor else { return [] }
        let rotatables = assignment.assignments.filter { $0.exercise != anchor.exercise }
        // ≈ 3 series por ejercicio, entre 1 y todos los asignados.
        let count = min(assignment.assignments.count, max(1, (sets + 2) / 3))
        var picked: [ExerciseID]
        if count == 1, occurrence > 0, !rotatables.isEmpty {
            // Pocas series ese día: un solo ejercicio. El ancla se entrena el primer día
            // de la semana y los demás días rota (cada día tiene su propia plantilla).
            picked = [rotatables[(occurrence - 1) % rotatables.count].exercise]
        } else {
            picked = [anchor.exercise]
            if count > 1, !rotatables.isEmpty {
                for step in 0..<(count - 1) {
                    picked.append(rotatables[(occurrence * (count - 1) + step) % rotatables.count].exercise)
                }
            }
        }
        // Sin repetir (pocos rotables) y con el reparto exacto; el ancla recibe el resto.
        var unique: [ExerciseID] = []
        for id in picked where !unique.contains(id) { unique.append(id) }
        let base = sets / unique.count
        let remainder = sets % unique.count
        return unique.enumerated().map { index, id in (id, base + (index < remainder ? 1 : 0)) }
    }

    /// Ordena la sesión: rol funcional y prioridad muscular (`ExerciseOrderEngine`), luego
    /// reduce la interferencia por fatiga (`FatigueInterferenceEngine`) sin adelantar un
    /// ejercicio menos prioritario a uno prioritario. Devuelve también el porqué.
    private func order(
        _ chosen: [DayExercise],
        title: String,
        input: BlockPlanningInput,
        fatigueConfig: FatigueInterferenceConfig
    ) throws -> ([DayExercise], SessionOrderExplanation) {
        let byID = Dictionary(chosen.map { ($0.exercise.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = try orderEngine.orderWithExplanation(input: ExerciseOrderInput(
            exercises: chosen.map(\.exercise), priorities: input.priorities, goal: input.goal
        ))
        let byRoleOrder = result.ordered.map(\.exercise)
        var finalOrder = byRoleOrder
        var interference = 0.0
        if byRoleOrder.count >= 2 {
            let assessment = try fatigueEngine.reorder(input: byRoleOrder, config: fatigueConfig)
            finalOrder = assessment.orderedExercises
            interference = assessment.totalPenalty
        }
        let factsByID = Dictionary(
            result.explanation.perExercise.map { ($0.exerciseID, $0.facts) },
            uniquingKeysWith: { first, _ in first }
        )
        let reordered = finalOrder.map(\.id) != byRoleOrder.map(\.id)
        let entries = finalOrder.enumerated().map { index, exercise in
            SessionOrderExplanation.Entry(
                exerciseID: exercise.id,
                rank: index + 1,
                facts: factsByID[exercise.id] ?? []
            )
        }
        let items = finalOrder.compactMap { byID[$0.id] }
        return (items, SessionOrderExplanation(
            sessionTitle: title, entries: entries, reorderedByFatigue: reordered, residualInterference: interference
        ))
    }

    /// Si la sesión excede los minutos del usuario, quita series de los últimos ejercicios
    /// (menor prioridad), de una en una; un ejercicio nunca baja de 1 serie.
    private func trimToFit(_ exercises: inout [DayExercise], minutes: Int, prescription: SetPrescription) {
        func seconds(_ list: [DayExercise]) -> Int {
            let sets = list.flatMap { item in
                Array(repeating: PlannedSet(exerciseID: item.exercise.id, prescription: prescription), count: item.sets)
            }
            return durationEstimator.estimate(plannedSets: sets)
        }
        while seconds(exercises) > minutes * 60 {
            guard let index = exercises.lastIndex(where: { $0.sets > 1 }) else { return }
            exercises[index].sets -= 1
        }
    }

    /// Los días de entrenamiento de la semana: N sesiones, cada una con su título y músculos.
    private func dayPlans(split: TrainingSplit, trainingDays: Int) -> [DayPlan] {
        let classes = classification(for: split)
        let names = trainingDaysBySplit(split)
        let total = max(1, trainingDays)
        return (0..<total).map { index in
            let classIndex = index % classes.count
            let occurrence = index / classes.count
            // Cuántas veces aparece este tipo de día en la semana; si se repite, A/B/C…
            let timesInWeek = (total - classIndex + classes.count - 1) / classes.count
            let letter = String(UnicodeScalar(UInt8(65 + min(occurrence, 25))))
            let title = timesInWeek > 1 ? "\(names[classIndex]) \(letter)" : names[classIndex]
            return DayPlan(title: title, muscles: classes[classIndex])
        }
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
        allocation: VolumeAllocation,
        sessionOrder: [SessionOrderExplanation]
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
            DecisionFact(key: "orderPrecedence", value: SessionOrderExplanation.precedence),
        ]
        let fatigue = try FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule()).reference()
        let references = [try volumeConfigReference(), try assignmentRuleReference(), fatigue]
        return BlockExplanation(facts: facts, ruleReferences: references, sessionOrder: sessionOrder)
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