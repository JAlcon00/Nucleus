//
//  DecisionExplanationSheet.swift
//  PR
//
//  SCRUM-274 (PR-I005, RF-025): "¿Por qué?" junto a lo que la app cambió. Muestra el título
//  y las razones que armó `DecisionExplanationPresenter` con los hechos del registro de la
//  decisión (SCRUM-270). Vista pura: no decide nada, no cambia la sesión ni el plan y no
//  detiene el descanso (el tiempo lo lleva el coordinador).
//

import PRCore
import SwiftUI

/// Lo que abre un botón "¿Por qué?": la explicación con un ID estable para la hoja.
struct WhyItem: Identifiable, Equatable {
    let id: String
    let explanation: DecisionExplanation
}

struct DecisionExplanationSheet: View {
    let explanation: DecisionExplanation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(explanation.reasons.enumerated()), id: \.offset) { index, reason in
                        Label {
                            Text(reason)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color.primaryAction)
                                .accessibilityHidden(true)
                        }
                        .accessibilityIdentifier("why.reason.\(index)")
                    }
                } footer: {
                    Text("Sale de lo que decidió el motor de Nucleus, no de la IA.")
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(explanation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .accessibilityIdentifier("why.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("why.sheet")
    }
}

/// El botón "¿Por qué?" que va dentro de una tarjeta. Secundario, con área de toque de 44 pt
/// o más, y la etiqueta de VoiceOver nombra la decisión.
struct WhyButton: View {
    let accessibilityName: LocalizedStringKey
    let identifier: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var minimumHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Label("¿Por qué?", systemImage: "questionmark.circle")
                .font(.footnote.weight(.semibold))
                .frame(minHeight: max(minimumHeight, 44))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.primaryAction)
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Cuatro razones") {
    DecisionExplanationSheet(explanation: DecisionExplanation(
        title: "Por qué tu sesión es más corta",
        reasons: [
            "Elegiste 30 min y la sesión duraba unos 52.",
            "Quitamos Elevaciones laterales.",
            "Dejamos menos series de Curl.",
            "Los ejercicios principales se quedan.",
        ]
    ))
    .ironEnergyTheme()
}

#Preview("Sin datos · oscuro") {
    DecisionExplanationSheet(explanation: DecisionExplanation(
        title: "Por qué este peso",
        reasons: ["No hay datos para explicar esta decisión."]
    ))
    .preferredColorScheme(.dark)
    .ironEnergyTheme()
}

#Preview("accessibility3") {
    DecisionExplanationSheet(explanation: DecisionExplanation(
        title: "Por qué hoy es más ligero",
        reasons: ["Dormiste poco.", "Cada serie termina 1 repetición más lejos del fallo.", "El peso y las repeticiones no cambian."]
    ))
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}

#Preview("Botón") {
    WhyButton(accessibilityName: "Por qué tu sesión es más corta", identifier: "preview.why") {}
        .padding()
        .ironEnergyTheme()
}

/// SCRUM-274: "¿Por qué?" de las tarjetas de Hoy. `nil` = sin registro, sin botón.
struct TodayWhy: Equatable {
    var time: WhyItem?
    var readiness: WhyItem?
    var gym: WhyItem?
}
