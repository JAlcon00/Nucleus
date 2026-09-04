//
//  WorkoutSummaryView.swift
//  PR
//
//  Created by PR.
//
//  Suscripción de sesión completada (PR-0605 UI, SKILL §44). Presenta duration,
//  working sets, volumen, PRs detectados y próxima acción. Célébra el PR de forma
//  breve (haptic + animación corta), sin confeti excesivo (SKILL §44). Vista pura:
//  renderiza `WorkoutSummary`; no decide nada.
//

import SwiftUI
import PRDomain

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let onDone: () -> Void

    @State private var burst = false

    private var durationText: String {
        let m = summary.durationSeconds / 60
        let s = summary.durationSeconds % 60
        if m >= 60 {
            return "\(m / 60) h \(m % 60) min"
        }
        return "\(m) min \(s) s"
    }

    private var volumeText: String {
        let value = summary.volume
        if value.rounded() == value {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DSpace.l) {
                if !summary.records.isEmpty {
                    prCard
                        .transition(.scale.combined(with: .opacity))
                }

                header

                statsGrid

                if summary.nextAction == .completed {
                    Text("Sesión completada. Sigue en el plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryActionButton("Seguir en el plan", systemImage: "checkmark") {
                    onDone()
                }
                .padding(.top, DSpace.s)
            }
            .padding(DSpace.l)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        Label("Entrenamiento completado", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(Color.success)
    }

    private var prCard: some View {
        VStack(spacing: DSpace.s) {
            Text("NUEVO RÉCORD")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.success)
            ForEach(summary.records, id: \.exerciseID) { record in
                Text("\(record.weight.cleanString) kg × \(record.reps)")
                    .font(.title2.bold())
            }
            Text(summary.records.count == 1 ? "Marca personal." : "Marcas personales.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DSpace.l)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DRadius.large))
        .onAppear { celebrate() }
    }

    private var statsGrid: some View {
        HStack(spacing: DSpace.m) {
            stat("Duración", durationText, symbol: "clock")
            stat("Series", "\(summary.workingSets)", symbol: "list.number")
            stat("Volumen", volumeText, symbol: "scalemass")
            if let energy = summary.energyKcal {
                stat("Energía", "\(Int(energy)) kcal", symbol: "flame")
            }
        }
        .padding(.vertical, DSpace.s)
    }

    private func stat(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(spacing: DSpace.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    /// Celebración breve del PR (SKILL §44): haptic success + animación corta.
    private func celebrate() {
        withAnimation(.spring(duration: 0.4)) { burst = true }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private extension Double {
    var cleanString: String {
        if self.rounded() == self {
            return "\(Int(self.rounded()))"
        }
        return String(format: "%.1f", self)
    }
}

#Preview("Resumen con PR") {
    NavigationStack {
        WorkoutSummaryView(
            summary: WorkoutSummary(
                durationSeconds: 42 * 60 + 12,
                workingSets: 12,
                volume: 12850,
                energyKcal: nil,
                records: [
                    PersonalRecord(
                        exerciseID: ExerciseID(),
                        weight: 85,
                        unit: .kilograms,
                        reps: 8,
                        achievedAt: Date()
                    )
                ],
                nextAction: .completed
            ),
            onDone: {}
        )
    }
}

#Preview("Resumen sin PR") {
    NavigationStack {
        WorkoutSummaryView(
            summary: WorkoutSummary(
                durationSeconds: 30 * 60,
                workingSets: 9,
                volume: 9400,
                energyKcal: nil,
                records: [],
                nextAction: .completed
            ),
            onDone: {}
        )
    }
}