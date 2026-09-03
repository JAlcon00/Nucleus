//
//  SafeLogging.swift
//  PRCore
//
//  Created by PR.
//
//  PR-0003 — Logging seguro. Wrapper sobre `os.Logger` con categorías
//  (app, workout, health, sync, agent, persistence) y redacción determinista: está
//  PROHIBIDO loggear notas de lesión, samples de salud, tokens o Apple identifiers.
//
//  Arquitectura:
//  - `LogCategory`/`LogLevel`: vocabulario tipado de categorías y niveles.
//  - `LogRedactor`: redacción PURA y testeable (formateo propio). Independiente de
//    `os` para poder verificarse en unit tests sin tocar el unified logging system.
//  - `PRLogger`: wrapper `Sendable` sobre `os.Logger` por categoría. Los valores que
//    pasan por su API se interpolan con privacidad por defecto (el sistema los
//    oculta); nunca se marcan como `.public`. Cualquier payload sensible se redacta
//    con `LogRedactor` ANTES de emitirse. No se persiste credenciales/secrets.
//

import Foundation
import os

/// Categorías de log (PR-0003). Cada una mapea a una categoría de `os.Logger`.
public enum LogCategory: String, Sendable, CaseIterable, Hashable {
    case app
    case workout
    case health
    case sync
    case agent
    case persistence
}

/// Niveles de log del wrapper.
public enum LogLevel: Int, Sendable, CaseIterable, Hashable, Comparable {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3
    case fault = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Redacción determinista de payloads prohibidos (PR-0003). Puro y sin IO para poder
/// verificar en unit tests el "formateo propio". Sustituye toda ocurrencia de un
/// valor sensible y de patrones peligrosos por `[REDACTED]`.
public struct LogRedactor: Sendable {
    /// Marcador que reemplaza todo payload sensible.
    public static let placeholder = "[REDACTED]"

    /// UUID-like: 8-4-4-4-12 hexadecimal (identificadores de sample de salud, IDs).
    private static let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    /// Prefijo de token conocido (`tok_`, `sk-`, `Bearer `).
    private static let tokenPrefixPattern = #"(tok_|sk-|eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+|Bearer\s+)[A-Za-z0-9_\-\.\+/=]{8,}"#
    /// Notas de lesión / dolor que nunca deben loguearse.
    private static let injuryPattern = #"(nota de lesión|lesion note|pain note|injury note|dolor[^,]{0,40})"#
    /// Apple identifier opaco (p. ej. el `user` de AuthenticationServices).
    private static let appleUserPattern = #"(user identifier|userIdentifier|apple user)[=:]\s*([^\s,;]+)"#

    public init() {}

    /// Redacta `raw` sustituyendo los valores sensibles explícitos y los patrones
    /// prohibidos conocidos.
    public func redact(_ raw: String, sensitiveValues: [String] = []) -> String {
        var out = raw
        // 1) Pequeños valores sensibles explícitos (tokens, ids, notas) primero.
        for value in sensitiveValues where !value.isEmpty && value != Self.placeholder {
            out = out.replacingOccurrences(of: value, with: Self.placeholder)
        }
        // 2) Tokens por prefijo conocido (antes de UUID para absorber `tok_<uuid>`).
        out = out.replacingOccurrences(
            of: Self.tokenPrefixPattern,
            with: Self.placeholder,
            options: .regularExpression
        )
        // 3) Identificadores UUID (samples de salud / ids de usuario).
        out = out.replacingOccurrences(
            of: Self.uuidPattern,
            with: Self.placeholder,
            options: .regularExpression
        )
        // 4) Notas de lesión/dolor.
        out = out.replacingOccurrences(
            of: Self.injuryPattern,
            with: Self.placeholder,
            options: .regularExpression
        )
        // 5) Apple identifier etiquetado.
        out = out.replacingOccurrences(
            of: Self.appleUserPattern,
            with: Self.placeholder,
            options: .regularExpression
        )
        return out
    }

    /// Redacta una entrada (clave, valor). Si la clave pertenece a un dominio
    /// prohibido (injury/pain/token/health-id/apple), el valor se oculta entero.
    public func redactEntry(key: String, value: String) -> String {
        let normalized = key.lowercased()
        let forbiddenKey =
            normalized.contains("injury")
            || normalized.contains("lesion")
            || normalized.contains("pain")
            || normalized.contains("nota")
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("authcode")
            || normalized.contains("authorization")
            || normalized.contains("user")
            || normalized.contains("sample")
            || normalized.contains("apple")
        if forbiddenKey {
            return Self.placeholder
        }
        return redact(value)
    }

    /// Comprueba si un mensaje redactado contiene aún un payload sensible conocido.
    public func wouldExpose(_ raw: String) -> Bool {
        let redacted = redact(raw)
        return redacted != raw
    }
}

/// Wrapper seguro sobre `os.Logger` (PR-0003). Abarca las seis categorías y NUNCA
/// emite payloads sensibles: interpolación con privacidad por defecto del sistema y
/// redacción previa con `LogRedactor`. `Sendable`.
public struct PRLogger: Sendable {
    /// Subsistema por defecto (com/company/app).
    public static let defaultSubsystem = "com.jalcon.pr"

    /// Logger subyacente. Se mantiene interno; la API del wrapper es la pública.
    let logger: Logger
    public let category: LogCategory

    public init(category: LogCategory, subsystem: String = PRLogger.defaultSubsystem) {
        self.category = category
        self.logger = Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Nivel por método.
    public func debug(_ message: String) { logger.debug("\(message, privacy: .private)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .private)") }
    public func notice(_ message: String) { logger.notice("\(message, privacy: .private)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .private)") }
    public func fault(_ message: String) { logger.fault("\(message, privacy: .private)") }

    /// Emite a un nivel concreto.
    public func log(level: LogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .private)")
        case .info: logger.info("\(message, privacy: .private)")
        case .notice: logger.notice("\(message, privacy: .private)")
        case .error: logger.error("\(message, privacy: .private)")
        case .fault: logger.fault("\(message, privacy: .private)")
        }
    }

    /// Variante segura para payloads potencialmente sensibles: redacta con
    /// `LogRedactor` antes de emitir y mantiene privacidad por defecto.
    public func redacted(_ message: String, sensitiveValues: [String], level: LogLevel = .info) {
        let safe = LogRedactor().redact(message, sensitiveValues: sensitiveValues)
        log(level: level, safe)
    }
}