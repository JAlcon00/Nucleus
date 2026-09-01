//
//  RestTimer.swift
//  PRDomain
//
//  Created by PR.
//
//  Rest timer service (plan §8, RF-008, PR-0604). Inicia automáticamente el
//  descanso tras un working set cuando corresponde, permite skip/extend, no
//  bloquea la navegación (estado puro sin callbacks bloqueantes) y sobrevive al
//  background/relaunch gracias a un `endDate` anclado en wall-clock (el resto se
//  computa contra `Date()` en lectura, nunca contra ticks en memoria).
//

import Foundation

/// Estado del timer de descanso.
public struct RestTimerState: Equatable, Sendable {
    /// Segundos de descanso recomendados para el set siguiente.
    public var recommendedSeconds: Int
    /// Momento (wall-clock) en el que termina el descanso, si está activo.
    public var endDate: Date?
    /// Momento en el que se inició el descanso, si está activo.
    public var startedAt: Date?

    public init(recommendedSeconds: Int = 0, endDate: Date? = nil, startedAt: Date? = nil) {
        self.recommendedSeconds = recommendedSeconds
        self.endDate = endDate
        self.startedAt = startedAt
    }

    public var isActive: Bool { endDate != nil }

    /// Segundos restantes para `now`. 0 si no está activo o ya terminó.
    /// Se computa contra `now`, por lo que sobrevive background/relaunch: no
    /// depende de ticks acumulados en memoria.
    public func remaining(at now: Date = Date()) -> Int {
        guard let endDate else { return 0 }
        return max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    /// El descanso ha terminado en `now`.
    public func hasElapsed(at now: Date = Date()) -> Bool {
        guard let endDate else { return true }
        return now.timeIntervalSince(endDate) >= 0
    }
}

/// Servicio de timer de descanso (PR-0604).
///
/// Reglas deterministas:
/// - `autoStart` tras un working set (no warmup) con la duración recomendada desde
///   la prescripción; los warmups no inician descanso.
/// - `extend(by:)` prolonga el `endDate`; sólo tiene efecto si el timer está activo.
/// - `skip` cancela el descanso (vuelve a inactivo).
/// - Nada bloquea: el timer es un valor con `endDate`; la UI decide cuándo consultar
///   `remaining(at:)`. Sobrevive background vía wall-clock.
public struct RestTimer: Sendable {

    public init() {}

    /// Recomienda la duración (segundos) del descanso para una prescripción.
    public func recommendedSeconds(for prescription: SetPrescription) -> Int {
        prescription.restSeconds.lowerBound
    }

    /// Inicia automáticamente el descanso tras completar un set.
    /// `didCompleteWarmup = prescription.isWarmup` → no inicia.
    public func autoStart(
        afterCompletedWarmup isWarmup: Bool,
        prescription: SetPrescription,
        now: Date = Date()
    ) -> RestTimerState {
        guard !isWarmup else {
            return RestTimerState(recommendedSeconds: recommendedSeconds(for: prescription))
        }
        let seconds = recommendedSeconds(for: prescription)
        return RestTimerState(
            recommendedSeconds: seconds,
            endDate: now.addingTimeInterval(TimeInterval(seconds)),
            startedAt: now
        )
    }

    /// Prolonga el descanso activo por `seconds` adicionales.
    public func extend(_ current: RestTimerState, by seconds: Int, now: Date = Date()) -> RestTimerState {
        guard seconds > 0 else { return current }
        guard let endDate = current.endDate else { return current }
        return RestTimerState(
            recommendedSeconds: current.recommendedSeconds,
            endDate: endDate.addingTimeInterval(TimeInterval(seconds)),
            startedAt: current.startedAt
        )
    }

    /// Cancela el descanso activo.
    public func skip(_ current: RestTimerState) -> RestTimerState {
        RestTimerState(recommendedSeconds: current.recommendedSeconds)
    }
}