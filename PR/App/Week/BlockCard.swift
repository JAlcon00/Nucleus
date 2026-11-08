//
//  BlockCard.swift
//  PR
//
//  SCRUM-266 (PR-H004): "Tu bloque" arriba de "Tu semana" en Plan. Muestra en qué semana va
//  el bloque, su objetivo y su fase, y ofrece "Cambiar objetivo o fase", que abre el mismo
//  cuestionario prellenado que Perfil › Rehacer cuestionario (RF-033: el bloque anterior y
//  su historial se conservan). La semana la calcula `BlockOverviewBuilder` (PRCore); aquí
//  sólo se pinta. Estados:
//  - en curso: "Semana 2 de 6" con su barra;
//  - terminado: "Tu bloque de 6 semanas terminó", nunca "semana 7 de 6";
//  - sin plan: no hay tarjeta (Plan muestra su estado vacío).
//

import SwiftUI
import PRCore
import PRDomain

struct BlockCard: View {
    let block: BlockOverview
    /// Intento: cambiar objetivo o fase (pide confirmación quien lo recibe).
    var onChangeGoal: (() -> Void)?

    @Environment(\.trainingAudience) private var audience

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            VStack(alignment: .leading, spacing: DSpace.s) {
                HStack(alignment: .center, spacing: DSpace.s) {
                    IconBadge(systemName: "calendar")
                    Text("Tu bloque")
                        .eyebrowStyle()
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(weekTitle)
                    .font(.title3.bold())
                    .numericStyle()
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .current(let week, let total) = block.week {
                    ProgressView(value: Double(week), total: Double(total))
                        .tint(Color.primaryAction)
                        .accessibilityHidden(true)
                }
                Text(goalAndPhase)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(startText, systemImage: "flag")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plan.block")

            if let onChangeGoal {
                Button(action: onChangeGoal) {
                    Label("Cambiar objetivo o fase", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.surface)
                .accessibilityIdentifier("plan.block.change")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSpace.m)
        .cardSurface()
    }

    private var presenter: OnboardingChoicePresenter {
        OnboardingChoicePresenter(locale: AppEnvironment.presentationLocale, audience: audience)
    }

    private var weekTitle: String {
        switch block.week {
        case .current(let week, let total):
            return String(localized: "Semana \(week) de \(total)")
        case .finished(let planned):
            return String(localized: "Tu bloque de \(planned) semanas terminó")
        }
    }

    /// "Hipertrofia · Mantenimiento". Sin fase elegida, sólo el objetivo.
    private var goalAndPhase: String {
        let goal = presenter.goalLabel(block.goal)
        switch block.phase {
        case .unspecified:
            return goal
        case .surplus, .deficit, .maintenance:
            return "\(goal) · \(presenter.phaseLabel(block.phase))"
        }
    }

    private var startText: String {
        let day = block.startDate.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(AppEnvironment.presentationLocale)
        )
        return String(localized: "Empezó el \(day)")
    }
}

// MARK: - Previews

private func previewBlock(_ week: BlockWeek, phase: BodyCompositionPhase = .maintenance) -> BlockOverview? {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    guard let block = try? TrainingBlock(
        name: "Bloque", goal: .hypertrophy, phase: phase, startDate: start, plannedWeeks: 6,
        progressionPolicy: .doubleProgression, deloadPolicy: .afterSixWeeks,
        varietyPolicy: try VarietyPolicy(percentStable: 0.65)
    ) else { return nil }
    let days: Int
    switch week {
    case .current(let number, _): days = (number - 1) * 7
    case .finished: days = 6 * 7
    }
    let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: start) ?? start
    return BlockOverviewBuilder().overview(block: block, date: date, timeZone: .current)
}

#Preview("En curso") {
    if let block = previewBlock(.current(week: 2, of: 6)) {
        BlockCard(block: block, onChangeGoal: {})
            .padding(DSpace.m)
            .screenBackground()
            .ironEnergyTheme()
    }
}

#Preview("En curso · claro") {
    if let block = previewBlock(.current(week: 2, of: 6)) {
        BlockCard(block: block, onChangeGoal: {})
            .padding(DSpace.m)
            .screenBackground()
            .ironEnergyTheme()
            .preferredColorScheme(.light)
    }
}

#Preview("Terminado · accessibility3") {
    if let block = previewBlock(.finished(plannedWeeks: 6), phase: .unspecified) {
        ScrollView {
            BlockCard(block: block, onChangeGoal: {})
                .padding(DSpace.m)
        }
        .screenBackground()
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
    }
}
