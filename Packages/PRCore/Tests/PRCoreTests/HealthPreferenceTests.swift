//
//  HealthPreferenceTests.swift
//  PRCoreTests
//
//  SCRUM-248 (PR-F005): cuándo se propone guardar en Salud y que la decisión sobreviva por
//  usuario. La persistencia es la real, en un directorio temporal.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

@Suite("Pedir permiso en el momento correcto (SCRUM-248)")
@MainActor
struct HealthPreferenceTests {

    private func offer(
        isEnabled: Bool = true,
        isAvailable: Bool = true,
        preference: HealthWritePreference = .notAsked,
        writeStatus: HealthAuthorizationStatus = .notDetermined,
        sessionGoesToHealth: Bool = true
    ) -> Bool {
        HealthPermissionOffer.shouldShow(
            isEnabled: isEnabled,
            isAvailable: isAvailable,
            preference: preference,
            writeStatus: writeStatus,
            sessionGoesToHealth: sessionGoesToHealth
        )
    }

    private func withPersistence(_ body: (LocalPersistence, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum248-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }), root)
    }

    // Criterio 1
    @Test("Sin haber decidido, un entrenamiento completado muestra la tarjeta")
    func showsOnFirstCompletedWorkout() {
        #expect(offer())
    }

    // Criterio 3
    @Test("Después de decidir no vuelve a salir", arguments: [HealthWritePreference.enabled, .disabled])
    func notShownAfterDeciding(preference: HealthWritePreference) {
        #expect(!offer(preference: preference))
    }

    // Criterio 7
    @Test("Si ya se contestó la hoja del sistema, no insiste", arguments: [
        HealthAuthorizationStatus.denied, .granted,
    ])
    func notShownAfterTheSheet(status: HealthAuthorizationStatus) {
        #expect(!offer(writeStatus: status))
    }

    // Casos límite
    @Test("Abandonado, sin Salud o con el flag apagado no sale")
    func notShownWhenItDoesNotApply() {
        #expect(!offer(sessionGoesToHealth: false))
        #expect(!offer(isAvailable: false))
        #expect(!offer(isEnabled: false))
    }

    // Criterio 4
    @Test("El interruptor de Perfil dice la verdad", arguments: [
        (HealthWritePreference.enabled, HealthAuthorizationStatus.granted, HealthWriteSetting.on),
        (.notAsked, .granted, .on),
        (.disabled, .granted, .off),
        (.notAsked, .notDetermined, .off),
        (.enabled, .notDetermined, .off),
        (.enabled, .denied, .deniedInSettings),
        (.disabled, .denied, .deniedInSettings),
    ])
    func settingFollowsBoth(
        preference: HealthWritePreference,
        status: HealthAuthorizationStatus,
        expected: HealthWriteSetting
    ) {
        let setting = HealthWriteSetting(preference: preference, writeStatus: status)
        #expect(setting == expected)
        #expect(setting.isOn == (expected == .on))
    }

    // Criterio 5
    @Test("Apagado no deja escribir; sin decidir, el permiso del sistema manda")
    func allowsWriting() throws {
        try withPersistence { persistence, _ in
            let coordinator = HealthPreferenceCoordinator(store: try persistence.healthPreferenceStore())
            coordinator.load(userID: "a")
            #expect(coordinator.allowsWriting)
            coordinator.set(.disabled)
            #expect(!coordinator.allowsWriting)
            coordinator.set(.enabled)
            #expect(coordinator.allowsWriting)
        }
    }

    // Criterio 8
    @Test("La decisión sobrevive a reabrir la app")
    func survivesReopening() throws {
        try withPersistence { persistence, root in
            let first = HealthPreferenceCoordinator(store: try persistence.healthPreferenceStore())
            first.load(userID: "a")
            #expect(first.set(.disabled))

            let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let second = HealthPreferenceCoordinator(store: try reopened.healthPreferenceStore())
            second.load(userID: "a")
            #expect(second.preference == .disabled)
        }
    }

    @Test("La decisión es por usuario")
    func isPerUser() throws {
        try withPersistence { persistence, _ in
            let coordinator = HealthPreferenceCoordinator(store: try persistence.healthPreferenceStore())
            coordinator.load(userID: "a")
            coordinator.set(.disabled)

            coordinator.load(userID: "b")
            #expect(coordinator.preference == .notAsked)

            coordinator.load(userID: "a")
            #expect(coordinator.preference == .disabled)
        }
    }

    @Test("Sin poder guardar, apagar aplica igual y avisa")
    func turningOffAppliesWithoutStore() {
        let coordinator = HealthPreferenceCoordinator(store: nil)
        coordinator.load(userID: "a")

        #expect(!coordinator.set(.disabled))
        #expect(coordinator.saveFailed)
        #expect(!coordinator.allowsWriting)
    }

    @Test("Sin poder guardar, encender no aplica")
    func turningOnNeedsStore() {
        let coordinator = HealthPreferenceCoordinator(store: nil)
        coordinator.load(userID: "a")

        #expect(!coordinator.set(.enabled))
        #expect(coordinator.preference == .notAsked)
    }

    @Test("Un archivo dañado cuenta como sin preguntar")
    func unreadableIsNotAsked() throws {
        try withPersistence { persistence, _ in
            try persistence.store(for: .healthPreference)
                .write(key: PlanStore.key(forUser: "a"), data: Data("no es json".utf8))

            #expect(try persistence.healthPreferenceStore().load(userID: "a") == .notAsked)
        }
    }
}
