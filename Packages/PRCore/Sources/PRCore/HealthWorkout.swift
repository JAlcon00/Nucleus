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
    /// Fuerza tradicional.
    case strengthTraining
    case functionalStrengthTraining
    case running
    /// Cualquier otra actividad que traiga Salud (SCRUM-249).
    case other
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

    /// Origen del ritmo cardiaco: sin resumen de HR es "no disponible" (SCRUM-35).
    public var heartRateOrigin: MeasurementOrigin {
        heartRate?.origin ?? .unavailable
    }

    /// El resumen sin los datos que no se pueden usar: quedan "no disponible", nunca medidos
    /// ni estimados (RN-018, SCRUM-35). Una lectura "no visible" se conserva: Salud no dice
    /// si se negó, y si se negó no habría llegado el dato (SCRUM-244). La duración no
    /// depende de permisos.
    public func limited(to permissions: HealthPermissionOutcome) -> HealthWorkoutSummary {
        var limited = self
        if !permissions.permitsReading(.activeEnergy) {
            limited.activeKilocalories = nil
            limited.energyOrigin = .unavailable
        }
        if !permissions.permitsReading(.heartRate) {
            limited.heartRate = nil
        }
        return limited
    }
}

/// Resultado de terminar el workout en Salud: la sesión local intacta y el resumen ya
/// limitado a los permisos concedidos (SCRUM-35).
public struct HealthWorkoutFinish: Sendable, Hashable {
    public let session: WorkoutSessionRecord
    public let summary: HealthWorkoutSummary
}

/// Workout de HealthKit de terceros (para reconciliación / lectura externa, PR-1102/PR-1104).
/// Sólo metadata autorizada: NUNCA incluye sets/reps/peso — esos son dominio propio de PR
/// (promptMaster §14.1) y nunca se inventan a partir de un workout externo.
public struct ExternalWorkout: Codable, Sendable, Hashable {
    public var referenceID: HealthWorkoutHandle.ID
    public var start: Date
    public var end: Date
    public var activityType: HealthWorkoutActivityType
    public var activeKilocalories: Double?
    /// Origen de la energy (measured/estimated/unavailable).
    public var energyOrigin: MeasurementOrigin
    /// Fuente (p. ej. "Apple Watch") y nombre del device cuando el store lo autorice.
    public var sourceName: String?
    public var deviceName: String?
    /// Qué tan confiable es su energía (§15.3). Apple Watch nativo u otra app (SCRUM-249).
    public var energySource: EnergySource

    public init(
        referenceID: HealthWorkoutHandle.ID,
        start: Date,
        end: Date,
        activityType: HealthWorkoutActivityType,
        activeKilocalories: Double? = nil,
        energyOrigin: MeasurementOrigin? = nil,
        sourceName: String? = nil,
        deviceName: String? = nil,
        energySource: EnergySource = .externalHealthKitWorkout
    ) {
        self.referenceID = referenceID
        self.start = start
        self.end = end
        self.activityType = activityType
        self.activeKilocalories = activeKilocalories
        self.energyOrigin = energyOrigin ?? (activeKilocalories == nil ? .unavailable : .measured)
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.energySource = energySource
    }
}

/// Consulta de workouts externos (PR-1104). Intervalo de fechas con filtros opcionales.
public struct ExternalWorkoutQuery: Codable, Sendable, Hashable {
    public var since: Date
    public var until: Date
    /// Filtro de actividad; nil = todas.
    public var activityType: HealthWorkoutActivityType?

    public init(since: Date, until: Date, activityType: HealthWorkoutActivityType? = nil) {
        self.since = since
        self.until = until
        self.activityType = activityType
    }
}

/// Origen de un vínculo workout externo ↔ plan (PR-1104).
public enum LinkDecision: String, Codable, Sendable, CaseIterable, Hashable {
    /// Sugerido automáticamente (nunca aplicado sin confirmación).
    case suggestion
    /// Elegido manualmente por el usuario.
    case manual
}

/// Vínculo entre un workout externo del día y un plantilla/sesión del plan (PR-1104).
/// NUNCA fabrica set data: sólo asocia metadata autorizada a una plantilla.
public struct WorkoutPlanLink: Codable, Sendable, Hashable {
    public var externalWorkoutReferenceID: HealthWorkoutHandle.ID
    public var templateID: SessionTemplate.ID?
    public var decision: LinkDecision

    public init(
        externalWorkoutReferenceID: HealthWorkoutHandle.ID,
        templateID: SessionTemplate.ID? = nil,
        decision: LinkDecision = .suggestion
    ) {
        self.externalWorkoutReferenceID = externalWorkoutReferenceID
        self.templateID = templateID
        self.decision = decision
    }
}

/// Sugerencia de vínculo workout externo → plantilla del plan (PR-1104).
///
/// Determinista: dado un workout externo y las plantillas candidatas del día, sugiere la
/// primera compatible (o ninguna). Es una SUGERENCIA: devuelve `decision == .suggestion`
/// y nunca aplica el vínculo por sí mismo; el usuario mantiene el control manual.
public struct WorkoutPlanLinker: Sendable {
    public init() {}

    /// Devuelve la plantilla más plausible para el workout externo, o nil si no hay
    /// candidata clara (no inventa un vínculo forzado).
    public func suggestTemplate(
        for workout: ExternalWorkout,
        candidates: [SessionTemplate],
        day: DayInterval
    ) -> SessionTemplate.ID? {
        // El workout debe caer dentro del día considerado.
        guard workout.start >= day.start && workout.end <= day.end else { return nil }
        // Determinista: primera candidata por título/orden estable del plan.
        return candidates.first?.id
    }

    /// Crea un vínculo por sugerencia (si hay plantilla) o manual, respetando que un
    /// vínculo manual con plantilla real prevalece.
    public func link(
        _ workout: ExternalWorkout,
        to templateID: SessionTemplate.ID?,
        manual: Bool
    ) -> WorkoutPlanLink {
        WorkoutPlanLink(
            externalWorkoutReferenceID: workout.referenceID,
            templateID: templateID,
            decision: manual ? .manual : .suggestion
        )
    }

    /// Aplica manualmente un vínculo (override de sugerencia). Soporta desvincular (nil).
    public func manualLink(
        _ workout: ExternalWorkout,
        to templateID: SessionTemplate.ID?
    ) -> WorkoutPlanLink {
        WorkoutPlanLink(
            externalWorkoutReferenceID: workout.referenceID,
            templateID: templateID,
            decision: .manual
        )
    }
}

/// Intervalo de un día (para agrupar workouts del mismo día).
public struct DayInterval: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
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
    /// Lee workouts externos de la consulta (sólo metadata autorizada, PR-1104).
    func recentWorkouts(in query: ExternalWorkoutQuery) async throws -> [ExternalWorkout]
}

/// Lo único que se manda a Salud de un entrenamiento terminado (SCRUM-246, DF-4): tipo,
/// horas y el identificador que evita duplicar. Nunca series, peso, reps, ejercicios ni notas.
public struct HealthWorkoutWrite: Sendable, Hashable {
    /// Versión con la que se guarda: repetir la misma escritura no duplica.
    public static let syncVersion = 1

    /// Identificador estable en Salud: el id de la sesión.
    public let syncIdentifier: String
    public let start: Date
    public let end: Date
    public let activityType: HealthWorkoutActivityType

    /// Sólo un entrenamiento completado con al menos una serie va a Salud (DF-4). Sin horas
    /// válidas, por ejemplo con el reloj cambiado, no hay nada que escribir.
    public init?(session: WorkoutSessionRecord) {
        guard session.lifecycle == .completed,
              let end = session.endedAt,
              end > session.startedAt,
              session.sets.contains(where: { $0.lifecycle == .completed })
        else { return nil }
        self.syncIdentifier = session.id.rawValue.uuidString
        self.start = session.startedAt
        self.end = end
        self.activityType = .strengthTraining
    }
}

/// Guarda en Salud un entrenamiento terminado (DF-1). La misma escritura repetida deja un
/// solo entrenamiento. Devuelve la referencia del entrenamiento en Salud.
public protocol HealthWorkoutWriting: Sendable {
    func saveFinishedWorkout(_ write: HealthWorkoutWrite) async throws -> HealthWorkoutHandle.ID
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
    /// Sólo exige el permiso de entrenamientos (SCRUM-35, bug 12): sin ritmo cardiaco ni
    /// energía se registra igual. Sin él lanza `missingPermission` y la sesión local sigue
    /// intacta: se entrena igual, sólo que sin registro en Salud.
    public func start(
        session: WorkoutSessionRecord,
        configuration: HealthWorkoutConfiguration = HealthWorkoutConfiguration()
    ) async throws -> WorkoutSessionRecord {
        let outcome = try await store.requestAuthorization()
        guard outcome.isGranted(.workout) else {
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
        try await finishWithSummary(session: session, completedAt: end, activeKilocalories: activeKilocalories).session
    }

    /// Finaliza el workout de HealthKit y devuelve el resumen limitado a los permisos
    /// vigentes: lo no permitido queda "no disponible" (SCRUM-35). Si no se pueden leer
    /// los permisos, nada se concede. Un fallo no elimina los sets locales.
    public func finishWithSummary(
        session: WorkoutSessionRecord,
        completedAt end: Date = Date(),
        activeKilocalories: Double? = nil
    ) async throws -> HealthWorkoutFinish {
        guard let rawID = session.healthWorkoutReferenceID else {
            throw HealthWorkoutError.notStarted
        }
        let handle = HealthWorkoutHandle(id: HealthWorkoutHandle.ID(rawValue: rawID))
        let permissions: HealthPermissionOutcome
        do {
            permissions = try await store.requestAuthorization()
        } catch {
            permissions = .failed(message: "\(error)")
        }
        let summary: HealthWorkoutSummary
        do {
            summary = try await store.finishWorkout(
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
        return HealthWorkoutFinish(session: session, summary: summary.limited(to: permissions))
    }
}

/// Fake in-memory de `HealthWorkoutStore` (tests/previews; §32.3 nunca HealthKit real).
public actor FakeHealthWorkoutStore: HealthWorkoutStore, HealthWorkoutWriting, HealthWorkoutReading {
    public let provider: any HealthKitProvider
    /// Lo que Salud tiene guardado, por identificador de sincronización (SCRUM-246).
    public private(set) var savedWorkouts: [String: HealthWorkoutWrite] = [:]
    /// Veces que se llamó a guardar, aunque no haya creado nada nuevo.
    public private(set) var saveAttempts = 0
    public private(set) var failsOnSave = false
    public var startedHandles: [HealthWorkoutHandle] = []
    public var finishedSummaries: [HealthWorkoutSummary] = []
    public let failOnStart: Bool
    public let failOnFinish: Bool
    /// HR del resumen; nil si no permitido/disponible (PR-1103).
    public let heartRate: HealthWorkoutHeartRate?
    /// Origen de la energy a forzar en el resumen; nil = derivar (PR-1103).
    public let energyOrigin: MeasurementOrigin?
    /// Workouts externos que devuelve `recentWorkouts` (PR-1104).
    public let externalWorkouts: [ExternalWorkout]

    public init(
        provider: any HealthKitProvider = InMemoryHealthKitProvider(),
        failOnStart: Bool = false,
        failOnFinish: Bool = false,
        heartRate: HealthWorkoutHeartRate? = nil,
        energyOrigin: MeasurementOrigin? = nil,
        externalWorkouts: [ExternalWorkout] = []
    ) {
        self.provider = provider
        self.failOnStart = failOnStart
        self.failOnFinish = failOnFinish
        self.heartRate = heartRate
        self.energyOrigin = energyOrigin
        self.externalWorkouts = externalWorkouts
    }

    /// Entrenamientos de otras fuentes que Salud devuelve (SCRUM-249).
    public private(set) var otherSamples: [HealthWorkoutSample] = []
    public private(set) var failsOnRead = false
    /// Fuente con la que Salud marca lo que escribe esta app.
    public static let ownBundleIdentifier = "creadevs.PR"

    /// Energía del entrenamiento de reloj que Salud "registra" junto a cada escritura.
    public private(set) var echoedWatchKilocalories: Double?

    public func setEchoedWatchKilocalories(_ kilocalories: Double?) {
        echoedWatchKilocalories = kilocalories
    }

    public func setOtherSamples(_ samples: [HealthWorkoutSample]) {
        otherSamples = samples
    }

    public func setFailsOnRead(_ fails: Bool) {
        failsOnRead = fails
    }

    /// Como Salud: lo que escribió esta app vuelve junto con lo de las demás.
    public func recentWorkoutSamples(since: Date, until: Date) async throws -> [HealthWorkoutSample] {
        if failsOnRead {
            throw NSError(domain: "HealthKit", code: 5, userInfo: [NSLocalizedDescriptionKey: "not determined"])
        }
        let own = savedWorkouts.values.map { write in
            HealthWorkoutSample(
                uuid: UUID(uuidString: write.syncIdentifier) ?? UUID(),
                start: write.start,
                end: write.end,
                activityType: write.activityType,
                sourceBundleIdentifier: Self.ownBundleIdentifier,
                sourceName: "Nucleus",
                syncIdentifier: write.syncIdentifier
            )
        }
        return (own + otherSamples).filter { $0.start >= since && $0.start <= until }
    }

    public func setFailsOnSave(_ fails: Bool) {
        failsOnSave = fails
    }

    public func saveFinishedWorkout(_ write: HealthWorkoutWrite) async throws -> HealthWorkoutHandle.ID {
        saveAttempts += 1
        if failsOnSave {
            throw NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "save failed"])
        }
        if savedWorkouts[write.syncIdentifier] == nil, let echoedWatchKilocalories {
            otherSamples.append(HealthWorkoutSample(
                uuid: UUID(),
                start: write.start,
                end: write.end,
                activityType: .strengthTraining,
                activeKilocalories: echoedWatchKilocalories,
                sourceBundleIdentifier: "com.apple.health.fake",
                sourceName: "Apple Watch"
            ))
        }
        savedWorkouts[write.syncIdentifier] = write
        return HealthWorkoutHandle.ID(rawValue: UUID(uuidString: write.syncIdentifier) ?? UUID())
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

    public func recentWorkouts(in query: ExternalWorkoutQuery) async throws -> [ExternalWorkout] {
        let provider = self.provider
        // Sólo se importa metadata cuando el permiso .workout está concedido.
        guard case .granted = await provider.authorizationStatus(for: .workout) else {
            return []
        }
        return externalWorkouts.filter {
            $0.start >= query.since && $0.end <= query.until
                && (query.activityType == nil || $0.activityType == query.activityType)
        }
    }
}