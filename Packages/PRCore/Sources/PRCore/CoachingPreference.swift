//
//  CoachingPreference.swift
//  PRCore
//
//  SCRUM-267 (PR-H005, RF-026): cuánto le explica la app a cada persona. Por defecto, el
//  nivel de su experiencia (`CoachingDetailMapper`); si elige uno en Perfil, ese manda
//  (`CoachingDetailPrefs`) hasta que vuelva a "según mi experiencia". La elección se guarda
//  por usuario en su propia colección (`coaching-preference/`): no toca el plan, así que
//  no lo regenera, y rehacer el cuestionario no la pisa. Ningún nivel quita el aviso por
//  molestia: eso lo garantiza `CoachingCardDriver`.
//

import Foundation
import Observation
import PRDomain

/// Lo que eligió la persona.
public enum CoachingLevelChoice: Codable, Sendable, Equatable, Hashable {
    /// Sin elección: el nivel sale de la experiencia.
    case byExperience
    /// Elegido en Perfil: manda sobre el de la experiencia.
    case manual(level: CoachingDetailLevel)
}

/// Registro guardado. Sin el ID del usuario: la clave del archivo ya lo identifica.
/// `choice` es obligatorio: así ningún otro registro se confunde con éste (SCRUM-40).
public struct StoredCoachingPreference: Codable, Sendable, Equatable {
    public let choice: CoachingLevelChoice
    public let updatedAt: Date

    public init(choice: CoachingLevelChoice, updatedAt: Date) {
        self.choice = choice
        self.updatedAt = updatedAt
    }
}

/// Lee y escribe la elección de cada usuario.
public struct CoachingPreferenceStore: Sendable {
    private let store: any RepositoryStore

    public init(store: some RepositoryStore) {
        self.store = store
    }

    /// Sin registro, o con uno ilegible (que no se borra), cuenta como "según tu experiencia".
    /// Lanza si falla la lectura.
    public func load(userID: String) throws -> CoachingLevelChoice {
        guard let data = try store.read(key: PlanStore.key(forUser: userID)),
              let stored = try? JSONDecoder().decode(StoredCoachingPreference.self, from: data) else {
            return .byExperience
        }
        return stored.choice
    }

    /// Guarda la elección. Lanza si la escritura falla (no se traga el error).
    public func save(_ choice: CoachingLevelChoice, userID: String, at date: Date) throws {
        let record = StoredCoachingPreference(choice: choice, updatedAt: date)
        try store.write(key: PlanStore.key(forUser: userID), data: JSONEncoder().encode(record))
    }
}

extension LocalPersistence {
    public func coachingPreferenceStore() throws -> CoachingPreferenceStore {
        CoachingPreferenceStore(store: try store(for: .coachingPreference))
    }
}

/// La elección de la cuenta activa y el nivel que usa la app.
@MainActor
@Observable
public final class CoachingPreferenceCoordinator {
    /// La elección guardada (o "según tu experiencia" si no hay).
    public private(set) var choice: CoachingLevelChoice = .byExperience
    /// La última elección no se pudo guardar: sigue la anterior y se avisa.
    public private(set) var saveFailed = false

    private let store: CoachingPreferenceStore?
    private let clock: () -> Date
    private var userID: String?

    public init(store: CoachingPreferenceStore?, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.clock = clock
    }

    /// Lee la elección de este usuario. Si no se puede leer queda "según tu experiencia".
    public func load(userID: String?) {
        self.userID = userID
        saveFailed = false
        guard let userID, let store else {
            choice = .byExperience
            return
        }
        do {
            choice = try store.load(userID: userID)
        } catch {
            choice = .byExperience
        }
    }

    /// Guarda y aplica. Si no se puede guardar, sigue la elección anterior y `saveFailed`
    /// lo avisa: lo que se ve es siempre lo guardado.
    @discardableResult
    public func choose(_ next: CoachingLevelChoice) -> Bool {
        guard let store, let userID else {
            saveFailed = true
            return false
        }
        do {
            try store.save(next, userID: userID, at: clock())
            choice = next
            saveFailed = false
            return true
        } catch {
            saveFailed = true
            return false
        }
    }

    /// El nivel efectivo y su origen para una experiencia (PR-0403).
    public func prefs(for experience: ExperienceLevel) -> CoachingDetailPrefs {
        let byExperience = CoachingDetailPrefs.defaulted(for: experience)
        switch choice {
        case .byExperience:
            return byExperience
        case .manual(let level):
            return byExperience.applyingManualOverride(level)
        }
    }
}
