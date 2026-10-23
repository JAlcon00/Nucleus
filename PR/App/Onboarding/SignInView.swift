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
//  SCRUM-199: logo de la identidad v2 (catálogo de assets).
//

import SwiftUI

struct SignInView: View {
    /// Intent: iniciar el flujo de Sign in with Apple.
    let onSignIn: () async -> Void

    /// Ancho del logo horizontal (mínimo de marca: 96 pt); escala con el texto.
    @ScaledMetric(relativeTo: .largeTitle) private var logoWidth = DSize.brandLogo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: DSpace.l) {
            Spacer()

            // Logo de marca (SCRUM-199): isotipo + "NUCLEUS" en vector. En oscuro la versión
            // a color; en claro la mono carbón (variante aprobada para fondos claros,
            // SCRUM-208). VoiceOver lo lee como el encabezado "Nucleus".
            VStack(spacing: DSpace.m) {
                Group {
                    if colorScheme == .light {
                        Image(.logoHorizontalTemplate)
                            .resizable()
                            .foregroundStyle(Color.textPrimary)
                    } else {
                        Image(.logoHorizontal)
                            .resizable()
                    }
                }
                    .scaledToFit()
                    .frame(width: logoWidth)
                    .accessibilityLabel("Nucleus")
                    .accessibilityAddTraits(.isHeader)
                Text("Tu entrenador experto")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            AppleSignInButton {
                Task { await onSignIn() }
            }
            .id(colorScheme)
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
