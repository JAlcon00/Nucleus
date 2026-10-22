//
//  LoadingComponents.swift
//  PR
//
//  Created by PR.
//
//  Piezas de carga reutilizables (SCRUM-193): brillo de skeleton que respeta Reduce
//  Motion y etiqueta de botón "en curso" que no cambia de tamaño al cargar. Vistas
//  puras: no deciden cuándo se carga, sólo cómo se ve.
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
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.45), location: 0),
                            .init(color: .black, location: 0.5),
                            .init(color: .black.opacity(0.45), location: 1),
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
}

#Preview("Botón en curso") {
    Button {} label: {
        LoadingButtonLabel(isLoading: true, loadingAccessibilityLabel: "Abriendo entrenamiento") {
            Label("Empezar Push", systemImage: "play.fill")
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
    .buttonStyle(.borderedProminent)
    .padding()
}
