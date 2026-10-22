//
//  SleepCheckInTests.swift
//  PRCoreTests
//
//  SCRUM-203 (IA-2): check-in de sueño guardado por usuario y día; aligera la sesión de
//  hoy sin tocar el bloque, y la sesión ajustada se puede retomar.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let mexico = TimeZone(identifier: "America/Mexico_City") ?? .current

/// Lunes 19 de octubre de 2026 a mediodía en Ciudad de México.
private func monday() throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = mexico
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
}

@MainActor
@Suite("Check-in de sueño (SCRUM-203)")
struct SleepCheckInTests {

    @Test("Se guarda por usuario y día; un registro dañado no ajusta nada")
    func storeRoundTrip() throws {
        let memory = MemoryRepositoryStore()
        let store = SleepCheckInStore(store: memory)
        let checkIn = try SleepCheckIn(day: "2026-10-19", hours: 5, quality: .poor)
        try store.save(checkIn, userID: "ana")
        #expect(try store.load(userID: "ana", day: "2026-10-19") == checkIn)
        #expect(try store.load(userID: "ana", day: "2026-10-20") == nil, "Otro día")
        #expect(try store.load(userID: "luis", day: "2026-10-19") == nil, "Otro usuario")
        let key = try #require(memory.readAllEntries().entries.first?.key)
        try memory.write(key: key, data: Data(#"{"day":"2026-10-19","hours":40,"quality":"poor"}"#.utf8))
        #expect(try store.load(userID: "ana", day: "2026-10-19") == nil, "Horas imposibles no se aceptan del disco")
    }

    @Test("Se pregunta una vez al día; \"hoy no\" no vuelve a preguntar hasta mañana")
    func askOncePerDay() throws {
        var now = try monday()
        let coordinator = SleepCheckInCoordinator(
            store: SleepCheckInStore(store: MemoryRepositoryStore()), clock: { now }, timeZone: { mexico }
        )
        coordinator.load(userID: "ana")
        #expect(coordinator.needsCheckIn)
        coordinator.skip()
        #expect(!coordinator.needsCheckIn)
        #expect(coordinator.adjustment == .none)
        now = now.addingTimeInterval(24 * 3600)
        coordinator.load(userID: "ana")
        #expect(coordinator.needsCheckIn, "Al día siguiente se vuelve a preguntar")
    }

    @Test("Registrar dormir mal devuelve el ajuste y queda guardado para el resto del día")
    func recordPersists() throws {
        let now = try monday()
        let store = SleepCheckInStore(store: MemoryRepositoryStore())
        let coordinator = SleepCheckInCoordinator(store: store, clock: { now }, timeZone: { mexico })
        coordinator.load(userID: "ana")
        let adjustment = coordinator.record(hours: 7.5, quality: .poor)
        #expect(adjustment == .lighter(reason: .poorSleep, rirIncrease: 1, isolationSetReduction: 1))
        #expect(!coordinator.needsCheckIn)

        let reopened = SleepCheckInCoordinator(store: store, clock: { now }, timeZone: { mexico })
        reopened.load(userID: "ana")
        #expect(reopened.today?.quality == .poor, "Al reabrir la app se conserva")
        #expect(reopened.adjustment == adjustment)
        #expect(reopened.record(hours: 30, quality: .good) == nil, "Horas inválidas no cambian nada")
    }

    @Test("Hoy se aligera sobre el mismo bloque y la sesión ajustada es la que se retoma")
    func todayIsLighter() async throws {
        let now = try monday()
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let todayPlan = TodayPlanCoordinator(catalog: catalog, clock: { now }, timeZone: { mexico })
        let profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 3, usualSessionMinutes: 60, varietyPreference: .balanced,
            defaultGymID: nil, restrictions: []
        )
        #expect(todayPlan.load(profile: profile))
        let before = try #require(todayPlan.plan?.todayTemplate)
        let blockBefore = try #require(todayPlan.plan?.block)

        let lighter = ReadinessAdjustment.lighter(reason: .shortSleep, rirIncrease: 1, isolationSetReduction: 1)
        todayPlan.applyReadiness(lighter)
        let after = try #require(todayPlan.plan?.todayTemplate)
        #expect(todayPlan.plan?.readiness == lighter)
        #expect(after.id == before.id)
        #expect(todayPlan.plan?.block == blockBefore, "El bloque no cambia")
        #expect(after.plannedSets.count <= before.plannedSets.count)
        for planned in after.plannedSets where !planned.prescription.isWarmup {
            let original = try #require(before.plannedSets.first { $0.exerciseID == planned.exerciseID && !$0.prescription.isWarmup })
            let rir = try #require(planned.prescription.targetRIR)
            let oldRIR = try #require(original.prescription.targetRIR)
            #expect(rir.lowerBound == oldRIR.lowerBound + 1)
        }
        let known = await todayPlan.allKnownTemplates()
        #expect(known.first == after, "Al retomar se usa la sesión aligerada")

        todayPlan.applyReadiness(.none)
        #expect(todayPlan.plan?.todayTemplate == before, "Sin ajuste vuelve la sesión planeada")
    }
}
