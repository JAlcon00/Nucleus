//
//  HealthPreference.swift
//  PRCore
//
//  SCRUM-248 (PR-F005, DF-2): si la persona quiere guardar sus entrenamientos en Salud, por
//  usuario y en su propia colección, y cuándo se le propone. El permiso se pide en el resumen
//  de un entrenamiento terminado, nunca al empezar ni durante.
//

import Foundation
import Observation
import PRDomain

/// Lo que la persona decidió en la app. El permiso del sistema es aparte: se puede querer
/// guardar y tenerlo negado en Ajustes.
public enum HealthWritePreference: String, Codable, Sendable, CaseIterable, Hashable {
    case notAsked
    case enabled
    /// "Ahora no", o el interruptor apagado en Perfil.
    case disabled
}

/// Registro guardado. Sin el ID del usuario: la clave del archivo ya lo identifica.
public struct StoredHealthPreference: Codable, Sendable, Equatable {
    public let preference: HealthWritePreference
    public let updatedAt: Date

    public init(preference: HealthWritePreference, updatedAt: Date) {
        self.preference = preference
        self.updatedAt = updatedAt
    }
}

/// Lee y escribe la preferencia de cada usuario.
public struct HealthPreferenceStore: Sendable {
    private let store: any RepositoryStore

    public init(store: some RepositoryStore) {
        self.store = store
    }

    /// Sin registro cuenta como "sin preguntar". Un archivo dañado también. Lanza si falla la lectura.
    public func load(userID: String) throws -> HealthWritePreference {
        guard let data = try store.read(key: PlanStore.key(forUser: userID)),
              let stored = try? JSONDecoder().decode(StoredHealthPreference.self, from: data) else {
            return .notAsked
        }
        return stored.preference
    }

    /// Guarda la decisión. Lanza si la escritura falla.
    public func save(_ preference: HealthWritePreference, userID: String, at date: Date) throws {
        let record = StoredHealthPreference(preference: preference, updatedAt: date)
        try store.write(key: PlanStore.key(forUser: userID), data: JSONEncoder().encode(record))
    }
}

extension LocalPersistence {
    public func healthPreferenceStore() throws -> HealthPreferenceStore {
        HealthPreferenceStore(store: try store(for: .healthPreference))
    }
}

/// Cuándo sale la tarjeta del resumen. Regla pura.
public enum HealthPermissionOffer {
    /// Sale con Salud disponible y el flag encendido, en un entrenamiento que iría a Salud,
    /// si la persona no ha decidido en la app ni en la hoja del sistema. Un entrenamiento
    /// abandonado no cuenta: la tarjeta espera al primero que sí se complete.
    public static func shouldShow(
        isEnabled: Bool,
        isAvailable: Bool,
        preference: HealthWritePreference,
        writeStatus: HealthAuthorizationStatus,
        sessionGoesToHealth: Bool
    ) -> Bool {
        isEnabled && isAvailable && sessionGoesToHealth
            && preference == .notAsked && writeStatus == .notDetermined
    }
}

/// Lo que muestra el interruptor de Perfil.
public enum HealthWriteSetting: Sendable, Hashable {
    case on
    case off
    /// Se negó en la hoja del sistema: sólo se cambia en Ajustes.
    case deniedInSettings

    public init(preference: HealthWritePreference, writeStatus: HealthAuthorizationStatus) {
        switch writeStatus {
        case .denied:
            self = .deniedInSettings
        case .granted:
            self = preference == .disabled ? .off : .on
        case .notDetermined, .notVisible:
            self = .off
        }
    }

    public var isOn: Bool {
        switch self {
        case .on: return true
        case .off, .deniedInSettings: return false
        }
    }
}

/// La preferencia de la cuenta activa.
@MainActor
@Observable
public final class HealthPreferenceCoordinator {
    public private(set) var preference: HealthWritePreference = .notAsked
    /// La última decisión no se pudo guardar.
    public private(set) var saveFailed = false

    private let store: HealthPreferenceStore?
    private let clock: () -> Date
    private var userID: String?

    public init(store: HealthPreferenceStore?, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.clock = clock
    }

    /// ¿La persona deja escribir? Sin decidir sí: el permiso del sistema manda.
    public var allowsWriting: Bool { preference != .disabled }

    /// Lee la decisión de este usuario. Si no se puede leer queda "sin preguntar".
    public func load(userID: String?) {
        self.userID = userID
        saveFailed = false
        guard let userID, let store else {
            preference = .notAsked
            return
        }
        preference = (try? store.load(userID: userID)) ?? .notAsked
    }

    /// Guarda y aplica. Apagar aplica aunque no se pueda guardar: nunca se escribe de más.
    @discardableResult
    public func set(_ next: HealthWritePreference) -> Bool {
        guard let store, let userID else {
            saveFailed = true
            if next == .disabled { preference = next }
            return false
        }
        do {
            try store.save(next, userID: userID, at: clock())
            preference = next
            saveFailed = false
            return true
        } catch {
            saveFailed = true
            if next == .disabled { preference = next }
            return false
        }
    }
}
