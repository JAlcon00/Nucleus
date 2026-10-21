//
//  AuthLaunchMode.swift
//  PRCore
//
//  Created by PR.
//
//  Modo de inicio de sesión al arrancar (SCRUM-181, apoyo a pruebas manuales).
//  Sign in with Apple no siempre funciona en el simulador; para poder probar el resto
//  de la app existe un inicio de sesión SIMULADO que:
//  - sólo se activa en builds Debug Y con el launch argument `-PRFakeSignIn`;
//  - nunca en Release, aunque venga el argumento;
//  - entra solo (sin tocar el botón) con un identificador local fijo, sin tokens.
//  La decisión es pura y testeable; la app sólo le pasa sus argumentos y si es Debug.
//

import Foundation

public enum AuthLaunchMode: Equatable, Sendable {
    /// Sign in with Apple real (AuthenticationServices).
    case appleID
    /// Inicio de sesión simulado para pruebas (sólo Debug + argumento).
    case simulated

    /// Launch argument que pide el modo simulado (Edit Scheme › Run › Arguments).
    public static let simulatedSignInArgument = "-PRFakeSignIn"

    /// Identificador local del usuario simulado. No es un identificador de Apple.
    public static let simulatedUserIdentifier = "debug.simulated-user"

    /// Resuelve el modo. En Release siempre es `.appleID`.
    public static func resolve(arguments: [String], isDebugBuild: Bool) -> AuthLaunchMode {
        guard isDebugBuild, arguments.contains(simulatedSignInArgument) else { return .appleID }
        return .simulated
    }

    /// En modo simulado se salta la pantalla de inicio de sesión.
    public var signsInAutomatically: Bool {
        switch self {
        case .appleID: return false
        case .simulated: return true
        }
    }

    /// Proveedor de autenticación para este modo. `.appleID` usa el que entrega la app.
    public func provider(appleID: @autoclosure () -> any AppleIDAuthProviding) -> any AppleIDAuthProviding {
        switch self {
        case .appleID: return appleID()
        case .simulated: return FakeAppleIDAuthProvider(behavior: .success(userIdentifier: Self.simulatedUserIdentifier))
        }
    }
}
