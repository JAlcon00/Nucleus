//
//  GymView.swift
//  PR
//
//  Perfil › Gimnasio (SCRUM-235). Se viene a ver cómo se llama el gimnasio y a cambiarle el
//  nombre, que es la única acción. Sólo muestra el estado de `GymCoordinator` y le manda
//  intenciones. Estados: cargado y con aviso; sin conexión no aplica (es 100 % local).
//

import SwiftUI
import PRCore
import PRDomain

struct GymView: View {
    let gyms: GymCoordinator
    /// Nombre visible de un ejercicio.
    var exerciseName: (ExerciseID) -> String = { _ in "" }
    /// Intento: quitar la marca "no hay" (SCRUM-236).
    var onRemoveMissing: (ExerciseID) -> Void = { _ in }

    @State private var editing = false
    @State private var draft = ""
    @State private var nameError = false

    var body: some View {
        List {
            Section {
                LabeledContent("Nombre", value: gyms.activeGym?.name ?? "")
                    .accessibilityIdentifier("gym.name")
                Button {
                    draft = ""
                    editing = true
                } label: {
                    Label("Cambiar nombre", systemImage: "pencil")
                }
                .accessibilityIdentifier("gym.rename")
            } footer: {
                Text("Aquí se guarda lo que la app aprende de este lugar.")
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.surface)

            missingSection

            if nameError {
                noticeRow("Escribe un nombre para tu gimnasio.")
            }
            switch gyms.notice {
            case .saveFailed:
                noticeRow("No se pudo guardar. Inténtalo de nuevo.")
            case .unreadable:
                noticeRow("Un gimnasio guardado no se pudo leer. Sigue en tu iPhone, sin cambios.")
            case nil:
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Gimnasio")
        .alert("Nombre del gimnasio", isPresented: $editing) {
            TextField(gyms.activeGym?.name ?? "", text: $draft)
                .accessibilityIdentifier("gym.rename.field")
            Button("Guardar") {
                Task { nameError = await gyms.renameActive(to: draft) == .emptyName }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    /// SCRUM-236: lo que no hay en este gimnasio. Quitarlo devuelve el ejercicio a la siguiente
    /// sesión; el entrenamiento en curso no cambia.
    @ViewBuilder
    private var missingSection: some View {
        let marks = gyms.activeGym?.missingExercises ?? []
        if !marks.isEmpty {
            Section("Máquinas que no hay") {
                ForEach(Array(marks.enumerated()), id: \.element.exercise) { index, mark in
                    HStack {
                        VStack(alignment: .leading, spacing: DSpace.xs) {
                            Text(exerciseName(mark.exercise))
                                .accessibilityIdentifier("gym.missing.\(index)")
                            if let replacement = mark.replacement {
                                Text("Se hace \(exerciseName(replacement))")
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                        Button("Quitar") { onRemoveMissing(mark.exercise) }
                            .frame(minHeight: DSize.dayChip)
                            .accessibilityIdentifier("gym.missing.remove.\(index)")
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
    }

    private func noticeRow(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.warning)
        }
        .accessibilityIdentifier("gym.notice")
        .listRowBackground(Color.surface)
    }
}

#Preview("Cargado") {
    NavigationStack { GymView(gyms: GymCoordinator(defaultName: "Mi gimnasio")) }
        .task {}
        .ironEnergyTheme()
}

#Preview("accessibility3") {
    NavigationStack { GymView(gyms: GymCoordinator(defaultName: "Mi gimnasio")) }
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
