//
//  TodayView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla "Hoy" (plan §8, RF-005, PR-0601). Presenta el estado derivado por
//  `TodayScreenDriver` (PRDomain) y reenvía intents (empezar/continuar). NO contiene
//  reglas de negocio: sólo renderiza `TodayScreenState` y conserva estados claros de
//  descanso / sin workout / en curso. Funciona offline.
//

import SwiftUI
import PRDomain

struct TodayView: View {
    /// Estado derivado por `TodayScreenDriver` (se inyecta desde el composition root).
    let state: TodayScreenState
    /// Intento: empezar la sesión planeada.
    let onStart: () -> Void
    /// Intento: continuar la sesión en curso.
    let onResume: () -> Void

    var body: some View {
        Group {
            switch state {
            case .restDay:
                restDayView
            case .readyToStart(let presentation):
                readyView(presentation)
            case .activeWorkout(let presentation, let isPaused):
                activeView(presentation, isPaused: isPaused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Rest day

    private var restDayView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Día de descanso")
                .font(.title3.bold())
            Text("Hoy toca recuperar. Vuelve mañana cuando toque entrenar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Día de descanso.")
    }

    // MARK: - Ready to start

    private func readyView(_ presentation: SessionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hoy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(presentation.title)
                    .font(.title2.bold())
                sessionSummary(presentation)
            }
            Spacer()
            startButton(presentation)
        }
        .padding(24)
    }

    // MARK: - Active

    private func activeView(_ presentation: SessionPresentation, isPaused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(isPaused ? "En pausa" : "En curso", systemImage: isPaused ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                .font(.headline)
                .foregroundStyle(isPaused ? .orange : .green)
            Text(presentation.title)
                .font(.title2.bold())
            sessionSummary(presentation)
            Spacer()
            resumeButton
        }
        .padding(24)
    }

    private func sessionSummary(_ presentation: SessionPresentation) -> some View {
        HStack(spacing: 12) {
            Label("\(presentation.workSetCount) series", systemImage: "list.number")
            if presentation.warmupSetCount > 0 {
                Label("\(presentation.warmupSetCount) cal.", systemImage: "flame")
            }
            if let minutes = presentation.estimatedMinutes {
                Label("~\(minutes) min", systemImage: "clock")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func startButton(_ presentation: SessionPresentation) -> some View {
        Button(action: onStart) {
            Label("Empezar \(presentation.title)", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Inicia la sesión de hoy.")
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Label("Continuar", systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Reanuda la sesión en curso.")
    }
}

#Preview("Día de descanso") {
    TodayView(state: .restDay, onStart: {}, onResume: {})
}

#Preview("Lista para empezar") {
    TodayView(
        state: .readyToStart(
            SessionPresentation(
                templateID: UUID(),
                title: "Torso y tríceps",
                workSetCount: 12,
                warmupSetCount: 2,
                estimatedMinutes: 55
            )
        ),
        onStart: {},
        onResume: {}
    )
}

#Preview("En curso") {
    TodayView(
        state: .activeWorkout(
            SessionPresentation(
                templateID: UUID(),
                title: "Torso y tríceps",
                workSetCount: 5,
                warmupSetCount: 0,
                estimatedMinutes: nil
            ),
            isPaused: false
        ),
        onStart: {},
        onResume: {}
    )
}