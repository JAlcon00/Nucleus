//
//  HealthKitWorkoutStore.swift
//  PR
//
//  SCRUM-247 (PR-F004): guarda en Salud un entrenamiento terminado, con `HKWorkoutBuilder` y
//  las horas reales (DF-1). El id de la sesión va como identificador de sincronización, con
//  versión fija, para que repetir la escritura no duplique. No lleva energía ni ritmo
//  cardiaco: la app no los mide y no los inventa (RN-018).
//

import Foundation
import HealthKit
import PRCore

struct HealthKitWorkoutStore: HealthWorkoutWriting, HealthWorkoutReading {
    private let store = HKHealthStore()

    enum WriteError: Error {
        case notSaved
    }

    func saveFinishedWorkout(_ write: HealthWorkoutWrite) async throws -> HealthWorkoutHandle.ID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(write.activityType)
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: write.start)
        try await builder.addMetadata([
            HKMetadataKeySyncIdentifier: write.syncIdentifier,
            HKMetadataKeySyncVersion: HealthWorkoutWrite.syncVersion,
            HKMetadataKeyIndoorWorkout: true,
        ])
        try await builder.endCollection(at: write.end)
        guard let workout = try await builder.finishWorkout() else { throw WriteError.notSaved }
        return HealthWorkoutHandle.ID(rawValue: workout.uuid)
    }

    /// SCRUM-249: sólo datos generales. Un `HKWorkout` no tiene series. La energía se pide en
    /// kilocalorías, así que no importa en qué unidad la guardó la otra app.
    func recentWorkoutSamples(since: Date, until: Date) async throws -> [HealthWorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: until)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let energy = HKQuantityType(.activeEnergyBurned)
        return try await descriptor.result(for: store).map { workout in
            HealthWorkoutSample(
                uuid: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                activityType: Self.activityType(workout.workoutActivityType),
                activeKilocalories: workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                sourceName: workout.sourceRevision.source.name,
                deviceName: workout.device?.name,
                syncIdentifier: workout.metadata?[HKMetadataKeySyncIdentifier] as? String
            )
        }
    }

    private static func activityType(_ type: HealthWorkoutActivityType) -> HKWorkoutActivityType {
        switch type {
        case .strengthTraining: return .traditionalStrengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .running: return .running
        case .other: return .other
        }
    }

    private static func activityType(_ type: HKWorkoutActivityType) -> HealthWorkoutActivityType {
        switch type {
        case .traditionalStrengthTraining: return .strengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .running: return .running
        default: return .other
        }
    }
}
