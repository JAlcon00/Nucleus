//
//  AIConsent.swift
//  PRCore
//
//  SCRUM-202 (IA-1): el consentimiento para compartir el perfil con la IA, guardado por
//  usuario en su propia colección (`ai-consent/`), y el coordinador que lo pide, lo
//  registra y lo retira. Sin consentimiento no existe contexto para la IA.
//

import Foundation
import Observation
import PRDomain

/// Registro guardado. Sin el ID del usuario: la clave del archivo ya lo identifica
/// (derivada, nunca el ID de Apple).
public struct StoredAIConsent: Codable, Sendable, Equatable {
    public let consent: AIDataConsent
    public let updatedAt: Date

    public init(consent: AIDataConsent, updatedAt: Date) {
        self.consent = consent
        self.updatedAt = updatedAt
    }
}

/// Lee y escribe el consentimiento de cada usuario.
public struct AIConsentStore: Sendable {
    private let store: any RepositoryStore

    public init(store: some RepositoryStore) {
        self.store = store
    }

    /// Decisión guardada. Sin registro, o si no se puede leer, cuenta como "sin preguntar":
    /// nunca se comparte nada por un archivo dañado. Lanza sólo si falla la lectura.
    public func load(userID: String) throws -> AIDataConsent {
        guard let data = try store.read(key: PlanStore.key(forUser: userID)),
              let stored = try? JSONDecoder().decode(StoredAIConsent.self, from: data) else {
            return .notAsked
        }
        return stored.consent
    }

    /// Guarda la decisión. Lanza si la escritura falla (no se traga el error).
    public func save(_ consent: AIDataConsent, userID: String, at date: Date) throws {
        let record = StoredAIConsent(consent: consent, updatedAt: date)
        try store.write(key: PlanStore.key(forUser: userID), data: JSONEncoder().encode(record))
    }
}

extension LocalPersistence {
    public func aiConsentStore() throws -> AIConsentStore {
        AIConsentStore(store: try store(for: .aiConsent))
    }
}

/// Estado del consentimiento para la app: pedirlo tras el formulario, aceptarlo,
/// rechazarlo o retirarlo desde Perfil.
@MainActor
@Observable
public final class AIConsentCoordinator {
    public private(set) var consent: AIDataConsent = .notAsked
    /// La última decisión no se pudo guardar: se avisa y se puede reintentar.
    public private(set) var saveFailed = false

    private let store: AIConsentStore?
    private let clock: () -> Date
    private let timeZone: () -> TimeZone
    private var userID: String?

    public init(
        store: AIConsentStore?,
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.store = store
        self.clock = clock
        self.timeZone = timeZone
    }

    /// ¿Hay que preguntarle a la persona?
    public var needsDecision: Bool { consent.needsDecision }

    /// Lee la decisión de este usuario (al iniciar sesión o retomarla). Si no se puede
    /// leer, queda "sin preguntar": no se comparte nada.
    public func load(userID: String?) {
        self.userID = userID
        saveFailed = false
        guard let userID, let store else {
            consent = .notAsked
            return
        }
        consent = (try? store.load(userID: userID)) ?? .notAsked
    }

    /// Acepta compartir el perfil con la IA.
    @discardableResult
    public func grant() -> Bool {
        record(.granted(at: clock()))
    }

    /// No acepta (o retira desde Perfil): desde ese momento no sale ningún dato.
    @discardableResult
    public func decline() -> Bool {
        record(.declined(at: clock()))
    }

    /// Contexto para la IA, sólo con consentimiento; `nil` en cualquier otro caso.
    public func context(for profile: OnboardingProfile, sleep: SleepCheckIn? = nil) -> AgentProfileContext? {
        AgentProfileContextBuilder().context(profile: profile, consent: consent, sleep: sleep, now: clock(), timeZone: timeZone())
    }

    /// Guarda primero y sólo entonces cambia el estado: si no se pudo guardar, la decisión
    /// anterior sigue vigente (retirar el consentimiento sí aplica de inmediato en memoria,
    /// para no seguir compartiendo aunque el disco falle).
    private func record(_ newValue: AIDataConsent) -> Bool {
        let date = clock()
        do {
            if let userID, let store {
                try store.save(newValue, userID: userID, at: date)
            }
            consent = newValue
            saveFailed = false
            return true
        } catch {
            saveFailed = true
            if !newValue.allowsSharing { consent = newValue }
            return false
        }
    }
}
