//
//  PlanDaysMigrationTests.swift
//  PRCoreTests
//
//  SCRUM-196 (U3): un plan guardado antes de poder elegir los días (sólo "N días") se lee
//  con el `LocalPersistence` real como los primeros N días desde el lunes, igual que antes:
//  ningún bloque cambia en silencio. Y un plan con días elegidos (L, Mi, V) deja descanso
//  intercalado en "Hoy".
//

import Foundation
import Testing
import PRCore
import PRDomain

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-days-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Un día concreto de la semana del 19 de octubre de 2026 (lunes = 0), a mediodía en UTC.
private func day(_ mondayIndex: Int) throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 19 + mondayIndex
    components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private let utc = TimeZone(identifier: "UTC") ?? .current

@MainActor
private func coordinator(root: URL, on date: Date) throws -> TodayPlanCoordinator {
    let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
    return TodayPlanCoordinator(
        catalog: try ExerciseCatalogLoader.loadBundled(),
        planStore: try persistence.planStore(),
        clock: { date },
        timeZone: { utc }
    )
}

@MainActor
@Suite("Plan guardado: días de entrenamiento (SCRUM-196)")
struct PlanDaysMigrationTests {

    @Test("Plan de la versión anterior (sólo N días): mismos días que antes y mismo bloque")
    func previousVersionPlanKeepsFirstDays() async throws {
        let root = try makeRoot()
        let legacyProfile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced
        )
        let first = try coordinator(root: root, on: try day(0))
        #expect(await first.activate(profile: legacyProfile, userID: "u1"))
        let blockID = try #require(first.plan?.block.id)

        // Reescribe el archivo como lo guardaba la versión anterior: sin `trainingWeekdays`.
        let plans = root.appendingPathComponent("plans", isDirectory: true)
        // El registro del plan; los ocultos son de control (marca de versión, SCRUM-40).
        let files = try FileManager.default.contentsOfDirectory(at: plans, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        let file = try #require(files.first { $0.pathExtension == "json" })
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var profileJSON = try #require(json["profile"] as? [String: Any])
        #expect(profileJSON["trainingWeekdays"] != nil, "La versión actual guarda los días")
        profileJSON.removeValue(forKey: "trainingWeekdays")
        json["profile"] = profileJSON
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        // Miércoles: tercer día de "3 días" de antes → se entrena.
        let wednesday = try coordinator(root: root, on: try day(2))
        guard case .restored(let restored) = await wednesday.restore(userID: "u1") else {
            Issue.record("El plan anterior debía recuperarse"); return
        }
        #expect(restored.trainingWeekdays == [.monday, .tuesday, .wednesday])
        #expect(wednesday.plan?.block.id == blockID, "El bloque no cambia")
        guard case .readyToStart = wednesday.plan?.todayState else {
            Issue.record("El miércoles debía tocar entrenar, estado \(String(describing: wednesday.plan?.todayState))"); return
        }

        // Jueves: descanso, como antes.
        let thursday = try coordinator(root: root, on: try day(3))
        _ = await thursday.restore(userID: "u1")
        #expect(thursday.plan?.todayState == .restDay)
    }

    @Test("Lunes, miércoles y viernes: el martes es descanso y el miércoles toca la segunda sesión")
    func chosenDaysInterleaveRest() async throws {
        let root = try makeRoot()
        let profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        let monday = try coordinator(root: root, on: try day(0))
        #expect(await monday.activate(profile: profile, userID: "u1"))
        let sessions = try #require(monday.plan?.sessions)
        #expect(monday.plan?.todayTemplate?.id == sessions.first?.id)

        let tuesday = try coordinator(root: root, on: try day(1))
        _ = await tuesday.restore(userID: "u1")
        #expect(tuesday.plan?.todayState == .restDay)

        let wednesday = try coordinator(root: root, on: try day(2))
        _ = await wednesday.restore(userID: "u1")
        #expect(wednesday.plan?.todayTemplate?.id == sessions[1 % sessions.count].id)
    }
}
