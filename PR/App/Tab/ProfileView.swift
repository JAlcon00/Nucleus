//
//  ProfileView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Perfil" (SKILL §6). SCRUM-195: aquí viven las acciones terciarias que antes
//  estaban en Hoy (restricciones, rehacer cuestionario, exportar), para que Hoy tenga una
//  sola acción. SCRUM-198: "Sobre ti" se consulta y se edita aquí. Vista de composición:
//  no contiene reglas de negocio.
//

import SwiftUI
import PRDomain

struct ProfileView: View {
    /// "Sobre ti" guardado; `nil` en un perfil anterior (se ofrece completarlo).
    var aboutYou: AboutYou?
    /// "Hoy" del reloj de la app (para mostrar la edad a partir del año de nacimiento).
    var now = Date()
    /// Intento: completar o editar "Sobre ti".
    var onEditAboutYou: () -> Void = {}
    /// Intento: rehacer el cuestionario (mismo flujo que un cambio de plan).
    var onRedoQuestionnaire: () -> Void = {}

    @State private var confirmingRedo = false

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                aboutYouSection

                Section("Mi entrenamiento") {
                    NavigationLink {
                        RestrictionManagementView(
                            restrictions: [],
                            onCreate: {},
                            onReview: { _ in },
                            onResolve: { _ in }
                        )
                    } label: {
                        Label("Restricciones", systemImage: "list.bullet.clipboard")
                    }
                    .accessibilityIdentifier("profile.restrictions")

                    Button {
                        confirmingRedo = true
                    } label: {
                        Label {
                            Text("Rehacer cuestionario").foregroundStyle(Color.textPrimary)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise").foregroundStyle(Color.primaryAction)
                        }
                    }
                    .accessibilityIdentifier("profile.redo")
                }
                .listRowBackground(Color.surface)

                Section {
                    NavigationLink {
                        ExportDataView()
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("profile.export")
                } header: {
                    Text("Mis datos")
                } footer: {
                    Text("Tus entrenamientos se guardan en este iPhone.")
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Perfil")
            .confirmationDialog(
                "¿Rehacer el cuestionario?",
                isPresented: $confirmingRedo,
                titleVisibility: .visible
            ) {
                Button("Sí, rehacer") { onRedoQuestionnaire() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Si cambias objetivo, fase o días se crea un bloque nuevo. El anterior y su historial se conservan.")
            }
        }
    }

    /// Cabecera con avatar: inicial del nombre o un icono si no hay nombre.
    private var profileHeader: some View {
        Section {
            HStack(spacing: DSpace.m) {
                if let initial = aboutYou?.name?.first {
                    Text(String(initial).uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(Color.onAccent)
                        .frame(width: DSize.iconBadge * 2, height: DSize.iconBadge * 2)
                        .background(LinearGradient.energy, in: Circle())
                        .accessibilityHidden(true)
                } else {
                    IconBadge(systemName: "person.fill", scale: 2)
                }
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    Text(aboutYou?.name ?? String(localized: "Tu perfil"))
                        .font(.title3.bold())
                    HStack(alignment: .firstTextBaseline, spacing: DSpace.xs) {
                        Image(systemName: "lock.fill").accessibilityHidden(true)
                        Text("Tus datos se quedan en este iPhone")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, DSpace.s)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.surface)
    }

    private var aboutYouSection: some View {
        Section {
            if let aboutYou {
                if let name = aboutYou.name {
                    LabeledContent {
                        Text(name)
                    } label: {
                        Label("Nombre", systemImage: "person.text.rectangle")
                    }
                }
                LabeledContent {
                    Text("\(aboutYou.age(on: now, timeZone: .current)) años").numericStyle()
                } label: {
                    Label("Edad", systemImage: "birthday.cake")
                }
                LabeledContent {
                    Text(AboutYouFields.label(aboutYou.sex))
                } label: {
                    Label("Sexo", systemImage: "person.2")
                }
                if let height = aboutYou.heightCentimeters {
                    LabeledContent {
                        Text("\(height) cm").numericStyle()
                    } label: {
                        Label("Estatura", systemImage: "ruler")
                    }
                }
                LabeledContent {
                    Text(Self.weightText(aboutYou)).numericStyle()
                } label: {
                    Label("Peso", systemImage: "scalemass")
                }
                Button(action: onEditAboutYou) {
                    Label("Editar", systemImage: "pencil")
                }
                .accessibilityIdentifier("profile.aboutYou.edit")
            } else {
                Button(action: onEditAboutYou) {
                    Label("Completa tu perfil", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("profile.aboutYou.complete")
            }
        } header: {
            Text("Sobre ti")
        } footer: {
            Text("Se guarda solo en tu iPhone.")
                .foregroundStyle(Color.textSecondary)
        }
        .listRowBackground(Color.surface)
    }

    private static func weightText(_ aboutYou: AboutYou) -> String {
        let unit: UnitMass = aboutYou.weightUnit == .pounds ? .pounds : .kilograms
        return Measurement(value: aboutYou.weight, unit: unit).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
        )
    }
}

#Preview("Sin 'Sobre ti'") {
    ProfileView()
        .ironEnergyTheme()
}

#Preview("Con 'Sobre ti'") {
    ProfileView(aboutYou: try? AboutYou(
        name: "Ana", birthYear: 1992, sex: .female, heightCentimeters: 165, weight: 61.5, weightUnit: .kilograms
    ))
    .ironEnergyTheme()
}

#Preview("accessibility3") {
    ProfileView()
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
