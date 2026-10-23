//
//  WorkoutSummaryView.swift
//  PR
//
//  Created by PR.
//
//  Resumen de sesión completada (PR-0605 UI). Presenta duration, working sets,
//  volumen, PRs y próxima acción. Celebración del PR (PR-1004): breve e inline (no
//  modal, no bloquea "Seguir en el plan"), haptic único, anuncio VoiceOver y animación
//  corta que con Reduce Motion se sustituye por un fundido. Vista pura: el contenido
//  de la celebración lo decide `PRCelebrationBuilder` en el dominio y los textos
//  localizados los produce `PRCelebrationPresenter` (PRCore).
//

import SwiftUI
import PRCore
import PRDomain

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    /// Celebración ya decidida y localizada (PR-1004); `nil` si no hay récords.
    var celebration: PRCelebrationPresentation? = nil
    /// Ejercicios saltados en la sesión (SCRUM-212), ya con su nombre.
    var skipped: [String] = []
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrationVisible = false
    @State private var celebrated = false

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
                if let celebration {
                    // El espacio de la tarjeta existe desde el primer frame: sólo se
                    // animan opacidad y escala (no afectan al layout), así el resto de
                    // la pantalla no salta al aparecer el récord. Reduce Motion: sólo fundido.
                    prCard(celebration)
                        .opacity(celebrationVisible ? 1 : 0)
                        .scaleEffect(celebrationVisible || reduceMotion ? 1 : 0.92)
                }

                header

                statsGrid

                if !skipped.isEmpty {
                    Label {
                        Text("Saltaste: \(skipped.formatted(.list(type: .and).locale(AppEnvironment.presentationLocale)))")
                    } icon: {
                        Image(systemName: "forward.end")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSpace.m)
                    .cardSurface(cornerRadius: DRadius.medium)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("summary.skipped")
                }

                if summary.nextAction == .completed {
                    Text("Sesión completada. Sigue en el plan.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryActionButton("Seguir en el plan", systemImage: "checkmark", identifier: "summary.done") {
                    onDone()
                }
                .padding(.top, DSpace.s)
            }
            .padding(DSpace.l)
        }
        .screenBackground()
        .onAppear { celebrate() }
    }

    private var header: some View {
        Label("Entrenamiento completado", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(Color.success)
    }

    private func prCard(_ celebration: PRCelebrationPresentation) -> some View {
        // Los récords van en naranja fuego (reservado a logros, SCRUM-194): titular 6.51:1
        // sobre la tarjeta y borde con el degradado de energía. El trofeo es redundante:
        // el significado lo lleva el texto.
        VStack(spacing: DSpace.s) {
            Label {
                Text(celebration.headline)
            } icon: {
                Image(systemName: "trophy.fill")
            }
            .font(.headline)
            .foregroundStyle(Color.accentSecondary)
            ForEach(celebration.rows) { item in
                VStack(spacing: DSpace.xs) {
                    Text(item.exerciseName)
                        .font(.subheadline)
                    Text(item.loadText)
                        .font(.title2.bold())
                        .numericStyle()
                }
            }
            if let detail = celebration.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(DSpace.l)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: DRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: DRadius.large)
                .strokeBorder(LinearGradient.energy, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
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
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.headline)
                .numericStyle()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    /// Celebración breve (PR-1004), una sola vez por presentación: animación corta (o
    /// fundido con Reduce Motion), un haptic de éxito y anuncio para VoiceOver.
    private func celebrate() {
        guard let celebration, !celebrated else { return }
        celebrated = true
        withAnimation(DMotion.celebration(reduceMotion: reduceMotion)) {
            celebrationVisible = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AccessibilityNotification.Announcement(celebration.accessibilityAnnouncement).post()
    }
}

/// Fixture de preview: resumen + celebración resuelta por el dominio (no en la View).
@MainActor
private func previewSummaryView(
    records: [(name: String, weight: Double, unit: LoadUnit, reps: Int)],
    level: CoachingDetailLevel
) -> some View {
    var names: [ExerciseID: String] = [:]
    let personalRecords = records.enumerated().map { index, record in
        let id = ExerciseID()
        names[id] = record.name
        return PersonalRecord(
            exerciseID: id,
            weight: record.weight,
            unit: record.unit,
            reps: record.reps,
            achievedAt: Date(timeIntervalSinceReferenceDate: Double(index))
        )
    }
    let summary = WorkoutSummary(
        durationSeconds: 42 * 60 + 12,
        workingSets: 12,
        volume: 12850,
        energyKcal: nil,
        records: personalRecords,
        nextAction: .completed
    )
    return NavigationStack {
        WorkoutSummaryView(
            summary: summary,
            celebration: PRCelebrationBuilder()
                .celebration(for: personalRecords, exerciseNames: names, level: level)
                .map(PRCelebrationPresenter(locale: AppEnvironment.presentationLocale).present),
            onDone: {}
        )
    }
    .ironEnergyTheme()
}

#Preview("PR · guided") {
    previewSummaryView(records: [("Press banca", 85, .kilograms, 8)], level: .guided)
}

#Preview("PR · balanced · varios en lb") {
    previewSummaryView(
        records: [("Press banca", 185, .pounds, 6), ("Remo con barra", 155, .pounds, 8)],
        level: .balanced
    )
}

#Preview("PR · advanced · accessibility3") {
    previewSummaryView(records: [("Sentadilla", 142.5, .kilograms, 3)], level: .advanced)
        .dynamicTypeSize(.accessibility3)
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
    .ironEnergyTheme()
}