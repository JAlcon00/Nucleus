//
//  AppleIDAuthCoordinator.swift
//  PRCore
//
//  Created by PR.
//
//  Coordinador de auth (PR-0401): máquina de estados manejable por la UI y
//  testeable con un fake. Maneja success/cancel/failure, crea el perfil local en el
//  primer login y NUNCA persiste el credential token. No importa HealthKit.
//

import Foundation
import Observation

/// Coordinador de Sign in with Apple.
///
/// Expone el estado observable `flowState` que la UI renderiza (PR-0401 "UI state
/// tests") y delega la llamada real en un `AppleIDAuthProviding` (fake en tests).
@MainActor
@Observable
public final class AppleIDAuthCoordinator {
    /// Proveedor de auth inyectado (fake en tests, producción en la app).
    public nonisolated let provider: any AppleIDAuthProviding

    /// Estado actual visible por la UI. `published` vía Observation.
    public var flowState: AuthFlowState = .idle

    /// Perfil local del usuario autenticado (nil mientras no haya login).
    public private(set) var profile: LocalUserProfile?

    public init(provider: any AppleIDAuthProviding) {
        self.provider = provider
    }

    /// Inicia el flujo de Sign in with Apple y actualiza `flowState`.
    ///
    /// - `success`: crea el perfil local (primer login) y pasa a `.signedIn`.
    ///   Sólo se conserva el `userIdentifier` opaco; el credential token NO se
    ///   persiste (RF-0401).
    /// - `canceled`: no es un error; vuelve a `.idle` sin alerta.
    /// - `failure`: pasa a `.failed(message)`.
    public func signIn() async {
        flowState = .authenticating

        let result = await provider.authenticate()

        switch result {
        case .success(let userIdentifier):
            guard !userIdentifier.isEmpty else {
                flowState = .failed("Sign in with Apple no devolvió un identificador válido.")
                return
            }
            let wasFirstLogin = profile == nil
            let newProfile = LocalUserProfile(
                userIdentifier: userIdentifier,
                displayName: nil,
                isFirstLogin: wasFirstLogin
            )
            profile = newProfile
            flowState = .signedIn(newProfile)

        case .canceled:
            // Cancelación del usuario: no es un error, no se muestra alerta.
            flowState = .idle

        case .failed(let message):
            flowState = .failed(message)
        }
    }

    /// Devuelve la UI a su estado base (tras cerrar la alerta de error o desconectar).
    public func reset() {
        flowState = .idle
    }

    /// Cierra la sesión y descarta el perfil local (puro estado de app).
    public func signOut() {
        profile = nil
        flowState = .idle
    }
}

/// Fake de `AppleIDAuthProviding` para tests y previews (§32.3: nunca depender de
/// AuthenticationServices real en unit tests). Permite simular success/cancel/failure.
public actor FakeAppleIDAuthProvider: AppleIDAuthProviding {
    public enum FakeAuthBehavior: Sendable {
        /// Autentica correctamente con el identificador dado (por defecto `"apple-user"`).
        case success(userIdentifier: String)
        /// Devuelve el identificador vacío (caso límite: se trata como fallo).
        case emptyIdentifier
        /// El usuario cancela.
        case cancel
        /// Fallo del proveedor con un mensaje.
        case fail(String)
    }

    private let behavior: FakeAuthBehavior

    public init(behavior: FakeAuthBehavior = .success(userIdentifier: "apple-user")) {
        self.behavior = behavior
    }

    public func authenticate() async -> AppleIDAuthResult {
        switch behavior {
        case .success(let userIdentifier):
            return .success(userIdentifier: userIdentifier)
        case .emptyIdentifier:
            return .success(userIdentifier: "")
        case .cancel:
            return .canceled
        case .fail(let message):
            return .failed(message: message)
        }
    }
}