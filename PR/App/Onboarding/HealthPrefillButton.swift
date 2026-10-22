//
//  HealthPrefillButton.swift
//  PR
//
//  "Usar datos de Salud" (SCRUM-206): botón opcional arriba de "Sobre ti" y el aviso de
//  cada estado. Ícono + texto en cada aviso (el color nunca es el único significado). El
//  formulario se puede llenar igual sin Salud. Vista pura.
//

import SwiftUI
import PRCore

struct HealthPrefillButton: View {
    let state: HealthPrefillState
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            Button(action: onTap) {
                HStack(spacing: DSpace.s) {
                    if state == .loading {
                        ProgressView()
                    } else {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(Color.primaryAction)
                            .accessibilityHidden(true)
                    }
                    Text(state == .loading ? "Leyendo Salud…" : "Usar datos de Salud")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.surface)
            .disabled(state == .loading)
            .accessibilityHint("Llena edad, sexo, estatura y peso desde Apple Salud. Es opcional.")
            .accessibilityIdentifier("aboutYou.health")

            if let status {
                Label {
                    Text(status.text)
                } icon: {
                    Image(systemName: status.icon)
                        .foregroundStyle(status.color)
                }
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("aboutYou.health.status")
            }
        }
    }

    private var status: (text: LocalizedStringKey, icon: String, color: Color)? {
        switch state {
        case .idle, .loading:
            return nil
        case .filled(let filled, let ignored) where ignored > 0:
            return ("Llenamos \(filled) datos. Algunos valores de Salud están fuera de rango: revísalos.", "exclamationmark.circle.fill", Color.warning)
        case .filled(let filled, _):
            return ("Llenamos \(filled) datos desde Salud. Revísalos antes de continuar.", "checkmark.circle.fill", Color.success)
        case .noData:
            return ("No encontramos datos en Salud. Si no diste permiso, puedes darlo en Ajustes › Salud. O llénalo a mano.", "info.circle.fill", Color.textSecondary)
        case .denied:
            return ("Sin permiso para leer Salud. Llena tus datos a mano.", "hand.raised.fill", Color.warning)
        case .unavailable:
            return ("Salud no está disponible en este dispositivo. Llena tus datos a mano.", "iphone.slash", Color.textSecondary)
        }
    }
}

#Preview("Estados") {
    VStack(spacing: DSpace.l) {
        HealthPrefillButton(state: .idle, onTap: {})
        HealthPrefillButton(state: .loading, onTap: {})
        HealthPrefillButton(state: .filled(filled: 4, ignored: 0), onTap: {})
        HealthPrefillButton(state: .filled(filled: 2, ignored: 1), onTap: {})
        HealthPrefillButton(state: .noData, onTap: {})
    }
    .padding()
    .screenBackground()
    .ironEnergyTheme()
}

#Preview("Negado · accessibility3 · oscuro") {
    HealthPrefillButton(state: .denied, onTap: {})
        .padding()
        .screenBackground()
        .ironEnergyTheme()
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
