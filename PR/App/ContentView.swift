//
//  ContentView.swift
//  PR
//
//  Created by Jesús Almanza on 31/08/26.
//
//  Vista raíz transitoria del esqueleto inicial (PR-0001). Enruta al flujo de
//  onboarding/auth (EPIC-04) y, tras completarlo, a la app. Renderiza estado y envía
//  intents; no contiene reglas de negocio.
//

import SwiftUI
import PRCore

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment(authProvider: FakeAppleIDAuthProvider()))
}