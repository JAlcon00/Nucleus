//
//  CoachingLevelView.swift
//  PR
//
//  SCRUM-267 (PR-H005, RF-026): Perfil › Explicaciones. Cuánto explica la app en el
//  entrenamiento y en el resumen. Qué cambia cada nivel ya lo decide el dominio
//  (`CoachingCardDriver`, `PRCelebrationBuilder`); el nivel efectivo y su origen los da
//  `CoachingPreferenceCoordinator` (PRCore). Aquí sólo se pintan y se envía la elección.
//  Estados:
//  - según la experiencia: marca el nivel que toca y lo dice;
//  - elegido: marca el elegido y ofrece volver al de la experiencia;
//  - no se pudo guardar: lo avisa; sigue marcado lo que quedó guardado;
//  - cargando, vacío y sin conexión: no aplican (es local y siempre hay un nivel).
//

import SwiftUI
import PRCore
import PRDomain

/// Textos de cada nivel (sólo formato).
enum CoachingLevelText {
    static func name(_ level: CoachingDetailLevel) -> String {
        switch level {
        case .guided: return String(localized: "Guiado")
        case .balanced: return String(localized: "Equilibrado")
        case .advanced: return String(localized: "Avanzado")
        }
    }

    static func detail(_ level: CoachingDetailLevel) -> String {
        switch level {
        case .guided:
            return String(localized: "Te explico el calentamiento, el descanso y por qué subes de carga.")
        case .balanced:
            return String(localized: "Una línea en el calentamiento y en cada récord.")
        case .advanced:
            return String(localized: "Sólo los números, sin explicaciones de rutina.")
        }
    }
}

struct CoachingLevelView: View {
    let coaching: CoachingPreferenceCoordinator
    let experience: ExperienceLevel

    var body: some View {
        let prefs = coaching.prefs(for: experience)
        List {
            if coaching.saveFailed {
                Section {
                    Label("No se pudo guardar tu elección. Sigue la que tenías.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                        .accessibilityIdentifier("coaching.saveFailed")
                }
                .listRowBackground(Color.surface)
            }

            Section {
                ForEach(CoachingDetailLevel.allCases, id: \.self) { level in
                    option(level, isSelected: prefs.level == level)
                }
            } footer: {
                Text(footer(prefs))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("coaching.source")
            }
            .listRowBackground(Color.surface)

            if prefs.isUserChosen {
                Section {
                    Button {
                        coaching.choose(.byExperience)
                    } label: {
                        Label("Usar el de mi experiencia", systemImage: "arrow.uturn.backward")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .frame(minHeight: DButton.secondaryHeight)
                    .accessibilityIdentifier("coaching.byExperience")
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Explicaciones")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ level: CoachingDetailLevel, isSelected: Bool) -> some View {
        Button {
            coaching.choose(.manual(level: level))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DSpace.m) {
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    Text(CoachingLevelText.name(level))
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(CoachingLevelText.detail(level))
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DSpace.s)
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Color.primaryAction)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: DButton.secondaryHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("coaching.option.\(level.rawValue)")
    }

    private func footer(_ prefs: CoachingDetailPrefs) -> String {
        let source = prefs.isUserChosen
            ? String(localized: "Lo elegiste tú.")
            : String(localized: "Según tu experiencia.")
        return source + " " + String(localized: "Los avisos por molestia salen en todos los niveles.")
    }
}

// MARK: - Previews

#Preview("Según la experiencia") {
    NavigationStack {
        CoachingLevelView(coaching: CoachingPreferenceCoordinator(store: nil), experience: .intermediate)
    }
    .ironEnergyTheme()
}

#Preview("Según la experiencia · claro") {
    NavigationStack {
        CoachingLevelView(coaching: CoachingPreferenceCoordinator(store: nil), experience: .beginner)
    }
    .ironEnergyTheme()
    .preferredColorScheme(.light)
}

#Preview("accessibility3") {
    NavigationStack {
        CoachingLevelView(coaching: CoachingPreferenceCoordinator(store: nil), experience: .advanced)
    }
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}

#Preview("No se pudo guardar") {
    let coaching = CoachingPreferenceCoordinator(store: nil)
    coaching.load(userID: "preview")
    coaching.choose(.manual(level: .advanced))
    return NavigationStack {
        CoachingLevelView(coaching: coaching, experience: .intermediate)
    }
    .ironEnergyTheme()
}
