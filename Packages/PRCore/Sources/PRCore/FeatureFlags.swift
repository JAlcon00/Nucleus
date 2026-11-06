//
//  FeatureFlags.swift
//  PRCore
//
//  Created by PR.
//
//  Feature flags y configuración (PR-0004, backlog §PR-0004). Permiten habilitar o
//  deshabilitar capacidades por una única clave estable y con defaults SEGUROS,
//  SIN guardar secretos en claro. La configuración nunca contiene claves de API ni
//  credenciales: esas viven fuera del bundle (NVIDIAKeyLoader, ver PR-2002).
//
//  Defaults:
//  - Toda capacidad del agente en producción está DESHABILITADA por defecto; la app
//    las enciende explícitamente cuando el usuario opta por ellas y el transporte
//    está configurado. Esto evita fuga de datos y coste no esperado.
//  - Los flags de "writes" del agente son independientes de los de "read-only":
//    se puede ofrecer coaching de lectura sin permitir escrituras (Appendix E).
//

import Foundation

/// Claves estables de feature flags (Appendix E del spec backend).
public enum FeatureFlagKey: String, Sendable, CaseIterable, Hashable {
    // Agente NVIDIA
    case agentNvidiaEnabled = "agent.nvidia.enabled"
    case agentNvidiaReasoningEnabled = "agent.nvidia.reasoning.enabled"
    case agentNvidiaStreamingEnabled = "agent.nvidia.streaming.enabled"
    // Capacidades del agente (escritura vs lectura)
    case agentToolsWriteEnabled = "agent.tools.write.enabled"
    case agentHealthContextEnabled = "agent.health_context.enabled"
    case agentRecoveryAdjustmentEnabled = "agent.recovery_adjustment.enabled"
    case agentExerciseSubstitutionEnabled = "agent.exercise_substitution.enabled"
    // Salud (SCRUM-39): botón "Usar datos de Salud" en "Sobre ti".
    case healthPrefillEnabled = "health.prefill.enabled"
    // Reloj (SCRUM-258): sesión de Salud en el reloj. Apagada hasta pasar el gate SCRUM-261.
    case watchHealthSessionEnabled = "watch.health_session.enabled"
}

/// Estado de un flag: valor + origen (default o sobrescrito). Auditable.
public struct FeatureFlagValue: Codable, Sendable, Equatable, Hashable {
    public enum Source: String, Codable, Sendable, Hashable {
        case `default`
        case override
    }

    public let enabled: Bool
    public let source: Source

    public init(enabled: Bool, source: Source = .default) {
        self.enabled = enabled
        self.source = source
    }
}

/// Configuration mínima que la app necesita y que NO contiene secretos.
public struct AppConfiguration: Codable, Sendable, Equatable {
    /// Número de reentrenos dentro de la sesión activa. no expone tokens.
    public var environmentTag: String

    public init(environmentTag: String = "production") {
        self.environmentTag = environmentTag
    }
}

/// Feature flags con defaults seguros para producción. Valor-semántica (Sendable);
/// la persistencia duradera la decide la capa de app.
public struct FeatureFlags: Sendable, Equatable {
    /// Mapa interno clave → valor. Sólo se admiten claves conocidas de
    /// `FeatureFlagKey.allCases`.
    private var storage: [String: FeatureFlagValue]

    public init(overrides: [FeatureFlagKey: Bool] = [:]) {
        var storage: [String: FeatureFlagValue] = [:]
        for key in FeatureFlagKey.allCases {
            let enabled = overrides[key] ?? Self.defaultValue(for: key)
            storage[key.rawValue] = FeatureFlagValue(
                enabled: enabled,
                source: overrides[key] != nil ? .override : .default
            )
        }
        self.storage = storage
    }

    /// Valor efectivo de un flag.
    public func isEnabled(_ key: FeatureFlagKey) -> Bool {
        storage[key.rawValue]?.enabled ?? false
    }

    /// Origen del valor (default vs override), para auditoría.
    public func source(of key: FeatureFlagKey) -> FeatureFlagValue.Source {
        storage[key.rawValue]?.source ?? .default
    }

    /// Fija un valor con origen explícito.
    public func setting(_ key: FeatureFlagKey, to enabled: Bool) -> FeatureFlags {
        var next = self
        next.storage[key.rawValue] = FeatureFlagValue(enabled: enabled, source: .override)
        return next
    }

    /// Todos los flags, ordenados por clave estable.
    public var all: [FeatureFlagKey: FeatureFlagValue] {
        var result: [FeatureFlagKey: FeatureFlagValue] = [:]
        for key in FeatureFlagKey.allCases {
            if let value = storage[key.rawValue] {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Defaults

    private static func defaultValue(for key: FeatureFlagKey) -> Bool {
        switch key {
        case .agentNvidiaEnabled: return false
        case .agentNvidiaReasoningEnabled: return false
        case .agentNvidiaStreamingEnabled: return false
        case .agentToolsWriteEnabled: return false
        case .agentHealthContextEnabled: return false
        case .agentRecoveryAdjustmentEnabled: return false
        case .agentExerciseSubstitutionEnabled: return false
        case .healthPrefillEnabled: return false
        case .watchHealthSessionEnabled: return false
        }
    }
}

// MARK: - Flags de la app (SCRUM-39)

extension FeatureFlags {
    /// `-PRFeatureFlag clave=0|1`, sólo en Debug (se puede repetir).
    public static let launchArgument = "-PRFeatureFlag"

    /// Lo que la app ya trae encendido (decisión de Jesús, 2026-11-02: "como hoy"). La IA
    /// sigue apagada en Release por el build (`AIConnection`); la flag sólo la puede apagar.
    public static let shipped: [FeatureFlagKey] = [.agentNvidiaEnabled, .healthPrefillEnabled]

    /// Las flags de la app, armadas una vez al arrancar: la base segura (todo apagado) con
    /// lo que la app trae encendido y, sólo en Debug, los cambios de `-PRFeatureFlag`. Una
    /// clave desconocida o un valor raro se ignoran.
    public static func forApp(arguments: [String], isDebugBuild: Bool) -> FeatureFlags {
        var flags = shipped.reduce(FeatureFlags()) { $0.setting($1, to: true) }
        guard isDebugBuild else { return flags }
        for (key, enabled) in launchOverrides(in: arguments) {
            flags = flags.setting(key, to: enabled)
        }
        return flags
    }

    /// Los `-PRFeatureFlag clave=valor` válidos, en orden (el último gana).
    private static func launchOverrides(in arguments: [String]) -> [(FeatureFlagKey, Bool)] {
        zip(arguments, arguments.dropFirst()).compactMap { flag, value in
            guard flag == launchArgument else { return nil }
            let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let key = FeatureFlagKey(rawValue: parts[0]) else { return nil }
            switch parts[1].lowercased() {
            case "1", "true": return (key, true)
            case "0", "false": return (key, false)
            default: return nil
            }
        }
    }
}

/// Error al decodificar una configuración de flags.
public enum FeatureFlagsError: Error, Equatable, Sendable {
    /// Clave desconocida en el JSON o diccionario de decode.
    case unknownKey(String)
}

// MARK: - Codable (rechaza claves desconocidas al decodificar)

extension FeatureFlags: Codable {
    private enum CodingKeys: String, CodingKey {
        case storage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([String: FeatureFlagValue].self, forKey: .storage)
        var storage: [String: FeatureFlagValue] = [:]
        for key in decoded.keys {
            guard FeatureFlagKey(rawValue: key) != nil else {
                throw FeatureFlagsError.unknownKey(key)
            }
            storage[key] = decoded[key]
        }
        self.storage = storage
    }
}