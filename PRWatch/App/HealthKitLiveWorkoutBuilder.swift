//
//  HealthKitLiveWorkoutBuilder.swift
//  PRWatch
//
//  SCRUM-258: la sesión de Salud en el reloj. Implementa el contrato `LiveWorkoutBuilder`
//  siguiendo "Running workout sessions" de Apple: la sesión sólo se cierra cuando pasó a
//  `.stopped`. El id de la sesión de PR va como identificador de sincronización: si el iPhone
//  también escribe, Salud se queda con uno solo.
//
//  `@unchecked Sendable`: HKWorkoutSession llama a su delegado en una cola propia. Lo mutable
//  de esta clase va protegido por `lock`.
//

import Foundation
import HealthKit
import PRCore

nonisolated final class HealthKitLiveWorkoutBuilder: NSObject, LiveWorkoutBuilder, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let store = HKHealthStore()
    private let lock = NSLock()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var syncIdentifier: String?
    private var stopped: CheckedContinuation<Date, Never>?
    private var averageBPM: Double?

    func tag(syncIdentifier: String) async {
        lock.withLock { self.syncIdentifier = syncIdentifier }
    }

    func start() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthLiveWorkoutError.infrastructure("health.unavailable")
        }
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: [HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        )
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = attach(session, configuration: configuration)
        let now = Date()
        session.startActivity(with: now)
        try await builder.beginCollection(at: now)
    }

    func recover() async throws -> Bool {
        guard let session = try await store.recoverActiveWorkoutSession() else { return false }
        _ = attach(session, configuration: session.workoutConfiguration)
        return true
    }

    func pause() async throws {
        current().session?.pause()
    }

    func resume() async throws {
        current().session?.resume()
    }

    func end() async throws -> HealthLiveMetrics {
        let (session, builder) = current()
        guard let session, let builder else { throw HealthLiveWorkoutError.notStarted }
        let end = await withCheckedContinuation { continuation in
            lock.withLock { stopped = continuation }
            session.stopActivity(with: Date())
        }
        try await builder.endCollection(at: end)
        if let identifier = lock.withLock({ syncIdentifier }) {
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: identifier,
                HKMetadataKeySyncVersion: HealthWorkoutWrite.syncVersion,
            ])
        }
        let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let heartRate = builder.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        lock.withLock { averageBPM = heartRate }
        _ = try await builder.finishWorkout()
        session.end()
        return HealthLiveMetrics(activeKilocalories: energy, heartRateBPM: heartRate)
    }

    func averageHeartRate() async -> Double? {
        lock.withLock { averageBPM }
    }

    private func current() -> (session: HKWorkoutSession?, builder: HKLiveWorkoutBuilder?) {
        lock.withLock { (session, builder) }
    }

    private func attach(_ session: HKWorkoutSession, configuration: HKWorkoutConfiguration) -> HKLiveWorkoutBuilder {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        lock.withLock {
            self.session = session
            self.builder = builder
        }
        return builder
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .stopped else { return }
        let waiting = lock.withLock {
            let waiting = stopped
            stopped = nil
            return waiting
        }
        waiting?.resume(returning: date)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        PRLogger(category: .health).diagnostic("watch.session.failed", level: .error)
        let waiting = lock.withLock {
            let waiting = stopped
            stopped = nil
            return waiting
        }
        waiting?.resume(returning: Date())
    }
}
