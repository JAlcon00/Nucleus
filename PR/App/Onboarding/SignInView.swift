//
//  SignInView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla gate de autenticación (EPIC-04, PR-0401). Renderiza el estado del
//  `OnboardingCoordinator` (signedOut/signingIn) y envía el intent `signIn`. NO contiene
//  reglas de negocio ni AuthenticationServices; sólo un botón que delega en el coordinador.
//  No persiste credenciales inseguras y el login no requiere HealthKit.
//

import SwiftUI

struct SignInView: View {
    /// Intent: iniciar el flujo de Sign in with Apple.
    let onSignIn: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("PR")
                    .font(.largeTitle.bold())
                Text("Tu entrenador experto")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await onSignIn() }
            } label: {
                Label("Continuar con Apple", systemImage: "apple.logo")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Inicia sesión con Sign in with Apple para empezar el entrenamiento.")
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SignInView(onSignIn: {})
}