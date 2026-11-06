//
//  ExternalWorkoutTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de consulta de workouts externos (PR-1104): importa metadata autorizada,
//  NO inventa set data (promptMaster §14.1) y permite vincular el workout del día al
//  plan por sugerencia o manualmente. HealthKit real queda detrás del protocolo.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("External workouts query (PR-1104)")
struct ExternalWorkoutTests {

    private func makeExternal(start: Date, end: Date, kcal: Double? = 120) -> ExternalWorkout {
        ExternalWorkout(
            referenceID: HealthWorkoutHandle.ID(),
            start: start,
            end: end,
            activityType: .strengthTraining,
            activeKilocalories: kcal,
            sourceName: "Apple Watch",
            deviceName: "Watch"
        )
    }

    private func template(_ title: String) -> SessionTemplate {
        SessionTemplate(id: UUID(), title: title, plannedSets: [], estimatedMinutes: nil)
    }

    // 1. Importa metadata autorizada: devuelve workouts dentro de la consulta.
    @Test("Importa metadata autorizada del intervalo consultado")
    func importsAuthorizedMetadata() async {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(initialStatus: [.workout: .granted]),
            externalWorkouts: [
                makeExternal(start: t, end: t.addingTimeInterval(3600)),
                makeExternal(start: t.addingTimeInterval(7200), end: t.addingTimeInterval(10800)),
            ]
        )
        // Consulta sólo la primera hora.
        let query = ExternalWorkoutQuery(since: t, until: t.addingTimeInterval(4000))
        let workouts = try! await store.recentWorkouts(in: query)
        #expect(workouts.count == 1)
        #expect(workouts[0].sourceName == "Apple Watch")
    }

    // 1b. Sin permiso .workout, no se importa metadata.
    @Test("Sin permiso .workout no se importa metadata")
    func noPermissionNoImport() async {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(),
            externalWorkouts: [makeExternal(start: t, end: t.addingTimeInterval(3600))]
        )
        // El provider por defecto tiene .notDetermined, así que no se importa.
        let query = ExternalWorkoutQuery(since: t.addingTimeInterval(-1000), until: t.addingTimeInterval(7200))
        let workouts = try! await store.recentWorkouts(in: query)
        #expect(workouts.isEmpty)
    }

    // 2. No inventa set data: el modelo de workout externo es sólo metadata (sin sets).
    @Test("El workout externo no inventa set data (sólo metadata autorizada)")
    func noSetDataInExternal() {
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600), kcal: 90)
        // Expone únicamente metadata autorizada: fecha, tipo, energía, fuente.
        #expect(workout.activityType == .strengthTraining)
        #expect(workout.activeKilocalories == 90)
        #expect(workout.energyOrigin == .measured)
        #expect(workout.sourceName == "Apple Watch")
    }

    // 3. Puede vincular el workout del día al plan por sugerencia.
    @Test("Sugiere vincular el workout del día a una plantilla candidata")
    func suggestsLinkToPlan() {
        let linker = WorkoutPlanLinker()
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let day = DayInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        let workout = makeExternal(start: dayStart.addingTimeInterval(3600), end: dayStart.addingTimeInterval(7200))
        let candidates = [template("Push Day"), template("Pull Day")]

        let suggestion = linker.suggestTemplate(for: workout, candidates: candidates, day: day)
        // Sugerencia determinista: primera candidata del día.
        #expect(suggestion == candidates[0].id)
    }

    // 3b. Fuera del día no hay sugerencia; nunca se inventa un vínculo forzado.
    @Test("Fuera del día no sugiere ninguna plantilla")
    func noSuggestionOutsideDay() {
        let linker = WorkoutPlanLinker()
        let dayStart = Date(timeIntervalSince1970: 1_000_000)
        let day = DayInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        // Workout en otro día (antes del día considerado).
        let workout = makeExternal(start: dayStart.addingTimeInterval(-86_400), end: dayStart.addingTimeInterval(-82_800))

        let suggestion = linker.suggestTemplate(for: workout, candidates: [template("Push")], day: day)
        #expect(suggestion == nil)
    }

    // 3c. El vínculo manual prevalece y permite desvincular.
    @Test("El vínculo manual prevalece sobre la sugerencia y permite desvincular")
    func manualLinkOverrides() {
        let linker = WorkoutPlanLinker()
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600))
        let push = template("Push Day")

        let manual = linker.manualLink(workout, to: push.id)
        #expect(manual.templateID == push.id)
        #expect(manual.decision == .manual)

        let unlinked = linker.manualLink(workout, to: nil)
        #expect(unlinked.decision == .manual)
        #expect(unlinked.templateID == nil)
    }

    // 3d. Una sugerencia nunca se aplica sola: queda marcada como .suggestion.
    @Test("Una sugerencia nunca se aplica sola (queda marcada como suggestion)")
    func suggestionIsNotSelfApplied() {
        let linker = WorkoutPlanLinker()
        let workout = makeExternal(start: Date(), end: Date().addingTimeInterval(600))
        let link = linker.link(workout, to: template("Push").id, manual: false)
        #expect(link.decision == .suggestion)
    }
}

// MARK: - SCRUM-249: leer entrenamientos externos sin confundirlos con los nuestros

@Suite("Entrenamientos externos reales (SCRUM-249)")
struct ExternalWorkoutReadingTests {

    private let own = FakeHealthWorkoutStore.ownBundleIdentifier
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func sample(
        minutesAgo: Double = 120,
        type: HealthWorkoutActivityType = .running,
        kcal: Double? = 300,
        bundle: String = "com.otra.app",
        sync: String? = nil,
        uuid: UUID = UUID()
    ) -> HealthWorkoutSample {
        let start = now.addingTimeInterval(-minutesAgo * 60)
        return HealthWorkoutSample(
            uuid: uuid,
            start: start,
            end: start.addingTimeInterval(1800),
            activityType: type,
            activeKilocalories: kcal,
            sourceBundleIdentifier: bundle,
            sourceName: "Otra app",
            syncIdentifier: sync
        )
    }

    private func reader(_ store: FakeHealthWorkoutStore, isEnabled: Bool = true) -> HealthExternalWorkoutsReader {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return HealthExternalWorkoutsReader(
            reader: store, isEnabled: isEnabled, ownBundleIdentifier: own, calendar: calendar
        )
    }

    // Criterio 1
    @Test("Un entrenamiento de otra app llega con inicio, fin, tipo, energía y fuente")
    func externalArrivesWithGeneralData() async {
        let store = FakeHealthWorkoutStore()
        let original = sample()
        await store.setOtherSamples([original])

        let workouts = await reader(store).recentWorkouts(now: now, ownSyncIdentifiers: [])

        #expect(workouts.count == 1)
        #expect(workouts[0].start == original.start)
        #expect(workouts[0].end == original.end)
        #expect(workouts[0].activityType == .running)
        #expect(workouts[0].activeKilocalories == 300)
        #expect(workouts[0].sourceName == "Otra app")
    }

    @Test("Se consultan 14 días: lo anterior no llega")
    func onlyTheLastFourteenDays() async {
        let store = FakeHealthWorkoutStore()
        await store.setOtherSamples([
            sample(minutesAgo: 13 * 24 * 60),
            sample(minutesAgo: 15 * 24 * 60),
        ])

        #expect(await reader(store).recentWorkouts(now: now, ownSyncIdentifiers: []).count == 1)
    }

    // Criterio 2
    @Test("Lo escrito por Nucleus nunca llega como externo: por fuente")
    func ownFilteredBySource() {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(bundle: own)], ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        #expect(workouts.isEmpty)
    }

    @Test("Lo escrito por Nucleus nunca llega como externo: por identificador")
    func ownFilteredBySyncIdentifier() {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(bundle: "creadevs.PR.otro", sync: "sesion-1")],
            ownBundleIdentifier: own,
            ownSyncIdentifiers: ["sesion-1"],
            now: now
        )
        #expect(workouts.isEmpty)
    }

    @Test("Un identificador ajeno no se confunde con uno propio")
    func foreignSyncIdentifierStays() {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(sync: "de-otra-app")],
            ownBundleIdentifier: own,
            ownSyncIdentifiers: ["sesion-1"],
            now: now
        )
        #expect(workouts.count == 1)
    }

    // Criterio 3
    @Test("La fuente se clasifica por identificador de la app", arguments: [
        ("com.apple.health.0A1B2C3D-AAAA-BBBB-CCCC-000000000000", EnergySource.externalAppleWorkout),
        ("com.apple.health", .externalAppleWorkout),
        ("com.strava.app", .externalHealthKitWorkout),
        ("com.apple.otra", .externalHealthKitWorkout),
    ])
    func classifiesSource(bundle: String, expected: EnergySource) {
        #expect(HealthWorkoutClassifier.energySource(bundleIdentifier: bundle) == expected)
    }

    @Test("Un entrenamiento del reloj llega con fuente Apple")
    func watchWorkoutKeepsItsSource() {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(bundle: "com.apple.health.ABC")], ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        #expect(workouts.first?.energySource == .externalAppleWorkout)
    }

    // Criterio 4
    @Test("Un tipo desconocido llega como otro y no falla")
    func unknownTypeIsOther() async {
        let store = FakeHealthWorkoutStore()
        await store.setOtherSamples([sample(type: .other)])

        #expect(await reader(store).recentWorkouts(now: now, ownSyncIdentifiers: []).first?.activityType == .other)
    }

    // Criterio 5
    @Test("Sin permiso o con error de Salud el resultado es vacío, sin error")
    func noPermissionIsEmpty() async {
        let store = FakeHealthWorkoutStore()
        await store.setOtherSamples([sample()])
        await store.setFailsOnRead(true)

        #expect(await reader(store).recentWorkouts(now: now, ownSyncIdentifiers: []).isEmpty)
    }

    @Test("Con el flag apagado no se lee nada")
    func flagOffReadsNothing() async {
        let store = FakeHealthWorkoutStore()
        await store.setOtherSamples([sample()])

        #expect(await reader(store, isEnabled: false).recentWorkouts(now: now, ownSyncIdentifiers: []).isEmpty)
    }

    // Criterio 6
    @Test("Ningún externo trae series, reps ni peso")
    func noSetData() throws {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample()], ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        let workout = try #require(workouts.first)
        let fields = Set(Mirror(reflecting: workout).children.compactMap(\.label))
        #expect(fields.isDisjoint(with: ["sets", "reps", "weight"]))
    }

    // Criterio 7
    @Test("La misma consulta dos veces no duplica; un uuid repetido llega una vez")
    func noDuplicates() async {
        let store = FakeHealthWorkoutStore()
        let id = UUID()
        await store.setOtherSamples([sample(uuid: id), sample(uuid: id)])
        let reader = reader(store)

        let first = await reader.recentWorkouts(now: now, ownSyncIdentifiers: [])
        let second = await reader.recentWorkouts(now: now, ownSyncIdentifiers: [])

        #expect(first.count == 1)
        #expect(first == second)
        #expect(first[0].referenceID.rawValue == id)
    }

    // Casos límite
    @Test("Sin energía sigue sin energía; negativa o NaN no cuenta", arguments: [Double?.none, -5, .nan])
    func withoutRealEnergy(kcal: Double?) {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(kcal: kcal)], ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        #expect(workouts.first?.activeKilocalories == nil)
        #expect(workouts.first?.energyOrigin == .unavailable)
    }

    @Test("Un entrenamiento en curso todavía no llega")
    func inProgressIsNotReturned() {
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: [sample(minutesAgo: 10)], ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        #expect(workouts.isEmpty)
    }

    @Test("Más de 500 entrenamientos llegan todos, en orden")
    func manyWorkouts() {
        let samples = (0..<600).map { sample(minutesAgo: 120 + Double($0)) }
        let workouts = HealthWorkoutClassifier.externalWorkouts(
            from: samples.shuffled(), ownBundleIdentifier: own, ownSyncIdentifiers: [], now: now
        )
        #expect(workouts.count == 600)
        #expect(workouts.map(\.start) == workouts.map(\.start).sorted())
    }

    // Integración: PR-F003 escribe y la consulta no lo devuelve.
    @Test("Lo que escribe la cola de Salud no vuelve como externo")
    func writtenWorkoutDoesNotComeBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum249-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).workoutRepository()
        let store = FakeHealthWorkoutStore()
        let session = WorkoutSessionRecord(
            startedAt: now.addingTimeInterval(-7200),
            endedAt: now.addingTimeInterval(-3600),
            lifecycle: .completed,
            sets: [try SetRecord(exerciseID: ExerciseID(), weight: 80, unit: .kilograms, reps: 8, lifecycle: .completed)]
        )
        try await repository.save(session)
        let writer = HealthWriteCoordinator(repository: repository, writer: store, canWrite: { true })
        try await writer.sessionFinished(id: session.id)
        #expect(await store.savedWorkouts.count == 1)

        let workouts = await reader(store).recentWorkouts(
            now: now, ownSyncIdentifiers: [session.id.rawValue.uuidString]
        )

        #expect(workouts.isEmpty)
    }
}

