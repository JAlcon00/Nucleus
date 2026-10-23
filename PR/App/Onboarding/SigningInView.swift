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
    /// Isotipo de la marca (SCRUM-199); escala con el texto.
    @ScaledMetric(relativeTo: .largeTitle) private var isotypeSize = DSize.brandIsotype
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: DSpace.l) {
            Spacer()
            // En claro, la versión mono carbón (SCRUM-208): la de color lleva el núcleo en
            // hueso y se pierde sobre el fondo claro.
            Group {
                if colorScheme == .light {
                    Image(.logoIsotipoTemplate)
                        .resizable()
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Image(.logoIsotipo)
                        .resizable()
                }
            }
                .scaledToFit()
                .frame(width: isotypeSize, height: isotypeSize)
                .accessibilityLabel("Nucleus")
            ProgressView()
                .controlSize(.large)
                .tint(Color.primaryAction)
                .accessibilityHidden(true)
            Text("Conectando con Apple…")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if isSlow {
                VStack(spacing: DSpace.s) {
                    Text("Está tardando más de lo normal. Revisa tu conexión.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        isSlow = false
                        attempt += 1
                        onRetry()
                    } label: {
                        Text("Reintentar")
                    }
                    .buttonStyle(.surface)
                    .accessibilityIdentifier("signIn.retry")
                }
                .padding(.horizontal, DSpace.l)
                .transition(.opacity)
            }
        }
        .padding(.bottom, DSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
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
        .ironEnergyTheme()
}

#Preview("Conectando · accessibility3") {
    SigningInView(onRetry: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
