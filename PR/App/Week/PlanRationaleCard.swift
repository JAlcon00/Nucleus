//
//  PlanRationaleCard.swift
//  PR
//
//  "Por qué tu plan es así" (SCRUM-205): explicación corta del bloque. La redacta la IA
//  (sólo con hechos del motor, ya filtrada en PRCore) o el texto local. Si la IA ajustó
//  algo se dice cuántos ajustes aceptó el motor. Vista pura.
//

import SwiftUI
import PRDomain

struct PlanRationaleCard: View {
    let record: PlanPersonalizationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            HStack(alignment: .center, spacing: DSpace.s) {
                IconBadge(systemName: "lightbulb")
                Text("Por qué tu plan es así")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(record.rationale.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(sourceText, systemImage: record.rationaleSource == .ai ? "sparkles" : "cpu")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSpace.m)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.rationale")
    }

    private var sourceText: String {
        let accepted = record.acceptedCount
        if accepted > 0 {
            return String(localized: "El motor aceptó \(accepted) ajustes sugeridos por la IA.")
        }
        switch record.rationaleSource {
        case .ai: return String(localized: "Explicado con IA. El plan lo armó el motor de Nucleus.")
        case .local: return String(localized: "Armado por el motor de Nucleus con tu perfil.")
        }
    }
}

private extension PlanPersonalizationRecord {
    static func preview(source: PlanRationaleSource, accepted: Bool) -> PlanPersonalizationRecord {
        PlanPersonalizationRecord(
            decisions: accepted ? [PersonalizationDecision(adjustment: .emphasize(.glutes), outcome: .accepted)] : [],
            rationale: [
                "Entrenas 4 días por semana en un bloque de 6 semanas.",
                "Tu semana suma 64 series, repartidas según tu objetivo.",
            ],
            rationaleSource: source,
            audit: []
        )
    }
}

#Preview("Local") {
    PlanRationaleCard(record: .preview(source: .local, accepted: false))
        .padding()
        .screenBackground()
        .ironEnergyTheme()
}

#Preview("IA con ajustes · oscuro") {
    PlanRationaleCard(record: .preview(source: .ai, accepted: true))
        .padding()
        .screenBackground()
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
}

#Preview("IA · accessibility3") {
    PlanRationaleCard(record: .preview(source: .ai, accepted: false))
        .padding()
        .screenBackground()
        .ironEnergyTheme()
        .dynamicTypeSize(.accessibility3)
}
