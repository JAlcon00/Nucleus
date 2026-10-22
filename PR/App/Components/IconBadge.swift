//
//  IconBadge.swift
//  PR
//
//  Created by PR.
//
//  Insignia de icono: símbolo con el acento sobre un círculo elevado. Acompaña a un texto
//  (título de sesión, dato del perfil…) para reconocerlo de un vistazo; nunca lo sustituye,
//  así que VoiceOver no la lee.
//

import SwiftUI

struct IconBadge: View {
    let systemName: String
    /// Múltiplo del tamaño base (`DSize.iconBadge`), que además escala con Dynamic Type.
    var scale: CGFloat = 1
    /// Relleno con el degradado de energía (estado activo o destacado).
    var isHighlighted = false

    @ScaledMetric(relativeTo: .body) private var base = DSize.iconBadge

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: base * scale * 0.45, weight: .semibold))
            .foregroundStyle(isHighlighted ? Color.onAccent : Color.primaryAction)
            .frame(width: base * scale, height: base * scale)
            .background {
                Circle().fill(isHighlighted ? AnyShapeStyle(LinearGradient.energy) : AnyShapeStyle(Color.surfaceElevated))
            }
            .overlay {
                Circle().strokeBorder(Color.hairline, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: DSpace.m) {
        IconBadge(systemName: "figure.strengthtraining.traditional", scale: 1.5)
        IconBadge(systemName: "bed.double.fill")
        IconBadge(systemName: "checkmark", isHighlighted: true)
    }
    .padding(DSpace.l)
    .screenBackground()
    .ironEnergyTheme()
}
