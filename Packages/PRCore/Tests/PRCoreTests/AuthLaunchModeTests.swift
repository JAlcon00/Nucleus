//
//  AuthLaunchModeTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  SCRUM-181 (apoyo a pruebas): el inicio de sesión simulado sólo se activa en Debug
//  con `-PRFakeSignIn`; en Release nunca, aunque venga el argumento.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("SCRUM-181 · Inicio de sesión simulado sólo en Debug")
struct AuthLaunchModeTests {

    @Test("Debug + -PRFakeSignIn ⇒ simulado y entra solo")
    func debugWithArgument() {
        let mode = AuthLaunchMode.resolve(arguments: ["PR", "-PRFakeSignIn"], isDebugBuild: true)
        #expect(mode == .simulated)
        #expect(mode.signsInAutomatically)
    }

    @Test("Release nunca simula, aunque venga el argumento")
    func releaseNeverSimulates() {
        let mode = AuthLaunchMode.resolve(arguments: ["PR", "-PRFakeSignIn"], isDebugBuild: false)
        #expect(mode == .appleID)
        #expect(!mode.signsInAutomatically)
    }

    @Test("Debug sin el argumento usa Sign in with Apple real",
          arguments: [[String](), ["PR"], ["PR", "-PRFakeSignInX"], ["PR", "PRFakeSignIn"]])
    func debugWithoutArgument(arguments: [String]) {
        #expect(AuthLaunchMode.resolve(arguments: arguments, isDebugBuild: true) == .appleID)
    }

    @MainActor
    @Test("El modo simulado inicia sesión con el usuario local y llega al cuestionario")
    func simulatedProviderSignsIn() async {
        let onboarding = OnboardingCoordinator(
            authProvider: AuthLaunchMode.simulated.provider(appleID: FakeAppleIDAuthProvider(behavior: .cancel))
        )
        await onboarding.signIn()
        #expect(onboarding.auth.profile?.userIdentifier == AuthLaunchMode.simulatedUserIdentifier)
        guard case .onboarding = onboarding.phase else {
            Issue.record("Tras el inicio simulado debía entrar al cuestionario, fase \(onboarding.phase)")
            return
        }
    }

    @MainActor
    @Test("El modo Apple usa el proveedor que entrega la app")
    func appleModeUsesGivenProvider() async {
        let onboarding = OnboardingCoordinator(
            authProvider: AuthLaunchMode.appleID.provider(appleID: FakeAppleIDAuthProvider(behavior: .cancel))
        )
        await onboarding.signIn()
        #expect(onboarding.phase == .signedOut)
    }

    // MARK: SCRUM-262: build de prueba para iPhone

    /// Tabla completa de build, condición y argumento (criterios 2, 4 y 5).
    @Test("Build, condición y argumento deciden el modo", arguments: [
        (isDebug: true, isDeviceTest: true, arguments: [String](), expected: AuthLaunchMode.simulated),
        (isDebug: true, isDeviceTest: true, arguments: ["PR"], expected: AuthLaunchMode.simulated),
        (isDebug: true, isDeviceTest: true, arguments: ["PR", "-PRFakeSignIn"], expected: AuthLaunchMode.simulated),
        (isDebug: true, isDeviceTest: false, arguments: ["PR"], expected: AuthLaunchMode.appleID),
        (isDebug: true, isDeviceTest: false, arguments: ["PR", "-PRFakeSignIn"], expected: AuthLaunchMode.simulated),
        (isDebug: true, isDeviceTest: false, arguments: ["PR", "-PRDemoData"], expected: AuthLaunchMode.simulated),
        (isDebug: false, isDeviceTest: true, arguments: ["PR"], expected: AuthLaunchMode.appleID),
        (isDebug: false, isDeviceTest: true, arguments: ["PR", "-PRFakeSignIn"], expected: AuthLaunchMode.appleID),
        (isDebug: false, isDeviceTest: false, arguments: ["PR", "-PRFakeSignIn"], expected: AuthLaunchMode.appleID),
        (isDebug: false, isDeviceTest: false, arguments: ["PR", "-PRDemoData"], expected: AuthLaunchMode.appleID),
        (isDebug: false, isDeviceTest: false, arguments: ["PR"], expected: AuthLaunchMode.appleID),
    ])
    func launchModeTable(
        row: (isDebug: Bool, isDeviceTest: Bool, arguments: [String], expected: AuthLaunchMode)
    ) {
        let mode = AuthLaunchMode.resolve(
            arguments: row.arguments,
            isDebugBuild: row.isDebug,
            isDeviceTestBuild: row.isDeviceTest
        )
        #expect(mode == row.expected)
    }

    @Test("Sin decir nada de la condición, el modo se decide como antes")
    func deviceTestDefaultsToOff() {
        #expect(AuthLaunchMode.resolve(arguments: ["PR"], isDebugBuild: true) == .appleID)
    }
}
