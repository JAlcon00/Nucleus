//
//  FeatureFlagsTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de feature flags y configuración (PR-0004): defaults seguros, override
//  auditable, round-trip Codable, y rechazo de claves desconocidas.
//

import Foundation
import Testing
@testable import PRCore

@Suite("Feature flags (PR-0004)")
struct FeatureFlagsTests {

    @Test("All agent capabilities are off by default in production")
    func safeDefaults() {
        let flags = FeatureFlags()
        for key in FeatureFlagKey.allCases {
            #expect(!flags.isEnabled(key), "\(key.rawValue) must default to disabled")
            #expect(flags.source(of: key) == .default)
        }
    }

    @Test("Override marks the source as override")
    func overrideIsAuditable() {
        let flags = FeatureFlags().setting(.agentToolsWriteEnabled, to: true)
        #expect(flags.isEnabled(.agentToolsWriteEnabled))
        #expect(flags.source(of: .agentToolsWriteEnabled) == .override)
        #expect(flags.isEnabled(.agentNvidiaEnabled) == false, "other flags unaffected")
    }

    @Test("Read-only coaching is independent from agentic writes")
    func readOnlyIndependentFromWrites() {
        let readOnly = FeatureFlags().setting(.agentNvidiaEnabled, to: true)
        #expect(readOnly.isEnabled(.agentNvidiaEnabled))
        #expect(readOnly.isEnabled(.agentToolsWriteEnabled) == false)
        #expect(readOnly.isEnabled(.agentExerciseSubstitutionEnabled) == false)
    }

    @Test("Codable round-trip preserves flags and sources")
    func codableRoundTrip() throws {
        let flags = FeatureFlags()
            .setting(.agentNvidiaStreamingEnabled, to: true)
            .setting(.agentRecoveryAdjustmentEnabled, to: true)
        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(FeatureFlags.self, from: data)
        #expect(decoded.isEnabled(.agentNvidiaStreamingEnabled))
        #expect(decoded.source(of: .agentNvidiaStreamingEnabled) == .override)
        #expect(decoded.isEnabled(.agentToolsWriteEnabled) == false)
        #expect(decoded.all.count == FeatureFlagKey.allCases.count)
    }

    @Test("Decoder rejects unknown keys")
    func rejectsUnknownKey() throws {
        let unknown = #"{"storage":{"agent.unknown.flag":{"enabled":true,"source":"override"}}}"#
        #expect(throws: FeatureFlagsError.unknownKey("agent.unknown.flag")) {
            _ = try JSONDecoder().decode(FeatureFlags.self, from: Data(unknown.utf8))
        }
    }

    @Test("Configuration carries no secrets, only an environment tag")
    func configHasNoSecrets() {
        let config = AppConfiguration(environmentTag: "production")
        #expect(config.environmentTag == "production")
        #expect(!config.environmentTag.contains("api_key"))
        #expect(!config.environmentTag.contains("token"))
    }
}