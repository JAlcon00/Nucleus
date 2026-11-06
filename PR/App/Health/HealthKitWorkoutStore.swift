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

struct HealthKitWorkoutStore: HealthWorkoutWriting {
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

    private static func activityType(_ type: HealthWorkoutActivityType) -> HKWorkoutActivityType {
        switch type {
        case .strengthTraining: return .traditionalStrengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .running: return .running
        }
    }
}
