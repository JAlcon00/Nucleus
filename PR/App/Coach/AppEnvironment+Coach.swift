//
//  AppEnvironment+Coach.swift
//  PR
//
//  SCRUM-275 (PR-I006) y SCRUM-276 (PR-I007): la app le da al entrenador
//  (`CoachConversationCoordinator`, PRCore) lo que ya sabe hacer, con los coordinadores que
//  ya existen. Nada se decide aquí: el intérprete, la política y el motor viven en PRCore.
//  - El transporte se pide en cada mensaje: sin conexión o sin consentimiento no hay IA
//    (`AIConnection.coachTransport`, SCRUM-277) y responde el intérprete local (DI-1 A).
//  - Cada pantalla (Hoy y el entrenamiento) tiene su conversación en memoria (DI-5 A).
//

import Foundation
import PRCore
import PRDomain

/// Lo que el entrenador de una pantalla le pide a la app. El coordinador la guarda débil y
/// la app es dueña de las dos cosas.
@MainActor
final class CoachBridge: CoachActionHandling {
    private weak var environment: AppEnvironment?
    let surface: CoachSurface

    init(environment: AppEnvironment, surface: CoachSurface) {
        self.environment = environment
        self.surface = surface
    }

    func coachSnapshot() -> CoachSnapshot {
        environment?.coachSnapshot(for: surface) ?? CoachSnapshot(surface: surface)
    }

    func adjustTodaySession(minutes: Int?) async -> CoachTimeOutcome {
        await environment?.coachAdjustToday(minutes: minutes) ?? .saveFailed
    }

    func markCurrentExerciseOccupied() -> OccupiedOutcome? {
        environment?.coachMarkCurrentExerciseOccupied()
    }

    func selectGym(_ id: GymID) async -> Bool {
        await environment?.coachSelectGym(id) ?? false
    }
}

extension AppEnvironment {
    /// El transporte del entrenador para este mensaje: con IA en vivo y consentimiento,
    /// el LLM medido (SCRUM-273); si no, ninguno.
    var coachTransport: (any AgentBackendTransport)? {
        aiConnection.metered(.coachInterpret, by: usageRecorder).coachTransport(consent: aiConsent.consent)
    }

    /// Lo que el entrenador necesita saber de esa pantalla, con lo que la app ya tiene.
    func coachSnapshot(for surface: CoachSurface) -> CoachSnapshot {
        let gyms = gym.gyms.map { AgentGymContext(id: $0.id, name: $0.name) }
        let restrictions = completedProfile?.restrictions.filter { $0.status == .active }.count ?? 0
        switch surface {
        case .today:
            return CoachSnapshot(
                surface: .today,
                gyms: gyms,
                activeGymID: gym.activeGym?.id,
                decisions: todayPlan.todayDecisions,
                activeRestrictionCount: restrictions
            )
        case .workout:
            guard let workout = activeWorkout else {
                return CoachSnapshot(surface: .workout, gyms: gyms, activeGymID: gym.activeGym?.id, activeRestrictionCount: restrictions)
            }
            let current = workout.currentExerciseID.flatMap { id in
                catalog.exercises.first { $0.id == id }.map { AgentExerciseContext(id: id, equipment: $0.equipment, name: $0.canonicalName) }
            }
            let sets: [SetRecord]
            do {
                sets = try workout.snapshot().session.sets
            } catch {
                sets = []
            }
            let pain: ExplainableDecision?
            do {
                pain = try workout.painDecision()
            } catch {
                pain = nil
            }
            return CoachSnapshot(
                surface: .workout,
                currentExercise: current,
                gyms: gyms,
                activeGymID: gym.activeGym?.id,
                decisions: [workout.suggestedLoadDecision, pain].compactMap { $0 },
                recentPain: sets.compactMap(\.painFeedback),
                activeRestrictionCount: restrictions,
                hasCompletedSet: !sets.isEmpty
            )
        }
    }

    /// SCRUM-30 desde el entrenador: el mismo ajuste que el menú de tiempo de Hoy.
    func coachAdjustToday(minutes: Int?) async -> CoachTimeOutcome {
        guard activeWorkout == nil else { return .workoutInProgress }
        if let minutes, !TrainingWeek.allowedSessionMinutes.contains(minutes) { return .outOfRange }
        guard await todayPlan.setTimeBudget(minutes) else {
            return todayPlan.saveFailed ? .saveFailed : .workoutInProgress
        }
        refreshTodayState()
        let time = todayPlan.todayDecisions.first { $0.topic == .timeFit }
        return .adjusted(time.map { DecisionExplanationPresenter(locale: Self.presentationLocale).explanation(for: $0) })
    }

    /// SCRUM-233 desde el entrenador: lo mismo que el botón "Máquina ocupada".
    func coachMarkCurrentExerciseOccupied() -> OccupiedOutcome? {
        guard let workout = activeWorkout else { return nil }
        do {
            return try workout.markCurrentExerciseOccupied()
        } catch {
            return nil
        }
    }

    /// SCRUM-238 desde el entrenador: cambiar al gimnasio con ese nombre.
    func coachSelectGym(_ id: GymID) async -> Bool {
        let saved = await gym.select(id, duringWorkout: activeWorkout != nil)
        if saved { applyGym() }
        return saved
    }
}
