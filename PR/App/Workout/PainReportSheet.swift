//
//  PainReportSheet.swift
//  PR
//
//  SCRUM-226: hoja "¿Te dolió esta serie?" del descanso. Presenta `PainReportUI` (lo arma
//  `WorkoutSessionCoordinator`) y envía intenciones: reportar el nivel y, si hay dolor,
//  dónde (opcional); saltar el ejercicio que dolió; cerrar. Los nombres de la escala y las
//  recomendaciones salen de `PainRecommendationPresenter`. No decide nada.
//

import SwiftUI
import PRCore
import PRDomain

struct PainReportSheet: View {
    let report: PainReportUI
    /// Reportar o cambiar el nivel y, si se indicó, el músculo.
    let onReport: (PainLevel, MuscleGroup.ID?) -> Void
    /// Saltar el ejercicio que dolió.
    let onSkipExercise: () -> Void
    let onDone: () -> Void

    private let presenter = PainRecommendationPresenter(locale: AppEnvironment.presentationLocale)
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    /// Lo que muestra la hoja según lo ya reportado. Cada caso tiene su preview.
    private enum Stage {
        /// Sin reportar (o "Sin dolor"): sólo la escala.
        case choosing
        /// Con dolor y sin recomendación (leve): además, dónde (opcional).
        case noAdvice(PainLevel)
        /// Con recomendación (moderado o alto): dónde y qué hacer; con alto, saltar el
        /// ejercicio si todavía le quedan series.
        case advice(PainLevel, message: String, canSkip: Bool, tint: Color)
    }

    private var stage: Stage {
        guard let level = report.level, level > PainLevel.none else { return .choosing }
        guard let message = presenter.message(for: report.recommendation) else { return .noAdvice(level) }
        switch report.recommendation {
        case .continueNormal, .reduceIntensityAndMonitor:
            return .advice(level, message: message, canSkip: false, tint: .warning)
        case .stopAndRest:
            return .advice(level, message: message, canSkip: report.canSkipExercise, tint: .destructive)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSpace.l) {
                header
                switch stage {
                case .choosing:
                    levels
                case .noAdvice(let level):
                    levels
                    muscles(level)
                    doneButton
                case .advice(let level, let message, let canSkip, let tint):
                    // Lo primero que se lee después de reportar: qué hacer.
                    recommendation(message, tint: tint)
                    levels
                    muscles(level)
                    if canSkip { skipButton }
                    doneButton
                }
            }
            .padding(DSpace.l)
        }
        .screenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSpace.xs) {
            Text("¿Te dolió esta serie?")
                .font(.title3.bold())
            Text(report.exerciseName)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// La escala única, siempre con texto. Un toque reporta (y reemplaza lo anterior).
    private var levels: some View {
        VStack(spacing: DSpace.s) {
            ForEach(PainLevel.allCases, id: \.self) { level in
                PainLevelRow(title: presenter.levelName(level), isSelected: report.level == level) {
                    onReport(level, report.muscleGroup)
                }
                .accessibilityIdentifier("pain.level.\(level)")
            }
        }
    }

    /// Dónde se sintió: opcional. Tocar el elegido lo quita.
    @ViewBuilder
    private func muscles(_ level: PainLevel) -> some View {
        if !report.muscleOptions.isEmpty {
            VStack(alignment: .leading, spacing: DSpace.s) {
                Text("¿Dónde lo sentiste? (opcional)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                FlowLayout(spacing: DSpace.s, lineSpacing: DSpace.s) {
                    ForEach(report.muscleOptions) { muscle in
                        let isSelected = report.muscleGroup == muscle
                        MuscleChip(title: vocabulary.muscleName(muscle), isSelected: isSelected) {
                            onReport(level, isSelected ? nil : muscle)
                        }
                        .accessibilityIdentifier("pain.muscle.\(muscle.rawValue)")
                    }
                }
            }
        }
    }

    /// Recomendación del motor. Icono y texto además del color.
    private func recommendation(_ message: String, tint: Color) -> some View {
        Label {
            Text(message)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
        }
        .font(.callout)
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DRadius.medium).strokeBorder(tint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pain.recommendation")
    }

    /// Con dolor alto, la acción principal: saltar el ejercicio (se puede retomar).
    private var skipButton: some View {
        PrimaryActionButton(
            "Saltar \(report.exerciseName)",
            systemImage: "forward.end",
            identifier: "pain.skip",
            action: onSkipExercise
        )
        .accessibilityHint("Las series que ya hiciste se guardan. Puedes retomarlo antes de terminar.")
    }

    private var doneButton: some View {
        Button("Listo", action: onDone)
            .buttonStyle(.surface)
            .accessibilityIdentifier("pain.done")
    }
}

/// Fila de un nivel de la escala: el elegido lleva palomita y borde, no sólo color. El
/// háptico lo da la pantalla del entrenamiento al guardarse (uno solo por reporte).
private struct PainLevelRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSpace.m) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.primaryAction : Color.secondaryAction)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DSpace.m)
            .padding(.vertical, DSpace.s)
            .frame(minHeight: DSize.inputHeight)
            .background(
                isSelected ? Color.primaryAction.opacity(0.12) : Color.surface,
                in: RoundedRectangle(cornerRadius: DRadius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DRadius.medium)
                    .strokeBorder(isSelected ? Color.primaryAction : Color.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Chip de un músculo: el elegido lleva palomita además del relleno.
private struct MuscleChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark" : "plus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                .padding(.horizontal, DSpace.m)
                .frame(minHeight: DSize.dayChip)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentFill) : AnyShapeStyle(Color.surface),
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(isSelected ? Color.clear : Color.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews (un estado por preview)

private func previewReport(
    level: PainLevel?,
    muscle: MuscleGroup.ID? = nil,
    recommendation: PainRecommendation = .continueNormal,
    canSkip: Bool = true
) -> PainReportUI {
    PainReportUI(
        exerciseName: "Press banca con barra",
        level: level,
        muscleGroup: muscle,
        muscleOptions: [.chest, .triceps, .shoulders],
        recommendation: recommendation,
        canSkipExercise: canSkip
    )
}

#Preview("Sin reportar") {
    PainReportSheet(report: previewReport(level: nil), onReport: { _, _ in }, onSkipExercise: {}, onDone: {})
        .ironEnergyTheme()
}

#Preview("Leve · hombro") {
    PainReportSheet(report: previewReport(level: .mild, muscle: .shoulders), onReport: { _, _ in }, onSkipExercise: {}, onDone: {})
        .ironEnergyTheme()
}

#Preview("Moderado · oscuro") {
    PainReportSheet(
        report: previewReport(level: .moderate, recommendation: .reduceIntensityAndMonitor),
        onReport: { _, _ in }, onSkipExercise: {}, onDone: {}
    )
    .ironEnergyTheme()
    .preferredColorScheme(.dark)
}

#Preview("Alto · puede saltar") {
    PainReportSheet(
        report: previewReport(level: .high, muscle: .chest, recommendation: .stopAndRest),
        onReport: { _, _ in }, onSkipExercise: {}, onDone: {}
    )
    .ironEnergyTheme()
}

#Preview("Alto · ejercicio terminado · oscuro") {
    PainReportSheet(
        report: previewReport(level: .high, recommendation: .stopAndRest, canSkip: false),
        onReport: { _, _ in }, onSkipExercise: {}, onDone: {}
    )
    .ironEnergyTheme()
    .preferredColorScheme(.dark)
}

#Preview("Alto · accessibility3") {
    PainReportSheet(
        report: previewReport(level: .high, muscle: .triceps, recommendation: .stopAndRest),
        onReport: { _, _ in }, onSkipExercise: {}, onDone: {}
    )
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}
