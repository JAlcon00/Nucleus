//
//  GymCoordinator.swift
//  PRCore
//
//  SCRUM-235 (PR-E004): el gimnasio del usuario. Sin pasos nuevos: al entrar se crea
//  "Mi gimnasio" si no hay ninguno. Vive en su propia colección por usuario, nunca dentro
//  del plan ni del perfil, así que cambiarlo no regenera el plan. Un error de escritura no
//  bloquea nada, pero tampoco se traga: queda en `notice`.
//

import Foundation
import Observation
import PRDomain

@MainActor
@Observable
public final class GymCoordinator {
    /// Lo que la pantalla tiene que avisar.
    public enum Notice: Equatable, Sendable {
        /// No se pudo guardar el gimnasio: lo de antes sigue guardado.
        case saveFailed
        /// Hay un gimnasio guardado que no se pudo leer: no se borró.
        case unreadable
    }

    public enum RenameOutcome: Equatable, Sendable {
        case saved
        case emptyName
        case notSaved
    }

    public private(set) var gyms: [GymProfile] = []
    public private(set) var notice: Notice?

    public var activeGym: GymProfile? { GymProfile.active(in: gyms) }

    private var repository: FileGymRepository?
    private let defaultName: String
    private let manager = GymProfileManager()
    private let clock: () -> Date
    private let log: PersistenceLog

    public init(defaultName: String, clock: @escaping () -> Date = { Date() }, log: PersistenceLog = .standard) {
        self.defaultName = defaultName
        self.clock = clock
        self.log = log
    }

    /// Carga los gimnasios del usuario y crea el implícito si no hay ninguno. Sin almacén, o
    /// con uno ilegible, sigue con uno en memoria: nunca escribe encima de lo que no leyó.
    public func load(repository: FileGymRepository?) async {
        self.repository = repository
        notice = nil
        guard let repository else {
            gyms = [implicitGym()]
            return
        }
        let result: RepositoryReadResult<GymProfile>
        do {
            result = try await repository.loadAllGyms()
        } catch {
            log.saveFailed(.gyms)
            notice = .unreadable
            gyms = [implicitGym()]
            return
        }
        gyms = result.items
        if result.unreadableCount > 0 { notice = .unreadable }
        guard gyms.isEmpty else { return }
        let gym = implicitGym()
        gyms = [gym]
        if result.unreadableCount == 0 { await save(gym) }
    }

    /// Cerrar sesión: nada de esta cuenta se queda en memoria.
    public func reset() {
        repository = nil
        gyms = []
        notice = nil
    }

    /// Renombra el activo. Con un error de escritura conserva el nombre guardado.
    @discardableResult
    public func renameActive(to name: String) async -> RenameOutcome {
        guard let active = activeGym else { return .notSaved }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let renamed = try? manager.rename(active, to: trimmed) else { return .emptyName }
        guard await save(renamed) else { return .notSaved }
        replace(renamed)
        return .saved
    }

    public func dismissNotice() {
        notice = nil
    }

    private func implicitGym() -> GymProfile {
        GymProfile(name: defaultName, lastSelectedAt: clock())
    }

    private func replace(_ gym: GymProfile) {
        gyms = gyms.map { $0.id == gym.id ? gym : $0 }
    }

    /// `false` si no se pudo guardar: se avisa y se registra.
    @discardableResult
    private func save(_ gym: GymProfile) async -> Bool {
        guard let repository else { return true }
        do {
            try await repository.save(gym)
            return true
        } catch {
            log.saveFailed(.gyms)
            notice = .saveFailed
            return false
        }
    }
}
