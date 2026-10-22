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
    public let setCount: Int
    public var id: ExerciseID { exerciseID }

    public init(exerciseID: ExerciseID, name: String?, setCount: Int) {
        self.exerciseID = exerciseID
        self.name = name
        self.setCount = setCount
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

    public init(
        block: TrainingBlock,
        sessions: [SessionTemplate],
        todayTemplate: SessionTemplate?,
        estimatedMinutes: Int?,
        todayState: TodayScreenState,
        todayExercises: [TodayExerciseLine] = [],
        todayOrder: [TodayOrderLine] = [],
        todayOrderReorderedByFatigue: Bool = false
    ) {
        self.block = block
        self.sessions = sessions
        self.todayTemplate = todayTemplate
        self.estimatedMinutes = estimatedMinutes
        self.todayState = todayState
        self.todayExercises = todayExercises
        self.todayOrder = todayOrder
        self.todayOrderReorderedByFatigue = todayOrderReorderedByFatigue
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
/// - Rotación semanal (`TrainingWeek`, SCRUM-27): los primeros `trainingDaysPerWeek`
///   días desde el lunes son de entrenamiento y cada uno tiene su slot 0…N-1; el resto
///   es descanso. La plantilla del día es `sessions[slot % sessions.count]`.
/// - Duración estimada: `profile.usualSessionMinutes` (estimación del usuario; el
///   cálculo por ejercicio real es PR-0801).
public struct TodayPlanBuilder: Sendable {

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

    /// Genera un bloque para el perfil. `blockID` conserva la identidad al regenerar.
    public func generate(
        profile: OnboardingProfile,
        catalog: ExerciseCatalog,
        planner: BlockPlanner,
        blockID: TrainingBlockID? = nil
    ) throws -> BlockPlanningResult {
        var input = try makeInput(profile: profile, catalog: catalog.exercises)
        input.blockID = blockID
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
        timeZone: TimeZone
    ) throws -> TodayPlan {
        let estimatedMinutes = profile.usualSessionMinutes
        let todayTemplate = try todaySession(
            from: block.sessions,
            trainingDaysPerWeek: profile.trainingDaysPerWeek,
            date: date,
            timeZone: timeZone
        )
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
            todayExercises: exerciseLines(for: todayTemplate, catalog: catalog),
            todayOrder: orderLines(for: orderExplanation, catalog: catalog),
            todayOrderReorderedByFatigue: orderExplanation?.reorderedByFatigue ?? false
        )
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

    /// Ejercicios de la plantilla en orden de aparición, con su número de series.
    func exerciseLines(for template: SessionTemplate?, catalog: ExerciseCatalog) -> [TodayExerciseLine] {
        guard let template else { return [] }
        let names = Dictionary(catalog.exercises.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
        var order: [ExerciseID] = []
        var counts: [ExerciseID: Int] = [:]
        for planned in template.plannedSets {
            if counts[planned.exerciseID] == nil { order.append(planned.exerciseID) }
            counts[planned.exerciseID, default: 0] += 1
        }
        return order.map { TodayExerciseLine(exerciseID: $0, name: names[$0], setCount: counts[$0] ?? 0) }
    }

    // MARK: - Defaults

    /// Planner por defecto con la configuración de volumen versionada (testable).
    public static func defaultPlanner() -> BlockPlanner {
        BlockPlanner(volumeAllocator: VolumeAllocator(config: try! VolumeConfig(rule: VolumeDefaults.makeRule())))
    }

    /// Prioridades por defecto: musculatura estándar del split a tier `.normal`.
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
        ]
    }

    /// Seed básico de equipment de gimnasio (documentado).
    public func defaultEquipmentKnownness() -> EquipmentKnownness {
        .knownAvailable([.barbell, .dumbbell, .machine, .cable, .bodyweight])
    }

    // MARK: - Helpers

    private func makeInput(
        profile: OnboardingProfile,
        catalog: [Exercise]
    ) throws -> BlockPlanningInput {
        BlockPlanningInput(
            goal: profile.goal,
            phase: profile.phase,
            experience: profile.experience,
            trainingDaysPerWeek: profile.trainingDaysPerWeek,
            priorities: defaultPriorities(),
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
        trainingDaysPerWeek: Int,
        date: Date,
        timeZone: TimeZone
    ) throws -> SessionTemplate? {
        guard !sessions.isEmpty else { return nil }
        let week: TrainingWeek
        do {
            week = try TrainingWeek(trainingDaysPerWeek: trainingDaysPerWeek)
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
    /// Usuario del plan activo (para buscar plantillas de bloques anteriores).
    private var activeUserID: String?

    public init(
        builder: TodayPlanBuilder = TodayPlanBuilder(),
        catalog: ExerciseCatalog,
        planner: BlockPlanner? = nil,
        driver: TodayScreenDriver = TodayScreenDriver(),
        planStore: PlanStore? = nil,
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
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
            activeProfile = profile
            return true
        } catch {
            plan = nil
            return false
        }
    }

    /// Olvida el plan EN MEMORIA (cambio de sesión). El disco no se toca.
    public func reset() {
        plan = nil
        notice = nil
        activeProfile = nil
        activeUserID = nil
    }

    /// Recalcula el estado de "Hoy" según haya o no un entrenamiento vivo (SCRUM-24): con
    /// uno en curso Hoy ofrece "Continuar" en lugar de "Empezar". `nil` = sin entrenamiento vivo.
    public func refreshState(activeSession: WorkoutSessionRecord?) {
        guard let current = plan else { return }
        let template = activeSession.flatMap { session in
            current.sessions.first { $0.id == session.templateID }
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
            todayOrderReorderedByFatigue: current.todayOrderReorderedByFatigue
        )
    }

    /// Plantillas conocidas del usuario: las del bloque activo y las de bloques anteriores.
    /// Sirve para retomar una sesión que se empezó con un plan que ya cambió.
    public func allKnownTemplates() async -> [SessionTemplate] {
        var templates = plan?.sessions ?? []
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
                guard let regenerated = try? builder.generate(
                    profile: stored.profile, catalog: catalog, planner: planner, blockID: block.id
                ) else { return .unreadable }
                var migrated = regenerated.block
                migrated.startDate = block.startDate
                migrated.status = block.status
                block = migrated
                explanation = regenerated.explanation
                stored.generatorVersion = StoredPlan.currentGeneratorVersion
                stored.explanation = explanation
                stored.updatedAt = saveClock()
                await persist(stored, block: block, closing: nil, store: planStore)
                notice = .planUpdated
            }
            guard let today = try? builder.todayPlan(
                profile: stored.profile, block: block, explanation: explanation,
                catalog: catalog, driver: driver, date: clock(), timeZone: timeZone()
            ) else { return .unreadable }
            plan = today
            activeProfile = stored.profile
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
        if activeProfile == profile, plan != nil { return true }
        guard let userID, let planStore else {
            return load(profile: profile)
        }
        activeUserID = userID
        let previous: (plan: StoredPlan, block: TrainingBlock)?
        switch await planStore.loadPlan(userID: userID) {
        case .loaded(let stored, let block): previous = (stored, block)
        case .none, .unreadable: previous = nil
        }
        let change = previous.map { PlanChangeDecider.decide(old: $0.plan.profile, new: profile) } ?? .newBlock
        do {
            switch change {
            case .unchanged:
                guard let previous else { return false }
                plan = try builder.todayPlan(
                    profile: profile, block: previous.block, explanation: previous.plan.explanation,
                    catalog: catalog, driver: driver, date: clock(), timeZone: timeZone()
                )
                activeProfile = profile
                return true
            case .regenerateInPlace:
                guard let previous else { return false }
                let result = try builder.generate(
                    profile: profile, catalog: catalog, planner: planner, blockID: previous.block.id
                )
                var block = result.block
                block.startDate = previous.block.startDate
                block.status = previous.block.status
                var stored = previous.plan
                stored.profile = profile
                stored.generatorVersion = StoredPlan.currentGeneratorVersion
                stored.explanation = result.explanation
                stored.updatedAt = saveClock()
                await persist(stored, block: block, closing: nil, store: planStore)
                try show(profile: profile, block: block, explanation: result.explanation)
                return true
            case .newBlock:
                let result = try builder.generate(profile: profile, catalog: catalog, planner: planner)
                var block = result.block
                block.status = .active
                var closed: TrainingBlock?
                if var old = previous?.block {
                    old.status = .completed
                    closed = old
                }
                let stored = StoredPlan(
                    userID: userID,
                    profile: profile,
                    activeBlockID: block.id,
                    blockHistory: (previous?.plan.blockHistory ?? []) + [block.id],
                    explanation: result.explanation,
                    updatedAt: saveClock()
                )
                await persist(stored, block: block, closing: closed, store: planStore)
                try show(profile: profile, block: block, explanation: result.explanation)
                return true
            }
        } catch {
            plan = nil
            return false
        }
    }

    private func show(profile: OnboardingProfile, block: TrainingBlock, explanation: BlockExplanation) throws {
        plan = try builder.todayPlan(
            profile: profile, block: block, explanation: explanation,
            catalog: catalog, driver: driver, date: clock(), timeZone: timeZone()
        )
        activeProfile = profile
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
