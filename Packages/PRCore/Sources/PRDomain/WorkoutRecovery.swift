//
//  WorkoutRecovery.swift
//  PRDomain
//
//  SCRUM-24: qué hacer, al abrir la app, con las sesiones de entrenamiento que quedaron
//  sin cerrar (cierre forzado, batería, crash). Puro y determinista: recibe las sesiones
//  guardadas y la hora actual, devuelve qué restaurar y qué registros actualizar. Nunca
//  borra series: abandonar o completar sólo cambia el estado y la hora de fin.
//

import Foundation

/// Descanso guardado como HORA DE FIN (no como contador): sobrevive al cierre de la app
/// porque lo que queda se calcula contra el reloj.
public struct RestSnapshot: Codable, Sendable, Equatable, Hashable {
    public var recommendedSeconds: Int
    public var startedAt: Date?
    public var endDate: Date?

    public init(recommendedSeconds: Int, startedAt: Date?, endDate: Date?) {
        self.recommendedSeconds = recommendedSeconds
        self.startedAt = startedAt
        self.endDate = endDate
    }

    public init(_ state: RestTimerState) {
        self.init(recommendedSeconds: state.recommendedSeconds, startedAt: state.startedAt, endDate: state.endDate)
    }

    /// Estado del temporizador a la hora `now`: si la hora de fin ya pasó, el descanso
    /// terminó (queda inactivo: 0 s restantes y la siguiente serie lista).
    public func timerState(at now: Date) -> RestTimerState {
        guard let endDate, endDate > now else { return RestTimerState(recommendedSeconds: recommendedSeconds) }
        return RestTimerState(recommendedSeconds: recommendedSeconds, endDate: endDate, startedAt: startedAt)
    }
}

/// Resultado de revisar las sesiones guardadas.
public struct WorkoutRecoveryPlan: Equatable, Sendable {
    /// La sesión a retomar ("Tienes un entrenamiento en curso"), si hay.
    public let restore: WorkoutSessionRecord?
    /// Registros cuyo estado cambió y hay que guardar (sesiones extra abandonadas, etc.).
    public let updates: [WorkoutSessionRecord]
    /// Cuántas sesiones activas SOBRABAN (más de una activa es un error que se registra).
    public let extraActiveCount: Int

    public init(restore: WorkoutSessionRecord?, updates: [WorkoutSessionRecord], extraActiveCount: Int) {
        self.restore = restore
        self.updates = updates
        self.extraActiveCount = extraActiveCount
    }
}

public struct WorkoutRecoveryPlanner: Sendable {

    public init() {}

    /// - `active`/`paused`: candidatas a retomar. Si hay varias, se retoma la MÁS RECIENTE
    ///   y las demás pasan a `abandoned` con sus series intactas.
    /// - `finishing`: el cierre quedó a medias ⇒ se completa.
    /// - `planned`/`preparing`: nunca empezaron ⇒ se abandonan.
    /// - `completed`/`abandoned`: no se tocan.
    public func plan(for sessions: [WorkoutSessionRecord], now: Date) -> WorkoutRecoveryPlan {
        var live: [WorkoutSessionRecord] = []
        var updates: [WorkoutSessionRecord] = []

        for session in sessions {
            switch session.lifecycle {
            case .active, .paused:
                live.append(session)
            case .finishing:
                updates.append(closed(session, as: .completed, at: now))
            case .planned, .preparing:
                updates.append(closed(session, as: .abandoned, at: now))
            case .completed, .abandoned:
                break
            }
        }

        // Más reciente primero; el desempate por id mantiene el resultado determinista.
        live.sort {
            $0.startedAt != $1.startedAt
                ? $0.startedAt > $1.startedAt
                : $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        let restore = live.first
        let extras = live.dropFirst()
        updates.append(contentsOf: extras.map { closed($0, as: .abandoned, at: now) })
        return WorkoutRecoveryPlan(restore: restore, updates: updates, extraActiveCount: extras.count)
    }

    private func closed(_ session: WorkoutSessionRecord, as target: WorkoutLifecycleState, at now: Date) -> WorkoutSessionRecord {
        var copy = session
        // Las transiciones desde estos estados son válidas (lo garantiza el `switch` de `plan`);
        // si el modelo cambiara, se fuerza el estado final en lugar de dejar la sesión abierta.
        do {
            try copy.transition(to: target)
        } catch {
            copy.lifecycle = target
        }
        copy.endedAt = copy.endedAt ?? now
        copy.rest = nil
        return copy
    }
}
