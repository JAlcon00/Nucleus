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

/// Plan derivado para la pantalla "Hoy": bloque generado + plantilla de hoy + estado.
public struct TodayPlan: Equatable, Sendable {
    public let block: TrainingBlock
    public let sessions: [SessionTemplate]
    public let todayTemplate: SessionTemplate?
    public let estimatedMinutes: Int?
    public let todayState: TodayScreenState

    public init(
        block: TrainingBlock,
        sessions: [SessionTemplate],
        todayTemplate: SessionTemplate?,
        estimatedMinutes: Int?,
        todayState: TodayScreenState
    ) {
        self.block = block
        self.sessions = sessions
        self.todayTemplate = todayTemplate
        self.estimatedMinutes = estimatedMinutes
        self.todayState = todayState
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
/// - Rotación semanal: los primeros `trainingDaysPerWeek` días laborables (lun..dom)
///   son días de entrenamiento; el resto son descanso. La plantilla del día se elige
///   rotando sobre las sesiones planificadas del bloque.
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
        date: Date = Date()
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
            date: date
        )
        let state = driver.derive(
            todayTemplate: todayTemplate,
            activeSession: nil,
            estimatedMinutes: estimatedMinutes
        )
        return TodayPlan(
            block: block,
            sessions: block.sessions,
            todayTemplate: todayTemplate,
            estimatedMinutes: estimatedMinutes,
            todayState: state
        )
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
            equipmentKnownness: defaultEquipmentKnownness()
        )
    }

    /// Elige la plantilla de hoy por rotación determinista sobre los días de la semana.
    private func todaySession(
        from sessions: [SessionTemplate],
        trainingDaysPerWeek: Int,
        date: Date
    ) throws -> SessionTemplate? {
        guard !sessions.isEmpty else { return nil }
        let weekdayIndex = try weekdayIndex(for: date)
        // Los primeros N días laborables son días de entrenamiento.
        guard weekdayIndex < trainingDaysPerWeek else { return nil }
        return sessions[weekdayIndex % sessions.count]
    }

    /// Calendario fijo (gregoriano, lunes como primer día) para una determinación
    /// reproducible del día de hoy independiente del entorno.
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // lunes
        return cal
    }()

    private func weekdayIndex(for date: Date) throws -> Int {
        if Self.calendar.component(.weekday, from: date) == 1 {
            // Domingo descartado por el esquema (primeros N días laborables = lun..); si
            // el calendario devuelve 1 (domingo en firstWeekday=2) lo tratamos como último.
            return 6
        }
        // weekday con firstWeekday=2 (lunes): lunes=1 ... sábado=6, domingo=7.
        let weekday = Self.calendar.component(.weekday, from: date)
        return weekday - 1
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

    public init(
        builder: TodayPlanBuilder = TodayPlanBuilder(),
        catalog: ExerciseCatalog,
        planner: BlockPlanner? = nil,
        driver: TodayScreenDriver = TodayScreenDriver()
    ) {
        self.builder = builder
        self.catalog = catalog
        self.planner = planner ?? TodayPlanBuilder.defaultPlanner()
        self.driver = driver
    }

    /// Deriva el plan a partir del perfil (determinista; falla si no se puede).
    public func load(profile: OnboardingProfile) -> Bool {
        do {
            plan = try builder.plan(
                profile: profile,
                catalog: catalog,
                planner: planner,
                driver: driver
            )
            return true
        } catch {
            plan = nil
            return false
        }
    }
}