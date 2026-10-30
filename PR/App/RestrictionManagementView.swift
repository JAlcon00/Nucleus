//
//  RestrictionManagementView.swift
//  PR
//
//  Created by PR.
//
//  Perfil › Restricciones (RF-023). SCRUM-216 la hizo de solo lectura; SCRUM-36 la hace
//  editable: una acción principal ("Agregar restricción"), las que tu plan cuida (cada una
//  abre su detalle para editarla, evitar o permitir un ejercicio y resolverla) y el
//  historial de las resueltas. El estado y las decisiones (cuándo confirmar, abrir la
//  existente en vez de duplicar, avisos) salen de `RestrictionScreenModel` (PRCore); esta
//  vista sólo muestra y envía intenciones. Nunca diagnostica.
//  Estados: vacía, con restricciones y con historial ("cargando" y "error" no aplican: el
//  perfil ya está en memoria y no hay red; un guardado fallido se avisa con una alerta).
//

import SwiftUI
import PRCore
import PRDomain

struct RestrictionManagementView: View {
    let model: RestrictionScreenModel

    @State private var adding = false
    /// Restricción abierta en su detalle (también la existente de una zona que se quiso agregar).
    @State private var opened: RestrictionID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            Section {
                addButton
            } footer: {
                Text("Nucleus no diagnostica: solo evita lo que tú declaras.")
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.surface)

            switch model.state {
            case .empty(let note):
                Section {
                    emptyState
                }
                .listRowBackground(Color.surface)
                if let note { noteSection(note) }
            case .loaded(let current, let history, let note):
                Section {
                    if current.isEmpty {
                        Text("Sin restricciones en vigor: tu plan no evita ninguna zona.")
                            .font(.callout)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, DSpace.xs)
                    }
                    ForEach(current) { item in
                        detailLink(item).accessibilityIdentifier("restrictions.row")
                    }
                } header: {
                    Text("Tus restricciones")
                }
                .listRowBackground(Color.surface)
                if !history.isEmpty {
                    Section {
                        ForEach(history) { item in
                            detailLink(item).accessibilityIdentifier("restrictions.history.row")
                        }
                    } header: {
                        Text("Historial")
                    } footer: {
                        Text("Las que resolviste. Ya no limitan tu plan.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.surface)
                }
                if let note { noteSection(note) }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Restricciones")
        .navigationDestination(item: $opened) { id in
            RestrictionDetailView(model: model, id: id)
        }
        .sheet(isPresented: $adding) {
            RestrictionFormSheet(model: model, editing: nil, draft: RestrictionFormDraft(editing: nil, now: Date())) { existing in
                // La zona ya estaba: se abre la existente para editarla (no se duplica).
                opened = existing
            }
        }
    }

    /// Enlace con destino de vista, como el de Perfil a esta pantalla: un enlace por valor
    /// quedaría DEBAJO de esta pantalla en la pila (NavigationStack apila los valores antes que
    /// las vistas empujadas).
    private func detailLink(_ item: RestrictionListItem) -> some View {
        NavigationLink {
            RestrictionDetailView(model: model, id: item.id)
        } label: {
            row(item)
        }
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            Label("Agregar restricción", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.primaryAction)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .disabled(model.isSaving)
        .accessibilityIdentifier("restrictions.add")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            Label {
                Text("Sin restricciones").foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: "checkmark.shield").foregroundStyle(Color.success)
            }
            .font(.headline)
            Text("Si algo te molesta, agrégalo aquí. Tu plan evitará lo que carga esa zona desde ese momento.")
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
                Image(systemName: RestrictionSymbols.source(item.sourceKind)).foregroundStyle(Color.textSecondary)
            }
            .font(.subheadline)
            Label {
                Text(item.resolved ?? item.status).foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: RestrictionSymbols.status(item.statusKind)).foregroundStyle(RestrictionSymbols.color(item.statusKind))
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
}

/// Iconos y colores del origen y el estado. El icono acompaña al texto; nunca es lo único
/// que lo dice.
enum RestrictionSymbols {
    static func source(_ source: RestrictionSource) -> String {
        switch source {
        case .userReported: return "person.fill"
        case .professionalGuidance: return "stethoscope"
        }
    }

    static func status(_ status: RestrictionStatus) -> String {
        switch status {
        case .active: return "checkmark.shield.fill"
        case .reviewNeeded: return "exclamationmark.shield.fill"
        case .resolved: return "checkmark.circle"
        }
    }

    static func color(_ status: RestrictionStatus) -> Color {
        switch status {
        case .active: return .success
        case .reviewNeeded: return .warning
        case .resolved: return .textSecondary
        }
    }
}

// MARK: - Previews

/// Modelo de previews sobre un perfil fijo (sin disco ni red).
@MainActor
enum RestrictionPreviewData {
    static let now = Date()

    static var profile: OnboardingProfile {
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
                TrainingRestriction(
                    bodyRegion: .wrist, startDate: now.addingTimeInterval(-90 * 86_400), status: .resolved,
                    forbiddenPatterns: [.carry], resolvedDate: now.addingTimeInterval(-10 * 86_400)
                ),
            ]
        )
        profile.restrictionNote = "Me molesta el codo al cargar la barra"
        return profile
    }

    static func model(_ profile: OnboardingProfile?) -> RestrictionScreenModel {
        let onboarding = OnboardingCoordinator()
        let catalog = (try? ExerciseCatalogLoader.loadBundled())?.exercises ?? []
        let todayPlan = TodayPlanCoordinator(catalog: ExerciseCatalog(
            source: ExerciseCatalogSource(name: "preview", version: "0", url: "", license: "none"), families: [], exercises: catalog
        ))
        return RestrictionScreenModel(
            session: AppSessionCoordinator(onboarding: onboarding, todayPlan: todayPlan, planStore: nil),
            profile: { profile },
            catalog: catalog,
            presenter: RestrictionListPresenter(locale: Locale(identifier: "es_MX")),
            clock: { now }
        )
    }
}

#Preview("Con restricciones e historial · claro") {
    NavigationStack { RestrictionManagementView(model: RestrictionPreviewData.model(RestrictionPreviewData.profile)) }
        .ironEnergyTheme()
        .preferredColorScheme(.light)
}

#Preview("Con restricciones e historial · oscuro") {
    NavigationStack { RestrictionManagementView(model: RestrictionPreviewData.model(RestrictionPreviewData.profile)) }
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
}

#Preview("Con restricciones · accessibility3") {
    NavigationStack { RestrictionManagementView(model: RestrictionPreviewData.model(RestrictionPreviewData.profile)) }
        .ironEnergyTheme()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Sólo historial") {
    var profile = RestrictionPreviewData.profile
    profile.restrictions = profile.restrictions.filter { !$0.isInForce }
    return NavigationStack { RestrictionManagementView(model: RestrictionPreviewData.model(profile)) }
        .ironEnergyTheme()
}

#Preview("Vacía") {
    NavigationStack { RestrictionManagementView(model: RestrictionPreviewData.model(nil)) }
        .ironEnergyTheme()
}
