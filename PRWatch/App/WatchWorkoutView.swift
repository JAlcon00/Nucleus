//
//  WatchWorkoutView.swift
//  PRWatch
//
//  Created by PR.
//
//  Watch workout UI shell (EPIC-12, PR-1201). Renderiza el estado derivado por
//  `WatchWorkoutDriver` (PRCore/PRDomain): ejercicio actual, peso, reps, índice del
//  set, botón grande de completar set y rest timer. NO contiene lógica de negocio:
//  sólo presenta el estado y reenvía la intención de completar. Touch targets grandes
//  para uso durante el entrenamiento.
//

import SwiftUI
import PRDomain

struct WatchWorkoutView: View {
    /// Plantilla de la sesión activa.
    let template: SessionTemplate?
    /// Sets ya realizados en la sesión.
    let performedSets: [SetRecord]
    /// Última vez que se completó un set (para el countdown del descanso).
    let lastCompletedPrescription: SetPrescription?
    /// Hora actual de referencia (renovada por un Timer en el host).
    let now: Date
    /// Acción al pulsar "completar set".
    let onCompleteSet: () -> Void
    /// Acción al extender/saltar el descanso.
    let onSkipRest: () -> Void

    private let driver = WatchWorkoutDriver()

    var body: some View {
        let progress = template.map { driver.current(template: $0, performedSets: performedSets, now: now) } ?? .idle
        let rest = restTimerState

        Group {
            switch progress {
            case .inProgress(let p):
                workoutContent(p, rest: rest)
            case .complete:
                completionView
            case .idle:
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private func workoutContent(_ p: WatchSetPresentation, rest: RestTimerState?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let rest, rest.isActive, rest.remaining(at: now) > 0 {
                    restBanner(rest)
                }
                setProgress(p)
                weightReps(p)
                Spacer(minLength: 8)
                completeButton
            }
            .padding(.horizontal)
        }
    }

    private func weightReps(_ p: WatchSetPresentation) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(weightText(p.weight))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(unitText(p.unit))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("×")
                .foregroundStyle(.secondary)
            Text("\(p.reps)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
        }
    }

    private func setProgress(_ p: WatchSetPresentation) -> some View {
        HStack {
            Text("Serie \(p.currentSetIndex) / \(p.totalSetsInExercise)")
                .font(.headline)
            Spacer()
            Text("\(p.targetRepRange.lowerBound)–\(p.targetRepRange.upperBound) reps")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func restBanner(_ rest: RestTimerState) -> some View {
        HStack {
            Image(systemName: "timer")
            Text("Descanso \(rest.remaining(at: now))s")
                .monospacedDigit()
            Spacer()
            Button("Saltar", action: onSkipRest)
                .font(.caption)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var completeButton: some View {
        Button(action: onCompleteSet) {
            Label("Completar set", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private var completionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .imageScale(.large)
            Text("Workout completo").font(.headline.bold())
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .imageScale(.large)
            Text("Sin sesión activa").font(.headline)
        }
    }

    // MARK: - Helpers

    private var restTimerState: RestTimerState? {
        guard let lastCompletedPrescription else { return nil }
        return RestTimer().autoStart(
            afterCompletedWarmup: lastCompletedPrescription.isWarmup,
            prescription: lastCompletedPrescription,
            now: now
        )
    }

    private func weightText(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func unitText(_ unit: LoadUnit) -> String {
        switch unit {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }
}

#Preview {
    WatchWorkoutView(
        template: nil,
        performedSets: [],
        lastCompletedPrescription: nil,
        now: Date(),
        onCompleteSet: {},
        onSkipRest: {}
    )
}