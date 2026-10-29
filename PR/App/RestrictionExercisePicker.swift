//
//  RestrictionExercisePicker.swift
//  PR
//
//  SCRUM-36: buscar un ejercicio del catálogo (en español o en inglés) para evitarlo o
//  permitirlo en una restricción. La búsqueda es local y sin red (`RestrictionScreenModel`).
//  Estados: sin texto (indicación), sin resultados y con resultados.
//

import SwiftUI
import PRCore
import PRDomain

struct RestrictionExercisePicker: View {
    let model: RestrictionScreenModel
    let title: LocalizedStringKey
    let onPick: (ExerciseID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                let results = model.exercises(matching: text)
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Escribe el nombre del ejercicio.")
                        .foregroundStyle(Color.textSecondary)
                } else if results.isEmpty {
                    Text("No encontramos ese ejercicio.")
                        .foregroundStyle(Color.textSecondary)
                }
                ForEach(results) { line in
                    Button {
                        dismiss()
                        onPick(line.id)
                    } label: {
                        Text(line.name)
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("restrictions.pick.result")
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Buscar ejercicio"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

#Preview("Buscar") {
    RestrictionExercisePicker(
        model: RestrictionPreviewData.model(RestrictionPreviewData.profile), title: "Evitar un ejercicio", onPick: { _ in }
    )
    .ironEnergyTheme()
}
