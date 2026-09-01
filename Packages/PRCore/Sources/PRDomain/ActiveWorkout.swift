//
//  ActiveWorkout.swift
//  PRDomain
//
//  Created by PR.
//
//  Active workout state machine service (plan §8, PR-0602). Gestiona el ciclo
//  de vida de un entrenamiento activo: start/pause/resume/finish/abandon con
//  transiciones validadas, y ofrece un snapshot persistible para restaurar un
//  workout activo tras kill/relaunch sin perder datos. Determinista y sin lógica
//  en Views.
//

import Foundation

/// Snapshot persistible de un workout activo (para restaurar tras relaunch).
public struct ActiveWorkoutSnapshot: Codable, Sendable, Hashable {
    public let session: WorkoutSessionRecord
    /// Última vez que se transicionó (referencia para timers/UI).
    public let lastTransitionAt: Date

    public init(session: WorkoutSessionRecord, lastTransitionAt: Date = Date()) {
        self.session = session
        self.lastTransitionAt = lastTransitionAt
    }

    /// ¿Puede restaurarse como workout activo? (los estados terminales no).
    public var isRestorable: Bool {
        switch session.lifecycle {
        case .completed, .abandoned: return false
        default: return true
        }
    }
}

/// Estado del servicio de workout activo.
public struct ActiveWorkoutState: Codable, Sendable, Hashable {
    public var session: WorkoutSessionRecord
    public var lastTransitionAt: Date

    public init(session: WorkoutSessionRecord, lastTransitionAt: Date = Date()) {
        self.session = session
        self.lastTransitionAt = lastTransitionAt
    }
}

/// Problemas del controlador de workout activo.
public enum ActiveWorkoutError: Error, Equatable, Sendable {
    case noActiveWorkout
    case alreadyActive
    case invalidTransition(from: String)
    case notRestorable
}

/// Controla el ciclo de vida de un entrenamiento activo (plan §8, PR-0602).
///
/// Reglas deterministas:
/// - `start` abre un workout nuevo (no se puede sobrescribir otro activo).
/// - `pause`/`resume`/`finish`/`abandon` validan la transición; el registro de lo
///   realizado no se muta.
/// - `finish`/`abandon` transicionan al workout; no borran historial previo.
/// - `snapshot`/`restore` permiten persistir y recuperar el workout activo tras
///   kill/relaunch, respetando estados terminales (no restaurables).
public struct ActiveWorkoutController: Sendable {
    private var state: ActiveWorkoutState?

    public init(state: ActiveWorkoutState? = nil) {
        self.state = state
    }

    public var current: ActiveWorkoutState? { state }

    public var isActive: Bool {
        guard let state else { return false }
        switch state.session.lifecycle {
        case .completed, .abandoned: return false
        default: return true
        }
    }

    /// Abre un workout activo desde una plantilla. Falla si ya hay uno activo.
    @discardableResult
    public mutating func start(from template: SessionTemplate? = nil, at now: Date = Date()) throws -> ActiveWorkoutState {
        guard !isActive else { throw ActiveWorkoutError.alreadyActive }
        let session = WorkoutSessionRecord(
            templateID: template?.id,
            startedAt: now,
            lifecycle: .active
        )
        let state = ActiveWorkoutState(session: session, lastTransitionAt: now)
        self.state = state
        return state
    }

    /// Pausa el workout activo.
    @discardableResult
    public mutating func pause(at now: Date = Date()) throws -> ActiveWorkoutState {
        try transition(to: .paused, now: now)
    }

    /// Reanuda el workout activo.
    @discardableResult
    public mutating func resume(at now: Date = Date()) throws -> ActiveWorkoutState {
        try transition(to: .active, now: now)
    }

    /// Inicia el cierre del workout activo (paso previo a completar).
    @discardableResult
    public mutating func finish(at now: Date = Date()) throws -> ActiveWorkoutState {
        try transition(to: .finishing, now: now)
    }

    /// Confirma el cierre: marca el workout como completado.
    @discardableResult
    public mutating func complete(at now: Date = Date()) throws -> ActiveWorkoutState {
        try transition(to: .completed, now: now)
    }

    /// Abandona el workout activo (no borra los sets ya realizados).
    @discardableResult
    public mutating func abandon(at now: Date = Date()) throws -> ActiveWorkoutState {
        try transition(to: .abandoned, now: now)
    }

    /// Snapshot persistible del workout activo (para restaurar tras relaunch).
    public func snapshot() throws -> ActiveWorkoutSnapshot {
        guard let state else { throw ActiveWorkoutError.noActiveWorkout }
        return ActiveWorkoutSnapshot(session: state.session, lastTransitionAt: state.lastTransitionAt)
    }

    /// Restaura un workout activo desde un snapshot tras relaunch.
    public static func restore(from snapshot: ActiveWorkoutSnapshot) throws -> ActiveWorkoutController {
        guard snapshot.isRestorable else { throw ActiveWorkoutError.notRestorable }
        return ActiveWorkoutController(
            state: ActiveWorkoutState(session: snapshot.session, lastTransitionAt: snapshot.lastTransitionAt)
        )
    }

    // MARK: - Helpers

    private mutating func transition(to target: WorkoutLifecycleState, now: Date) throws -> ActiveWorkoutState {
        guard var state else { throw ActiveWorkoutError.noActiveWorkout }
        do {
            try state.session.transition(to: target)
        } catch {
            throw ActiveWorkoutError.invalidTransition(from: state.session.lifecycle.rawValue)
        }
        state.lastTransitionAt = now
        self.state = state
        return state
    }
}