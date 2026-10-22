//
//  SigningInView.swift
//  PR
//
//  Created by PR.
//
//  Espera del inicio de sesión con Apple (SCRUM-193). Dice qué está pasando con la marca
//  Nucleus y, si tarda más de `DMotion.slowSignInThreshold`, ofrece "Reintentar" (el
//  coordinador cancela el intento colgado antes de lanzar otro). Vista pura.
//

import SwiftUI

struct SigningInView: View {
    /// Intento: cancelar el intento colgado y volver a lanzarlo.
    let onRetry: () -> Void

    @State private var isSlow = false
    /// Cambiarlo reinicia la cuenta de la espera larga.
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: DSpace.l) {
            Spacer()
            Text("Nucleus")
                .font(.largeTitle.bold())
            ProgressView()
                .controlSize(.large)
                .tint(Color.primaryAction)
                .accessibilityHidden(true)
            Text("Conectando con Apple…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if isSlow {
                VStack(spacing: DSpace.s) {
                    Text("Está tardando más de lo normal. Revisa tu conexión.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        isSlow = false
                        attempt += 1
                        onRetry()
                    } label: {
                        Text("Reintentar")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("signIn.retry")
                }
                .padding(.horizontal, DSpace.l)
                .transition(.opacity)
            }
        }
        .padding(.bottom, DSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("signIn.connecting")
        .task(id: attempt) {
            do {
                try await Task.sleep(for: DMotion.slowSignInThreshold)
                withAnimation { isSlow = true }
            } catch {
                // La vista desapareció (sesión iniciada o cancelada): nada que mostrar.
            }
        }
    }
}

#Preview("Conectando") {
    SigningInView(onRetry: {})
}

#Preview("Conectando · oscuro · accessibility3") {
    SigningInView(onRetry: {})
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
