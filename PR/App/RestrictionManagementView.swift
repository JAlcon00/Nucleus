//
//  RestrictionManagementView.swift
//  PR
//
//  Created by PR.
//
//  Perfil › Restricciones (RF-023). SCRUM-216: solo lectura. Muestra las restricciones del
//  mismo perfil con el que se arma el plan, ya traducidas por `RestrictionListPresenter`
//  (PRCore): zona, lado, quién la declaró, si el plan la sigue cuidando y la nota. Crear,
//  revisar y resolver llegan con SCRUM-36; mientras, no hay botones que no hagan nada.
//  Nunca diagnostica. Estados: vacío y con restricciones ("cargando" y "error" no aplican:
//  el perfil ya está en memoria y no hay red).
//

import SwiftUI
import PRCore
import PRDomain

struct RestrictionManagementView: View {
    /// Estado ya traducido (la capa de app lo arma con el perfil vigente).
    let state: RestrictionListState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            switch state {
            case .empty(let note):
                Section {
                    emptyState
                } footer: {
                    Text("Nucleus no diagnostica: solo evita lo que tú declaras.")
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.surface)
                if let note { noteSection(note) }
            case .loaded(let items, let note):
                Section {
                    ForEach(items) { row($0) }
                } header: {
                    Text("Tus restricciones")
                } footer: {
                    Text("Para agregar o quitar una zona, rehaz el cuestionario desde Perfil. Nucleus no diagnostica: solo evita lo que tú declaras.")
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.surface)
                if let note { noteSection(note) }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Restricciones")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            Label {
                Text("Sin restricciones").foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: "checkmark.shield").foregroundStyle(Color.success)
            }
            .font(.headline)
            Text("Si algo te molesta, rehaz el cuestionario desde Perfil y marca la zona en el paso Restricciones. Tu plan evitará lo que la carga.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, DSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("restrictions.empty")
    }

    private func row(_ item: RestrictionListItem) -> some View {
        VStack(alignment: .leading, spacing: DSpace.xs) {
            // Con letra muy grande, el lado baja a su propia línea en vez de cortarse.
            let titleLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSpace.xs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DSpace.s))
            titleLayout {
                Text(item.region)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                if let side = item.side {
                    Text(side)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Label {
                Text(item.source).foregroundStyle(Color.textSecondary)
            } icon: {
                Image(systemName: sourceSymbol(item.sourceKind)).foregroundStyle(Color.textSecondary)
            }
            .font(.subheadline)
            Label {
                Text(item.status).foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: statusSymbol(item.statusKind)).foregroundStyle(statusColor(item.statusKind))
            }
            .font(.subheadline)
            if let note = item.note {
                Label {
                    Text(note).foregroundStyle(Color.textSecondary)
                } icon: {
                    Image(systemName: "text.quote").foregroundStyle(Color.textSecondary)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, DSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("restrictions.row")
    }

    private func noteSection(_ note: String) -> some View {
        Section {
            Text(note)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .accessibilityIdentifier("restrictions.note")
        } header: {
            Text("Tu nota")
        } footer: {
            Text("Solo informa: no cambia tu plan ni se comparte con la IA.")
                .foregroundStyle(Color.textSecondary)
        }
        .listRowBackground(Color.surface)
    }

    private func sourceSymbol(_ source: RestrictionSource) -> String {
        switch source {
        case .userReported: return "person.fill"
        case .professionalGuidance: return "stethoscope"
        }
    }

    /// El icono acompaña al texto del estado; nunca es el único que lo dice.
    private func statusSymbol(_ status: RestrictionStatus) -> String {
        switch status {
        case .active: return "checkmark.shield.fill"
        case .reviewNeeded: return "exclamationmark.shield.fill"
        case .resolved: return "checkmark.circle"
        }
    }

    private func statusColor(_ status: RestrictionStatus) -> Color {
        switch status {
        case .active: return .success
        case .reviewNeeded: return .warning
        case .resolved: return .textSecondary
        }
    }
}

// MARK: - Previews

private enum RestrictionPreviewData {
    static let now = Date()

    static var loaded: RestrictionListState {
        var profile = OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: 4, usualSessionMinutes: 60, varietyPreference: .balanced,
            restrictions: [
                TrainingRestriction(bodyRegion: .elbow, startDate: now, forbiddenPatterns: [.elbowFlexion, .elbowExtension]),
                TrainingRestriction(
                    bodyRegion: .shoulder, side: .right, startDate: now.addingTimeInterval(-60 * 86_400),
                    reviewDate: now.addingTimeInterval(-86_400), source: .professionalGuidance,
                    forbiddenPatterns: [.verticalPress], notes: "Sin press por encima de la cabeza"
                ),
                TrainingRestriction(bodyRegion: .wrist, startDate: now, status: .resolved, forbiddenPatterns: [.carry]),
            ]
        )
        profile.restrictionNote = "Me molesta el codo al cargar la barra"
        return RestrictionListPresenter(locale: Locale(identifier: "es_MX")).state(for: profile, now: now)
    }
}

#Preview("Con restricciones · claro") {
    NavigationStack { RestrictionManagementView(state: RestrictionPreviewData.loaded) }
        .ironEnergyTheme()
        .preferredColorScheme(.light)
}

#Preview("Con restricciones · oscuro") {
    NavigationStack { RestrictionManagementView(state: RestrictionPreviewData.loaded) }
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
}

#Preview("Con restricciones · accessibility3") {
    NavigationStack { RestrictionManagementView(state: RestrictionPreviewData.loaded) }
        .ironEnergyTheme()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Vacío") {
    NavigationStack { RestrictionManagementView(state: .empty(note: nil)) }
        .ironEnergyTheme()
}

#Preview("Vacío con nota · oscuro") {
    NavigationStack { RestrictionManagementView(state: .empty(note: "A veces me truena la rodilla")) }
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
}
