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
        #expect(HealthUsageDescription.plistKeys[.workout] == "NSHealthUpdateUsageDescription")
        #expect(HealthUsageDescription.allTexts.count == 3)
    }
}

// MARK: - SCRUM-244: permisos reales, sin fingir lo que Salud no dice

/// Sistema falso: responde como Salud, que sólo revela el permiso de escritura.
private final class FakeHealthSystem: HealthSystemAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable = true
    var writeAnswer: HealthWriteAuthorization = .notDetermined
    /// Lo que queda decidido cuando la persona contesta la hoja.
    var answerAfterRequest: HealthWriteAuthorization?
    var requestError: (any Error)?
    private(set) var requests: [HealthAccessRequest] = []

    func writeAuthorization(for type: HealthPermissionType) -> HealthWriteAuthorization {
        writeAnswer
    }

    func requestAuthorization(_ request: HealthAccessRequest) async throws {
        requests.append(request)
        if let requestError { throw requestError }
        if let answerAfterRequest { writeAnswer = answerAfterRequest }
    }
}

private struct SystemFailure: Error {}

@Suite("Permisos reales de Salud (SCRUM-244)")
struct HealthRealPermissionsTests {

    private let requested: [HealthPermissionType] = [.workout, .activeEnergy]

    // Criterio 1
    @Test("Se piden exactamente escribir entrenamientos, leerlos y leer energía activa")
    func requestsExactlyWhatIsNeeded() async {
        let system = FakeHealthSystem()
        let provider = HealthSystemPermissionProvider(system: system)

        _ = await provider.requestAuthorization(for: requested)

        #expect(system.requests == [HealthAccessRequest.workouts])
        #expect(HealthAccessRequest.workouts.write == [.workout])
        #expect(HealthAccessRequest.workouts.read == [.workout, .activeEnergy])
    }

    @Test("El ritmo cardiaco no se pide aunque alguien lo solicite (DF-3)")
    func heartRateIsNeverRequested() async {
        let system = FakeHealthSystem()
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: HealthPermissionType.allCases)

        #expect(system.requests.allSatisfy { !$0.write.contains(.heartRate) && !$0.read.contains(.heartRate) })
        #expect(!outcome.isGranted(.heartRate))
        #expect(await provider.authorizationStatus(for: .heartRate) == .notDetermined)
    }

    // Criterios 2 y 3
    @Test("Negar escribir deja workout negado; conceder lo deja concedido", arguments: [
        (HealthWriteAuthorization.denied, HealthAuthorizationStatus.denied),
        (.authorized, .granted),
        (.notDetermined, .notDetermined),
    ])
    func writeStatusIsTheRealOne(answer: HealthWriteAuthorization, expected: HealthAuthorizationStatus) async {
        let system = FakeHealthSystem()
        system.answerAfterRequest = answer
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: requested)

        guard case .success(let map) = outcome else {
            Issue.record("Debía ser success")
            return
        }
        #expect(map[.workout] == expected)
        #expect(await provider.authorizationStatus(for: .workout) == expected)
    }

    // Criterio 4
    @Test("Un permiso de lectura es no visible: nunca concedido ni negado", arguments: [
        HealthWriteAuthorization.authorized, .denied, .notDetermined,
    ])
    func readPermissionIsNotVisible(writeAnswer: HealthWriteAuthorization) async {
        let system = FakeHealthSystem()
        system.answerAfterRequest = writeAnswer
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: requested)

        guard case .success(let map) = outcome else {
            Issue.record("Debía ser success")
            return
        }
        #expect(map[.activeEnergy] == .notVisible)
        #expect(await provider.authorizationStatus(for: .activeEnergy) == .notVisible)
        #expect(!outcome.isGranted(.activeEnergy))
        #expect(!outcome.anyDeniedButCoreUsable || writeAnswer == .denied)
    }

    // Criterio 5
    @Test("Con permiso no visible, la energía del resumen se conserva")
    func notVisibleKeepsEnergy() {
        let summary = HealthWorkoutSummary(
            referenceID: HealthWorkoutHandle.ID(),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3600),
            activeKilocalories: 240
        )
        let limited = summary.limited(to: HealthPermissionOutcome([.workout: .granted, .activeEnergy: .notVisible]))

        #expect(limited.activeKilocalories == 240)
        #expect(limited.energyOrigin == .measured)
    }

    @Test("Con energía negada o sin respuesta de Salud se sigue quitando", arguments: [
        HealthPermissionOutcome([.activeEnergy: .denied]),
        HealthPermissionOutcome([.activeEnergy: .notDetermined]),
        HealthPermissionOutcome([:]),
        .failed(message: "sin respuesta"),
    ])
    func deniedStillRemovesEnergy(outcome: HealthPermissionOutcome) {
        let summary = HealthWorkoutSummary(
            referenceID: HealthWorkoutHandle.ID(),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3600),
            activeKilocalories: 240
        )
        let limited = summary.limited(to: outcome)

        #expect(limited.activeKilocalories == nil)
        #expect(limited.energyOrigin == .unavailable)
    }

    // Criterio 6
    @Test("Sin Salud en el dispositivo es un fallo recuperable y no se pide nada")
    func unavailableIsRecoverable() async {
        let system = FakeHealthSystem()
        system.isHealthDataAvailable = false
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: requested)

        guard case .failed(let message) = outcome else {
            Issue.record("Debía ser failed")
            return
        }
        #expect(!message.isEmpty)
        #expect(system.requests.isEmpty)
        #expect(await provider.authorizationStatus(for: .workout) == .notDetermined)
        #expect(await provider.authorizationStatus(for: .activeEnergy) == .notDetermined)
    }

    @Test("Si el sistema falla al pedir, el resultado es un fallo recuperable sin detalles")
    func systemErrorIsRecoverable() async {
        let system = FakeHealthSystem()
        system.requestError = SystemFailure()
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: requested)

        guard case .failed(let message) = outcome else {
            Issue.record("Debía ser failed")
            return
        }
        #expect(!message.contains("SystemFailure"))
    }

    // Criterio 7
    @Test("Info.plist coincide con HealthUsageDescription y no dice que la app no escribe")
    func infoPlistMatchesTheDescriptions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("PR/Info.plist"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let share = try #require(plist["NSHealthShareUsageDescription"] as? String)
        let update = try #require(plist["NSHealthUpdateUsageDescription"] as? String)

        #expect(share == HealthUsageDescription.workoutShare)
        #expect(update == HealthUsageDescription.workoutUpdate)
        for text in [share, update] {
            #expect(!text.localizedCaseInsensitiveContains("no escribe"))
        }
    }

    @Test("plistKeys asigna a cada permiso el texto de lo que hace")
    func plistKeysFollowTheAccess() {
        #expect(HealthUsageDescription.plistKeys[.workout] == "NSHealthUpdateUsageDescription")
        #expect(HealthUsageDescription.plistKeys[.activeEnergy] == "NSHealthShareUsageDescription")
    }

    // Criterio 8
    @Test("Con el flag apagado no se pide ni se lee nada")
    func flagOffDoesNothing() async {
        let system = FakeHealthSystem()
        system.writeAnswer = .authorized
        let access = HealthWorkoutsAccess(
            flags: FeatureFlags(),
            provider: HealthSystemPermissionProvider(system: system)
        )

        let outcome = await access.requestPermissions()

        #expect(!access.isEnabled)
        #expect(system.requests.isEmpty)
        #expect(!outcome.isGranted(.workout))
        #expect(await access.writeStatus() == .notDetermined)
    }

    @Test("El flag viene apagado, aunque la app ya traiga Salud para \"Sobre ti\"")
    func flagIsOffByDefault() {
        #expect(!FeatureFlags().isEnabled(.healthWorkoutsEnabled))
        #expect(!FeatureFlags.forApp(arguments: [], isDebugBuild: false).isEnabled(.healthWorkoutsEnabled))
        #expect(!FeatureFlags.forApp(arguments: [], isDebugBuild: true).isEnabled(.healthWorkoutsEnabled))
    }

    @Test("Con el flag encendido se pide lo mínimo y se lee el estado real")
    func flagOnRequests() async {
        let system = FakeHealthSystem()
        system.answerAfterRequest = .authorized
        let access = HealthWorkoutsAccess(
            flags: FeatureFlags(overrides: [.healthWorkoutsEnabled: true]),
            provider: HealthSystemPermissionProvider(system: system)
        )

        let outcome = await access.requestPermissions()

        #expect(outcome.isGranted(.workout))
        #expect(system.requests == [HealthAccessRequest.workouts])
        #expect(await access.writeStatus() == .granted)
    }

    @Test("El build de prueba para iPhone enciende el flag; Release nunca")
    func deviceTestBuildEnablesTheFlag() {
        let debug = FeatureFlags.forApp(arguments: [], isDebugBuild: true, isDeviceTestBuild: true)
        let release = FeatureFlags.forApp(arguments: [], isDebugBuild: false, isDeviceTestBuild: true)

        #expect(debug.isEnabled(.healthWorkoutsEnabled))
        #expect(!release.isEnabled(.healthWorkoutsEnabled))
    }

    // Casos límite
    @Test("Un permiso cambiado en Ajustes con la app abierta se ve en la siguiente lectura")
    func statusIsReadLive() async {
        let system = FakeHealthSystem()
        system.writeAnswer = .authorized
        let provider = HealthSystemPermissionProvider(system: system)
        #expect(await provider.authorizationStatus(for: .workout) == .granted)

        system.writeAnswer = .denied

        #expect(await provider.authorizationStatus(for: .workout) == .denied)
    }

    @Test("Solicitud cancelada: sigue sin decidir y no bloquea")
    func cancelledRequestStaysUndetermined() async {
        let system = FakeHealthSystem()
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: requested)

        #expect(!outcome.isGranted(.workout))
        #expect(!outcome.anyDeniedButCoreUsable)
    }

    @Test("Dos solicitudes seguidas dan el mismo resultado")
    func twoRequestsInARow() async {
        let system = FakeHealthSystem()
        system.answerAfterRequest = .authorized
        let provider = HealthSystemPermissionProvider(system: system)

        let first = await provider.requestAuthorization(for: requested)
        let second = await provider.requestAuthorization(for: requested)

        #expect(first == second)
    }

    @Test("Pedir sólo una parte no agrega lo que nadie pidió")
    func partialRequestStaysPartial() async {
        let system = FakeHealthSystem()
        let provider = HealthSystemPermissionProvider(system: system)

        let outcome = await provider.requestAuthorization(for: [.activeEnergy])

        #expect(system.requests == [HealthAccessRequest(write: [], read: [.activeEnergy])])
        guard case .success(let map) = outcome else {
            Issue.record("Debía ser success")
            return
        }
        #expect(map == [.activeEnergy: .notVisible])
    }
}
