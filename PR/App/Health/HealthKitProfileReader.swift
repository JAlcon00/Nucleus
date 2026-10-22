//
//  HealthKitProfileReader.swift
//  PR
//
//  SCRUM-206 (IA-5): lector de Apple Salud para prellenar "Sobre ti". SÓLO LECTURA de
//  fecha de nacimiento, sexo, estatura y peso (el último registro): no pide permiso de
//  escritura y nunca escribe. Por privacidad, Salud no dice si la persona negó la
//  lectura: en ese caso simplemente no llegan datos ("sin datos"). Infraestructura: la
//  conversión y las validaciones viven en PRDomain (`HealthPrefillMapper`).
//

import Foundation
import HealthKit
import PRCore
import PRDomain

struct HealthKitProfileReader: HealthProfileReading {
    func readProfile() async -> HealthReadResult {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let store = HKHealthStore()
        let height = HKQuantityType(.height)
        let weight = HKQuantityType(.bodyMass)
        let read: Set<HKObjectType> = [
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
            height,
            weight,
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch {
            return .unavailable
        }
        // Cada dato por separado: si uno falta o no se autorizó, los demás siguen.
        let birthDate = try? store.dateOfBirthComponents()
        let sex = (try? store.biologicalSex()).map { Self.sex($0.biologicalSex) }
        let meters = await latest(height, unit: .meter(), store: store)
        let kilograms = await latest(weight, unit: .gramUnit(with: .kilo), store: store)
        return .sample(HealthProfileSample(
            birthDate: birthDate,
            biologicalSex: sex,
            heightMeters: meters,
            weightKilograms: kilograms
        ))
    }

    /// Valor del registro más reciente, o `nil` si no hay (o no se autorizó).
    private func latest(_ type: HKQuantityType, unit: HKUnit, store: HKHealthStore) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }

    private static func sex(_ value: HKBiologicalSex) -> HealthBiologicalSex {
        switch value {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        case .notSet: return .notSet
        @unknown default: return .notSet
        }
    }
}
