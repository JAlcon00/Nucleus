//
//  PRApp.swift
//  PR
//
//  Created by Jesús Almanza on 31/08/26.
//
//  Punto de entrada. No contiene lógica de negocio (PR-0001);
//  delega la composición de dependencias en `AppEnvironment`.
//

import SwiftUI

@main
struct PRApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
        }
    }
}
