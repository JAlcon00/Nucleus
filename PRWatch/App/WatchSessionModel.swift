//
//  WatchSessionModel.swift
//  PRWatch
//
//  SCRUM-256: arma lo que necesita el reloj. Las reglas viven en `WatchSessionController`
//  (PRCore); aquí sólo se elige dónde guardar y cómo hablar con el iPhone y con Salud.
//

import Foundation
import HealthKit
import PRCore
import WatchKit

@MainActor
enum WatchSessionModel {
    /// Uno solo: la pantalla y el sistema (que abre el reloj desde el iPhone) hablan con él.
    /// `nil` si no hay dónde guardar: sin disco no se finge que una serie quedó segura.
    static let shared: WatchSessionController? = {
        do {
            let directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PR/watch-session", isDirectory: true)
            let store = try AtomicFileRepositoryStore(directory: directory)
            return WatchSessionController(
                store: WatchLocalStore(store: store),
                link: PhoneConnectivityLink(),
                health: HealthLiveWorkoutCoordinator(builder: HealthKitLiveWorkoutBuilder())
            )
        } catch {
            PRLogger(category: .persistence).diagnostic("watch.store.unavailable", level: .error)
            return nil
        }
    }()
}

/// El sistema despierta al reloj cuando el iPhone empieza, o tras un cierre con la sesión de
/// Salud abierta. En los dos casos basta con ponerla al día.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WatchSessionModel.shared?.syncHealth() }
    }

    func handleActiveWorkoutRecovery() {
        Task { await WatchSessionModel.shared?.syncHealth() }
    }
}
