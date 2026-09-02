//
//  HealthLiveWorkout.swift
//  PRCore
//
//  Created by PR.
//
//  Live HealthKit workout lifecycle (plan §14 Fase 11, §32.3, PR-1202). Encapsula el
//  ciclo start/pause/resume/end de un workout con `HKLiveWorkoutBuilder` como una
//  state machine determinista detrás de un protocolo, para que los tests NO dependan
//  de HealthKit real (§7). PRCore NO importa HealthKit: la app del Watch inyecta un
//  `LiveWorkoutBuilder` de producción que gestiona `HKWorkoutSession`/`HKLiveWorkoutBuilder`;
//  aquí viven la máquina de estados, el snapshot de métricas y el contrato.
//

import Foundation
import PRDomain

/// Estado del lifecycle de un workout en vivo (PR-1202). Transiciones inválidas se
/// rechazan; la sesión no puede terminar dos veces ni reanudar sin estar en pausa,
/// y un error terminal deja la sesión en un estado final que conserva el resumen
/// parcial (los sets locales de PR ya están persistidos por PR-0602).
public enum HealthLiveWorkoutState: Equatable, Sendable {
    /// Sin workout live iniciado.
    case idle
    /// Workout iniciado y recopilando (running).
    case running
    /// Workout en pausa (seguirá acumulando al reanudar).
    case paused
    /// Workout finalizado con éxito.
    case ended
    /// Workout finalizado con fallo. Conserva cualquier métrica parcial ya capturada.
    case failed(reason: String)

    /// States alcanzables directamente desde el actual (por shape del estado).
    public var allowedNext: [HealthLiveWorkoutState] {
        switch isKind {
        case .idle: return [.running]
        case .running: return [.paused, .ended, .failed(reason: "")]
        case .paused: return [.running, .ended, .failed(reason: "")]
        case .ended: return []
        case .failed: return []
        }
    }

    public func canTransition(to next: HealthLiveWorkoutState) -> Bool {
        allowedNext.contains { $0.isKind == next.isKind }
    }

    /// Si el workout está en marcha y recopilando métricas.
    public var isLive: Bool { self == .running }

    /// Estado terminal (no se puede continuar).
    public var isTerminal: Bool {
        self == .ended || self.isFailed
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Shape del estado ignorando el payload de error (para la tabla de transiciones).
    private var isKind: HealthLiveWorkoutKind {
        switch self {
        case .idle: return .idle
        case .running: return .running
        case .paused: return .paused
        case .ended: return .ended
        case .failed: return .failed
        }
    }

    private enum HealthLiveWorkoutKind: String, Equatable {
        case idle
        case running
        case paused
        case ended
        case failed
    }

    @discardableResult
    public func transitioning(to next: HealthLiveWorkoutState) throws -> HealthLiveWorkoutState {
        guard canTransition(to: next) else {
            let from = isKind.rawValue
            throw DomainValidationError.invalidStateTransition(from: from, to: next.isKind.rawValue)
        }
        return next
    }
}

/// Snapshot de métricas en vivo (PR-1202). Con origen measured/estimated para que la
/// UI del Watch muestre la procedencia y NUNCA sume energy estimada como medida
/// (§11 doble-conteo). Sólo contexto; nunca diagnóstico.
public struct HealthLiveMetrics: Equatable, Sendable {
    public var activeKilocalories: Double?
    public var energyOrigin: MeasurementOrigin
    public var heartRateBPM: Double?
    public var heartRateOrigin: MeasurementOrigin

    public init(
        activeKilocalories: Double? = nil,
        energyOrigin: MeasurementOrigin? = nil,
        heartRateBPM: Double? = nil,
        heartRateOrigin: MeasurementOrigin? = nil
    ) {
        self.activeKilocalories = activeKilocalories
        self.energyOrigin = energyOrigin ?? (activeKilocalories == nil ? .unavailable : .measured)
        self.heartRateBPM = heartRateBPM
        self.heartRateOrigin = heartRateOrigin ?? (heartRateBPM == nil ? .unavailable : .measured)
    }
}

/// Eventos que notifica el adaptador de `HKWorkoutSession`/`HKLiveWorkoutBuilder`
/// (PR-1202). La state machine los reduce en orden; eventos inválidos se rechazan.
public enum HealthLiveWorkoutEvent: Equatable, Sendable {
    case didStart
    case didPause
    case didResume
    case didUpdateMetrics(HealthLiveMetrics)
    case didEnd(HealthLiveMetrics)
    case didFail(reason: String)
}

/// Reducer determinista del ciclo de vida del workout live (PR-1202).
///
/// Reglas:
/// - sólo `running` acumula; `didUpdateMetrics`/`didEnd` fuera de `running`/`paused`
///   no mutan el estado;
/// - `didPause` sólo desde `running`; `didResume` sólo desde `paused`;
/// - `didEnd`/`didFail` son terminales; eventos posteriores se ignoran (no rebotan);
/// - un fallo conserva el último snapshot de métricas capturado (§7, §14.4).
public struct HealthLiveWorkoutStateMachine: Sendable {
    public private(set) var state: HealthLiveWorkoutState
    public private(set) var lastMetrics: HealthLiveMetrics

    public init(state: HealthLiveWorkoutState = .idle, lastMetrics: HealthLiveMetrics = HealthLiveMetrics()) {
        self.state = state
        self.lastMetrics = lastMetrics
    }

    /// Reduce un evento del adaptador y devuelve el nuevo estado. Eventos inválidos
    /// lanzan `HealthLiveWorkoutError.invalidTransition`; los eventos ajenos al estado
    /// (p. ej. métricas mientras `idle`) se ignoran sin error.
    public mutating func apply(_ event: HealthLiveWorkoutEvent) throws {
        switch event {
        case .didStart:
            state = try state.transitioning(to: .running)
        case .didPause:
            state = try state.transitioning(to: .paused)
        case .didResume:
            state = try state.transitioning(to: .running)
        case .didUpdateMetrics(let metrics):
            guard state == .running || state == .paused else { return }
            lastMetrics = metrics
        case .didEnd(let metrics):
            guard state == .running || state == .paused else {
                throw HealthLiveWorkoutError.invalidEnd
            }
            lastMetrics = metrics
            state = .ended
        case .didFail(let reason):
            guard state == .running || state == .paused else {
                throw HealthLiveWorkoutError.alreadyEnded
            }
            state = .failed(reason: reason)
        }
    }
}

/// Errores del lifecycle de un workout live (PR-1202). Passthrough de errores de
/// HealthKit se tipan para que la UI los presente sin filtrar stack details.
public enum HealthLiveWorkoutError: Error, Equatable, Sendable {
    /// Transición no permitida desde el estado actual.
    case invalidTransition
    /// Se intentó finalizar una sesión nunca iniciada.
    case notStarted
    /// Finalización doble: la sesión ya terminó.
    case invalidEnd
    /// La sesión ya está en estado terminal.
    case alreadyEnded
    /// Fallo de la infraestructura (adaptador HealthKit), sin datos sensibles.
    case infrastructure(String)
}

/// Contrato del adaptador del workout live (PR-1202). La app del Watch lo implementa
/// gestionando `HKWorkoutSession`/`HKLiveWorkoutBuilder` reales. Los tests usan un
/// fake y un `HealthLiveWorkoutStateMachine` (nunca HealthKit real, §7).
public protocol LiveWorkoutBuilder: Sendable {
    /// Inicia la sesión live. Lanza `HealthLiveWorkoutError` si HealthKit falla.
    func start() async throws
    /// Pausa la sesión live. Sólo tiene efecto si está corriendo.
    func pause() async throws
    /// Reanuda la sesión live. Sólo tiene efecto si está pausada.
    func resume() async throws
    /// Finaliza la sesión live y devuelve el resumen final (métricas).
    func end() async throws -> HealthLiveMetrics
}

/// Coordinador del workout live (PR-1202): orquesta el adaptador de infraestructura y
/// la state machine con value semantics (inmutable). Cada operación toma la máquina de
/// estados actual y devuelve la actualizada, de modo que reanudar/finalizar respete el
/// ciclo y un fallo de HealthKit jamás deje la sesión en un estado inconsistente. La
/// UI del Watch (MainActor) decide cuándo consultar el estado; aquí nada coalesce.
public nonisolated struct HealthLiveWorkoutCoordinator: Sendable {
    public let builder: any LiveWorkoutBuilder

    public init(builder: any LiveWorkoutBuilder) {
        self.builder = builder
    }

    /// Inicia el workout live. Devuelve la máquina de estados actualizada.
    public func start(stateMachine: HealthLiveWorkoutStateMachine) async throws -> HealthLiveWorkoutStateMachine {
        guard stateMachine.state == .idle else {
            throw HealthLiveWorkoutError.invalidTransition
        }
        do {
            try await builder.start()
        } catch {
            var next = stateMachine
            try next.apply(.didFail(reason: "\(error)"))
            throw HealthLiveWorkoutError.infrastructure("\(error)")
        }
        var next = stateMachine
        try next.apply(.didStart)
        return next
    }

    /// Pausa el workout live. Devuelve la máquina de estados actualizada.
    public func pause(stateMachine: HealthLiveWorkoutStateMachine) async throws -> HealthLiveWorkoutStateMachine {
        do {
            try await builder.pause()
        } catch {
            throw HealthLiveWorkoutError.infrastructure("\(error)")
        }
        var next = stateMachine
        try next.apply(.didPause)
        return next
    }

    /// Reanuda un workout live pausado. Devuelve la máquina de estados actualizada.
    public func resume(stateMachine: HealthLiveWorkoutStateMachine) async throws -> HealthLiveWorkoutStateMachine {
        do {
            try await builder.resume()
        } catch {
            throw HealthLiveWorkoutError.infrastructure("\(error)")
        }
        var next = stateMachine
        try next.apply(.didResume)
        return next
    }

    /// Finaliza el workout live. Devuelve las métricas finales y la máquina actualizada.
    public func end(stateMachine: HealthLiveWorkoutStateMachine) async throws -> (HealthLiveMetrics, HealthLiveWorkoutStateMachine) {
        do {
            let metrics = try await builder.end()
            var next = stateMachine
            try next.apply(.didEnd(metrics))
            return (metrics, next)
        } catch {
            var next = stateMachine
            try next.apply(.didFail(reason: "\(error)"))
            throw HealthLiveWorkoutError.infrastructure("\(error)")
        }
    }
}