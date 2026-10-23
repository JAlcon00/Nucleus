//
//  AppleSignInButton.swift
//  PR
//
//  Created by PR.
//
//  Botón OFICIAL de Sign in with Apple (SCRUM-195): `ASAuthorizationAppleIDButton` tipo
//  "Continuar con Apple", blanco sobre el fondo carbón y negro sobre el fondo claro
//  (SCRUM-208), como piden las guías de Apple. El estilo sólo se fija al crearlo: quien lo
//  usa lo reconstruye al cambiar la apariencia (`.id(colorScheme)`). Sólo dibuja el botón y reenvía el toque: la petición la hace
//  `SignInWithAppleProvider` a través del coordinador (así el modo simulado y los tests
//  siguen igual). Se usa la versión UIKit porque `SignInWithAppleButton` de SwiftUI lanza
//  su propia petición y saltaría el coordinador.
//

import AuthenticationServices
import SwiftUI

struct AppleSignInButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let style: ASAuthorizationAppleIDButton.Style = context.environment.colorScheme == .light ? .black : .white // color-guard: allow (estilo oficial de Apple)
        let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: style)
        button.cornerRadius = DRadius.medium
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
