//
//  WatchWorkoutLauncher.swift
//  PR
//
//  SCRUM-258: al empezar en el iPhone se abre el reloj (DG-4). Sólo pide abrirlo: la sesión
//  de Salud la lleva el reloj. Si no responde, el iPhone sigue solo y nada se pierde.
//

import Foundation
import HealthKit
import PRCore

struct WatchWorkoutLauncher {
    private let store = HKHealthStore()

    func start() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            try await store.startWatchApp(toHandle: configuration)
        } catch {
            PRLogger(category: .health).diagnostic("watch.launch.failed", level: .notice)
        }
    }
}
