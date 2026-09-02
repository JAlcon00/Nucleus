//
//  HealthWorkout.swift
//  PRCore
//
//  Created by PR.
//
//  HealthKit workout store abstraction (plan §13 Fase 10, §32.3, PR-1102). PRCore
//  NO importa HealthKit: la app inyecta una implementación de producción que crea la
//  `HKWorkoutConfiguration` real y gestiona el ciclo del workout. Aquí vivien el
//  protocolo, la configuración transportable, el handle estable y el coordinador que
//  alinea HealthKit con el `WorkoutSessionRecord` local SIN que un error pierda su
//  sets ya registrados (§14.4). Determinista.
//

import Foundation
import PRDomain

/// Tipo de actividad del workout (configuración transportable; la app lo mapea a
/// `HKWorkoutConfiguration`/`HKWorkoutActivityType` correcto).
public enum HealthWorkoutActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case strengthTraining
}

/// Configuración del workout HealthKit (forma transportable; no importa HealthKit).
public struct HealthWorkoutConfiguration: Codable, Sendable, Hashable {
    public var activityType: HealthWorkoutActivityType
    /// ¿El workout se integra con un Apple Watch (HKLiveWorkoutBuilder)?
    public var supportsLiveWatchBuilder: Bool

    public init(
        activityType: HealthWorkoutActivityType = .strengthTraining,
        supportsLiveWatchBuilder: Bool = false
    ) {
        self.activityType = activityType
        self.supportsLiveWatchBuilder = supportsLiveWatchBuilder
    }
}

/// Handle estable devuelto por `startWorkout` y persistido en `WorkoutSessionRecord`.
/// Es la referencia asociada para reconciliar el registro propio con el `HKWorkout`.
public struct HealthWorkoutHandle: Codable, Sendable, Hashable, Identifiable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
        public let rawValue: UUID
        public init(rawValue: UUID) { self.rawValue = rawValue }
        public init() { self.rawValue = UUID() }
        public var id: UUID { rawValue }
    }

    public let id: ID

    public init(id: ID = ID()) {
        self.id = id
    }
}

/// Datos para finalizar un workout de HealthKit (entradas de la reconciliación §13).
public struct HealthWorkoutFinishInput: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var activeKilocalories: Double?
    public var activityType: HealthWorkoutActivityType

    public init(
        start: Date,
        end: Date,
        activeKilocalories: Double? = nil,
        activityType: HealthWorkoutActivityType = .strengthTraining
    ) {
        self.start = start
        self.end = end
        self.activeKilocalories = activeKilocalories
        self.activityType = activityType
    }
}

/// Origen de un dato del workout: marcado como medido por sensor o estimado (PR-1103).
public enum MeasurementOrigin: String, Codable, Sendable, CaseIterable, Hashable {
    /// Medido por sensor real (p. ej. energy activa del Apple Watch).
    case measured
    /// Estimado por una heurística/otra fuente local/móvil (NO debe sumarse como medida).
    case estimated
    /// No disponible o no autorizado.
    case unavailable
}

/// Resumen de HR del workout, sólo si está permitido/disponible (PR-1103).
/// Sólo contexto; nunca diagnóstico (§14.1).
public struct HealthWorkoutHeartRate: Codable, Sendable, Hashable {
    public var averageBPM: Double?
    public var peakBPM: Double?
    public var origin: MeasurementOrigin

    public init(averageBPM: Double? = nil, peakBPM: Double? = nil, origin: MeasurementOrigin = .unavailable) {
        self.averageBPM = averageBPM
        self.peakBPM = peakBPM
        self.origin = origin
    }
}

/// Resumen de un workout de HealthKit finalizado (PR-1103).
///
/// Incluye: duración, energy activa (sólo si disponible), resumen de HR (sólo si
/// permitido/disponible) y, para cada dato, origen `measured` vs `estimated` vs
/// `unavailable`. Determinista: la duración se deriva de `start`/`end`; la energy y
/// HR se propagan tal cual llegan del store. No se inventa ningún número.
public struct HealthWorkoutSummary: Codable, Sendable, Hashable {
    public var referenceID: HealthWorkoutHandle.ID
    public var start: Date
    public var end: Date
    /// Duración en segundos (derivada de start/end).
    public var durationSeconds: Int
    public var activeKilocalories: Double?
    /// Origen de la energy: measured/estimated/unavailable.
    public var energyOrigin: MeasurementOrigin
    /// Resumen de HR, nil si no permitido/disponible.
    public var heartRate: HealthWorkoutHeartRate?

    public init(
        referenceID: HealthWorkoutHandle.ID,
        start: Date,
        end: Date,
        activeKilocalories: Double? = nil,
        energyOrigin: MeasurementOrigin? = nil,
        heartRate: HealthWorkoutHeartRate? = nil
    ) {
        self.referenceID = referenceID
        self.start = start
        self.end = end
        self.durationSeconds = Int(max(0, end.timeIntervalSince(start)))
        self.activeKilocalories = activeKilocalories
        self.energyOrigin = energyOrigin ?? (activeKilocalories == nil ? .unavailable : .measured)
        self.heartRate = heartRate
    }
}

/// Workout de HealthKit de terceros (para reconciliación / lectura externa).
public struct ExternalWorkout: Codable, Sendable, Hashable {
    public var referenceID: HealthWorkoutHandle.ID
    public var start: Date
    public var end: Date
    public var activityType: HealthWorkoutActivityType
    public var activeKilocalories: Double?

    public init(
        referenceID: HealthWorkoutHandle.ID,
        start: Date,
        end: Date,
        activityType: HealthWorkoutActivityType,
        activeKilocalories: Double? = nil
    ) {
        self.referenceID = referenceID
        self.start = start
        self.end = end
        self.activityType = activityType
        self.activeKilocalories = activeKilocalories
    }
}

/// Almacén de workouts de HealthKit detrás de un protocolo (plan §13, §32.3).
public protocol HealthWorkoutStore: Sendable {
    /// Solicita autorización para los tipos mínimos (permisos granulares, PR-1101).
    func requestAuthorization() async throws -> HealthPermissionOutcome
    /// Inicia un workout de HealthKit con la configuración dada. Devuelve el handle estable.
    func startWorkout(configuration: HealthWorkoutConfiguration) async throws -> HealthWorkoutHandle
    /// Finaliza el workout referenciado.
    func finishWorkout(_ handle: HealthWorkoutHandle, with input: HealthWorkoutFinishInput) async throws -> HealthWorkoutSummary
    /// Lee workouts recientes de terceros (para reconciliación).
    func recentWorkouts() async throws -> [ExternalWorkout]
}

/// Problemas del coordinador de workouts de HealthKit.
public enum HealthWorkoutError: Error, Equatable, Sendable {
    case missingPermission
    case alreadyStarted
    case notStarted
    /// Fallo al completar el workout de HealthKit. Los sets locales ya registrados NO se pierden.
    case completionFailed(reason: String)
}

/// Coordina HealthKit con el `WorkoutSessionRecord` local (plan §13, PR-1102).
///
/// Garantías deterministas:
/// - `start` pide autorización, inicia el workout de HealthKit y asocia el handle
///   estable al `WorkoutSessionRecord` (referencia para reconciliar).
/// - Un error de HealthKit en `start` o `finish` NUNCA muta ni descarta los sets ya
///   registrados localmente (§14.4): las operaciones locales son independientes.
/// - `finish` requiere que el workout se haya iniciado (handle presente).
public nonisolated struct HealthWorkoutCoordinator: Sendable {
    public let store: any HealthWorkoutStore

    public init(store: any HealthWorkoutStore) {
        self.store = store
    }

    /// Autoriza (no-bloqueante) antes de iniciar.
    public func authorize() async throws -> HealthPermissionOutcome {
        try await store.requestAuthorization()
    }

    /// Inicia el workout de HealthKit y asocia el handle a la sesión local.
    /// Devuelve la sesión con la referencia asociada. No toca `sets` existentes.
    public func start(
        session: WorkoutSessionRecord,
        configuration: HealthWorkoutConfiguration = HealthWorkoutConfiguration()
    ) async throws -> WorkoutSessionRecord {
        let outcome = try await store.requestAuthorization()
        guard outcome.allGranted else {
            throw HealthWorkoutError.missingPermission
        }
        guard session.healthWorkoutReferenceID == nil else {
            throw HealthWorkoutError.alreadyStarted
        }
        let handle = try await store.startWorkout(configuration: configuration)
        var updated = session
        updated.healthWorkoutReferenceID = handle.id.rawValue
        return updated
    }

    /// Finaliza el workout de HealthKit. Un fallo no elimina los sets locales.
    public func finish(
        session: WorkoutSessionRecord,
        completedAt end: Date = Date(),
        activeKilocalories: Double? = nil
    ) async throws -> WorkoutSessionRecord {
        guard let rawID = session.healthWorkoutReferenceID else {
            throw HealthWorkoutError.notStarted
        }
        let handle = HealthWorkoutHandle(id: HealthWorkoutHandle.ID(rawValue: rawID))
        do {
            _ = try await store.finishWorkout(
                handle,
                with: HealthWorkoutFinishInput(
                    start: session.startedAt,
                    end: end,
                    activeKilocalories: activeKilocalories
                )
            )
        } catch {
            // La sesión local permanece intacta (sets conservados). El error queda
            // tipado para que la UI lo presente, sin tocar los datos locales.
            throw HealthWorkoutError.completionFailed(reason: "\(error)")
        }
        // La sesión local permanece intacta (sets conservados).
        return session
    }
}

/// Fake in-memory de `HealthWorkoutStore` (tests/previews; §32.3 nunca HealthKit real).
public actor FakeHealthWorkoutStore: HealthWorkoutStore {
    public let provider: any HealthKitProvider
    public var startedHandles: [HealthWorkoutHandle] = []
    public var finishedSummaries: [HealthWorkoutSummary] = []
    public let failOnStart: Bool
    public let failOnFinish: Bool
    /// HR del resumen; nil si no permitido/disponible (PR-1103).
    public let heartRate: HealthWorkoutHeartRate?
    /// Origen de la energy a forzar en el resumen; nil = derivar (PR-1103).
    public let energyOrigin: MeasurementOrigin?

    public init(
        provider: any HealthKitProvider = InMemoryHealthKitProvider(),
        failOnStart: Bool = false,
        failOnFinish: Bool = false,
        heartRate: HealthWorkoutHeartRate? = nil,
        energyOrigin: MeasurementOrigin? = nil
    ) {
        self.provider = provider
        self.failOnStart = failOnStart
        self.failOnFinish = failOnFinish
        self.heartRate = heartRate
        self.energyOrigin = energyOrigin
    }

    public func requestAuthorization() async throws -> HealthPermissionOutcome {
        let provider = self.provider
        if let coordinatorProvider = provider as? InMemoryHealthKitProvider {
            // Solicita los permisos mínimos con el provider in-memory.
            return await coordinatorProvider.requestAuthorization(for: HealthPermissionType.allCases)
        }
        return .failed(message: "no provider")
    }

    public func startWorkout(configuration: HealthWorkoutConfiguration) async throws -> HealthWorkoutHandle {
        if failOnStart {
            throw NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "start failed"])
        }
        let handle = HealthWorkoutHandle()
        startedHandles.append(handle)
        return handle
    }

    public func finishWorkout(_ handle: HealthWorkoutHandle, with input: HealthWorkoutFinishInput) async throws -> HealthWorkoutSummary {
        if failOnFinish {
            throw NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "finish failed"])
        }
        let summary = HealthWorkoutSummary(
            referenceID: handle.id,
            start: input.start,
            end: input.end,
            activeKilocalories: input.activeKilocalories,
            energyOrigin: energyOrigin,
            heartRate: heartRate
        )
        finishedSummaries.append(summary)
        return summary
    }

    public func recentWorkouts() async throws -> [ExternalWorkout] {
        []
    }
}