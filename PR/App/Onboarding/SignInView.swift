//
//  SignInView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla gate de autenticación (EPIC-04, PR-0401). Renderiza el estado del
//  `OnboardingCoordinator` (signedOut/signingIn) y envía el intent `signIn`. NO contiene
//  reglas de negocio: el botón oficial de Apple (`AppleSignInButton`) sólo delega en el
//  coordinador. No persiste credenciales inseguras y el login no requiere HealthKit.
//  SCRUM-195: marca Nucleus y botón oficial blanco sobre carbón (guías de Apple).
//

import SwiftUI

struct SignInView: View {
    /// Intent: iniciar el flujo de Sign in with Apple.
    let onSignIn: () async -> Void

    var body: some View {
        VStack(spacing: DSpace.l) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(LinearGradient.energy)
                .accessibilityHidden(true)

            VStack(spacing: DSpace.s) {
                Text("Nucleus")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Tu entrenador experto")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            AppleSignInButton {
                Task { await onSignIn() }
            }
            .frame(maxWidth: .infinity, minHeight: DButton.primaryHeight, maxHeight: DButton.primaryHeight)
            .accessibilityHint("Inicia sesión con Sign in with Apple para empezar el entrenamiento.")
            .accessibilityIdentifier("signIn.apple")
            .padding(.horizontal, DSpace.l)

            Text("Tus entrenamientos se guardan en este iPhone.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSpace.l)
        }
        .padding(.bottom, DSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SignInView(onSignIn: {})
        .ironEnergyTheme()
}

#Preview("accessibility3") {
    SignInView(onSignIn: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
