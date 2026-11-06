//
//  HealthExternalWorkouts.swift
//  PRCore
//
//  SCRUM-249 (PR-F006): leer entrenamientos de otras apps o del reloj sin confundirlos con los
//  nuestros y sin inventar lo que no se sabe. Sólo datos generales: inicio, fin, tipo, energía
//  si existe y fuente. Sin permiso o sin datos el resultado es vacío: Salud no dice si se negó.
//

import Foundation

/// Lo que Salud devuelve de un entrenamiento, sin importar HealthKit.
public struct HealthWorkoutSample: Sendable, Hashable {
    public let uuid: UUID
    public let start: Date
    public let end: Date
    public let activityType: HealthWorkoutActivityType
    public let activeKilocalories: Double?
    public let sourceBundleIdentifier: String
    public let sourceName: String?
    public let deviceName: String?
    public let syncIdentifier: String?

    public init(
        uuid: UUID,
        start: Date,
        end: Date,
        activityType: HealthWorkoutActivityType,
        activeKilocalories: Double? = nil,
        sourceBundleIdentifier: String,
        sourceName: String? = nil,
        deviceName: String? = nil,
        syncIdentifier: String? = nil
    ) {
        self.uuid = uuid
        self.start = start
        self.end = end
        self.activityType = activityType
        self.activeKilocalories = activeKilocalories
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.syncIdentifier = syncIdentifier
    }
}

/// Lee de Salud los entrenamientos de un intervalo. La implementación real vive en la app.
public protocol HealthWorkoutReading: Sendable {
    func recentWorkoutSamples(since: Date, until: Date) async throws -> [HealthWorkoutSample]
}

/// Clasifica lo que llega de Salud. Funciones puras.
public enum HealthWorkoutClassifier {
    /// Prefijo con el que Salud marca lo que registra Apple (app Entrenamiento del reloj).
    private static let appleHealthPrefix = "com.apple.health"

    public static func energySource(bundleIdentifier: String) -> EnergySource {
        bundleIdentifier.hasPrefix(appleHealthPrefix) ? .externalAppleWorkout : .externalHealthKitWorkout
    }

    /// ¿Lo escribió Nucleus? Por la fuente o por el identificador de una sesión propia, que
    /// sirve aunque la app cambie de identificador entre builds.
    public static func isOwn(
        _ sample: HealthWorkoutSample,
        ownBundleIdentifier: String,
        ownSyncIdentifiers: Set<String>
    ) -> Bool {
        if sample.sourceBundleIdentifier == ownBundleIdentifier { return true }
        guard let syncIdentifier = sample.syncIdentifier else { return false }
        return ownSyncIdentifiers.contains(syncIdentifier)
    }

    /// Los entrenamientos externos ya terminados, sin los propios ni repetidos.
    public static func externalWorkouts(
        from samples: [HealthWorkoutSample],
        ownBundleIdentifier: String,
        ownSyncIdentifiers: Set<String>,
        now: Date
    ) -> [ExternalWorkout] {
        var seen = Set<UUID>()
        return samples
            .filter { sample in
                sample.end <= now
                    && !isOwn(sample, ownBundleIdentifier: ownBundleIdentifier, ownSyncIdentifiers: ownSyncIdentifiers)
                    && seen.insert(sample.uuid).inserted
            }
            .sorted { ($0.start, $0.uuid.uuidString) < ($1.start, $1.uuid.uuidString) }
            .map(externalWorkout)
    }

    private static func externalWorkout(_ sample: HealthWorkoutSample) -> ExternalWorkout {
        ExternalWorkout(
            referenceID: HealthWorkoutHandle.ID(rawValue: sample.uuid),
            start: sample.start,
            end: sample.end,
            activityType: sample.activityType,
            activeKilocalories: sample.activeKilocalories.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            sourceName: sample.sourceName,
            deviceName: sample.deviceName,
            energySource: energySource(bundleIdentifier: sample.sourceBundleIdentifier)
        )
    }
}

/// Consulta los últimos días de Salud. Nunca lanza: sin permiso, sin datos o con el flag
/// apagado devuelve vacío, sin decir "negado" (§37.1).
public struct HealthExternalWorkoutsReader: Sendable {
    /// Días hacia atrás que se consultan.
    public static let lookbackDays = 14

    private let reader: any HealthWorkoutReading
    private let isEnabled: Bool
    private let ownBundleIdentifier: String
    private let calendar: Calendar

    public init(
        reader: any HealthWorkoutReading,
        isEnabled: Bool,
        ownBundleIdentifier: String,
        calendar: Calendar = .current
    ) {
        self.reader = reader
        self.isEnabled = isEnabled
        self.ownBundleIdentifier = ownBundleIdentifier
        self.calendar = calendar
    }

    public func recentWorkouts(now: Date, ownSyncIdentifiers: Set<String>) async -> [ExternalWorkout] {
        guard isEnabled,
              let since = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now),
              let samples = try? await reader.recentWorkoutSamples(since: since, until: now)
        else { return [] }
        return HealthWorkoutClassifier.externalWorkouts(
            from: samples,
            ownBundleIdentifier: ownBundleIdentifier,
            ownSyncIdentifiers: ownSyncIdentifiers,
            now: now
        )
    }
}
