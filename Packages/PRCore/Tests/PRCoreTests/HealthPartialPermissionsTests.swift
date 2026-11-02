//
//  HealthPartialPermissionsTests.swift
//  PRCoreTests
//
//  SCRUM-35 (PR-0113, bug 12): negar el ritmo cardiaco (o la energía) no impide registrar
//  el entrenamiento en Salud; negar todo deja el entrenamiento local completo; y lo que no
//  está permitido se marca "no disponible", nunca medido ni estimado (RN-018).
//  HealthKit real queda detrás de `HealthWorkoutStore`; aquí sólo fakes.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Salud con permisos parciales (SCRUM-35)")
struct HealthPartialPermissionsTests {

    private static let measuredHeartRate = HealthWorkoutHeartRate(averageBPM: 128, peakBPM: 152, origin: .measured)

    private func store(
        _ behavior: InMemoryHealthKitProvider.HealthGrantBehavior,
        heartRate: HealthWorkoutHeartRate? = measuredHeartRate
    ) -> FakeHealthWorkoutStore {
        FakeHealthWorkoutStore(provider: InMemoryHealthKitProvider(grantBehavior: behavior), heartRate: heartRate)
    }

    private func set(_ weight: Double, _ reps: Int) throws -> SetRecord {
        try SetRecord(exerciseID: ExerciseID(), weight: weight, unit: .kilograms, reps: reps, lifecycle: .completed)
    }

    // MARK: - 1. Sin ritmo cardiaco se registra igual

    @Test("Sin ritmo cardiaco ni energía, pero con permiso de entrenamientos, se registra en Salud", arguments: [
        Set<HealthPermissionType>([.workout]),
        [.workout, .activeEnergy],
        [.workout, .heartRate],
    ])
    func recordsWithOnlyWorkoutPermission(_ granted: Set<HealthPermissionType>) async throws {
        let store = store(.grantOnly(granted))
        let started = try await HealthWorkoutCoordinator(store: store).start(session: WorkoutSessionRecord(lifecycle: .active))
        let handles = await store.startedHandles
        #expect(handles.count == 1)
        #expect(started.healthWorkoutReferenceID == handles.first?.id.rawValue)
    }

    @Test("Sin permiso de entrenamientos no se registra, aunque haya ritmo cardiaco y energía")
    func workoutPermissionIsRequired() async throws {
        let store = store(.grantOnly([.heartRate, .activeEnergy]))
        await #expect(throws: HealthWorkoutError.missingPermission) {
            _ = try await HealthWorkoutCoordinator(store: store).start(session: WorkoutSessionRecord(lifecycle: .active))
        }
        #expect(await store.startedHandles.isEmpty)
    }

    // MARK: - 2. Todo negado: el entrenamiento local sigue completo

    @Test("Con todo negado o Salud sin responder, la sesión local queda intacta y el error no es de datos", arguments: [
        InMemoryHealthKitProvider.HealthGrantBehavior.denyAll,
        .fail,
    ])
    func deniedLeavesTheLocalSessionIntact(_ behavior: InMemoryHealthKitProvider.HealthGrantBehavior) async throws {
        let session = WorkoutSessionRecord(lifecycle: .active, sets: [try set(80, 8)])
        await #expect(throws: HealthWorkoutError.missingPermission) {
            _ = try await HealthWorkoutCoordinator(store: store(behavior)).start(session: session)
        }
        #expect(session.sets.count == 1)
        #expect(session.healthWorkoutReferenceID == nil)
        #expect(session.lifecycle == .active)
    }

    @Test("Con todo negado se entrena y se guarda completo en disco (persistencia real)")
    func deniedTrainingIsPersistedLocally() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scrum35-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).workoutRepository()

        var session = WorkoutSessionRecord(lifecycle: .active, sets: [try set(80, 8)])
        try await repository.save(session)
        await #expect(throws: HealthWorkoutError.missingPermission) {
            _ = try await HealthWorkoutCoordinator(store: store(.denyAll)).start(session: session)
        }
        session.sets.append(try set(80, 7))
        try await repository.save(session)

        let saved = try #require(try await repository.session(id: session.id))
        #expect(saved.sets.count == 2)
        #expect(saved.healthWorkoutReferenceID == nil)
    }

    // MARK: - 3. El resumen marca "no disponible" lo que no está permitido

    @Test("Sin ritmo cardiaco ni energía, el resumen los marca no disponibles aunque Salud traiga números")
    func summaryMarksDeniedDataUnavailable() async throws {
        let coordinator = HealthWorkoutCoordinator(store: store(.grantOnly([.workout])))
        let started = try await coordinator.start(session: WorkoutSessionRecord(lifecycle: .active))
        let finish = try await coordinator.finishWithSummary(
            session: started,
            completedAt: started.startedAt.addingTimeInterval(3600),
            activeKilocalories: 240
        )
        #expect(finish.summary.heartRate == nil)
        #expect(finish.summary.heartRateOrigin == .unavailable)
        #expect(finish.summary.activeKilocalories == nil)
        #expect(finish.summary.energyOrigin == .unavailable)
        #expect(finish.summary.durationSeconds == 3600)
        #expect(finish.session == started)
    }

    struct PermissionCase: Sendable, CustomTestStringConvertible {
        let granted: Set<HealthPermissionType>
        let keepsHeartRate: Bool
        let keepsEnergy: Bool
        var testDescription: String { granted.map(\.rawValue).sorted().joined(separator: "+") }
    }

    @Test("Cada dato se limita por su propio permiso", arguments: [
        PermissionCase(granted: [.workout, .heartRate], keepsHeartRate: true, keepsEnergy: false),
        PermissionCase(granted: [.workout, .activeEnergy], keepsHeartRate: false, keepsEnergy: true),
        PermissionCase(granted: [.workout, .heartRate, .activeEnergy], keepsHeartRate: true, keepsEnergy: true),
    ])
    func eachValueFollowsItsPermission(_ permissionCase: PermissionCase) async throws {
        let coordinator = HealthWorkoutCoordinator(store: store(.grantOnly(permissionCase.granted)))
        let started = try await coordinator.start(session: WorkoutSessionRecord(lifecycle: .active))
        let summary = try await coordinator.finishWithSummary(session: started, activeKilocalories: 240).summary

        #expect(summary.heartRateOrigin == (permissionCase.keepsHeartRate ? .measured : .unavailable))
        #expect(summary.heartRate?.averageBPM == (permissionCase.keepsHeartRate ? 128 : nil))
        #expect(summary.energyOrigin == (permissionCase.keepsEnergy ? .measured : .unavailable))
        #expect(summary.activeKilocalories == (permissionCase.keepsEnergy ? 240 : nil))
    }

    @Test("Un dato estimado con su permiso negado tampoco se muestra: queda no disponible")
    func estimatedDeniedDataIsUnavailable() async throws {
        let estimated = HealthWorkoutHeartRate(averageBPM: 110, peakBPM: 130, origin: .estimated)
        let coordinator = HealthWorkoutCoordinator(store: store(.grantOnly([.workout]), heartRate: estimated))
        let started = try await coordinator.start(session: WorkoutSessionRecord(lifecycle: .active))
        let summary = try await coordinator.finishWithSummary(session: started).summary
        #expect(summary.heartRate == nil)
        #expect(summary.heartRateOrigin == .unavailable)
    }

    @Test("Si Salud falla al terminar, la sesión local no se pierde")
    func finishFailureKeepsTheSession() async throws {
        let store = FakeHealthWorkoutStore(provider: InMemoryHealthKitProvider(grantBehavior: .grantOnly([.workout])), failOnFinish: true)
        let coordinator = HealthWorkoutCoordinator(store: store)
        let started = try await coordinator.start(session: WorkoutSessionRecord(lifecycle: .active, sets: [try set(60, 10)]))
        await #expect {
            _ = try await coordinator.finishWithSummary(session: started)
        } throws: { error in
            guard case HealthWorkoutError.completionFailed = error else { return false }
            return true
        }
        #expect(started.sets.count == 1)
        #expect(started.healthWorkoutReferenceID != nil)
    }
}
