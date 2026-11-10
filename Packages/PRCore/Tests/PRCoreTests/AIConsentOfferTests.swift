//
//  AIConsentOfferTests.swift
//  PRCoreTests
//
//  SCRUM-277 (PR-I008, DI-3 y DI-6): el consentimiento sólo se pide si la IA puede usarse en
//  este build, y el entrenador nunca usa la IA sin consentimiento, aunque haya llave.
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

@Suite("SCRUM-277 · Cuándo se pide el consentimiento y cuándo usa la IA el entrenador")
struct AIConsentOfferTests {
    private let appFlags = FeatureFlags.forApp(arguments: [], isDebugBuild: true)

    @Test("Se pide en Debug (con o sin llave) y en pruebas de UI; no en Release ni con la flag apagada",
          arguments: [
            (AIConnectionStatus.live, true),
            (.offline(.missingKey), true),
            (.offline(.uiTesting), true),
            (.offline(.releaseBuild), false),
            (.offline(.disabledByFlag), false),
          ])
    func offered(connection: AIConnectionStatus, expected: Bool) {
        #expect(AIConsentCoordinator.isOffered(flags: appFlags, connection: connection) == expected)
        let off = appFlags.setting(.agentNvidiaEnabled, to: false)
        #expect(!AIConsentCoordinator.isOffered(flags: off, connection: connection), "Sin la flag nunca se pide")
    }

    @Test("Release de verdad: la conexión queda en .releaseBuild y no se pide consentimiento")
    func releaseBuildIsNotOffered() {
        let flags = FeatureFlags.forApp(arguments: [], isDebugBuild: false)
        let connection = AIConnection.resolve(build: .release, flags: flags, keyLoader: { "llave-que-no-se-usa" })
        #expect(connection.status == .offline(.releaseBuild))
        #expect(!AIConsentCoordinator.isOffered(flags: flags, connection: connection.status))
    }

    @Test("El entrenador sólo usa la IA con conexión y consentimiento; retirarlo la apaga en el siguiente mensaje")
    func coachTransportNeedsConsent() {
        let live = AIConnection(status: .live, provider: MockLLMProvider())
        let granted = AIDataConsent.granted(at: Date(timeIntervalSince1970: 0))
        #expect(live.coachTransport(consent: granted) != nil)
        #expect(live.coachTransport(consent: .notAsked) == nil, "Sin decidir no va nada")
        #expect(live.coachTransport(consent: .declined(at: Date(timeIntervalSince1970: 1))) == nil, "Retirado: nada")
        let offline = AIConnection(status: .offline(.missingKey), provider: MockLLMProvider())
        #expect(offline.coachTransport(consent: granted) == nil, "Sin conexión, el intérprete local")
    }
}
