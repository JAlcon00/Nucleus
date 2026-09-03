//
//  AuthTypes.swift
//  PRCore
//
//  Created by PR.
//
//  Abstracción de autenticación (PR-0401). AuthenticationServices queda detrás
//  de un protocolo: el coordinador de auth es testeable con un fake y el provider
//  de producción (Sign in with Apple) lo provee la capa de aplicación. NUNCA se
//  persiste el credential token de forma insegura; sólo se conserva un
//  identificador opaco del usuario para crear el perfil local. El login NO requiere
//  HealthKit (RF-001): este módulo no importa HealthKit ni AuthenticationServices.
//

import Foundation

/// Resultado de una autenticación con Apple ID.
public enum AppleIDAuthResult: Equatable, Sendable {
    /// Autenticación correcta. `userIdentifier` es el identificador opaco del
    /// usuario en Apple (estable y no sensible); se usa como clave del perfil local.
    case success(userIdentifier: String)
    /// El usuario canceló el flujo (no es un error: no se muestra alerta).
    case canceled
    /// Fallo del proveedor de auth.
    case failed(message: String)
}

/// Contrato `Sign in with Apple` detrás de un protocolo. La capa de aplicación
/// provee la implementación de producción con `AuthenticationServices`; los tests
/// y previews usan un fake (nunca AuthenticationServices real en unit tests, §32.3).
public protocol AppleIDAuthProviding: Sendable {
    /// Inicia el flujo de Sign in with Apple y devuelve el resultado.
    func authenticate() async -> AppleIDAuthResult
}

/// Perfil local creado en el primer login. NO contiene el credential token ni el
/// email sin necesidad; sólo un identificador opaco y datos de perfil editables.
public struct LocalUserProfile: Equatable, Sendable, Hashable {
    /// Identificador opaco del usuario (clave estable; nunca un token sensible).
    public let userIdentifier: String
    /// Nombre mostrado cuando Apple lo proporciona (opcional).
    public var displayName: String?
    /// `true` para el primer inicio de sesión (orientación de onboarding posterior).
    public var isFirstLogin: Bool

    public init(userIdentifier: String, displayName: String? = nil, isFirstLogin: Bool) {
        self.userIdentifier = userIdentifier
        self.displayName = displayName
        self.isFirstLogin = isFirstLogin
    }
}

/// Estado del flujo de autenticación visible por la UI. No contiene secretos.
public enum AuthFlowState: Equatable, Sendable {
    /// Sin flujo en curso.
    case idle
    /// Flujo de Sign in with Apple en curso.
    case authenticating
    /// Usuario autenticado con su perfil local.
    case signedIn(LocalUserProfile)
    /// Último flujo fallido (mensaje mostrado al usuario).
    case failed(String)
}