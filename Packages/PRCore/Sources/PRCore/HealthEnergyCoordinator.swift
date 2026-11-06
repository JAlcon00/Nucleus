//
//  HealthEnergyCoordinator.swift
//  PRCore
//
//  SCRUM-250 (PR-F007): la energía de cada sesión, una sola vez y con su fuente, y lo demás que
//  Salud registró como "Actividad de Salud". Sólo agrega `energy` a la sesión: series, horas y
//  resumen no cambian. Si otra escritura la pisa, la siguiente corrida la repone: es idempotente.
//

import Foundation
import PRDomain

/// Texto de la energía, para la sesión y para las actividades.
public enum HealthEnergyPresenter {
    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    /// "Energía activa · Apple Watch".
    public static func label(for source: EnergySource, locale: Locale) -> String {
        switch source {
        case .externalAppleWorkout, .ourHealthKitWorkout:
            return String(localized: LocalizedStringResource(
                "Energía activa · Apple Watch", locale: locale, bundle: bundle,
                comment: "Origen de la energía de la sesión"
            ))
        case .externalHealthKitWorkout:
            return String(localized: LocalizedStringResource(
                "Energía activa · otra app", locale: locale, bundle: bundle,
                comment: "Origen de la energía de la sesión"
            ))
        case .fallbackEstimate:
            return String(localized: LocalizedStringResource(
                "Energía estimada", locale: locale, bundle: bundle,
                comment: "Nunca se presenta una estimación como medida"
            ))
        }
    }

    /// "240 kcal".
    public static func value(_ energy: CanonicalWorkoutEnergy) -> String {
        "\(Int(energy.activeKilocalories.rounded())) kcal"
    }
}

/// Reconcilia lo guardado con lo que hay en Salud. Se crea uno por cuenta.
public actor HealthEnergyCoordinator {
    private let repository: any WorkoutRepository
    private let reader: HealthExternalWorkoutsReader
    private let canRead: @Sendable () async -> Bool
    private let engine: WorkoutReconciliationEngine

    public init(
        repository: any WorkoutRepository,
        reader: HealthExternalWorkoutsReader,
        canRead: @escaping @Sendable () async -> Bool,
        engine: WorkoutReconciliationEngine = WorkoutReconciliationEngine()
    ) {
        self.repository = repository
        self.reader = reader
        self.canRead = canRead
        self.engine = engine
    }

    /// Le pone energía a las sesiones que coinciden con algo de Salud y devuelve lo que no
    /// coincide con ninguna, una vez por entrenamiento. Con Salud apagada no entra nada nuevo y
    /// lo guardado se queda. Lanza si no se pudo guardar.
    public func refresh(now: Date) async throws -> [HealthActivity] {
        guard await canRead() else { return [] }
        let sessions = try await repository.loadAllSessions().items
        let ownIdentifiers = Set(sessions.map { $0.id.rawValue.uuidString })
        let externals = await reader.recentWorkouts(now: now, ownSyncIdentifiers: ownIdentifiers)
        guard !externals.isEmpty else { return [] }

        let completed = sessions.filter { $0.lifecycle == .completed }
        let byIdentifier = Dictionary(
            completed.map { ($0.id.rawValue.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let externalByIdentifier = Dictionary(
            externals.map { ($0.referenceID.rawValue.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let candidates = completed.compactMap(Self.candidate)
            + externals.map { $0.asCandidate(source: $0.energySource) }

        var activities: [HealthActivity] = []
        for group in engine.groups(candidates) {
            let members = group.candidates.compactMap { byIdentifier[$0.identifier] }
            if members.isEmpty {
                if let activity = Self.activity(group, externals: externalByIdentifier) {
                    activities.append(activity)
                }
            } else if let energy = group.resolution.energy, members.allSatisfy({ $0.energy == nil }) {
                try await assign(energy, to: Self.target(among: members))
            }
        }
        return activities.sorted { ($0.start, $0.id.uuidString) > ($1.start, $1.id.uuidString) }
    }

    /// La energía de una sesión, ya guardada.
    public func energy(of id: WorkoutID) async throws -> CanonicalWorkoutEnergy? {
        try await repository.session(id: id)?.energy
    }

    private func assign(_ energy: CanonicalWorkoutEnergy, to session: WorkoutSessionRecord) async throws {
        guard var current = try await repository.session(id: session.id), current.energy == nil else { return }
        current.energy = energy
        try await repository.save(current)
    }

    private static func candidate(_ session: WorkoutSessionRecord) -> WorkoutEnergyCandidate? {
        guard let end = session.endedAt else { return nil }
        return WorkoutEnergyCandidate(
            identifier: session.id.rawValue.uuidString,
            start: session.startedAt,
            end: end,
            activityType: .strengthTraining,
            source: .ourHealthKitWorkout
        )
    }

    /// Si un entrenamiento externo cubre dos sesiones, su energía va a una sola: la más larga.
    private static func target(among sessions: [WorkoutSessionRecord]) -> WorkoutSessionRecord {
        let ordered = sessions.sorted { first, second in
            let firstDuration = first.endedAt?.timeIntervalSince(first.startedAt) ?? 0
            let secondDuration = second.endedAt?.timeIntervalSince(second.startedAt) ?? 0
            return (-firstDuration, first.id.rawValue.uuidString) < (-secondDuration, second.id.rawValue.uuidString)
        }
        return ordered[0]
    }

    /// Una fila por entrenamiento: si dos apps registraron lo mismo, manda la más confiable.
    private static func activity(
        _ group: WorkoutEnergyGroup,
        externals: [String: ExternalWorkout]
    ) -> HealthActivity? {
        let best = group.candidates
            .compactMap { externals[$0.identifier] }
            .min { ($0.energySource.priority, $0.referenceID.rawValue.uuidString)
                < ($1.energySource.priority, $1.referenceID.rawValue.uuidString) }
        guard let best else { return nil }
        return HealthActivity(
            id: best.referenceID.rawValue,
            start: best.start,
            end: best.end,
            activity: best.activityType.rawValue,
            sourceName: best.sourceName ?? best.deviceName,
            energy: group.resolution.energy
        )
    }
}
