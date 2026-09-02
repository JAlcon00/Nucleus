//
//  ContentView.swift
//  PR
//
//  Created by Jesús Almanza on 31/08/26.
//
//  Vista raíz transitoria del esqueleto inicial (PR-0001).
//  Renderiza estado y envía intents; no contiene reglas de negocio.
//

import SwiftUI
import PRDomain

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        // Pantalla "Hoy" (PR-0601). Estado derivado por `TodayScreenDriver`; el
        // cableado con la programación real de sesiones llega en historias
        // posteriores (hoy → día de descanso hasta que exista sesión planeada).
        TodayView(
            state: TodayScreenDriver().derive(todayTemplate: nil, activeSession: nil),
            onStart: startWorkout,
            onResume: resumeWorkout
        )
    }

    private func startWorkout() {
        // Intento de empezar sesión: la capa de aplicación lo gestiona (PR-0602).
    }

    private func resumeWorkout() {
        // Intento de continuar sesión en curso.
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
