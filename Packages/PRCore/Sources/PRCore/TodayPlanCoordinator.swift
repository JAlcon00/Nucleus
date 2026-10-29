//
//  TodayPlanCoordinator.swift
//  PRCore
//
//  Created by PR.
//
//  App-core coordinador que cablea "Hoy" con un plan REAL (PR-0601): a partir del
//  `OnboardingProfile` genera un `TrainingBlock` (vía `BlockPlanner`), elige la
//  plantilla de la sesión de hoy de forma determinista según el día de la semana y
//  los días de entrenamiento por semana, y deriva `TodayScreenState` con
//  `TodayScreenDriver`. No contiene reglas de negocio: sóolo orquesta engines y
//  conserva el estado derivado para que la UI lo presente. Funciona offline.
//

import Foundation
import Observation
import PRDomain

/// Un ejercicio de la sesión de hoy tal como se lista en "Hoy": nombre del catálogo y
/// número de series. Sin nombre inventado: si el catálogo no lo tiene, `name` es `nil`.
public struct TodayExerciseLine: Equatable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String?
    /// Todas las series (calentamiento incluido).
    public let setCount: Int
    /// Series de trabajo (SCRUM-197, M1: "3 × 8–12").
    public let workSetCount: Int
    /// Rango de repeticiones de las series de trabajo; `nil` si sólo hay calentamiento.
    public let repRange: ClosedRange<Int>?
    /// Compuesto (multiarticular) o aislado (monoarticular), según el catálogo; `nil` si el
    /// ejercicio ya no está en el catálogo (no se adivina).
    public let jointClass: JointClass?
    /// RIR objetivo de las series de trabajo, tal como lo dejó el motor (SCRUM-200).
    public let targetRIR: ClosedRange<Int>?
    /// ¿Conviene dropset en la última serie? `nil` si no se conoce el perfil o el ejercicio.
    public let dropset: DropsetAdvice?
    public var id: ExerciseID { exerciseID }

    public init(
        exerciseID: ExerciseID,
        name: String?,
        setCount: Int,
        workSetCount: Int? = nil,
        repRange: ClosedRange<Int>? = nil,
        jointClass: JointClass? = nil,
        targetRIR: ClosedRange<Int>? = nil,
        dropset: DropsetAdvice? = nil
    ) {
        self.exerciseID = exerciseID
        self.name = name
        self.setCount = setCount
        self.workSetCount = workSetCount ?? setCount
        self.repRange = repRange
        self.jointClass = jointClass
        self.targetRIR = targetRIR
        self.dropset = dropset
    }
}

/// Motivo (determinista, derivado de los facts del motor de orden) por el que un
/// ejercicio va en su posición. La View sólo lo traduce a texto.
public enum TodayOrderReason: Equatable, Sendable {
    case functionalRole
    case musclePriority
    case technicalDemand
}

/// Una fila de "¿Por qué este orden?": posición, ejercicio y motivos.
public struct TodayOrderLine: Equatable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String?
    public let rank: Int
    public let reasons: [TodayOrderReason]
    public var id: ExerciseID { exerciseID }

    public init(exerciseID: ExerciseID, name: String?, rank: Int, reasons: [TodayOrderReason]) {
        self.exerciseID = exerciseID
        self.name = name
        self.rank = rank
        self.reasons = reasons
    }
}

/// Plan derivado para la pantalla "Hoy": bloque generado + plantilla de hoy + estado.
public struct TodayPlan: Equatable, Sendable {
    public let block: TrainingBlock
    public let sessions: [SessionTemplate]
    public let todayTemplate: SessionTemplate?
    public let estimatedMinutes: Int?
    public let todayState: TodayScreenState
    /// Ejercicios de la sesión de hoy en el orden de la plantilla (vacío en descanso).
    public let todayExercises: [TodayExerciseLine]
    /// Explicación del orden de hoy (SCRUM-29), tomada del `DecisionRecord` del bloque.
    public let todayOrder: [TodayOrderLine]
    /// ¿La fatiga reordenó la sesión de hoy?
    public let todayOrderReorderedByFatigue: Bool
    /// Explicación del bloque (orden de cada sesión), para "Tu semana" (SCRUM-197).
    public let explanation: BlockExplanation?
    /// Ajuste del día por el check-in de sueño (SCRUM-203); ya aplicado a `todayTemplate`.
    public let readiness: ReadinessAdjustment
    /// El orden de hoy lo eligió la persona (SCRUM-211), no el motor.
    public let todayOrderIsCustom: Bool
    /// Ajuste de hoy al tiempo que la persona dijo tener (SCRUM-30); ya aplicado a
    /// `todayTemplate`. `nil` sin tiempo elegido.
    public let timeAdjustment: SessionTimeAdjustment?

    public init(
        block: TrainingBlock,
        sessions: [SessionTemplate],
        todayTemplate: SessionTemplate?,
        estimatedMinutes: Int?,
        todayState: TodayScreenState,
        todayExercises: [TodayExerciseLine] = [],
        todayOrder: [TodayOrderLine] = [],
        todayOrderReorderedByFatigue: Bool = false,
        explanation: BlockExplanation? = nil,
        readiness: ReadinessAdjustment = .none,
        todayOrderIsCustom: Bool = false,
        timeAdjustment: SessionTimeAdjustment? = nil
    ) {
        self.block = block
        self.sessions = sessions
        self.todayTemplate = todayTemplate
        self.estimatedMinutes = estimatedMinutes
        self.todayState = todayState
        self.todayExercises = todayExercises
        self.todayOrder = todayOrder
        self.todayOrderReorderedByFatigue = todayOrderReorderedByFatigue
        self.explanation = explanation
        self.readiness = readiness
        self.todayOrderIsCustom = todayOrderIsCustom
        self.timeAdjustment = timeAdjustment
    }
}

/// Errores al generar el plan de hoy (determinista; no inventa valores).
public enum TodayPlanError: Error, Equatable, Sendable {
    /// El perfil no permite generar un bloque (p. ej. sin músculos prioritarios válidos).
    case cannotBuildBlock(String)
    /// Entrada incoherente (p. ej. el día de la semana no es reconocible).
    case invalidInput
}

/// Construye el plan de hoy de forma determinista y pura.
///
/// Decisiones documentadas (no invención):
/// - Prioridades musculares por defecto: todas las musculaturas estándar del split a
///   tier `.normal` (mantener/equilibrado). El onboarding no recoge prioridades
///   explícitas; tratar todas igual es una elección determinista y conservadora.
/// - Equipment: conjunto básico de gimnasio `knownAvailable` (barbell/dumbbell/machine/
///   cable/bodyweight) como seed documentado; el perfil de gym real la refina en PR-0901.
/// - Rotación semanal (`TrainingWeek`, SCRUM-27/196): los días elegidos son de
///   entrenamiento y cada uno tiene su slot 0…N-1 en orden de lunes a domingo; el resto
///   es descanso. La plantilla del día es `sessions[slot % sessions.count]`.
/// - Duración estimada (SCRUM-30): la de la sesión real de hoy, con `SessionTimeFitter`
///   (series, descansos y transiciones), no los minutos del cuestionario.
public struct TodayPlanBuilder: Sendable {
    private let timeFitter = SessionTimeFitter()

    public init() {}

    /// Construye el `TodayPlan` para hoy a partir del perfil de onboarding (genera el bloque).
    public func plan(
        profile: OnboardingProfile,
        catalog: ExerciseCatalog,
        planner: BlockPlanner,
        driver: TodayScreenDriver,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> TodayPlan {
        let result = try generate(profile: profile, catalog: catalog, planner: planner)
        return try todayPlan(
            profile: profile,
            block: result.block,
            explanation: result.explanation,
            catalog: catalog,
            driver: driver,
            date: date,
            timeZone: timeZone
        )
    }

    /// Genera un bloque para el perfil. `blockID` conserva la identidad al regenerar;
    /// `blockSequence` es su lugar en el historial (SCRUM-219: los rotables cambian de un
    /// bloque al siguiente y el mismo bloque sale igual).
    public func generate(
        profile: OnboardingProfile,
        catalog: ExerciseCatalog,
        planner: BlockPlanner,
        blockID: TrainingBlockID? = nil,
        blockSequence: Int = 0,
        emphasis: [MuscleGroup] = []
    ) throws -> BlockPlanningResult {
        // SCRUM-205/210: músculos con énfasis (los que eligió la persona avanzada y los que
        // la IA propuso y se aceptaron); el motor decide cuántas series implica.
        var input = try makeInput(profile: profile, catalog: catalog.exercises, emphasis: profile.priorityMuscles + emphasis)
        input.blockID = blockID
        input.blockSequence = blockSequence
        do {
            return try planner.plan(input: input)
        } catch {
            throw TodayPlanError.cannotBuildBlock("\(error)")
        }
    }

    /// Deriva lo que "Hoy" muestra a partir de un bloque ya generado (o recuperado del disco).
    public func todayPlan(
        profile: OnboardingProfile,
        block: TrainingBlock,
        explanation: BlockExplanation,
        catalog: ExerciseCatalog,
        driver: TodayScreenDriver,
        date: Date,
        timeZone: TimeZone,
        readiness: ReadinessAdjustment = .none,
        customOrders: [SessionTemplate.ID: [ExerciseID]] = [:],
        timeBudget: Int? = nil,
        planner: BlockPlanner? = nil
    ) throws -> TodayPlan {
        // SCRUM-211: el orden propio de cada sesión se aplica encima del bloque del motor.
        let block = SessionOrderOverride.apply(customOrders, to: block)
        let jointClasses = Dictionary(catalog.exercises.map { ($0.id, $0.jointClass) }, uniquingKeysWith: { first, _ in first })
        // SCRUM-203: el check-in de sueño sólo aligera la sesión de hoy (mismo ID).
        let lightened = try todaySession(
            from: block.sessions,
            profile: profile,
            date: date,
            timeZone: timeZone
        ).map { ReadinessEngine().apply(readiness, to: $0, jointClass: { jointClasses[$0] }) }
        // SCRUM-30: y el tiempo que la persona dice tener la ajusta encima (mismo ID).
        var todayTemplate = lightened
        var timeAdjustment: SessionTimeAdjustment?
        if let lightened, let timeBudget {
            let roles = try timeRoles(
                for: lightened, profile: profile, block: block, catalog: catalog, planner: planner ?? Self.defaultPlanner()
            )
            let fitted = timeFitter.fit(lightened, budgetMinutes: timeBudget, roles: roles, goal: profile.goal, phase: profile.phase)
            todayTemplate = fitted.template
            timeAdjustment = fitted.adjustment
        }
        let estimatedMinutes = todayTemplate.map(timeFitter.minutes(of:))
        let state = driver.derive(
            todayTemplate: todayTemplate,
            activeSession: nil,
            estimatedMinutes: estimatedMinutes
        )
        let orderExplanation = todayTemplate.flatMap { template in
            explanation.sessionOrder.first { $0.sessionTitle == template.title }
        }
        return TodayPlan(
            block: block,
            sessions: block.sessions,
            todayTemplate: todayTemplate,
            estimatedMinutes: estimatedMinutes,
            todayState: state,
            todayExercises: exerciseLines(for: todayTemplate, catalog: catalog, profile: profile),
            todayOrder: orderLines(for: orderExplanation, catalog: catalog),
            todayOrderReorderedByFatigue: orderExplanation?.reorderedByFatigue ?? false,
            explanation: explanation,
            readiness: readiness,
            todayOrderIsCustom: todayTemplate.map { customOrders[$0.id] != nil } ?? false,
            timeAdjustment: timeAdjustment
        )
    }

    /// Papel de cada ejercicio al recortar por tiempo (SCRUM-30): las anclas son las del
    /// motor (una por músculo), son prioritarios los de músculos con énfasis y opcionales
    /// los que sólo calientan o movilizan. Lo demás es accesorio.
    public func timeRoles(
        for template: SessionTemplate,
        profile: OnboardingProfile,
        block: TrainingBlock,
        catalog: ExerciseCatalog,
        planner: BlockPlanner
    ) throws -> SessionTimeRoles {
        let anchors = planner.anchorExercises(input: try makeInput(profile: profile, catalog: catalog.exercises))
        let emphasized = Set(block.priorities.filter { $0.priority.rawValue >= PriorityTier.emphasize.rawValue }.map(\.muscleGroupID))
        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var roles = SessionTimeRoles(anchors: anchors)
        for id in Set(template.plannedSets.map(\.exerciseID)) {
            guard let exercise = exercises[id] else { continue }
            if exercise.primaryMuscles.contains(where: { emphasized.contains($0.muscleGroupID) }) {
                roles.priority.insert(id)
            }
            if !exercise.defaultRoles.isEmpty, exercise.defaultRoles.isSubset(of: [.warmup, .mobility]) {
                roles.optional.insert(id)
            }
        }
        return roles
    }

    /// Filas "¿Por qué este orden?" a partir de la explicación guardada del planificador.
    func orderLines(for explanation: SessionOrderExplanation?, catalog: ExerciseCatalog) -> [TodayOrderLine] {
        guard let explanation else { return [] }
        let names = Dictionary(catalog.exercises.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
        return explanation.entries.map { entry in
            var reasons: [TodayOrderReason] = []
            for fact in entry.facts {
                switch fact.key {
                case "exercise.order.role": reasons.append(.functionalRole)
                case "exercise.order.musclePriority": reasons.append(.musclePriority)
                case "exercise.order.skillDemand": reasons.append(.technicalDemand)
                default: break
                }
            }
            return TodayOrderLine(exerciseID: entry.exerciseID, name: names[entry.exerciseID], rank: entry.rank, reasons: reasons)
        }
    }

    /// Ejercicios de la plantilla en orden de aparición, con su número de series, series de
    /// trabajo y rango de repeticiones (el más amplio si las series difieren).
    /// Con `profile`, cada línea dice además si conviene dropset (SCRUM-200: lo decide
    /// `IntensityAdvisor` con la experiencia y las restricciones activas de la persona).
    func exerciseLines(
        for template: SessionTemplate?,
        catalog: ExerciseCatalog,
        profile: OnboardingProfile? = nil,
        intensityAdvisor: IntensityAdvisor = IntensityAdvisor()
    ) -> [TodayExerciseLine] {
        guard let template else { return [] }
        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rirs: [ExerciseID: ClosedRange<Int>] = [:]
        var order: [ExerciseID] = []
        var counts: [ExerciseID: Int] = [:]
        var workCounts: [ExerciseID: Int] = [:]
        var ranges: [ExerciseID: ClosedRange<Int>] = [:]
        for planned in template.plannedSets {
            if counts[planned.exerciseID] == nil { order.append(planned.exerciseID) }
            counts[planned.exerciseID, default: 0] += 1
            guard !planned.prescription.isWarmup else { continue }
            workCounts[planned.exerciseID, default: 0] += 1
            if rirs[planned.exerciseID] == nil, let rir = planned.prescription.targetRIR {
                rirs[planned.exerciseID] = rir
            }
            let range = planned.prescription.targetRepRange
            if let current = ranges[planned.exerciseID] {
                ranges[planned.exerciseID] = min(current.lowerBound, range.lowerBound)...max(current.upperBound, range.upperBound)
            } else {
                ranges[planned.exerciseID] = range
            }
        }
        return order.map { id in
            let exercise = exercises[id]
            let dropset = exercise.flatMap { exercise in
                profile.map { profile in
                    intensityAdvisor.advice(
                        for: exercise,
                        experience: profile.experience,
                        isRestricted: IntensityAdvisor.isRestricted(exercise, by: profile.restrictions)
                    ).dropset
                }
            }
            return TodayExerciseLine(
                exerciseID: id, name: exercise?.canonicalName, setCount: counts[id] ?? 0,
                workSetCount: workCounts[id] ?? 0, repRange: ranges[id],
                jointClass: exercise?.jointClass,
                targetRIR: rirs[id],
                dropset: dropset
            )
        }
    }

    // MARK: - Defaults

    /// Planner por defecto con la configuración de volumen versionada (testable).
    public static func defaultPlanner() -> BlockPlanner {
        BlockPlanner(volumeAllocator: VolumeAllocator(config: try! VolumeConfig(rule: VolumeDefaults.makeRule())))
    }

    /// Prioridades por defecto: los 8 grupos principales a `.normal`, y pantorrilla y core a
    /// `.maintain` (SCRUM-215) para que el plan no los deje fuera.
    public func defaultPriorities() -> [MusclePriority] {
        [
            MusclePriority(muscleGroupID: .chest, priority: .normal),
            MusclePriority(muscleGroupID: .back, priority: .normal),
            MusclePriority(muscleGroupID: .shoulders, priority: .normal),
            MusclePriority(muscleGroupID: .biceps, priority: .normal),
            MusclePriority(muscleGroupID: .triceps, priority: .normal),
            MusclePriority(muscleGroupID: .quadriceps, priority: .normal),
            MusclePriority(muscleGroupID: .hamstrings, priority: .normal),
            MusclePriority(muscleGroupID: .glutes, priority: .normal),
            MusclePriority(muscleGroupID: .calves, priority: .maintain),
            MusclePriority(muscleGroupID: .core, priority: .maintain),
        ]
    }

    /// Seed básico de equipment de gimnasio (documentado).
    public func defaultEquipmentKnownness() -> EquipmentKnownness {
        .knownAvailable([.barbell, .dumbbell, .machine, .smithMachine, .cable, .bodyweight])
    }

    // MARK: - Helpers

    private func makeInput(
        profile: OnboardingProfile,
        catalog: [Exercise],
        emphasis: [MuscleGroup] = []
    ) throws -> BlockPlanningInput {
        BlockPlanningInput(
            goal: profile.goal,
            phase: profile.phase,
            experience: profile.experience,
            trainingDaysPerWeek: profile.trainingDaysPerWeek,
            priorities: PlanPersonalizationApplier.priorities(defaultPriorities(), emphasizing: emphasis),
            plannedWeeks: 6,
            varietyPreference: profile.varietyPreference,
            catalog: catalog,
            restrictions: profile.restrictions,
            equipmentKnownness: defaultEquipmentKnownness(),
            sessionMinutes: profile.usualSessionMinutes
        )
    }

    /// Elige la plantilla de hoy con la semana del dominio (`TrainingWeek`, SCRUM-27).
    private func todaySession(
        from sessions: [SessionTemplate],
        profile: OnboardingProfile,
        date: Date,
        timeZone: TimeZone
    ) throws -> SessionTemplate? {
        guard !sessions.isEmpty else { return nil }
        let week: TrainingWeek
        do {
            week = try profile.trainingWeek()
        } catch {
            throw TodayPlanError.invalidInput
        }
        let dayIndex = TrainingWeek.dayIndex(for: date, timeZone: timeZone)
        guard let slot = week.sessionSlot(dayIndex: dayIndex) else { return nil }
        return sessions[slot % sessions.count]
    }
}

/// Aviso breve que "Hoy" muestra cuando la app tocó el plan por su cuenta.
public enum TodayPlanNotice: Equatable, Sendable {
    /// Un plan guardado con un generador anterior (volumen inflado, ejercicios genéricos) se regeneró,
    /// conservando el ID del bloque.
    case planUpdated
}

/// Lo que la pantalla "Hoy" puede mostrar (SCRUM-193). Mientras el plan no está listo es
/// `loading`: nunca se presenta como día de descanso un plan que todavía no existe.
public enum TodayScreen: Equatable, Sendable {
    /// El plan se está leyendo o generando.
    case loading
    /// Plan listo: estado derivado del día (descanso, lista para empezar o en curso).
    case ready(TodayScreenState)
    /// No se pudo generar el plan; se puede reintentar.
    case failed
}

/// En qué va la generación del plan (SCRUM-193). Sólo pasos que ocurren de verdad: la UI
/// los marca conforme se cumplen y nunca alarga la espera.
public enum PlanGeneration: Equatable, Sendable {
    /// Nada en curso.
    case idle
    /// Leyendo el plan anterior del disco.
    case reading
    /// Repartiendo el volumen y ordenando los ejercicios del bloque.
    case generating
    /// La IA propone ajustes y el motor los valida (SCRUM-205). Sólo con consentimiento.
    case personalizing
    /// Guardando el bloque en el dispositivo.
    case saving
    /// El último intento no pudo generar el plan.
    case failed
}

/// Qué encontró la app al intentar recordar el plan del usuario.
public enum PlanRestoreOutcome: Equatable, Sendable {
    /// Primer arranque de este usuario: falta el cuestionario.
    case none
    /// Plan recuperado: se entra directo a "Hoy".
    case restored(OnboardingProfile)
    /// El perfil o el bloque guardados no se pueden leer: se ofrece rehacer el cuestionario.
    case unreadable
}

/// Coordinador observable del plan de hoy para la UI (vía composition root).
@MainActor
@Observable
public final class TodayPlanCoordinator {
    /// Plan derivado más reciente; `nil` mientras no haya perfil completo.
    public private(set) var plan: TodayPlan?
    /// Aviso para mostrar una vez (p. ej. el plan se actualizó).
    public private(set) var notice: TodayPlanNotice?
    /// `true` si el último guardado del plan falló (el plan sigue usable en memoria).
    public private(set) var saveFailed = false
    /// En qué va la generación del plan (SCRUM-193).
    public private(set) var generation: PlanGeneration = .idle
    /// Historial de entrenamientos del usuario ("Tu semana" y "última vez", SCRUM-197).
    public private(set) var history: [WorkoutSessionRecord] = []
    /// "Última vez" por ejercicio (M1), derivada del historial.
    public private(set) var lastPerformance: [ExerciseID: LastPerformance] = [:]
    /// Cómo fue la última lectura del historial (Progreso, SCRUM-186).
    public private(set) var historyStatus: HistoryStatus = .notLoaded
    /// Títulos de las plantillas conocidas (bloque activo y anteriores) para nombrar cada
    /// entrenamiento del historial aunque el plan haya cambiado.
    private var knownTemplateTitles: [SessionTemplate.ID: String] = [:]

    /// Lo que muestra Progreso: el registro desde el primer entrenamiento completado.
    public var progress: ProgressScreen {
        switch historyStatus {
        case .notLoaded:
            return .loading
        case .failed:
            return .failed
        case .loaded(let unreadable):
            var titles = knownTemplateTitles
            for session in plan?.sessions ?? [] { titles[session.id] = session.title }
            let names = Dictionary(catalog.exercises.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
            let overview = ProgressOverviewBuilder().overview(
                history: history,
                templateTitles: titles,
                exerciseNames: names,
                plannedPerWeek: activeProfile?.trainingDaysPerWeek,
                blockStart: plan?.block.startDate,
                date: clock(),
                timeZone: timeZone()
            )
            return overview.entries.isEmpty
                ? .empty(unreadable: unreadable)
                : .loaded(overview, unreadable: unreadable)
        }
    }

    /// "Tu semana" del plan activo (lunes a domingo); `nil` sin plan.
    public var week: WeekOverview? {
        guard let plan, let activeProfile else { return nil }
        // El día de hoy, como se va a entrenar: con el check-in de sueño y el tiempo
        // elegido (SCRUM-30). Su "Empezar" abre exactamente esa sesión.
        var block = plan.block
        if let today = plan.todayTemplate, let index = block.sessions.firstIndex(where: { $0.id == today.id }) {
            block.sessions[index] = today
        }
        return WeekOverviewBuilder().overview(
            profile: activeProfile,
            block: block,
            explanation: plan.explanation ?? BlockExplanation(facts: [], ruleReferences: []),
            catalog: catalog,
            history: history,
            date: clock(),
            timeZone: timeZone()
        )
    }

    /// Lo que "Hoy" debe mostrar. Sin plan (o con uno nuevo en camino) es `loading`,
    /// nunca descanso por defecto.
    public var screen: TodayScreen {
        switch generation {
        case .reading, .generating, .personalizing, .saving: return .loading
        case .failed: return .failed
        case .idle: return plan.map { .ready($0.todayState) } ?? .loading
        }
    }

    private let builder: TodayPlanBuilder
    private let catalog: ExerciseCatalog
    private let planner: BlockPlanner
    private let driver: TodayScreenDriver
    private let clock: () -> Date
    private let timeZone: () -> TimeZone
    private let planStore: PlanStore?
    private let saveClock: () -> Date
    /// Perfil con el que se armó `plan`; evita regenerar al volver a entrar con el mismo.
    private var activeProfile: OnboardingProfile?
    /// Ajuste del día vigente (SCRUM-203). Se aplica cada vez que se arma "Hoy".
    public private(set) var readiness: ReadinessAdjustment = .none
    /// Usuario del plan activo (para buscar plantillas de bloques anteriores).
    private var activeUserID: String?

    /// Personalización del plan activo y "Por qué tu plan es así" (SCRUM-205).
    public private(set) var personalization: PlanPersonalizationRecord?
    /// Orden propio de los ejercicios por sesión (SCRUM-211); se aplica encima del bloque.
    private var customOrders: [SessionTemplate.ID: [ExerciseID]] = [:]
    /// Bloque tal como lo armó el motor (sin órdenes propios): base para restablecer.
    private var engineBlock: TrainingBlock?
    /// Tiempo que la persona eligió para hoy (SCRUM-30). Se guarda con el plan; sólo
    /// aplica el día en que se eligió.
    public private(set) var timeChoice: SessionTimeChoice?
    /// Quién habla con la IA; `nil` = sólo motor local.
    private let personalizer: (any PlanPersonalizing)?
    /// Datos del perfil para la IA; `nil` sin consentimiento (entonces no se manda nada).
    private let profileContext: (OnboardingProfile) -> AgentProfileContext?
    private let flow: PlanPersonalizationFlow?
    private let newConversationID: () -> UUID

    public init(
        builder: TodayPlanBuilder = TodayPlanBuilder(),
        catalog: ExerciseCatalog,
        planner: BlockPlanner? = nil,
        driver: TodayScreenDriver = TodayScreenDriver(),
        planStore: PlanStore? = nil,
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current },
        personalizer: (any PlanPersonalizing)? = nil,
        profileContext: @escaping (OnboardingProfile) -> AgentProfileContext? = { _ in nil },
        newConversationID: @escaping () -> UUID = { UUID() }
    ) {
        self.personalizer = personalizer
        self.profileContext = profileContext
        self.newConversationID = newConversationID
        // Sin reglas de política válidas no hay personalización: el plan sigue siendo el del motor.
        self.flow = (try? PlanPersonalizationValidator.standard()).map { PlanPersonalizationFlow(validator: $0) }
        self.builder = builder
        self.catalog = catalog
        self.planner = planner ?? TodayPlanBuilder.defaultPlanner()
        self.driver = driver
        self.planStore = planStore
        self.clock = clock
        self.saveClock = { Date() }
        self.timeZone = timeZone
    }

    /// Deriva el plan a partir del perfil, SIN persistir (determinista; falla si no se puede).
    public func load(profile: OnboardingProfile) -> Bool {
        do {
            plan = try builder.plan(
                profile: profile,
                catalog: catalog,
                planner: planner,
                driver: driver,
                date: clock(),
                timeZone: timeZone()
            )
            personalization = plan?.explanation.map { localPersonalization(facts: $0.facts) }
            customOrders = [:]
            engineBlock = plan?.block
            activeProfile = profile
            generation = .idle
            return true
        } catch {
            plan = nil
            generation = .failed
            return false
        }
    }

    /// Olvida el plan EN MEMORIA (cambio de sesión). El disco no se toca.
    public func reset() {
        plan = nil
        notice = nil
        personalization = nil
        customOrders = [:]
        engineBlock = nil
        timeChoice = nil
        activeProfile = nil
        activeUserID = nil
        generation = .idle
        history = []
        lastPerformance = [:]
        historyStatus = .notLoaded
        knownTemplateTitles = [:]
    }

    /// Historial leído del disco (lo pasa la capa de app): alimenta "Tu semana" y "última vez".
    public func updateHistory(
        _ sessions: [WorkoutSessionRecord],
        unreadable: Int = 0,
        knownTemplates: [SessionTemplate] = []
    ) {
        history = sessions
        lastPerformance = LastPerformanceIndex.build(from: sessions)
        for template in knownTemplates { knownTemplateTitles[template.id] = template.title }
        historyStatus = .loaded(unreadable: unreadable)
    }

    /// El historial no se pudo leer (SCRUM-186). Si ya había uno en memoria se sigue
    /// mostrando; si no, Progreso dice que falló y ofrece reintentar.
    public func historyLoadFailed() {
        if case .notLoaded = historyStatus { historyStatus = .failed }
    }

    /// Recalcula el estado de "Hoy" según haya o no un entrenamiento vivo (SCRUM-24): con
    /// uno en curso Hoy ofrece "Continuar" en lugar de "Empezar". `nil` = sin entrenamiento vivo.
    public func refreshState(activeSession: WorkoutSessionRecord?) {
        guard let current = plan else { return }
        let template = activeSession.flatMap { session in
            current.todayTemplate?.id == session.templateID
                ? current.todayTemplate
                : current.sessions.first { $0.id == session.templateID }
        } ?? current.todayTemplate
        let state = driver.derive(
            todayTemplate: template,
            activeSession: activeSession,
            estimatedMinutes: current.estimatedMinutes
        )
        plan = TodayPlan(
            block: current.block,
            sessions: current.sessions,
            todayTemplate: current.todayTemplate,
            estimatedMinutes: current.estimatedMinutes,
            todayState: state,
            todayExercises: current.todayExercises,
            todayOrder: current.todayOrder,
            todayOrderReorderedByFatigue: current.todayOrderReorderedByFatigue,
            explanation: current.explanation,
            readiness: current.readiness,
            todayOrderIsCustom: current.todayOrderIsCustom,
            timeAdjustment: current.timeAdjustment
        )
    }

    /// Plantillas conocidas del usuario: las del bloque activo y las de bloques anteriores.
    /// Sirve para retomar una sesión que se empezó con un plan que ya cambió.
    public func allKnownTemplates() async -> [SessionTemplate] {
        // La sesión de hoy va primero: si el check-in la aligeró, se retoma tal cual se empezó.
        var templates = (plan?.todayTemplate).map { [$0] } ?? []
        templates.append(contentsOf: plan?.sessions ?? [])
        if let planStore, let activeUserID,
           case .loaded(let stored, _) = await planStore.loadPlan(userID: activeUserID) {
            for block in await planStore.blockHistory(of: stored) {
                templates.append(contentsOf: block.sessions)
            }
        }
        return templates
    }

    /// Descarta el aviso ya mostrado.
    public func dismissNotice() {
        notice = nil
    }

    // MARK: - SCRUM-26: recordar el plan

    /// Intenta recuperar el plan guardado de `userID` (también sin internet: sólo lee disco).
    /// Si el plan se guardó con un generador anterior se regenera conservando el ID del bloque.
    public func restore(userID: String) async -> PlanRestoreOutcome {
        guard let planStore else { return .none }
        activeUserID = userID
        switch await planStore.loadPlan(userID: userID) {
        case .none:
            return .none
        case .unreadable:
            return .unreadable
        case .loaded(var stored, var block):
            var explanation = stored.explanation
            if stored.needsMigration {
                // La personalización aceptada se conserva: mismo énfasis y mismas sustituciones
                // si siguen siendo válidas sobre el bloque regenerado.
                guard let regenerated = try? regenerateKeepingPersonalization(stored, blockID: block.id)
                else { return .unreadable }
                var migrated = regenerated.block
                migrated.startDate = block.startDate
                migrated.status = block.status
                block = migrated
                explanation = regenerated.explanation
                stored.generatorVersion = StoredPlan.currentGeneratorVersion
                stored.explanation = explanation
                // Sesiones nuevas: los órdenes propios de las anteriores ya no aplican.
                stored.customOrders = nil
                stored.updatedAt = saveClock()
                await persist(stored, block: block, closing: nil, store: planStore)
                notice = .planUpdated
            }
            customOrders = stored.sessionOrders
            engineBlock = block
            timeChoice = stored.timeBudget
            guard let today = try? todayPlan(profile: stored.profile, block: block, explanation: explanation)
            else { return .unreadable }
            plan = today
            personalization = stored.personalization ?? localPersonalization(facts: explanation.facts)
            activeProfile = stored.profile
            generation = .idle
            return .restored(stored.profile)
        }
    }

    /// Activa el plan del perfil recién contestado y lo guarda para `userID`.
    /// - Sin plan previo: bloque nuevo.
    /// - Mismo perfil: no cambia nada.
    /// - Cambió objetivo, fase o días: bloque nuevo; el anterior se cierra y se conserva.
    /// - Cambió otra cosa: se regenera el mismo bloque.
    /// Devuelve `false` si no se pudo generar el plan (nunca inventa uno).
    @discardableResult
    public func activate(profile: OnboardingProfile, userID: String?) async -> Bool {
        if activeProfile == profile, plan != nil {
            generation = .idle
            return true
        }
        if let activeProfile, plan != nil, activeProfile.trainingFields == profile.trainingFields {
            // Sólo cambió "Sobre ti" (SCRUM-198): se guarda el perfil; el bloque no cambia y
            // Hoy no pasa por "cargando".
            return await saveProfileOnly(profile, userID: userID)
        }
        guard let userID, let planStore else {
            return load(profile: profile)
        }
        activeUserID = userID
        // Mientras llega el plan nuevo, "Hoy" muestra carga (nunca el plan anterior ni descanso).
        generation = .reading
        let previous: (plan: StoredPlan, block: TrainingBlock)?
        let replacesUnreadable: Bool
        switch await planStore.loadPlan(userID: userID) {
        case .loaded(let stored, let block):
            previous = (stored, block)
            replacesUnreadable = false
        case .none:
            previous = nil
            replacesUnreadable = false
        case .unreadable:
            previous = nil
            replacesUnreadable = true
        }
        let change = previous.map { PlanChangeDecider.decide(old: $0.plan.profile, new: profile) } ?? .newBlock
        do {
            switch change {
            case .unchanged:
                guard let previous else { return failActivation() }
                personalization = previous.plan.personalization ?? localPersonalization(facts: previous.plan.explanation.facts)
                customOrders = previous.plan.sessionOrders
                engineBlock = previous.block
                timeChoice = previous.plan.timeBudget
                plan = try todayPlan(profile: profile, block: previous.block, explanation: previous.plan.explanation)
                activeProfile = profile
                generation = .idle
                return true
            case .updateProfileOnly:
                guard let previous else { return failActivation() }
                var stored = previous.plan
                stored.profile = profile
                stored.updatedAt = saveClock()
                generation = .saving
                await persist(stored, block: previous.block, closing: nil, store: planStore)
                personalization = stored.personalization ?? localPersonalization(facts: stored.explanation.facts)
                customOrders = stored.sessionOrders
                try show(profile: profile, block: previous.block, explanation: previous.plan.explanation)
                return true
            case .regenerateInPlace:
                guard let previous else { return failActivation() }
                generation = .generating
                let sequence = previous.plan.blockSequence(of: previous.block.id)
                let base = try builder.generate(
                    profile: profile, catalog: catalog, planner: planner, blockID: previous.block.id, blockSequence: sequence
                )
                let personalized = try await personalize(base, profile: profile, blockID: previous.block.id, blockSequence: sequence)
                let result = personalized.result
                var block = result.block
                block.startDate = previous.block.startDate
                block.status = previous.block.status
                var stored = previous.plan
                stored.profile = profile
                stored.generatorVersion = StoredPlan.currentGeneratorVersion
                stored.explanation = result.explanation
                stored.personalization = personalized.record
                // Sesiones regeneradas: los órdenes propios de las anteriores ya no aplican.
                stored.customOrders = nil
                stored.updatedAt = saveClock()
                personalization = personalized.record
                customOrders = [:]
                generation = .saving
                await persist(stored, block: block, closing: nil, store: planStore)
                try show(profile: profile, block: block, explanation: result.explanation)
                return true
            case .newBlock:
                // SCRUM-223: el plan ilegible se guarda intacto antes de escribir encima; si
                // no se puede, no se escribe nada (la activación falla y se puede reintentar).
                let rescuedHistory = replacesUnreadable
                    ? try planStore.preserveUnreadablePlan(userID: userID).blockHistory
                    : []
                generation = .generating
                // El bloque nuevo va al final del historial: sus rotables cambian frente al anterior.
                let history = previous?.plan.blockHistory ?? rescuedHistory
                let base = try builder.generate(profile: profile, catalog: catalog, planner: planner, blockSequence: history.count)
                let personalized = try await personalize(base, profile: profile, blockID: base.block.id, blockSequence: history.count)
                let result = personalized.result
                var block = result.block
                block.status = .active
                // El bloque empieza "hoy" según el reloj de la app (no el de pared): así la
                // semana del bloque y sus récords cuadran con -PRFixedDate y el demo (SCRUM-188).
                block.startDate = clock()
                var closed: TrainingBlock?
                if var old = previous?.block {
                    old.status = .completed
                    closed = old
                }
                let stored = StoredPlan(
                    userID: userID,
                    profile: profile,
                    activeBlockID: block.id,
                    blockHistory: history + [block.id],
                    explanation: result.explanation,
                    updatedAt: saveClock(),
                    personalization: personalized.record
                )
                personalization = personalized.record
                customOrders = [:]
                // Plan nuevo: el tiempo elegido para hoy no viaja (el disco tampoco lo tiene).
                timeChoice = nil
                generation = .saving
                await persist(stored, block: block, closing: closed, store: planStore)
                try show(profile: profile, block: block, explanation: result.explanation)
                return true
            }
        } catch {
            return failActivation()
        }
    }

    /// SCRUM-205: motor → IA → validación → motor. Sin consentimiento o sin IA, el plan del
    /// motor con la explicación local (no se manda nada). El paso "Personalizando con IA"
    /// sólo se muestra cuando de verdad se le pregunta a la IA.
    private func personalize(
        _ base: BlockPlanningResult,
        profile: OnboardingProfile,
        blockID: TrainingBlockID,
        blockSequence: Int
    ) async throws -> PersonalizedPlan {
        guard let flow else {
            return PersonalizedPlan(
                result: base, record: localPersonalization(facts: base.explanation.facts), rationaleFallback: .notRequested
            )
        }
        let context = profileContext(profile)
        if context != nil, personalizer != nil { generation = .personalizing }
        let builder = builder, catalog = catalog, planner = planner
        return try await flow.personalize(
            base: base,
            context: context,
            personalizer: personalizer,
            catalog: catalog.exercises,
            restrictions: profile.restrictions,
            equipment: builder.defaultEquipmentKnownness(),
            conversationID: newConversationID(),
            now: saveClock(),
            regenerate: { emphasis in
                try builder.generate(
                    profile: profile, catalog: catalog, planner: planner, blockID: blockID, blockSequence: blockSequence, emphasis: emphasis
                )
            }
        )
    }

    /// Regenera un plan guardado (migración) conservando lo que la IA personalizó y se aceptó.
    private func regenerateKeepingPersonalization(_ stored: StoredPlan, blockID: TrainingBlockID) throws -> BlockPlanningResult {
        let decisions = stored.personalization?.decisions.filter(\.isAccepted) ?? []
        let emphasis = decisions.compactMap { decision -> MuscleGroup? in
            guard case .emphasize(let muscle) = decision.adjustment else { return nil }
            return muscle
        }
        let substitutions = decisions.compactMap { decision -> ProposedSubstitution? in
            guard case .substitute(let substitution) = decision.adjustment else { return nil }
            return substitution
        }
        let regenerated = try builder.generate(
            profile: stored.profile, catalog: catalog, planner: planner, blockID: blockID,
            blockSequence: stored.blockSequence(of: blockID), emphasis: emphasis
        )
        guard !substitutions.isEmpty, let flow else { return regenerated }
        let review = try flow.validator.reviewSubstitutions(
            substitutions, block: regenerated.block, catalog: catalog.exercises,
            activeRestrictions: stored.profile.restrictions, equipment: builder.defaultEquipmentKnownness(),
            conversationID: newConversationID(), now: saveClock()
        )
        return BlockPlanningResult(
            block: PlanPersonalizationApplier.substituting(review.acceptedSubstitutions, in: regenerated.block),
            explanation: regenerated.explanation,
            split: regenerated.split
        )
    }

    private func localPersonalization(facts: [DecisionFact]) -> PlanPersonalizationRecord {
        PlanPersonalizationRecord(
            decisions: [],
            rationale: PlanRationalePresenter().lines(facts: facts, emphasis: [], substitutions: []),
            rationaleSource: .local,
            audit: []
        )
    }

    private func show(profile: OnboardingProfile, block: TrainingBlock, explanation: BlockExplanation) throws {
        engineBlock = block
        plan = try todayPlan(profile: profile, block: block, explanation: explanation)
        activeProfile = profile
        generation = .idle
    }

    /// "Hoy" sobre `block` con todo lo del día: check-in de sueño, órdenes propios y el
    /// tiempo elegido si es de hoy.
    private func todayPlan(profile: OnboardingProfile, block: TrainingBlock, explanation: BlockExplanation) throws -> TodayPlan {
        let now = clock()
        let zone = timeZone()
        return try builder.todayPlan(
            profile: profile, block: block, explanation: explanation,
            catalog: catalog, driver: driver, date: now, timeZone: zone, readiness: readiness, customOrders: customOrders,
            timeBudget: timeChoice.flatMap { $0.applies(on: now, timeZone: zone) ? $0.minutes : nil },
            planner: planner
        )
    }

    /// Vuelve a armar "Hoy" sobre el mismo bloque (el bloque guardado no cambia).
    private func rebuildToday() {
        guard let current = plan, let profile = activeProfile, let explanation = current.explanation else { return }
        if let today = try? todayPlan(profile: profile, block: engineBlock ?? current.block, explanation: explanation) {
            plan = today
        }
    }

    /// SCRUM-203: aplica el ajuste del día (check-in de sueño) y vuelve a armar "Hoy" sobre
    /// el mismo bloque. El bloque guardado no cambia. Sin plan, sólo recuerda el ajuste.
    public func applyReadiness(_ adjustment: ReadinessAdjustment) {
        readiness = adjustment
        rebuildToday()
    }

    // MARK: - SCRUM-30: ajustar la sesión a mi tiempo

    /// Ajusta la sesión de hoy a `minutes` (`nil` quita el ajuste). Guarda primero y sólo
    /// entonces cambia "Hoy": si el disco falla, el ajuste anterior sigue y se informa
    /// (`saveFailed`). Con un entrenamiento en curso no se cambia: esa sesión ya empezó con
    /// su plantilla y retomarla debe dar la misma. `false` si no se aplicó.
    @discardableResult
    public func setTimeBudget(_ minutes: Int?) async -> Bool {
        if case .activeWorkout = plan?.todayState { return false }
        let choice: SessionTimeChoice?
        if let minutes {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone()
            guard let made = SessionTimeChoice(minutes: minutes, day: calendar.startOfDay(for: clock())) else { return false }
            choice = made
        } else {
            choice = nil
        }
        if let planStore, let activeUserID {
            guard case .loaded(var stored, let block) = await planStore.loadPlan(userID: activeUserID) else {
                saveFailed = true
                return false
            }
            stored.timeBudget = choice
            stored.updatedAt = saveClock()
            do {
                try await planStore.save(plan: stored, block: block, closing: nil)
                saveFailed = false
            } catch {
                saveFailed = true
                return false
            }
        }
        timeChoice = choice
        rebuildToday()
        return true
    }

    // MARK: - SCRUM-211: orden propio de los ejercicios

    /// ¿La sesión tiene un orden elegido por la persona?
    public func hasCustomOrder(_ templateID: SessionTemplate.ID) -> Bool {
        customOrders[templateID] != nil
    }

    /// Guarda el orden propio de una sesión. Sólo acepta una permutación exacta de sus
    /// ejercicios (no agrega ni quita); la prescripción no cambia. `false` si no se pudo.
    @discardableResult
    public func reorderSession(_ templateID: SessionTemplate.ID, to order: [ExerciseID]) async -> Bool {
        guard let template = (engineBlock ?? plan?.block)?.sessions.first(where: { $0.id == templateID }),
              SessionOrderOverride.isPermutation(order, of: template) else { return false }
        var updated = customOrders
        // Volver exactamente al del motor es lo mismo que restablecer.
        updated[templateID] = order == SessionOrderOverride.exerciseOrder(of: template) ? nil : order
        return await commitOrders(updated)
    }

    /// Vuelve al orden recomendado de la sesión.
    @discardableResult
    public func resetSessionOrder(_ templateID: SessionTemplate.ID) async -> Bool {
        var updated = customOrders
        updated[templateID] = nil
        return await commitOrders(updated)
    }

    /// Guarda primero y sólo entonces cambia "Hoy": si el disco falla, el orden anterior
    /// sigue vigente y se informa (`saveFailed`).
    private func commitOrders(_ orders: [SessionTemplate.ID: [ExerciseID]]) async -> Bool {
        if let planStore, let activeUserID {
            guard case .loaded(var stored, let block) = await planStore.loadPlan(userID: activeUserID) else {
                saveFailed = true
                return false
            }
            stored.customOrders = orders.isEmpty ? nil : Dictionary(uniqueKeysWithValues: orders.map { ($0.key.uuidString, $0.value) })
            stored.updatedAt = saveClock()
            do {
                try await planStore.save(plan: stored, block: block, closing: nil)
                saveFailed = false
            } catch {
                saveFailed = true
                return false
            }
        }
        customOrders = orders
        rebuildToday()
        return true
    }

    /// Guarda el perfil con su "Sobre ti" nuevo sobre el mismo bloque (SCRUM-198).
    private func saveProfileOnly(_ profile: OnboardingProfile, userID: String?) async -> Bool {
        activeProfile = profile
        guard let userID, let planStore,
              case .loaded(var stored, let block) = await planStore.loadPlan(userID: userID) else {
            return true
        }
        stored.profile = profile
        stored.updatedAt = saveClock()
        await persist(stored, block: block, closing: nil, store: planStore)
        return true
    }

    /// No se pudo generar el plan: se dice (nunca se inventa uno ni se muestra descanso).
    private func failActivation() -> Bool {
        plan = nil
        generation = .failed
        return false
    }

    /// Guarda y deja constancia si falló: el error no se traga (se expone en `saveFailed`).
    private func persist(_ stored: StoredPlan, block: TrainingBlock, closing: TrainingBlock?, store: PlanStore) async {
        do {
            try await store.save(plan: stored, block: block, closing: closing)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}
