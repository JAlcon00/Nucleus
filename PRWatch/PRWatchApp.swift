//
//  PRWatchApp.swift
//  PRWatch
//
//  Created on 31/08/26.
//
//  Companion watchOS del app iOS. No contiene lógica de negocio (PR-0001);
//  delega la composición de dependencias en `PRWatchEnvironment`.
//

import SwiftUI

@main
struct PRWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
