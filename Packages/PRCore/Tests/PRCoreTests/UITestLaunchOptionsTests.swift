//
//  UITestLaunchOptionsTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Las opciones de arranque para pruebas de UI sólo valen en Debug; fechas inválidas
//  se ignoran; el día fijado es el día LOCAL a mediodía.
//

import Foundation
import Testing
import PRCore

@Suite("Opciones de arranque para pruebas de UI")
struct UITestLaunchOptionsTests {

    private let utc = TimeZone(identifier: "UTC")!

    @Test("Release ignora siempre los argumentos")
    func releaseIgnoresEverything() {
        let options = UITestLaunchOptions.resolve(
            arguments: ["PR", "-PRUITestReset", "-PRFixedDate", "2026-10-19"], isDebugBuild: false
        )
        #expect(options == .none)
    }

    @Test("Demora del plan (SCRUM-193): sólo en Debug y sólo de 1 a 10 segundos")
    func planDelay() {
        #expect(UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestPlanDelay", "3"], isDebugBuild: true).planDelay == .seconds(3))
        #expect(UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestPlanDelay", "3"], isDebugBuild: false).planDelay == nil)
        for invalid in ["0", "11", "-2", "dos", ""] {
            #expect(UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestPlanDelay", invalid], isDebugBuild: true).planDelay == nil)
        }
        #expect(UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestPlanDelay"], isDebugBuild: true).planDelay == nil)
    }

    @Test("Debug sin argumentos = comportamiento normal")
    func debugWithoutArguments() {
        #expect(UITestLaunchOptions.resolve(arguments: ["PR"], isDebugBuild: true) == .none)
    }

    @Test("Debug con -PRUITestReset aísla la persistencia")
    func isolatedPersistence() {
        let options = UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestReset"], isDebugBuild: true)
        #expect(options.isolatedPersistence)
        #expect(options.fixedDay == nil)
    }

    @Test("Debug con -PRFixedDate fija el día local a mediodía")
    func fixedDate() throws {
        let options = UITestLaunchOptions.resolve(arguments: ["-PRFixedDate", "2026-10-19"], isDebugBuild: true)
        let date = try #require(options.fixedDate(timeZone: utc))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: date)
            == DateComponents(year: 2026, month: 10, day: 19, hour: 12))
    }

    @Test("El mismo día fijado es el mismo día local en otra zona horaria")
    func fixedDateIsLocalDay() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let options = UITestLaunchOptions(fixedDay: DateComponents(year: 2026, month: 10, day: 25))
        let date = try #require(options.fixedDate(timeZone: tokyo))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        #expect(calendar.component(.day, from: date) == 25)
    }

    @Test("Fechas mal escritas o inexistentes se ignoran",
          arguments: ["2026-13-01", "2026-02-30", "26-10-19", "2026-1-9", "hoy", "2026-10", ""])
    func invalidDatesAreIgnored(text: String) {
        let options = UITestLaunchOptions.resolve(arguments: ["-PRFixedDate", text], isDebugBuild: true)
        #expect(options.fixedDate(timeZone: utc) == nil)
    }

    @Test("-PRFixedDate sin valor se ignora")
    func missingValue() {
        let options = UITestLaunchOptions.resolve(arguments: ["-PRFixedDate"], isDebugBuild: true)
        #expect(options.fixedDay == nil)
    }

    // MARK: - Perfil sembrado (SCRUM-228)

    @Test("Debug con -PRUITestReset y -PRUITestProfile intermedio-lmv arranca con ese perfil")
    func seededProfile() {
        let options = UITestLaunchOptions.resolve(
            arguments: ["PR", "-PRUITestReset", "-PRUITestProfile", "intermedio-lmv"], isDebugBuild: true
        )
        #expect(options.seededProfile == .intermediateMondayWednesdayFriday)
        #expect(options.isolatedPersistence)
    }

    @Test("Release ignora el perfil sembrado aunque vengan todos los argumentos")
    func releaseIgnoresSeededProfile() {
        let options = UITestLaunchOptions.resolve(
            arguments: ["PR", "-PRFakeSignIn", "-PRUITestReset", "-PRUITestProfile", "intermedio-lmv"], isDebugBuild: false
        )
        #expect(options.seededProfile == nil)
        #expect(options == .none)
    }

    @Test("Sin -PRUITestReset el perfil se ignora: nunca se contesta sobre los datos reales")
    func seededProfileNeedsIsolatedPersistence() {
        let options = UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestProfile", "intermedio-lmv"], isDebugBuild: true)
        #expect(options.seededProfile == nil)
        #expect(options == .none)
    }

    @Test("Un perfil desconocido o sin valor se ignora",
          arguments: [["-PRUITestProfile", "avanzado"], ["-PRUITestProfile", ""], ["-PRUITestProfile", "INTERMEDIO-LMV"], ["-PRUITestProfile"]])
    func unknownSeededProfileIsIgnored(profileArguments: [String]) {
        let options = UITestLaunchOptions.resolve(arguments: ["PR", "-PRUITestReset"] + profileArguments, isDebugBuild: true)
        #expect(options.seededProfile == nil)
        #expect(options.isolatedPersistence)
    }

    @Test("Cada perfil sembrado se puede pedir por su nombre", arguments: UITestSeededProfile.allCases)
    func everySeededProfileResolves(profile: UITestSeededProfile) {
        let options = UITestLaunchOptions.resolve(
            arguments: ["-PRUITestReset", "-PRUITestProfile", profile.rawValue], isDebugBuild: true
        )
        #expect(options.seededProfile == profile)
    }
}
