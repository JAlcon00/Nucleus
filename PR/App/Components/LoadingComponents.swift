//
//  LoadingComponents.swift
//  PR
//
//  Created by PR.
//
//  Piezas de carga reutilizables (SCRUM-193): brillo de skeleton que respeta Reduce
//  Motion y etiqueta de botón "en curso" que no cambia de tamaño al cargar (pensada para
//  el CTA de energía: el indicador va en `onAccent`). Vistas puras: no deciden cuándo se
//  carga, sólo cómo se ve.
//

import SwiftUI

// MARK: - Shimmer

/// Brillo suave que recorre un skeleton. Con Reduce Motion el skeleton queda quieto
/// (mismo significado, sin movimiento).
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = -1

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .mask {
                    // Máscara: sólo cuenta la opacidad, el color no se ve.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.45), location: 0), // color-guard: allow (máscara)
                            .init(color: .black, location: 0.5), // color-guard: allow (máscara)
                            .init(color: .black.opacity(0.45), location: 1), // color-guard: allow (máscara)
                        ],
                        startPoint: UnitPoint(x: offset, y: 0.5),
                        endPoint: UnitPoint(x: offset + 1, y: 0.5)
                    )
                }
                .onAppear {
                    withAnimation(DMotion.shimmer) { offset = 1 }
                }
        }
    }
}

extension View {
    /// Brillo de carga para skeletons (`.redacted(reason: .placeholder)`).
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

// MARK: - Botón en curso

/// Etiqueta de un botón que dispara una carga: con `isLoading` muestra un indicador en el
/// mismo espacio (el botón no salta de tamaño) y VoiceOver dice qué está pasando.
struct LoadingButtonLabel<Label: View>: View {
    let isLoading: Bool
    let loadingAccessibilityLabel: LocalizedStringKey
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            label
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView()
                    .tint(Color.onAccent)
                    .accessibilityLabel(Text(loadingAccessibilityLabel))
            }
        }
    }
}

#Preview("Skeleton") {
    VStack(alignment: .leading, spacing: DSpace.s) {
        Text("Título de ejemplo").font(.title2.bold())
        Text("Una línea de detalle más larga").font(.callout)
    }
    .redacted(reason: .placeholder)
    .shimmering()
    .padding()
    .screenBackground()
    .ironEnergyTheme()
}

#Preview("Botón en curso") {
    Button {} label: {
        LoadingButtonLabel(isLoading: true, loadingAccessibilityLabel: "Abriendo entrenamiento") {
            Label("Empezar Push", systemImage: "play.fill")
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
    .buttonStyle(.energy)
    .padding()
    .screenBackground()
    .ironEnergyTheme()
}
