//
//  RestrictionManagementView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla de gestión de restricciones (plan §15 Fase 12, RF-023, PR-1401).
//  Renderiza las restricciones y sus estados sin reglas de negocio (éstas viven en
//  `RestrictionManager`/`RestrictionStatus`, PRDomain). No diagnostica ni resuelve
//  nada por tiempo: sólo presenta el estado y permite intents de creación/edición/
//  revisión/resolución que delegan en la capa de dominio.
//

import SwiftUI
import PRDomain

struct RestrictionManagementView: View {
    /// Restricciones activas/reviewNeeded/resolved (inyectadas por la capa de app).
    let restrictions: [TrainingRestriction]
    /// Intentos hacia la capa de dominio (crear/editar/revisar/resolver).
    let onCreate: () -> Void
    let onReview: (TrainingRestriction.ID) -> Void
    let onResolve: (TrainingRestriction.ID) -> Void

    var body: some View {
        List {
            Section {
                if restrictions.isEmpty {
                    emptyState
                } else {
                    ForEach(restrictions) { restriction in
                        row(restriction)
                    }
                }
            } header: {
                Text("Restricciones (\(restrictions.count))")
            }
        }
        .navigationTitle("Restricciones")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onCreate) {
                    Label("Nueva", systemImage: "plus")
                }
                .accessibilityHint("Añade una restricción de entrenamiento.")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sin restricciones", systemImage: "checkmark.shield")
                .font(.headline)
            Text("Documenta aquí qué regiones/ejercicios evitar. Nunca diagnosticamos: tú decides qué registras.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func row(_ restriction: TrainingRestriction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(restriction.bodyRegion.rawValue.capitalized)
                    .font(.headline)
                if let side = restriction.side {
                    Text(side.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(restriction.status)
            }
            HStack(spacing: 8) {
                sourceBadge(restriction.source)
                if !restriction.forbiddenPatterns.isEmpty {
                    Label("\(restriction.forbiddenPatterns.count) patrones", systemImage: "xmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let review = restriction.reviewDate {
                Text("Revisión: \(review.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch restriction.status {
            case .reviewNeeded:
                Button("Marcar como revisado", action: { onReview(restriction.id) })
                    .font(.footnote)
            case .resolved:
                Text("Resuelta. Se requiere acción explícita para re-activar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .active:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: RestrictionStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func sourceBadge(_ source: RestrictionSource) -> some View {
        Label(
            source == .userReported ? "Usuario" : "Profesional",
            systemImage: source == .userReported ? "person" : "stethoscope"
        )
        .font(.footnote)
        .foregroundStyle(source == .professionalGuidance ? .indigo : .secondary)
    }

    private func statusColor(_ status: RestrictionStatus) -> Color {
        switch status {
        case .active: return .red
        case .reviewNeeded: return .orange
        case .resolved: return .green
        }
    }
}

#Preview("Con restricciones") {
    NavigationStack {
        RestrictionManagementView(
            restrictions: [
                TrainingRestriction(
                    bodyRegion: .shoulder,
                    side: .right,
                    reviewDate: Date().addingTimeInterval(86400),
                    status: .reviewNeeded,
                    source: .professionalGuidance,
                    forbiddenPatterns: [.verticalPress],
                    restrictionTags: [.shoulder]
                ),
                TrainingRestriction(bodyRegion: .knee, source: .userReported, forbiddenPatterns: [.squat]),
            ],
            onCreate: {},
            onReview: { _ in },
            onResolve: { _ in }
        )
    }
}

#Preview("Vacío") {
    NavigationStack {
        RestrictionManagementView(restrictions: [], onCreate: {}, onReview: { _ in }, onResolve: { _ in })
    }
}