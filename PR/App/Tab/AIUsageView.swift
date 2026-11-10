//
//  AIUsageView.swift
//  PR
//
//  SCRUM-273 (PR-I004, DI-4 A): Perfil › "Uso de la IA (pruebas)", sólo en Debug. Muestra el
//  resumen por operación que arma PRCore (`AgentUsageSummary`): llamadas, mediana y p95 de la
//  latencia, tokens promedio y cuántas cayeron al respaldo. Sirve para decidir D2 de
//  ADR-0005; el costo en dinero no se muestra porque falta el precio del proveedor.
//

import PRCore
import PRDomain
import SwiftUI

struct AIUsageView: View {
    /// Lee el resumen guardado; lanza si no se pudo leer.
    let load: () async throws -> [AgentUsageRow]

    private enum Screen: Equatable {
        case loading
        case empty
        case loaded([AgentUsageRow])
        case failed
    }

    @State private var screen: Screen = .loading

    var body: some View {
        List {
            switch screen {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.surface)
            case .empty:
                Text("Todavía no hay llamadas a la IA en este iPhone.")
                    .foregroundStyle(Color.textSecondary)
                    .listRowBackground(Color.surface)
                    .accessibilityIdentifier("aiUsage.empty")
            case .failed:
                Label("No se pudo leer el uso guardado.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.textPrimary)
                    .listRowBackground(Color.surface)
            case .loaded(let rows):
                ForEach(rows, id: \.operation) { row in
                    Section(header: Text(title(row.operation))) {
                        LabeledContent("Llamadas", value: "\(row.calls)")
                        LabeledContent("Mediana", value: "\(row.medianMilliseconds) ms")
                        LabeledContent("p95", value: "\(row.p95Milliseconds) ms")
                        LabeledContent("Tokens promedio", value: row.averageTotalTokens.map { "\($0)" } ?? String(localized: "Sin dato"))
                        LabeledContent("Respaldo local", value: "\(row.fallbacks)")
                    }
                    .monospacedDigit()
                    .listRowBackground(Color.surface)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Sólo en pruebas. No guarda lo que escribes ni lo que responde la IA. El costo en dinero se calcula cuando haya precio del proveedor.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Uso de la IA")
        .task {
            do {
                let rows = try await load()
                screen = rows.isEmpty ? .empty : .loaded(rows)
            } catch {
                screen = .failed
            }
        }
    }

    private func title(_ operation: AgentOperation) -> LocalizedStringKey {
        switch operation {
        case .coachInterpret: return "Entrenador: interpretar"
        case .planPersonalization: return "Plan: personalizar"
        case .planRationale: return "Plan: explicar"
        }
    }
}

#Preview("Con llamadas") {
    NavigationStack {
        AIUsageView(load: {
            AgentUsageSummary.rows(for: [
                AgentUsageRecord(id: UUID(), date: .now, operation: .coachInterpret, promptTokens: 420, completionTokens: 35, reasoningTokens: nil, durationMilliseconds: 1_240, outcome: .answered),
                AgentUsageRecord(id: UUID(), date: .now, operation: .coachInterpret, promptTokens: nil, completionTokens: nil, reasoningTokens: nil, durationMilliseconds: 10_000, outcome: .failed(.timeout)),
                AgentUsageRecord(id: UUID(), date: .now, operation: .planRationale, promptTokens: 900, completionTokens: 120, reasoningTokens: nil, durationMilliseconds: 3_100, outcome: .answered),
            ])
        })
    }
    .ironEnergyTheme()
}

#Preview("Vacío · oscuro · accessibility3") {
    NavigationStack {
        AIUsageView(load: { [] })
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}
