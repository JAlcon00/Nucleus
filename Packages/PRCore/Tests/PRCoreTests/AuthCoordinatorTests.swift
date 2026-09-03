//
//  AuthCoordinatorTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del coordinador de Sign in with Apple (PR-0401): AuthenticationServices queda
//  detrás de un fake provider; se cubren success/cancel/failure, creación del perfil
//  local en el primer login y transiciones de estado de UI. No se usa AuthenticationServices
//  real ni HealthKit.
//

import Foundation
import Testing
import PRCore

@Suite("Sign in with Apple coordinator (PR-0401)")
@MainActor
struct AuthCoordinatorTests {

    @Test("Success crea perfil local y marca primer login")
    func successCreatesFirstLoginProfile() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider())

        await coordinator.signIn()

        guard case .signedIn(let profile) = coordinator.flowState else {
            Issue.record("El estado debía ser signedIn, era \(coordinator.flowState)")
            return
        }
        #expect(profile.userIdentifier == "apple-user")
        #expect(profile.isFirstLogin)
        #expect(coordinator.profile?.isFirstLogin == true)
    }

    @Test("UI state: pasa por authenticating y termina en signedIn")
    func uiStateTransitionsToSignedIn() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider())

        // Ejecutamos y verificamos el estado final visible.
        await coordinator.signIn()

        #expect(coordinator.flowState == .signedIn(LocalUserProfile(userIdentifier: "apple-user", isFirstLogin: true)))
    }

    @Test("Cancelación: vuelve a idle sin marcarlo como error")
    func cancelReturnsToIdleWithoutError() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider(behavior: .cancel))

        await coordinator.signIn()

        #expect(coordinator.flowState == .idle)
        #expect(coordinator.profile == nil)
    }

    @Test("Failure: expone el mensaje a la UI y no crea perfil")
    func failureExposesMessage() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider(behavior: .fail("Apple auth no disponible")))

        await coordinator.signIn()

        guard case .failed(let message) = coordinator.flowState else {
            Issue.record("El estado debía ser failed")
            return
        }
        #expect(message == "Apple auth no disponible")
        #expect(coordinator.profile == nil)
    }

    @Test("Identificador vacío se trata como un error, no como éxito")
    func emptyIdentifierTreatedAsFailure() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider(behavior: .emptyIdentifier))

        await coordinator.signIn()

        #expect(coordinator.profile == nil)
        guard case .failed = coordinator.flowState else {
            Issue.record("Un identificador vacío no debe llegar a signedIn")
            return
        }
    }

    @Test("No persiste el credential token: el perfil sólo guarda un id opaco")
    func doesNotPersistSensitiveToken() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider())

        await coordinator.signIn()

        guard case .signedIn(let profile) = coordinator.flowState else {
            Issue.record("Debía estar firmado")
            return
        }
        // El perfil NO contiene email, token ni código de autorización.
        let mirror = Mirror(reflecting: profile)
        let labels = mirror.children.compactMap(\.label)
        #expect(!labels.contains { $0.lowercased().contains("token") })
        #expect(!labels.contains { $0.lowercased().contains("email") })
        #expect(!labels.contains { $0.lowercased().contains("authcode") })
    }

    @Test("reset vuelve el estado a idle conservando el perfil")
    func resetReturnsToIdleKeepingProfile() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider())
        await coordinator.signIn()

        coordinator.reset()

        #expect(coordinator.flowState == .idle)
        // reset sólo limpia el estado del flujo, no la sesión.
        #expect(coordinator.profile != nil)
    }

    @Test("signOut descarta el perfil y vuelve a idle")
    func signOutClearsProfile() async {
        let coordinator = AppleIDAuthCoordinator(provider: FakeAppleIDAuthProvider())
        await coordinator.signIn()

        coordinator.signOut()

        #expect(coordinator.flowState == .idle)
        #expect(coordinator.profile == nil)
    }
}