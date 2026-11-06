//
//  HealthEnergyTests.swift
//  PRCoreTests
//
//  SCRUM-250 (PR-F007): la energía de cada sesión una sola vez y con su fuente, y las
//  actividades de Salud como contexto. Salud va con fake; el disco es real.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

private struct EnergyHarness {
    let root: URL
    let repository: FileWorkoutRepository
    let health = FakeHealthWorkoutStore()
    let start = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { start.addingTimeInterval(4 * 3600) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum250-\(UUID().uuidString)")
        repository = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).workoutRepository()
    }

    func coordinator(canRead: Bool = true, repository: FileWorkoutRepository? = nil) -> HealthEnergyCoordinator {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return HealthEnergyCoordinator(
            repository: repository ?? self.repository,
            reader: HealthExternalWorkoutsReader(
                reader: health,
                isEnabled: true,
                ownBundleIdentifier: FakeHealthWorkoutStore.ownBundleIdentifier,
                calendar: calendar
            ),
            canRead: { canRead }
        )
    }

    func session(from startMinute: Double = 0, to endMinute: Double = 60) throws -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            startedAt: start.addingTimeInterval(startMinute * 60),
            endedAt: start.addingTimeInterval(endMinute * 60),
            lifecycle: .completed,
            sets: [try SetRecord(exerciseID: ExerciseID(), weight: 80, unit: .kilograms, reps: 8, lifecycle: .completed)]
        )
    }

    func watch(from startMinute: Double = 0, to endMinute: Double = 60, kcal: Double? = 240, bundle: String = "com.apple.health.x", type: HealthWorkoutActivityType = .strengthTraining) -> HealthWorkoutSample {
        HealthWorkoutSample(
            uuid: UUID(),
            start: start.addingTimeInterval(startMinute * 60),
            end: start.addingTimeInterval(endMinute * 60),
            activityType: type,
            activeKilocalories: kcal,
            sourceBundleIdentifier: bundle,
            sourceName: "Reloj"
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite("Ver la energía una sola vez (SCRUM-250)")
struct HealthEnergyTests {

    // Criterio 1
    @Test("Con un entrenamiento de reloj que se solapa, la sesión muestra su energía una vez")
    func sessionGetsWatchEnergy() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch(from: 5, to: 65)])

        let activities = try await harness.coordinator().refresh(now: harness.now)

        let saved = try #require(try await harness.repository.session(id: session.id))
        #expect(saved.energy?.activeKilocalories == 240)
        #expect(saved.energy?.source == .externalAppleWorkout)
        #expect(activities.isEmpty)
        let label = HealthEnergyPresenter.label(for: .externalAppleWorkout, locale: Locale(identifier: "es_MX"))
        #expect(label == "Energía activa · Apple Watch")
        #expect(HealthEnergyPresenter.value(try #require(saved.energy)) == "240 kcal")
    }

    // Criterio 2
    @Test("Sin coincidencia no hay energía: ni cero ni estimación")
    func noMatchNoEnergy() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch(from: 120, to: 150)])

        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: session.id)?.energy == nil)
    }

    @Test("Un entrenamiento coincidente sin energía no inventa energía")
    func matchWithoutEnergyStaysEmpty() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch(kcal: nil)])

        let activities = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: session.id)?.energy == nil)
        #expect(activities.isEmpty)
    }

    // Criterio 3
    @Test("Dos fuentes del mismo entrenamiento no se suman: el total semanal cuenta una")
    func weeklyTotalCountsOnce() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([
            harness.watch(kcal: 240),
            harness.watch(kcal: 300, bundle: "com.otra.app"),
        ])

        _ = try await harness.coordinator().refresh(now: harness.now)

        let sessions = try await harness.repository.allSessions()
        let total = ProgressOverviewBuilder().activeEnergy(inWeekOf: harness.start, timeZone: .gmt, sessions: sessions)
        #expect(total == 240)
    }

    @Test("El total semanal suma sesiones distintas y sin energía es nil")
    func weeklyTotalAcrossSessions() throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        var first = try harness.session()
        var second = try harness.session(from: 120, to: 180)
        #expect(ProgressOverviewBuilder().activeEnergy(inWeekOf: harness.start, timeZone: .gmt, sessions: [first, second]) == nil)

        first.energy = CanonicalWorkoutEnergy(activeKilocalories: 100, source: .externalAppleWorkout, confidence: 0.92)
        second.energy = CanonicalWorkoutEnergy(activeKilocalories: 50, source: .externalHealthKitWorkout, confidence: 0.85)
        #expect(ProgressOverviewBuilder().activeEnergy(inWeekOf: harness.start, timeZone: .gmt, sessions: [first, second]) == 150)
    }

    // Criterio 4 e integración
    @Test("Si el reloj llega tarde, al reabrir aparece la energía, una vez")
    func lateWatchWorkout() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        _ = try await harness.coordinator().refresh(now: harness.now)
        #expect(try await harness.repository.session(id: session.id)?.energy == nil)

        await harness.health.setOtherSamples([harness.watch()])
        let reopened = try LocalPersistence(rootURL: harness.root, log: PersistenceLog { _ in }).workoutRepository()
        let coordinator = harness.coordinator(repository: reopened)
        _ = try await coordinator.refresh(now: harness.now)
        _ = try await coordinator.refresh(now: harness.now)

        #expect(try await reopened.session(id: session.id)?.energy?.activeKilocalories == 240)
        #expect(try await coordinator.energy(of: session.id)?.source == .externalAppleWorkout)
    }

    @Test("Lo ya guardado no se reemplaza por otra fuente que llegue después")
    func storedEnergyIsKept() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch(kcal: 300, bundle: "com.otra.app")])
        _ = try await harness.coordinator().refresh(now: harness.now)

        await harness.health.setOtherSamples([harness.watch(kcal: 240)])
        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: session.id)?.energy?.activeKilocalories == 300)
    }

    // Criterio 5
    @Test("Un externo sin sesión sale como actividad, con duración, fuente y energía")
    func externalWithoutSession() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        await harness.health.setOtherSamples([harness.watch(from: 0, to: 30, type: .running)])

        let activities = try await harness.coordinator().refresh(now: harness.now)

        #expect(activities.count == 1)
        #expect(activities[0].durationSeconds == 1800)
        #expect(activities[0].sourceName == "Reloj")
        #expect(activities[0].energy?.activeKilocalories == 240)
        #expect(activities[0].activity == "running")
    }

    @Test("Dos apps con el mismo entrenamiento son una sola actividad")
    func duplicateExternalsAreOneActivity() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        await harness.health.setOtherSamples([
            harness.watch(kcal: 240),
            harness.watch(kcal: 300, bundle: "com.otra.app"),
        ])

        let activities = try await harness.coordinator().refresh(now: harness.now)

        #expect(activities.count == 1)
        #expect(activities[0].energy?.activeKilocalories == 240)
    }

    // Criterio 6
    @Test("Una actividad no cuenta en el historial ni en la semana")
    func activityDoesNotCount() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        await harness.health.setOtherSamples([harness.watch()])

        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.allSessions().isEmpty)
        let overview = ProgressOverviewBuilder().overview(
            history: try await harness.repository.allSessions(),
            templateTitles: [:],
            exerciseNames: [:],
            plannedPerWeek: 3,
            date: harness.now,
            timeZone: .gmt
        )
        #expect(overview.totalWorkouts == 0)
        #expect(overview.completedThisWeek == 0)
    }

    // Criterio 7
    @Test("El export lleva la energía con su fuente y las actividades como actividades")
    func exportCarriesBoth() throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        var session = try harness.session()
        session.energy = CanonicalWorkoutEnergy(activeKilocalories: 240, source: .externalAppleWorkout, confidence: 0.92)
        let activity = HealthActivity(
            id: UUID(), start: harness.start, end: harness.now, activity: "running",
            sourceName: "Reloj", energy: nil
        )

        let file = try DataExportCoordinator().exportJSON(
            sessions: [session], exercises: [], blocks: [], gyms: [], restrictions: [], profile: nil,
            healthActivities: [activity]
        )

        let text = String(decoding: file.data, as: UTF8.self)
        #expect(text.contains("externalAppleWorkout"))
        #expect(text.contains("healthActivities"))
        let bundle = try JSONDecoder.iso8601.decode(ExportBundle.self, from: file.data)
        #expect(bundle.healthActivities?.count == 1)
        #expect(bundle.sessions.count == 1)
        #expect(bundle.sessions[0].sets.count == 1)
    }

    @Test("Sin actividades el export no agrega la clave")
    func exportWithoutActivities() throws {
        let file = try DataExportCoordinator().exportJSON(
            sessions: [], exercises: [], blocks: [], gyms: [], restrictions: [], profile: nil
        )
        #expect(!String(decoding: file.data, as: UTF8.self).contains("healthActivities"))
    }

    // Criterio 8
    @Test("Con Salud apagada no entra energía nueva y lo guardado se queda")
    func turnedOff() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        var stored = try harness.session()
        stored.energy = CanonicalWorkoutEnergy(activeKilocalories: 200, source: .externalAppleWorkout, confidence: 0.92)
        let other = try harness.session(from: 120, to: 180)
        try await harness.repository.save(stored)
        try await harness.repository.save(other)
        await harness.health.setOtherSamples([harness.watch(from: 120, to: 180)])

        let activities = try await harness.coordinator(canRead: false).refresh(now: harness.now)

        #expect(activities.isEmpty)
        #expect(try await harness.repository.session(id: other.id)?.energy == nil)
        #expect(try await harness.repository.session(id: stored.id)?.energy?.activeKilocalories == 200)
    }

    // Criterio 9
    @Test("Ni energía ni actividades entran al contexto de la IA")
    func notInAIContext() throws {
        // El contexto sólo se arma con perfil, consentimiento y sueño: su fuente no los nombra.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PRDomain/AgentProfileContext.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        for word in ["CanonicalWorkoutEnergy", "HealthActivity", "activeKilocalories", "WorkoutSessionRecord"] {
            #expect(!text.contains(word))
        }
    }

    // Casos límite
    @Test("Una sesión contra dos externos toma una sola energía")
    func oneSessionTwoExternals() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([
            harness.watch(from: 0, to: 30, kcal: 100),
            harness.watch(from: 30, to: 60, kcal: 120),
        ])

        let activities = try await harness.coordinator().refresh(now: harness.now)

        let energy = try await harness.repository.session(id: session.id)?.energy
        #expect(energy?.activeKilocalories == 100 || energy?.activeKilocalories == 120)
        #expect(activities.isEmpty)
    }

    @Test("Un externo que cubre dos sesiones da su energía a una sola")
    func oneExternalTwoSessions() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let long = try harness.session(from: 0, to: 40)
        let short = try harness.session(from: 45, to: 60)
        try await harness.repository.save(long)
        try await harness.repository.save(short)
        await harness.health.setOtherSamples([harness.watch(from: 0, to: 60)])

        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: long.id)?.energy?.activeKilocalories == 240)
        #expect(try await harness.repository.session(id: short.id)?.energy == nil)
    }

    @Test("Energía cero real se guarda y se muestra")
    func zeroEnergy() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch(kcal: 0)])

        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: session.id)?.energy?.activeKilocalories == 0)
    }

    @Test("Una sesión abierta no se toca")
    func openSessionIsIgnored() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        var open = try harness.session()
        open.lifecycle = .active
        open.endedAt = nil
        try await harness.repository.save(open)
        await harness.health.setOtherSamples([harness.watch()])

        _ = try await harness.coordinator().refresh(now: harness.now)

        #expect(try await harness.repository.session(id: open.id)?.energy == nil)
    }

    @Test("Sin permiso o con Salud fallando no pasa nada")
    func readFailure() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        await harness.health.setOtherSamples([harness.watch()])
        await harness.health.setFailsOnRead(true)

        #expect(try await harness.coordinator().refresh(now: harness.now).isEmpty)
        #expect(try await harness.repository.session(id: session.id)?.energy == nil)
    }

    @Test("Lo que escribió Nucleus no se cuenta como su propia energía")
    func ownWriteIsNotEnergy() async throws {
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let session = try harness.session()
        try await harness.repository.save(session)
        let writer = HealthWriteCoordinator(repository: harness.repository, writer: harness.health, canWrite: { true })
        try await writer.sessionFinished(id: session.id)

        let activities = try await harness.coordinator().refresh(now: harness.now)

        #expect(activities.isEmpty)
        #expect(try await harness.repository.session(id: session.id)?.energy == nil)
    }

    // Formato
    @Test("El tipo movido conserva sus claves y una sesión anterior se lee igual")
    func formatIsKept() throws {
        let energy = CanonicalWorkoutEnergy(activeKilocalories: 240, source: .externalAppleWorkout, confidence: 0.92)
        let text = String(decoding: try JSONEncoder().encode(energy), as: UTF8.self)
        for key in ["activeKilocalories", "source", "confidence", "externalAppleWorkout"] {
            #expect(text.contains(key))
        }
        let harness = try EnergyHarness()
        defer { harness.cleanUp() }
        let data = try JSONEncoder().encode(try harness.session())
        #expect(!String(decoding: data, as: UTF8.self).contains("\"energy\""))
        #expect(try JSONDecoder().decode(WorkoutSessionRecord.self, from: data).energy == nil)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
