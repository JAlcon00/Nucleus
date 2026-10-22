//
//  ProfileView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Perfil" (SKILL §6). SCRUM-195: aquí viven las acciones terciarias que antes
//  estaban en Hoy (restricciones, rehacer cuestionario, exportar), para que Hoy tenga una
//  sola acción. Vista de composición: no contiene reglas de negocio.
//

import SwiftUI

struct ProfileView: View {
    /// Intento: rehacer el cuestionario (mismo flujo que un cambio de plan).
    var onRedoQuestionnaire: () -> Void = {}

    @State private var confirmingRedo = false

    var body: some View {
        NavigationStack {
            List {
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
                        Label("Rehacer cuestionario", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Color.textPrimary)
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
}

#Preview {
    ProfileView()
        .ironEnergyTheme()
}

#Preview("accessibility3") {
    ProfileView()
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
