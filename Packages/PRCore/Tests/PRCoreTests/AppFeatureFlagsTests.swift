//
//  AppFeatureFlagsTests.swift
//  PRCoreTests
//
//  SCRUM-39 (PR-0117): las feature flags se consultan de verdad. La app las arma una vez
//  (`FeatureFlags.forApp`): enciende lo que ya trae (IA y Salud) y, sólo en Debug,
//  `-PRFeatureFlag clave=0|1` las cambia. Con la IA apagada no se busca la llave, no se
//  pide el consentimiento y la conexión queda local; con Salud apagada no se ofrece el
//  botón ni se lee Salud. `FeatureFlags()` sigue con todo apagado (PR-0004).
//

import Foundation
import Testing
import PRDomain
@testable import PRCore

/// Cuenta cuántas veces se pidió la llave.
private final class KeyRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

/// Lector de Salud que cuenta las lecturas.
private final class CountingHealthReader: HealthProfileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var reads: Int { lock.withLock { value } }

    func readProfile() async -> HealthReadResult {
        lock.withLock { value += 1 }
        return .sample(HealthProfileSample(biologicalSex: .female, weightKilograms: 64))
    }
}

@Suite("SCRUM-39 · Feature flags de la app")
struct AppFeatureFlagsTests {

    private func arguments(_ pairs: String...) -> [String] {
        pairs.flatMap { [FeatureFlags.launchArgument, $0] }
    }

    // MARK: - Un solo lugar: forApp

    @Test("La app enciende lo que ya trae (IA y Salud); lo demás sigue apagado", arguments: [true, false])
    func appDefaults(isDebugBuild: Bool) {
        let flags = FeatureFlags.forApp(arguments: [], isDebugBuild: isDebugBuild)
        #expect(flags.isEnabled(.agentNvidiaEnabled))
        #expect(flags.isEnabled(.healthPrefillEnabled))
        for key in FeatureFlagKey.allCases where !FeatureFlags.shipped.contains(key) {
            #expect(!flags.isEnabled(key), "\(key.rawValue) sigue apagada")
        }
    }

    @Test("La base sigue con todo apagado, también la flag nueva de Salud")
    func baseStaysOff() {
        #expect(!FeatureFlags().isEnabled(.healthPrefillEnabled))
        #expect(FeatureFlags().source(of: .healthPrefillEnabled) == .default)
    }

    @Test("En Debug, -PRFeatureFlag apaga y enciende (se puede repetir)")
    func debugArgumentsApply() {
        let flags = FeatureFlags.forApp(
            arguments: arguments("agent.nvidia.enabled=0", "health.prefill.enabled=false", "agent.nvidia.streaming.enabled=1"),
            isDebugBuild: true
        )
        #expect(!flags.isEnabled(.agentNvidiaEnabled))
        #expect(!flags.isEnabled(.healthPrefillEnabled))
        #expect(flags.isEnabled(.agentNvidiaStreamingEnabled))
        #expect(flags.source(of: .agentNvidiaEnabled) == .override)
    }

    @Test("En Release los argumentos se ignoran")
    func releaseIgnoresArguments() {
        let flags = FeatureFlags.forApp(arguments: arguments("agent.nvidia.enabled=0", "agent.tools.write.enabled=1"), isDebugBuild: false)
        #expect(flags == FeatureFlags.forApp(arguments: [], isDebugBuild: false))
    }

    @Test("Una clave desconocida, un valor raro o un argumento sin valor se ignoran sin romper")
    func oddArgumentsAreIgnored() {
        var odd = arguments("agent.unknown.flag=0", "agent.nvidia.enabled=quizá", "health.prefill.enabled", "=1")
        odd.append(FeatureFlags.launchArgument)
        #expect(FeatureFlags.forApp(arguments: odd, isDebugBuild: true) == FeatureFlags.forApp(arguments: [], isDebugBuild: true))
    }

    // MARK: - IA

    @Test("IA apagada: conexión local por la flag y la llave ni siquiera se busca")
    func aiOffNeverReadsTheKey() {
        let requests = KeyRequests()
        let flags = FeatureFlags.forApp(arguments: arguments("agent.nvidia.enabled=0"), isDebugBuild: true)
        let connection = AIConnection.resolve(build: .debug, flags: flags, keyLoader: { requests.record(); return "llave-de-prueba" })
        #expect(connection.status == .offline(.disabledByFlag))
        #expect(requests.count == 0)
        #expect(connection.provider is OfflineLLMProvider)
    }

    @Test("IA encendida: como hoy (Debug con llave se conecta; Release sigue apagada por el build)")
    func aiOnBehavesAsToday() {
        let flags = FeatureFlags.forApp(arguments: [], isDebugBuild: true)
        #expect(AIConnection.resolve(build: .debug, flags: flags, keyLoader: { "llave-de-prueba" }).status == .live)
        #expect(AIConnection.resolve(build: .debug, flags: flags, keyLoader: { nil }).status == .offline(.missingKey))
        let release = FeatureFlags.forApp(arguments: [], isDebugBuild: false)
        #expect(AIConnection.resolve(build: .release, flags: release, keyLoader: { "llave-de-prueba" }).status == .offline(.releaseBuild))
    }

    @MainActor
    @Test("IA apagada: no se pide el consentimiento; encendida: sí, con la misma persona")
    func consentFollowsTheFlag() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scrum39-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = try LocalPersistence(rootURL: directory, log: PersistenceLog { _ in })

        let off = AIConsentCoordinator(store: try persistence.aiConsentStore(), isOffered: false)
        off.load(userID: "persona-1")
        #expect(off.consent == .notAsked)
        #expect(!off.needsDecision, "sin la función no hay nada que consentir")

        let on = AIConsentCoordinator(store: try persistence.aiConsentStore(), isOffered: true)
        on.load(userID: "persona-1")
        #expect(on.needsDecision)
    }

    // MARK: - Salud

    @MainActor
    @Test("Salud apagada: el botón no se ofrece y no se lee Salud aunque se pida")
    func healthOffNeverReads() async {
        let reader = CountingHealthReader()
        let sut = HealthPrefillCoordinator(reader: reader, isEnabled: false)
        #expect(!sut.isOffered)
        let answer = await sut.prefill(AboutYouAnswer())
        #expect(answer == AboutYouAnswer())
        #expect(reader.reads == 0)
        #expect(sut.state == .idle)
    }

    @MainActor
    @Test("Salud encendida: como hoy, se ofrece y lee")
    func healthOnReads() async {
        let reader = CountingHealthReader()
        let sut = HealthPrefillCoordinator(reader: reader, isEnabled: true)
        #expect(sut.isOffered)
        let answer = await sut.prefill(AboutYouAnswer())
        #expect(answer.sex == .female)
        #expect(reader.reads == 1)
    }
}
