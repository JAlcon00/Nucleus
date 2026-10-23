//
//  AppearancePreferenceTests.swift
//  PRCoreTests
//
//  SCRUM-208 (FB-1): la apariencia elegida se recuerda; sin elección o con un valor que
//  ya no existe, la app queda en oscuro (como hasta ahora).
//

import Foundation
import Testing
import PRCore

@Suite("Apariencia (SCRUM-208)")
struct AppearancePreferenceTests {

    @Test("Lo guardado se lee igual")
    func roundTrip() {
        for preference in AppearancePreference.allCases {
            #expect(AppearancePreference.resolve(preference.rawValue) == preference)
        }
    }

    @Test("Sin elección o con un valor desconocido: oscuro")
    func fallback() {
        #expect(AppearancePreference.resolve(nil) == .dark)
        #expect(AppearancePreference.resolve("sepia") == .dark)
    }

    @Test("Se recuerda entre arranques en UserDefaults con su clave")
    func persistsInDefaults() throws {
        let suite = "appearance-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppearancePreference.light.rawValue, forKey: AppearancePreference.storageKey)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(AppearancePreference.resolve(reopened.string(forKey: AppearancePreference.storageKey)) == .light)
    }
}
