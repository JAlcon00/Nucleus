//
//  HealthKitPermissionProvider.swift
//  PR
//
//  SCRUM-244 (PR-F001): el lado real de los permisos de Salud. Sólo traduce a HealthKit;
//  lo que significa cada respuesta vive en `HealthSystemPermissionProvider` (PRCore). Salud
//  sólo revela el permiso de escritura: el de lectura nunca se consulta aquí.
//

import Foundation
import HealthKit
import PRCore

struct HealthKitPermissionProvider: HealthSystemAuthorizing {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func writeAuthorization(for type: HealthPermissionType) -> HealthWriteAuthorization {
        switch store.authorizationStatus(for: Self.objectType(type)) {
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .denied
        case .sharingAuthorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization(_ request: HealthAccessRequest) async throws {
        try await store.requestAuthorization(
            toShare: Set(request.write.map(Self.objectType)),
            read: Set(request.read.map { Self.objectType($0) as HKObjectType })
        )
    }

    private static func objectType(_ type: HealthPermissionType) -> HKSampleType {
        switch type {
        case .workout: return HKObjectType.workoutType()
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .heartRate: return HKQuantityType(.heartRate)
        }
    }
}
