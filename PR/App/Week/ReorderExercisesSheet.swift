//
//  ReorderExercisesSheet.swift
//  PR
//
//  SCRUM-211 (FB-4): cambiar el orden de los ejercicios de una sesión, aunque el motor
//  (o la IA) haya recomendado otro. Se arrastra o se usan los botones subir/bajar (también
//  como acciones de VoiceOver). Guardar o "Volver al recomendado" son intentos: el
//  coordinador valida y guarda; aquí no se decide nada. Las series, reps y RIR no cambian.
//

import SwiftUI
import PRCore
import PRDomain

/// Acciones de orden propio que la raíz pone en el entorno (nil = no se ofrece).
struct SessionOrderActions {
    /// ¿La sesión se puede reordenar ahora? (no si está en curso).
    var canReorder: @MainActor (SessionTemplate.ID) -> Bool
    var isCustom: @MainActor (SessionTemplate.ID) -> Bool
    var reorder: @MainActor (SessionTemplate.ID, [ExerciseID]) async -> Bool
    var reset: @MainActor (SessionTemplate.ID) async -> Bool
}

extension EnvironmentValues {
    @Entry var sessionOrderActions: SessionOrderActions?
}

struct ReorderExercisesSheet: View {
    let templateID: SessionTemplate.ID
    let actions: SessionOrderActions

    @State private var order: [TodayExerciseLine]
    @State private var saving = false
    @State private var saveFailed = false
    @Environment(\.dismiss) private var dismiss

    init(templateID: SessionTemplate.ID, lines: [TodayExerciseLine], actions: SessionOrderActions) {
        self.templateID = templateID
        self.actions = actions
        _order = State(initialValue: lines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, line in
                        row(line, index: index)
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Arrastra o usa las flechas. Las series, repeticiones y el RIR de cada ejercicio no cambian.")
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.surface)

                if actions.isCustom(templateID) {
                    Section {
                        Button {
                            Task { await commit { await actions.reset(templateID) } }
                        } label: {
                            Label("Volver al orden recomendado", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("reorder.reset")
                    }
                    .listRowBackground(Color.surface)
                }

                if saveFailed {
                    Label("No se pudo guardar. Intenta de nuevo.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.warning)
                        .listRowBackground(Color.surface)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Ordenar ejercicios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let ids = order.map(\.exerciseID)
                        Task { await commit { await actions.reorder(templateID, ids) } }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("reorder.save")
                }
            }
        }
        .ironEnergyTheme()
        .accessibilityIdentifier("reorder.sheet")
    }

    private func row(_ line: TodayExerciseLine, index: Int) -> some View {
        HStack(spacing: DSpace.s) {
            Text("\(index + 1)")
                .font(.headline)
                .numericStyle()
                .foregroundStyle(Color.primaryAction)
                .frame(minWidth: DSize.fieldIcon)
            Text(line.name ?? String(localized: "Ejercicio"))
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: DSpace.s)
            moveButton("chevron.up", label: "Subir", disabled: index == 0, identifier: "reorder.up.\(index)") {
                move(from: index, by: -1)
            }
            moveButton("chevron.down", label: "Bajar", disabled: index == order.count - 1, identifier: "reorder.down.\(index)") {
                move(from: index, by: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index + 1). \(line.name ?? String(localized: "Ejercicio"))")
        .accessibilityAction(named: "Subir") { move(from: index, by: -1) }
        .accessibilityAction(named: "Bajar") { move(from: index, by: 1) }
        .accessibilityIdentifier("reorder.row.\(index)")
    }

    private func moveButton(
        _ systemName: String,
        label: LocalizedStringKey,
        disabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: DSize.dayChip, height: DSize.dayChip)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard order.indices.contains(index), order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    private func commit(_ operation: () async -> Bool) async {
        saving = true
        let saved = await operation()
        saving = false
        if saved { dismiss() } else { saveFailed = true }
    }
}
