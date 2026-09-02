//
//  HealthWorkoutTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de start/finish de workout de HealthKit (PR-1102): configuración correcta,
//  ciclo start/finish, la referencia estable queda asociada al WorkoutSessionRecord
//  y un error de HealthKit NUNCA pierde los sets locales (§14.4). HealthKit real queda
//  detrás del protocolo `HealthWorkoutStore`; PRCore no lo importa.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Start/finish HealthKit workout (PR-1102)")
struct HealthWorkoutTests {

    private func grantedStore(failOnStart: Bool = false, failOnFinish: Bool = false) -> FakeHealthWorkoutStore {
        FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(),
            failOnStart: failOnStart,
            failOnFinish: failOnFinish
        )
    }

    private func session(withSets: [SetRecord] = []) -> WorkoutSessionRecord {
        WorkoutSessionRecord(lifecycle: .active, sets: withSets)
    }

    private func set(_ weight: Double, _ reps: Int) throws -> SetRecord {
        try SetRecord(
            exerciseID: ExerciseID(),
            weight: weight,
            unit: .kilograms,
            reps: reps,
            lifecycle: .completed
        )
    }

    private func setList(_ weights: [Double], _ reps: Int) throws -> [SetRecord] {
        try weights.map { try set($0, reps) }
    }

    // 1. La configuración del workout es correcta (categorizada como strength training).
    @Test("La configuración del workout es correcta y transportable")
    func configurationIsCorrect() {
        let config = HealthWorkoutConfiguration()
        #expect(config.activityType == .strengthTraining)
        let configured = HealthWorkoutConfiguration(activityType: .strengthTraining, supportsLiveWatchBuilder: true)
        #expect(configured.supportsLiveWatchBuilder)
    }

    // 2. El ciclo start devuelve un handle estable y lo asocia al WorkoutSessionRecord.
    @Test("El ciclo start asocia la referencia estable al WorkoutSessionRecord")
    func startAssociatesStableReference() async throws {
        let coordinator = HealthWorkoutCoordinator(store: grantedStore())
        let result = try await coordinator.start(session: session())

        // La referencia (handle) quedó asociada a la sesión local.
        #expect(result.healthWorkoutReferenceID != nil)
        // Los sets (vacíos aquí) no se ven alterados.
        #expect(result.sets.isEmpty)
    }

    // 2b. Una sesión ya iniciada no se inicia dos veces.
    @Test("No se puede iniciar dos veces: yaStarted")
    func alreadyStarted() async throws {
        let store = grantedStore()
        let coordinator = HealthWorkoutCoordinator(store: store)
        let started = try await coordinator.start(session: session())
        await #expect(throws: HealthWorkoutError.self) {
            _ = try await coordinator.start(session: started)
        }
    }

    // 2c. Finalizar sin haber iniciado falla con notStarted.
    @Test("Finalizar sin iniciar falla con notStarted")
    func finishWithoutStartFails() async throws {
        let store = grantedStore()
        let coordinator = HealthWorkoutCoordinator(store: store)
        await #expect(throws: HealthWorkoutError.self) {
            _ = try await coordinator.finish(session: session())
        }
    }

    // 2d. El ciclo finish produce el resumen y conserva la sesión.
    @Test("El ciclo finish produce el resumen y conserva la sesión")
    func finishProducesSummary() async throws {
        let store = grantedStore()
        let coordinator = HealthWorkoutCoordinator(store: store)
        let started = try await coordinator.start(session: session(), configuration: .init())
        let handleRaw = started.healthWorkoutReferenceID!

        let finished = try await coordinator.finish(session: started, completedAt: started.startedAt.addingTimeInterval(60), activeKilocalories: 42)

        // La sesión conserva su referencia y no ve alterados sus sets.
        #expect(finished.healthWorkoutReferenceID == handleRaw)
        #expect(finished.sets.isEmpty)
        // El store registró exactamente un resumen con los datos de entrada.
        let summaries = await store.finishedSummaries
        #expect(summaries.count == 1)
        #expect(summaries[0].activeKilocalories == 42)
    }

    // 3. Un error de HealthKit en el finish NO pierde los sets locales.
    @Test("Un error de HealthKit en finish no pierde los sets locales")
    func finishFailureDoesNotLoseLocalSets() async throws {
        let store = grantedStore(failOnFinish: true)
        let coordinator = HealthWorkoutCoordinator(store: store)
        let sets = try setList([80], 8)
        let started = try await coordinator.start(session: session(withSets: sets))

        // El finish falla, pero la sesión conserva intactos sus sets.
        await #expect {
            _ = try await coordinator.finish(session: started)
        } throws: { error in
            error is HealthWorkoutError
        }
        #expect(started.sets == sets)
        #expect(started.sets.count == 1)
        #expect(started.healthWorkoutReferenceID != nil)
    }

    // 3b. Un error en el start no pierde los sets locales.
    @Test("Un error de HealthKit en start no pierde los sets locales")
    func startFailureDoesNotLoseLocalSets() async throws {
        let store = grantedStore(failOnStart: true)
        let coordinator = HealthWorkoutCoordinator(store: store)
        let sets = try setList([60], 8)

        await #expect {
            _ = try await coordinator.start(session: session(withSets: sets))
        } throws: { error in
            true
        }
        // La sesión original sigue con sus sets intactos.
        #expect(session(withSets: sets).sets.count == 1)
    }

    // 3c. La autorización negada impide el inicio sin bloquear el core.
    @Test("Permiso denegado impide el start sin bloquear el core")
    func deniedPermissionPreventsStart() async throws {
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(grantBehavior: .denyAll)
        )
        let coordinator = HealthWorkoutCoordinator(store: store)
        await #expect(throws: HealthWorkoutError.missingPermission) {
            _ = try await coordinator.start(session: session())
        }
    }

    // 4. La referencia asociada es estable y reconciliable (coincide con el handle del store).
    @Test("La referencia asociada es estable y reconciliable")
    func stableReferenceIsReconcilable() async throws {
        let store = grantedStore()
        let coordinator = HealthWorkoutCoordinator(store: store)
        let started = try await coordinator.start(session: session())

        let startedHandle = await store.startedHandles.first
        #expect(startedHandle?.id.rawValue == started.healthWorkoutReferenceID)
    }
}

@Suite("Health workout summary (PR-1103)")
struct HealthWorkoutSummaryTests {

    private func finishSummary(
        startedAt: Date = Date(),
        durationSeconds: Double = 3600,
        activeKcal: Double? = 180,
        heartRate: HealthWorkoutHeartRate? = nil,
        energyOrigin: MeasurementOrigin? = nil
    ) async throws -> HealthWorkoutSummary {
        let store = FakeHealthWorkoutStore(
            provider: InMemoryHealthKitProvider(),
            heartRate: heartRate,
            energyOrigin: energyOrigin
        )
        let coordinator = HealthWorkoutCoordinator(store: store)
        let started = try await coordinator.start(session: WorkoutSessionRecord(startedAt: startedAt, lifecycle: .active))
        let end = startedAt.addingTimeInterval(durationSeconds)
        _ = try await coordinator.finish(session: started, completedAt: end, activeKilocalories: activeKcal)
        guard let summary = await store.finishedSummaries.first else {
            Issue.record("Debía existir un resumen finalizado")
            throw HealthWorkoutError.notStarted
        }
        return summary
    }

    // 1. Duración derivada de start/end.
    @Test("La duración deriva de start/end")
    func durationDerivedFromStartEnd() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        let summary = try await finishSummary(startedAt: startedAt, durationSeconds: 5400, activeKcal: 200)
        #expect(summary.durationSeconds == 5400)
    }

    // 2. Active energy presente si disponible.
    @Test("Active energy presente cuando está disponible")
    func activeEnergyPresentWhenAvailable() async throws {
        let summary = try await finishSummary(activeKcal: 180)
        #expect(summary.activeKilocalories == 180)
    }

    // 2b. Sin energía disponible, queda nil (no se inventa).
    @Test("Sin energía, queda nil (no se inventa)")
    func noEnergyIsNil() async throws {
        let summary = try await finishSummary(activeKcal: nil)
        #expect(summary.activeKilocalories == nil)
        #expect(summary.energyOrigin == .unavailable)
    }

    // 3. HR summary presente sólo si permitido/disponible.
    @Test("HR summary presente sólo si permitido/disponible")
    func heartRateOnlyWhenPermitted() async throws {
        let withHR = try await finishSummary(heartRate: HealthWorkoutHeartRate(averageBPM: 128, peakBPM: 152, origin: .measured))
        #expect(withHR.heartRate?.averageBPM == 128)
        #expect(withHR.heartRate?.peakBPM == 152)
        #expect(withHR.heartRate?.origin == .measured)

        let withoutHR = try await finishSummary(heartRate: nil)
        #expect(withoutHR.heartRate == nil)
    }

    // 4. Datos marcados como measured vs estimated.
    @Test("Datos marcados como measured vs estimated")
    func measuredVersusEstimated() async throws {
        // Energy derivada: se marca measured cuando viene con valor.
        let measured = try await finishSummary(activeKcal: 150)
        #expect(measured.energyOrigin == .measured)

        // Energy forzada a estimated (p. ej. fuente de terceros).
        let estimated = try await finishSummary(activeKcal: 150, energyOrigin: .estimated)
        #expect(estimated.energyOrigin == .estimated)

        // HR puede marcarse estimated mientras energy es distinta (independientes).
        let mixed = try await finishSummary(
            activeKcal: 90,
            heartRate: HealthWorkoutHeartRate(averageBPM: 120, peakBPM: 140, origin: .estimated),
            energyOrigin: .measured
        )
        #expect(mixed.energyOrigin == .measured)
        #expect(mixed.heartRate?.origin == .estimated)
    }
}