//
//  RedoQuestionnaireConfirmation.swift
//  PR
//
//  La confirmación antes de rehacer el cuestionario. La comparten Perfil › Rehacer
//  cuestionario y Plan › "Cambiar objetivo o fase" (SCRUM-266) para que digan lo mismo:
//  cambiar objetivo, fase o días crea un bloque nuevo y el anterior se conserva (RF-033).
//

import SwiftUI

private struct RedoQuestionnaireConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "¿Rehacer el cuestionario?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Sí, rehacer") { onConfirm() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Si cambias objetivo, fase o días se crea un bloque nuevo. El anterior y su historial se conservan.")
        }
    }
}

extension View {
    /// Pide confirmación y, si se acepta, abre el cuestionario prellenado.
    func redoQuestionnaireConfirmation(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        modifier(RedoQuestionnaireConfirmation(isPresented: isPresented, onConfirm: onConfirm))
    }
}
