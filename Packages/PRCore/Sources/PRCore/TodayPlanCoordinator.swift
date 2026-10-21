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

    /// Construye el `TodayPlan` para hoy a partir del perfil de onboarding.
    public func plan(
        profile: OnboardingProfile,
        catalog: ExerciseCatalog,
        planner: BlockPlanner,
        driver: TodayScreenDriver,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> TodayPlan {
        let input = try makeInput(profile: profile, catalog: catalog.exercises)
        let result: BlockPlanningResult
        do {
            result = try planner.plan(input: input)
        } catch {
            throw TodayPlanError.cannotBuildBlock("\(error)")
        }

        let block = result.block
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
            result.explanation.sessionOrder.first { $0.sessionTitle == template.title }
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

/// Coordinador observable del plan de hoy para la UI (vía composition root).
@MainActor
@Observable
public final class TodayPlanCoordinator {
    /// Plan derivado más reciente; `nil` mientras no haya perfil completo.
    public private(set) var plan: TodayPlan?

    private let builder: TodayPlanBuilder
    private let catalog: ExerciseCatalog
    private let planner: BlockPlanner
    private let driver: TodayScreenDriver
    private let clock: () -> Date
    private let timeZone: () -> TimeZone

    public init(
        builder: TodayPlanBuilder = TodayPlanBuilder(),
        catalog: ExerciseCatalog,
        planner: BlockPlanner? = nil,
        driver: TodayScreenDriver = TodayScreenDriver(),
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.builder = builder
        self.catalog = catalog
        self.planner = planner ?? TodayPlanBuilder.defaultPlanner()
        self.driver = driver
        self.clock = clock
        self.timeZone = timeZone
    }

    /// Deriva el plan a partir del perfil (determinista; falla si no se puede).
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
            return true
        } catch {
            plan = nil
            return false
        }
    }
}