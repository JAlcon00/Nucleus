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
    /// Lugar del bloque en el historial de la persona (0 = el primero). Los rotables cambian
    /// de un bloque al siguiente; las anclas no (SCRUM-219). Al regenerar un bloque guardado
    /// se pasa el suyo, así sale igual.
    public var blockSequence: Int

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
        blockID: TrainingBlockID? = nil,
        blockSequence: Int = 0
    ) {
        self.sessionMinutes = sessionMinutes
        self.blockID = blockID
        self.blockSequence = blockSequence
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
    /// RIR objetivo por tipo de ejercicio (SCRUM-200).
    private let intensityAdvisor: IntensityAdvisor
    /// Ejercicios por sesión según los minutos y mínimo de series (SCRUM-218).
    private let compositionRule: SessionCompositionRule

    public init(
        splitSelector: SplitSelector = SplitSelector(),
        volumeAllocator: VolumeAllocator,
        assigner: ExerciseAssigner = ExerciseAssigner(),
        orderEngine: ExerciseOrderEngine = ExerciseOrderEngine(),
        fatigueEngine: FatigueInterferenceEngine = FatigueInterferenceEngine(),
        durationEstimator: DurationEstimator = DurationEstimator(),
        intensityAdvisor: IntensityAdvisor = IntensityAdvisor(),
        compositionRule: SessionCompositionRule = .standard
    ) {
        self.durationEstimator = durationEstimator
        self.intensityAdvisor = intensityAdvisor
        self.compositionRule = compositionRule
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

        // Volumen semanal por músculo: la experiencia elige el punto del rango y el tiempo pone
        // el techo (SCRUM-227, ADR-0004). Si el volumen del nivel no cabe en la semana, baja
        // hacia el mínimo del rango; lo que ni así quepa lo recorta la composición (SCRUM-218).
        let allocation = try volumeAllocator.allocate(
            priorities: input.priorities,
            experience: input.experience,
            maxWeeklySets: input.sessionMinutes.map {
                weeklySetCapacity(minutes: $0, days: input.trainingDaysPerWeek, goal: input.goal)
            }
        )

        // Asignación de ejercicios por músculo (anchor + rotatables).
        var assignmentsByMuscle: [MuscleGroup.ID: MuscleExerciseAssignment] = [:]
        // SCRUM-209: músculos que una restricción activa dejó sin ejercicios permitidos.
        var restrictedMuscles: [MuscleGroup.ID] = []
        var firstRestrictionError: ExerciseAssignmentError?
        for assignment in allocation.targets {
            let assignmentInput = assignmentInput(for: assignment.muscleGroupID, input: input)
            do {
                assignmentsByMuscle[assignment.muscleGroupID] = try assigner.assign(input: assignmentInput)
            } catch let error as ExerciseAssignmentError where isEmptiedByRestrictions(assignmentInput) {
                // Seguridad antes que completitud: nunca se evade la restricción; el
                // músculo se omite esta vez y la explicación lo dice.
                restrictedMuscles.append(assignment.muscleGroupID)
                firstRestrictionError = firstRestrictionError ?? error
            }
        }
        // Si las restricciones dejaron sin ejercicios a TODOS los músculos no hay plan que
        // armar: error explícito (como antes), nunca un bloque vacío.
        if assignmentsByMuscle.isEmpty, let firstRestrictionError {
            throw firstRestrictionError
        }

        // Construimos una plantilla de sesión por día de entrenamiento.
        let built = try buildSessions(
            split: split,
            input: input,
            allocation: allocation,
            assignmentsByMuscle: assignmentsByMuscle
        )
        let sessions = built.sessions

        let muscleTargets = try allocation.targets.filter { !restrictedMuscles.contains($0.muscleGroupID) }.map { assignment in
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
            input: input, split: split, allocation: allocation, sessionOrder: built.order,
            restrictedMuscles: restrictedMuscles, composition: built.composition
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
        /// Músculos de la sesión para los que se eligió.
        var muscles: Set<MuscleGroup.ID>
        /// ¿Es el ancla de alguno de esos músculos?
        var isAnchor: Bool

        var isCompound: Bool { exercise.jointClass == .multiJoint }
    }

    /// Sesiones donde lo protegido no dejó cumplir el tope de ejercicios o el tiempo
    /// (SCRUM-218, decisión 3): se quedan así y la explicación lo dice.
    struct CompositionNotes: Equatable {
        /// Músculos de mantenimiento (pantorrilla, core) que no cupieron en ninguna sesión de
        /// la semana con los minutos del usuario (SCRUM-215: gana el tiempo).
        var maintenanceLeftOut: [MuscleGroup.ID] = []
        var overRange: [String] = []
        var overTime: [String] = []
    }

    /// Construye UNA plantilla por día de entrenamiento (N días ⇒ N sesiones):
    /// - el objetivo semanal de cada músculo se reparte entre los días en que se entrena
    ///   (suma exacta, nunca menos de 2 series en un día) y luego entre pocos ejercicios
    ///   (≈3 series cada uno, nunca menos de 2), no por ejercicio;
    /// - el ancla sale al menos 2 veces por semana; los rotables cambian de un día a otro;
    /// - cada sesión se ordena (rol/prioridad, luego fatiga) y se compone con el rango de
    ///   ejercicios y el tiempo del usuario (SCRUM-218).
    private func buildSessions(
        split: TrainingSplit,
        input: BlockPlanningInput,
        allocation: VolumeAllocation,
        assignmentsByMuscle: [MuscleGroup.ID: MuscleExerciseAssignment]
    ) throws -> (sessions: [SessionTemplate], order: [SessionOrderExplanation], composition: CompositionNotes) {
        let days = dayPlans(split: split, trainingDays: input.trainingDaysPerWeek)
        let catalog = Dictionary(input.catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fatigueConfig = try FatigueInterferenceConfig(rule: FatigueInterferenceDefaults.makeRule())
        let priorityMuscles = Set(input.priorities.filter { $0.priority.rawValue > PriorityTier.normal.rawValue }.map(\.muscleGroupID))
        let maintenanceMuscles = Set(input.priorities.filter { $0.priority == .maintain }.map(\.muscleGroupID))

        // Días (índices) en que se entrena cada músculo: nunca tantos que toque menos de
        // 2 series en un día (con poco volumen semanal se entrena en menos días).
        var daysByMuscle: [MuscleGroup.ID: [Int]] = [:]
        for (index, day) in days.enumerated() {
            for muscle in day.muscles { daysByMuscle[muscle, default: []].append(index) }
        }
        for (muscle, muscleDays) in daysByMuscle {
            guard let weeklySets = allocation.target(for: muscle) else { continue }
            let usable = max(1, min(muscleDays.count, weeklySets / compositionRule.minimumWorkSets))
            daysByMuscle[muscle] = (0..<usable).map { muscleDays[$0 * muscleDays.count / usable] }
        }

        var sessions: [SessionTemplate] = []
        var orderExplanations: [SessionOrderExplanation] = []
        var notes = CompositionNotes()
        var programmed: Set<MuscleGroup.ID> = []
        for (dayIndex, day) in days.enumerated() {
            func choose(preferTwoSets: Bool) -> [DayExercise] {
                var chosen: [DayExercise] = []
                for (muscleIndex, muscle) in day.muscles.enumerated() {
                    guard let assignment = assignmentsByMuscle[muscle],
                          let weeklySets = allocation.target(for: muscle),
                          let muscleDays = daysByMuscle[muscle],
                          let position = muscleDays.firstIndex(of: dayIndex) else { continue }
                    // Reparto exacto del objetivo semanal entre los días del músculo.
                    let setsToday = weeklySets / muscleDays.count + (position < weeklySets % muscleDays.count ? 1 : 0)
                    guard setsToday > 0 else { continue }
                    let picks = distribute(
                        setsToday, among: assignment, occurrence: position, timesInWeek: muscleDays.count,
                        muscleIndex: muscleIndex, preferTwoSets: preferTwoSets
                    )
                    for pick in picks {
                        guard let exercise = catalog[pick.exercise] else { continue }
                        if let existing = chosen.firstIndex(where: { $0.exercise.id == pick.exercise }) {
                            chosen[existing].sets += pick.sets
                            chosen[existing].muscles.insert(muscle)
                            chosen[existing].isAnchor = chosen[existing].isAnchor || pick.isAnchor
                        } else {
                            chosen.append(DayExercise(exercise: exercise, sets: pick.sets, muscles: [muscle], isAnchor: pick.isAnchor))
                        }
                    }
                }
                return chosen
            }
            var chosen = choose(preferTwoSets: false)
            // Mínimo del rango sólo si el volumen alcanza: más ejercicios de 2 series, nunca
            // más series (decisión 1).
            if let minutes = input.sessionMinutes,
               chosen.count < compositionRule.exerciseRange(forMinutes: minutes).lowerBound {
                let finer = choose(preferTwoSets: true)
                if finer.count > chosen.count { chosen = finer }
            }
            guard !chosen.isEmpty else { continue }

            let (ordered, fullOrder) = try order(
                chosen, title: day.title, input: input, fatigueConfig: fatigueConfig
            )
            var exercises = ordered
            let rx = try prescription(for: input.goal, isAnchor: false)
            if let minutes = input.sessionMinutes {
                let outcome = compose(
                    &exercises, minutes: minutes, goal: input.goal,
                    priorityMuscles: priorityMuscles, maintenanceMuscles: maintenanceMuscles, prescription: rx
                )
                if outcome.overRange { notes.overRange.append(day.title) }
                if outcome.overTime { notes.overTime.append(day.title) }
            }
            // "¿Por qué este orden?" sólo con lo que quedó, en su posición final.
            let explanation = keeping(exercises, in: fullOrder)
            var plannedSets: [PlannedSet] = []
            for item in exercises {
                // SCRUM-200: cada ejercicio con el RIR de su tipo (barra libre, compuesto, aislado).
                var exerciseRx = rx
                exerciseRx.targetRIR = intensityAdvisor.targetRIR(for: item.exercise)
                for _ in 0..<item.sets {
                    plannedSets.append(PlannedSet(exerciseID: item.exercise.id, prescription: exerciseRx))
                }
            }
            sessions.append(SessionTemplate(title: day.title, plannedSets: plannedSets))
            orderExplanations.append(explanation)
            for item in exercises { programmed.formUnion(item.muscles) }
        }
        // Un músculo de mantenimiento con ejercicios permitidos que no quedó en ninguna sesión:
        // no cupo en el tiempo. El que dejó fuera una restricción se explica aparte.
        notes.maintenanceLeftOut = input.priorities
            .filter { $0.priority == .maintain && assignmentsByMuscle[$0.muscleGroupID] != nil && !programmed.contains($0.muscleGroupID) }
            .map(\.muscleGroupID)
        return (sessions, orderExplanations, notes)
    }

    /// Un ejercicio elegido para un músculo en un día.
    private struct Pick {
        let exercise: ExerciseID
        let sets: Int
        let isAnchor: Bool
    }

    /// Reparte las series del día entre pocos ejercicios del músculo, cada uno con al menos
    /// 2 series: el ancla y rotables que cambian según cuántas veces se entrenó ya ese
    /// músculo en la semana. Con un solo ejercicio ese día, el ancla sale todos los días
    /// menos uno (si el músculo se entrena 3+ días), así sale al menos 2 veces por semana y
    /// cada día tiene su propia plantilla (el día que rota cambia según el músculo).
    private func distribute(
        _ sets: Int,
        among assignment: MuscleExerciseAssignment,
        occurrence: Int,
        timesInWeek: Int,
        muscleIndex: Int,
        preferTwoSets: Bool
    ) -> [Pick] {
        let anchor = assignment.assignments.first { $0.role == .anchor } ?? assignment.assignments.first
        guard let anchor else { return [] }
        let rotatables = assignment.assignments.filter { $0.exercise != anchor.exercise }
        // ≈ 3 series por ejercicio (≈ 2 para llegar al mínimo del rango), nunca menos de 2.
        let perExercise = preferTwoSets ? compositionRule.minimumWorkSets : 3
        let byPreference = (sets + perExercise - 1) / perExercise
        let byMinimum = sets / compositionRule.minimumWorkSets
        let count = max(1, min(assignment.assignments.count, byPreference, byMinimum))
        var picked: [ExerciseID]
        let rotationDay = timesInWeek - 1 - muscleIndex % max(1, timesInWeek)
        if count == 1, timesInWeek >= 3, occurrence == rotationDay, let first = rotatables.first {
            // El primer rotable cubre el siguiente slot del músculo (SCRUM-219).
            picked = [first.exercise]
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
        return unique.enumerated().map { index, id in
            Pick(exercise: id, sets: base + (index < remainder ? 1 : 0), isAnchor: id == anchor.exercise)
        }
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

    /// La explicación del orden con sólo los ejercicios que quedaron tras componer la sesión,
    /// numerados en su posición final.
    private func keeping(_ kept: [DayExercise], in explanation: SessionOrderExplanation) -> SessionOrderExplanation {
        let factsByID = Dictionary(explanation.entries.map { ($0.exerciseID, $0.facts) }, uniquingKeysWith: { first, _ in first })
        let entries = kept.enumerated().map { index, item in
            SessionOrderExplanation.Entry(exerciseID: item.exercise.id, rank: index + 1, facts: factsByID[item.exercise.id] ?? [])
        }
        return SessionOrderExplanation(
            sessionTitle: explanation.sessionTitle, entries: entries,
            reorderedByFatigue: explanation.reorderedByFatigue, residualInterference: explanation.residualInterference
        )
    }

    /// Lleva la sesión (ya ordenada, de lo más a lo menos importante) a su rango de ejercicios
    /// y a los minutos del usuario (SCRUM-218). Nunca deja un ejercicio con menos de 2 series
    /// ni quita lo protegido: anclas compuestas y músculos prioritarios. Lo de mantenimiento
    /// (pantorrilla y core, SCRUM-215) sale después del resto de lo no protegido.
    /// 1. Tope de ejercicios: sale primero un aislamiento no protegido, luego otro no
    ///    protegido y, al final, lo de mantenimiento; sus series pasan a otro ejercicio de la
    ///    sesión del mismo músculo.
    /// 2. Tiempo, en este orden: quitar aislamientos no protegidos que no son de
    ///    mantenimiento; bajar series hasta el mínimo (3 en un ancla compuesta con objetivo
    ///    fuerza, 2 en lo demás); quitar los aislamientos de mantenimiento; sólo entonces
    ///    quitar otro ejercicio no protegido.
    /// Los supersets (`CompatibleSuperset`) no se aplican aquí: la sesión guardada todavía no
    /// tiene cómo representarlos.
    private func compose(
        _ exercises: inout [DayExercise],
        minutes: Int,
        goal: TrainingGoal,
        priorityMuscles: Set<MuscleGroup.ID>,
        maintenanceMuscles: Set<MuscleGroup.ID>,
        prescription: SetPrescription
    ) -> (overRange: Bool, overTime: Bool) {
        func isProtected(_ item: DayExercise) -> Bool {
            (item.isAnchor && item.isCompound) || !item.muscles.isDisjoint(with: priorityMuscles)
        }
        func isMaintenance(_ item: DayExercise) -> Bool {
            !item.muscles.isDisjoint(with: maintenanceMuscles)
        }
        func minimumSets(_ item: DayExercise) -> Int {
            goal == .strength && item.isAnchor && item.isCompound
                ? compositionRule.strengthAnchorMinimumSets
                : compositionRule.minimumWorkSets
        }
        func fits() -> Bool {
            let sets = exercises.flatMap { item in
                Array(repeating: PlannedSet(exerciseID: item.exercise.id, prescription: prescription), count: item.sets)
            }
            return durationEstimator.estimate(plannedSets: sets) <= minutes * 60
        }
        /// El último ejercicio no protegido que se puede quitar; con `sparingMaintenance`,
        /// sin contar lo de mantenimiento.
        func lastRemovable(isolationOnly: Bool, sparingMaintenance: Bool = false) -> Int? {
            exercises.lastIndex {
                !isProtected($0) && (!isolationOnly || !$0.isCompound) && !(sparingMaintenance && isMaintenance($0))
            }
        }

        // 1. Tope de ejercicios.
        let cap = compositionRule.exerciseRange(forMinutes: minutes).upperBound
        var overRange = false
        while exercises.count > cap {
            guard let index = lastRemovable(isolationOnly: true, sparingMaintenance: true)
                ?? lastRemovable(isolationOnly: false, sparingMaintenance: true)
                ?? lastRemovable(isolationOnly: true)
                ?? lastRemovable(isolationOnly: false) else {
                overRange = true
                break
            }
            let removed = exercises.remove(at: index)
            let sameMuscle = { (item: DayExercise) in !item.muscles.isDisjoint(with: removed.muscles) }
            if let target = exercises.firstIndex(where: { sameMuscle($0) && $0.isAnchor }) ?? exercises.firstIndex(where: sameMuscle) {
                exercises[target].sets += removed.sets
            }
        }

        // 2. Tiempo.
        while !fits(), let index = lastRemovable(isolationOnly: true, sparingMaintenance: true) {
            exercises.remove(at: index)
        }
        while !fits(), let index = exercises.lastIndex(where: { $0.sets > minimumSets($0) }) {
            exercises[index].sets -= 1
        }
        while !fits(), let index = lastRemovable(isolationOnly: true) {
            exercises.remove(at: index)
        }
        while !fits(), let index = lastRemovable(isolationOnly: false) {
            exercises.remove(at: index)
        }
        return (overRange, !fits())
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

    /// Series de trabajo que caben en la semana (SCRUM-227): días × ⌊minutos ÷ (serie +
    /// descanso + transición)⌋, con los mismos tiempos con los que el estimador mide la sesión.
    private func weeklySetCapacity(minutes: Int, days: Int, goal: TrainingGoal) -> Int {
        let defaults = durationEstimator.defaults
        let secondsPerSet = defaults.defaultSetSeconds + Double(Self.defaultRest(for: goal).lowerBound)
            + defaults.defaultTransitionSeconds
        guard secondsPerSet > 0 else { return Int.max }
        return max(0, days) * Int((Double(minutes * 60) / secondsPerSet).rounded(.down))
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

    /// Las clases de cada día de entrenamiento del split. El core va en el día con más
    /// espacio (SCRUM-215): pierna en torso/pierna y jalón en empuje/jalón/pierna, donde
    /// sólo hay espalda y bíceps; la pantorrilla, con la pierna.
    private func classification(for split: TrainingSplit) -> [[MuscleGroup.ID]] {
        switch split {
        case .fullBody:
            return [[.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .calves, .core]]
        case .upperLower:
            return [
                [.chest, .back, .shoulders, .biceps, .triceps],
                [.quadriceps, .hamstrings, .glutes, .calves, .core],
            ]
        case .pushPullLegs:
            return [
                [.chest, .shoulders, .triceps],
                [.back, .biceps, .forearms, .core],
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

    /// El ancla de cada músculo del bloque: la misma que usa `plan` para repartir series
    /// (SCRUM-30 la protege al recortar una sesión por tiempo). Un músculo que se quedó sin
    /// ejercicios permitidos no tiene ancla; no es un error aquí porque `plan` ya lo manejó.
    public func anchorExercises(input: BlockPlanningInput) -> Set<ExerciseID> {
        Set(input.priorities.compactMap { priority -> ExerciseID? in
            guard let assignment = try? assigner.assign(input: assignmentInput(for: priority.muscleGroupID, input: input))
            else { return nil }
            return (assignment.assignments.first { $0.role == .anchor } ?? assignment.assignments.first)?.exercise
        })
    }

    /// Lo que el assigner necesita para un músculo: catálogo, restricciones, equipo, y el
    /// objetivo, la experiencia, la fase y el lugar del bloque (SCRUM-219).
    private func assignmentInput(for muscle: MuscleGroup.ID, input: BlockPlanningInput) -> ExerciseAssignmentInput {
        ExerciseAssignmentInput(
            muscleGroupID: muscle,
            catalog: input.catalog,
            varietyPreference: input.varietyPreference,
            restrictions: input.restrictions,
            equipmentKnownness: input.equipmentKnownness,
            selectionProfile: ExerciseSelectionProfile(goal: input.goal, experience: input.experience, phase: input.phase),
            blockSequence: input.blockSequence
        )
    }

    /// ¿El músculo se quedó sin ejercicios SÓLO por las restricciones? Si sin ellas tampoco
    /// hay ejercicio (catálogo o equipo), el error sigue siendo error.
    private func isEmptiedByRestrictions(_ input: ExerciseAssignmentInput) -> Bool {
        guard !input.restrictions.isEmpty else { return false }
        let unrestricted = ExerciseAssignmentInput(
            muscleGroupID: input.muscleGroupID,
            catalog: input.catalog,
            varietyPreference: input.varietyPreference,
            restrictions: [],
            equipmentKnownness: input.equipmentKnownness,
            selectionProfile: input.selectionProfile,
            blockSequence: input.blockSequence
        )
        return (try? assigner.assign(input: unrestricted)) != nil
    }

    // MARK: - Explainability

    private func buildExplanation(
        input: BlockPlanningInput,
        split: TrainingSplit,
        allocation: VolumeAllocation,
        sessionOrder: [SessionOrderExplanation],
        restrictedMuscles: [MuscleGroup.ID] = [],
        composition: CompositionNotes = CompositionNotes()
    ) throws -> BlockExplanation {
        let totalVolume = allocation.targets
            .filter { !restrictedMuscles.contains($0.muscleGroupID) }
            .reduce(0) { $0 + $1.weeklySets }
        let anchorCount = input.priorities.count
        var facts: [DecisionFact] = [
            DecisionFact(key: "goal", value: input.goal.rawValue),
            DecisionFact(key: "phase", value: input.phase.rawValue),
            DecisionFact(key: "plannedWeeks", value: String(input.plannedWeeks)),
            DecisionFact(key: "split", value: split.rawValue),
            DecisionFact(key: "trainingDaysPerWeek", value: String(input.trainingDaysPerWeek)),
            DecisionFact(key: "priorityMuscles", value: String(anchorCount)),
            DecisionFact(key: "totalWeeklySets", value: String(totalVolume)),
            DecisionFact(key: "orderPrecedence", value: SessionOrderExplanation.precedence),
        ]
        // SCRUM-209: zonas cuidadas y músculos omitidos por una restricción.
        let regions = BodyRegion.allCases.filter { region in
            input.restrictions.contains { $0.bodyRegion == region && $0.status != .resolved }
        }
        if !regions.isEmpty {
            facts.append(DecisionFact(key: "restrictedRegions", value: regions.map(\.rawValue).joined(separator: ", ")))
        }
        if !restrictedMuscles.isEmpty {
            facts.append(DecisionFact(key: "restrictedMuscles", value: restrictedMuscles.map(\.rawValue).joined(separator: ", ")))
        }
        // SCRUM-218: regla de composición y sesiones donde lo protegido no dejó cumplir el
        // tope de ejercicios o el tiempo (se quedan así; la explicación lo dice).
        facts.append(DecisionFact(key: "sessionComposition", value: compositionRule.version))
        // SCRUM-219: regla de selección por slots, objetivo, experiencia y fase.
        facts.append(DecisionFact(key: "exerciseSelection", value: assigner.selectionRule.version))
        if !composition.overRange.isEmpty {
            facts.append(DecisionFact(key: "sessionsOverRange", value: composition.overRange.joined(separator: ", ")))
        }
        if !composition.overTime.isEmpty {
            facts.append(DecisionFact(key: "sessionsOverTime", value: composition.overTime.joined(separator: ", ")))
        }
        // SCRUM-215: pantorrilla o core que no cupieron en la semana con los minutos del usuario.
        if !composition.maintenanceLeftOut.isEmpty {
            facts.append(DecisionFact(key: "maintenanceLeftOut", value: composition.maintenanceLeftOut.map(\.rawValue).joined(separator: ", ")))
        }
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