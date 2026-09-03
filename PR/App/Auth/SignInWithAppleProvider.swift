//
//  SignInWithAppleProvider.swift
//  PR
//
//  Created by PR.
//
//  Implementación de producción de `AppleIDAuthProviding` usando AuthenticationServices
//  (PR-0401). La capa de aplicación inyecta este provider en el coordinador; los tests
//  usan un fake y nunca tocan AuthenticationServices real.
//
//  NO se guarda el credential token (identityToken/authorizationCode): el coordinador
//  sólo conserva el `userIdentifier` opaco para el perfil local. El flujo no requiere
//  HealthKit.
//

import AuthenticationServices
import Foundation
import PRCore

/// Provider real de Sign in with Apple, puente entre `AuthenticationServices` y el
/// contrato `AppleIDAuthProviding` del core.
@MainActor
public final class SignInWithAppleProvider: NSObject, AppleIDAuthProviding {
    private var continuation: CheckedContinuation<AppleIDAuthResult, Never>?
    private var currentController: ASAuthorizationController?

    public override init() {}

    /// Inicia el flujo de Sign in with Apple y espera el resultado del delegado.
    public func authenticate() async -> AppleIDAuthResult {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            startRequest()
        }
    }

    private func startRequest() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        currentController = controller
        controller.performRequests()
    }

    private func finish(_ result: AppleIDAuthResult) {
        continuation?.resume(returning: result)
        continuation = nil
        currentController = nil
    }
}

extension SignInWithAppleProvider: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failed(message: "No se pudo leer la credencial de Apple."))
            return
        }
        // De la credencial SÓLO se usa el `user` opaco; el identityToken/código NO
        // se conserva (RF-0401: no persistir el token de forma insegura).
        finish(.success(userIdentifier: credential.user))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError,
           authError.code == .canceled {
            // Cancelación del usuario: no es un error.
            finish(.canceled)
            return
        }
        finish(.failed(message: error.localizedDescription))
    }
}

extension SignInWithAppleProvider: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // La ventana key de la escena activa es el ancla correcto.
        if let keyWindow = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow {
            return keyWindow
        }
        // Fallback: primera ventana de la primera escena conectada.
        if let window = scenes.first?.windows.first {
            return window
        }
        // Caso extremo: primera escena conectada (app recién lanzada).
        if let scene = scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        // Sin escena conectada no se puede presentar el flujo; se recupera en el
        // siguiente `signIn` cuando el sistema haya establecido una escena.
        return ASPresentationAnchor(windowScene: sceneForMissingAnchor())
    }

    private func sceneForMissingAnchor() -> UIWindowScene {
        // Nunca alcanzado en la práctica: el sistema crea una escena antes de que
        // el usuario pueda iniciar sesión. Mantenemos el retorno válido por tipo.
        preconditionFailure("No hay ninguna UIWindowScene conectada para presentar Sign in with Apple.")
    }
}