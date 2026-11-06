//
//  WatchSessionModel.swift
//  PRWatch
//
//  SCRUM-256: arma lo que necesita el reloj. Las reglas viven en `WatchSessionController`
//  (PRCore); aquí sólo se elige dónde guardar y cómo hablar con el iPhone.
//

import Foundation
import PRCore

@MainActor
enum WatchSessionModel {
    /// `nil` si no hay dónde guardar: sin disco no se finge que una serie quedó segura.
    static func makeController() -> WatchSessionController? {
        do {
            let directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PR/watch-session", isDirectory: true)
            let store = try AtomicFileRepositoryStore(directory: directory)
            return WatchSessionController(store: WatchLocalStore(store: store), link: PhoneConnectivityLink())
        } catch {
            PRLogger(category: .persistence).diagnostic("watch.store.unavailable", level: .error)
            return nil
        }
    }
}
