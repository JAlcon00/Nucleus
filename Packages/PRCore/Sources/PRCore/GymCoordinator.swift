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
        /// Ya hay un gimnasio con ese nombre, sin importar mayúsculas (SCRUM-238).
        case repeatedName
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
        guard !isTaken(trimmed, except: active.id) else { return .repeatedName }
        guard await save(renamed) else { return .notSaved }
        replace(renamed)
        return .saved
    }

    /// SCRUM-238: agrega un gimnasio. No lo vuelve activo: eso se elige aparte.
    @discardableResult
    public func addGym(named name: String) async -> RenameOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gym = try? manager.create(name: trimmed) else { return .emptyName }
        guard !isTaken(trimmed, except: nil) else { return .repeatedName }
        guard await save(gym) else { return .notSaved }
        gyms.append(gym)
        return .saved
    }

    /// SCRUM-238: elige el gimnasio activo. No toca el plan guardado, el historial ni la racha.
    /// Con un entrenamiento en curso no cambia: esa sesión sigue en el gimnasio donde empezó.
    @discardableResult
    public func select(_ id: GymID, duringWorkout: Bool) async -> Bool {
        guard !duringWorkout else { return false }
        guard var gym = gyms.first(where: { $0.id == id }) else { return false }
        guard gym.id != activeGym?.id else { return true }
        // Siempre después del activo actual, aunque el reloj no haya avanzado.
        let latest = activeGym?.lastSelectedAt ?? .distantPast
        gym.lastSelectedAt = max(clock(), latest.addingTimeInterval(1))
        guard await save(gym) else { return false }
        replace(gym)
        return true
    }

    /// SCRUM-236: "en este gimnasio no hay `exercise`; se hace `replacement`". Sólo afecta al
    /// activo. `false` si no se pudo guardar: el gimnasio no queda marcado y se avisa.
    @discardableResult
    public func markMissing(_ exercise: ExerciseID, replacement: ExerciseID?) async -> Bool {
        guard var active = activeGym else { return false }
        var marks = (active.missingExercises ?? []).filter { $0.exercise != exercise }
        marks.append(MissingExercise(exercise: exercise, replacement: replacement))
        active.missingExercises = marks
        guard await save(active) else { return false }
        replace(active)
        return true
    }

    /// Quita la marca: la siguiente sesión vuelve a tener el ejercicio.
    @discardableResult
    public func removeMissing(_ exercise: ExerciseID) async -> Bool {
        guard var active = activeGym else { return false }
        let marks = (active.missingExercises ?? []).filter { $0.exercise != exercise }
        active.missingExercises = marks.isEmpty ? nil : marks
        guard await save(active) else { return false }
        replace(active)
        return true
    }

    public func dismissNotice() {
        notice = nil
    }

    private func implicitGym() -> GymProfile {
        GymProfile(name: defaultName, lastSelectedAt: clock())
    }

    /// ¿Otro gimnasio ya se llama así? Sin importar mayúsculas (SCRUM-238).
    private func isTaken(_ name: String, except id: GymID?) -> Bool {
        gyms.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
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
