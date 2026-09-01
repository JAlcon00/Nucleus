//
//  HealthAuthorizationTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de la abstracción de autorización de HealthKit (PR-1101): HealthKit detrás
//  de un protocolo, permisos granulares, denegar permiso NO bloquea el core (RF-002),
//  y usage descriptions correctas. PRCore no importa HealthKit real.
//

import Foundation
import Testing
import PRCore

@Suite("HealthKit authorization abstraction (PR-1101)")
struct HealthAuthorizationTests {

    @Test("HealthKit queda detrás de un protocolo: el coordinador usa un provider")
    func healthKitBehindProtocol() async {
        let provider = InMemoryHealthKitProvider()
        let coordinator = HealthAuthorizationCoordinator(provider: provider)
        // El coordinador sólo depende del `HealthKitProvider`; un fake es suficiente.
        let outcome = await coordinator.requestAuth(for: [.workout])
        #expect(outcome.allGranted)
    }

    @Test("Permisos granulares: solicitar un subconjunto sólo actualiza ese permiso")
    func granularPermissions() async {
        let provider = InMemoryHealthKitProvider()
        let coordinator = HealthAuthorizationCoordinator(provider: provider)

        let outcome = await coordinator.requestAuth(for: [.activeEnergy])
        guard case .success(let map) = outcome else {
            Issue.record("Debía ser success")
            return
        }
        #expect(map.count == 1 && map[.activeEnergy] == .granted)
        // El permiso no solicitado permanece notDetermined.
        #expect(await coordinator.status(of: .workout) == .notDetermined)
        #expect(await coordinator.status(of: .activeEnergy) == .granted)
    }

    @Test("Denegar un permiso no bloquea la app (RF-002): el resultado no bloqueante")
    func denyDoesNotBlockCore() async {
        let provider = InMemoryHealthKitProvider(grantBehavior: .denyAll)
        let coordinator = HealthAuthorizationCoordinator(provider: provider)

        let outcome = await coordinator.requestAuth(for: [.heartRate, .workout])
        // Hay una denegación, pero el core sigue usable (no lanza).
        #expect(outcome.anyDeniedButCoreUsable)
        #expect(!outcome.allGranted)
    }

    @Test("Un fallo de HealthKit es no-bloqueante y no lanza")
    func failureIsNonBlocking() async {
        let provider = InMemoryHealthKitProvider(grantBehavior: .fail)
        let coordinator = HealthAuthorizationCoordinator(provider: provider)

        let outcome = await coordinator.requestCorePermissions()
        guard case .failed(let message) = outcome else {
            Issue.record("Debía ser failed")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("Solicita todos los permisos mínimos salvo los excluidos")
    func requestsCorePermissionsExcludingTypes() async {
        let provider = InMemoryHealthKitProvider()
        let coordinator = HealthAuthorizationCoordinator(provider: provider)

        let outcome = await coordinator.requestCorePermissions(excluding: [.heartRate])
        guard case .success(let map) = outcome else {
            Issue.record("Debía ser success")
            return
        }
        #expect(map.keys.contains(.workout))
        #expect(map.keys.contains(.activeEnergy))
        #expect(!map.keys.contains(.heartRate))
    }

    @Test("Usage descriptions correctas: textos no vacíos y claves de plist coherentes")
    func usageDescriptionsCorrect() {
        #expect(HealthUsageDescription.allTexts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(HealthUsageDescription.plistKeys[.workout] == "NSHealthShareUsageDescription")
        #expect(HealthUsageDescription.allTexts.count == 3)
    }
}