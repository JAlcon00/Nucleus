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
import PRCore
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
    /// ¿La IA puede usar los datos del perfil? (SCRUM-202)
    var aiConsentGranted = false
    /// Intento: dar o retirar el consentimiento (retirarlo aplica al instante).
    var onSetAIConsent: (Bool) -> Void = { _ in }
    /// Estado de la conexión con la IA (SCRUM-204): sólo se informa, no se decide aquí.
    var aiStatus: AIConnectionStatus = .offline(.releaseBuild)
    /// ¿Hay un entrenamiento en curso? Cambia el aviso al cerrar sesión (SCRUM-208).
    var hasActiveWorkout = false
    /// Intento: cerrar sesión (no borra datos).
    var onSignOut: () -> Void = {}

    @State private var confirmingRedo = false
    @State private var confirmingSignOut = false
    /// Apariencia de la app (SCRUM-208): preferencia del dispositivo, no del entrenamiento.
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.fallback.rawValue

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                aboutYouSection
                aiSection

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

                appearanceSection
                accountSection
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
            .confirmationDialog(
                "¿Cerrar sesión?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Cerrar sesión", role: .destructive) { onSignOut() }
                    .accessibilityIdentifier("profile.signOut.confirm")
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(hasActiveWorkout
                     ? "Tienes un entrenamiento en curso. Se guarda tal cual y lo retomas al volver a entrar con tu cuenta."
                     : "Tu plan y tu historial se quedan en este iPhone y vuelven al entrar con tu cuenta.")
            }
        }
    }

    /// SCRUM-208: claro, oscuro o como el sistema.
    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearance) {
                Text("Sistema").tag(AppearancePreference.system.rawValue)
                Text("Claro").tag(AppearancePreference.light.rawValue)
                Text("Oscuro").tag(AppearancePreference.dark.rawValue)
            } label: {
                Label {
                    Text("Apariencia")
                } icon: {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(Color.primaryAction)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("profile.appearance")
        } header: {
            Text("Apariencia")
        }
        .listRowBackground(Color.surface)
    }

    /// SCRUM-208: cerrar sesión (con confirmación; no borra datos).
    private var accountSection: some View {
        Section {
            Button {
                confirmingSignOut = true
            } label: {
                Label {
                    Text("Cerrar sesión").foregroundStyle(Color.destructive)
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(Color.destructive)
                }
            }
            .accessibilityIdentifier("profile.signOut")
        } header: {
            Text("Cuenta")
        }
        .listRowBackground(Color.surface)
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

    /// SCRUM-202: dar o retirar el consentimiento para la IA.
    private var aiSection: some View {
        Section {
            Toggle(isOn: Binding(get: { aiConsentGranted }, set: onSetAIConsent)) {
                Label {
                    Text("Personalizar con IA")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Color.primaryAction)
                }
            }
            .tint(Color.primaryAction)
            .accessibilityIdentifier("profile.aiConsent")
            LabeledContent {
                Text(aiStatusText)
            } label: {
                Label {
                    Text("Conexión")
                } icon: {
                    Image(systemName: aiStatus.isLive ? "bolt.horizontal.circle.fill" : "iphone")
                        .foregroundStyle(aiStatus.isLive ? Color.success : Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.aiStatus")
        } header: {
            Text("Inteligencia artificial")
        } footer: {
            Text(aiConsentGranted
                 ? "La IA usa tu perfil y tu check-in para adaptar tu rutina. Nunca tu nombre."
                 : "La IA no recibe tus datos. Tu plan lo arma el motor de Nucleus en este iPhone.")
                .foregroundStyle(Color.textSecondary)
        }
        .listRowBackground(Color.surface)
    }

    private var aiStatusText: String {
        switch aiStatus {
        case .live: return String(localized: "Conectada (desarrollo)")
        case .offline(.missingKey): return String(localized: "Modo local (sin llave)")
        case .offline(.releaseBuild): return String(localized: "Modo local")
        case .offline(.uiTesting): return String(localized: "Modo local (pruebas)")
        }
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

#Preview("Claro") {
    ProfileView(aboutYou: try? AboutYou(
        name: "Ana", birthYear: 1992, sex: .female, heightCentimeters: 165, weight: 61.5, weightUnit: .kilograms
    ))
    .ironEnergyTheme()
    .preferredColorScheme(.light)
}
