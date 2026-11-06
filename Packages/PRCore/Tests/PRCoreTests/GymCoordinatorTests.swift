//
//  GymCoordinatorTests.swift
//  PRCoreTests
//
//  SCRUM-235 (PR-E004): el gimnasio activo se guarda por usuario, con `LocalPersistence` real
//  en un directorio temporal. Sin pasos nuevos, sin tocar el plan y sin guardar la ocupación.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

/// Almacén que lee bien y falla al escribir.
private struct ReadOnlyStore: RepositoryStore {
    struct Failure: Error {}
    let base: any RepositoryStore
    func read(key: String) throws -> Data? { try base.read(key: key) }
    func readAll() throws -> [Data] { try base.readAll() }
    func readAllEntries() throws -> StoreReadResult { try base.readAllEntries() }
    func write(key: String, data: Data) throws { throw Failure() }
    func delete(key: String) throws { throw Failure() }
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-gym-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func persistence(_ root: URL, user: String = "u1") throws -> LocalPersistence {
    try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).scoped(toUser: user)
}

@MainActor
private func coordinator(_ root: URL, user: String = "u1") async throws -> GymCoordinator {
    let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
    await gyms.load(repository: try persistence(root, user: user).gymRepository())
    return gyms
}

@MainActor
@Suite("SCRUM-235 · Mi gimnasio: el gimnasio activo se guarda por usuario")
struct GymCoordinatorTests {

    @Test("Sin gimnasio guardado se crea \"Mi gimnasio\" y al reabrir sigue siendo el mismo")
    func implicitGymIsCreatedOnce() async throws {
        let root = try makeRoot()
        let first = try await coordinator(root)
        let id = try #require(first.activeGym?.id)
        #expect(first.activeGym?.name == "Mi gimnasio")

        let reopened = try await coordinator(root)
        #expect(reopened.activeGym?.id == id)
        #expect(reopened.gyms.count == 1, "No se crea otro al reabrir")
    }

    @Test("Renombrar sobrevive a cerrar y abrir; un nombre vacío se rechaza")
    func rename() async throws {
        let root = try makeRoot()
        let gyms = try await coordinator(root)

        #expect(await gyms.renameActive(to: "   ") == .emptyName)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
        #expect(await gyms.renameActive(to: "  Oficina ") == .saved)
        #expect(gyms.activeGym?.name == "Oficina")

        let reopened = try await coordinator(root)
        #expect(reopened.activeGym?.name == "Oficina")
    }

    @Test("Dos cuentas en el mismo iPhone tienen su propio gimnasio")
    func twoUsers() async throws {
        let root = try makeRoot()
        let first = try await coordinator(root, user: "u1")
        await first.renameActive(to: "Oficina")
        let second = try await coordinator(root, user: "u2")

        #expect(second.activeGym?.name == "Mi gimnasio")
        #expect(second.activeGym?.id != first.activeGym?.id)
        #expect(try await coordinator(root, user: "u1").activeGym?.name == "Oficina")
    }

    @Test("La ocupación nunca se guarda")
    func occupancyIsNeverSaved() async throws {
        let root = try makeRoot()
        let repository = try persistence(root).gymRepository()
        let gym = GymProfile(name: "Oficina").markingOccupied(.machine)

        try await repository.save(gym)

        let saved = try #require(try await repository.gym(id: gym.id))
        #expect(saved.occupiedDuringSession.isEmpty)
        #expect(gym.occupiedDuringSession == [.machine], "La sesión en memoria sigue igual")
    }

    @Test("Un error al escribir avisa, conserva el nombre y no se traga")
    func writeFailureIsReported() async throws {
        let root = try makeRoot()
        _ = try await coordinator(root)
        let store = try persistence(root).store(for: .gyms)
        let silent = PersistenceLog { _ in }
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: silent)
        await gyms.load(repository: FileGymRepository(store: ReadOnlyStore(base: store), log: silent))

        #expect(await gyms.renameActive(to: "Oficina") == .notSaved)
        #expect(gyms.notice == .saveFailed)
        #expect(gyms.activeGym?.name == "Mi gimnasio", "No dice que guardó lo que no guardó")
    }

    @Test("Un archivo ilegible no se borra: avisa y sigue con uno en memoria")
    func unreadableFileIsKept() async throws {
        let root = try makeRoot()
        let store = try persistence(root).store(for: .gyms)
        let garbage = Data("no es json".utf8)
        try store.write(key: "dañado", data: garbage)

        let gyms = try await coordinator(root)

        #expect(gyms.notice == .unreadable)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
        #expect(try store.read(key: "dañado") == garbage, "El archivo sigue intacto")
        #expect(try store.readAllEntries().entries.filter { $0.key != "dañado" }.isEmpty, "No se escribió otro encima")
    }

    @Test("Sin almacén funciona en memoria")
    func withoutStore() async throws {
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: PersistenceLog { _ in })
        await gyms.load(repository: nil)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
        #expect(gyms.notice == nil)
    }

    @Test("Cerrar sesión no deja el gimnasio de la cuenta en memoria")
    func resetClears() async throws {
        let gyms = try await coordinator(try makeRoot())
        gyms.reset()
        #expect(gyms.activeGym == nil)
    }

    @Test("El activo es el elegido más recientemente, también con varios")
    func activeIsTheLatestSelected() {
        let old = GymProfile(name: "Antes", lastSelectedAt: now)
        let new = GymProfile(name: "Ahora", lastSelectedAt: now.addingTimeInterval(60))
        let never = GymProfile(name: "Nunca")
        #expect(GymProfile.active(in: [old, new, never])?.id == new.id)
        #expect(GymProfile.active(in: [never, new, old])?.id == new.id)
        #expect(GymProfile.active(in: []) == nil)
    }

    @Test("SCRUM-238: agregar rechaza nombres vacíos o repetidos, sin importar mayúsculas")
    func addGym() async throws {
        let gyms = try await coordinator(try makeRoot())

        #expect(await gyms.addGym(named: "  ") == .emptyName)
        #expect(await gyms.addGym(named: "mi GIMNASIO") == .repeatedName)
        #expect(await gyms.addGym(named: " Oficina ") == .saved)
        #expect(await gyms.addGym(named: "oficina") == .repeatedName)
        #expect(gyms.gyms.map(\.name).sorted() == ["Mi gimnasio", "Oficina"])
        #expect(gyms.activeGym?.name == "Mi gimnasio", "Agregar no lo vuelve activo")
    }

    @Test("SCRUM-238: el activo sobrevive a cerrar y abrir, y es por usuario")
    func selectSurvivesReopening() async throws {
        let root = try makeRoot()
        let gyms = try await coordinator(root)
        await gyms.addGym(named: "Oficina")
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })

        #expect(await gyms.select(office.id, duringWorkout: false))
        #expect(gyms.activeGym?.id == office.id, "Aunque el reloj no haya avanzado")

        let reopened = try await coordinator(root)
        #expect(reopened.activeGym?.id == office.id)
        #expect(try await coordinator(root, user: "u2").activeGym?.name == "Mi gimnasio")
    }

    @Test("SCRUM-238: volver al primero también queda guardado")
    func selectBack() async throws {
        let root = try makeRoot()
        let gyms = try await coordinator(root)
        let first = try #require(gyms.activeGym)
        await gyms.addGym(named: "Oficina")
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })
        await gyms.select(office.id, duringWorkout: false)
        await gyms.select(first.id, duringWorkout: false)

        #expect(try await coordinator(root).activeGym?.id == first.id)
    }

    @Test("SCRUM-238: cada gimnasio arma el día con lo suyo")
    func eachGymHasItsMarks() async throws {
        let gyms = try await coordinator(try makeRoot())
        let exercise = ExerciseID()
        await gyms.markMissing(exercise, replacement: nil)
        await gyms.addGym(named: "Oficina")
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })

        await gyms.select(office.id, duringWorkout: false)

        #expect(gyms.activeGym?.missingExercises == nil, "Lo que no hay en Mi gimnasio no pasa a Oficina")
    }

    @Test("SCRUM-238: renombrar tampoco deja dos gimnasios iguales, pero sí cambia sus mayúsculas")
    func renameCannotRepeat() async throws {
        let gyms = try await coordinator(try makeRoot())
        await gyms.addGym(named: "Oficina")

        #expect(await gyms.renameActive(to: "OFICINA") == .repeatedName)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
        #expect(await gyms.renameActive(to: "MI GIMNASIO") == .saved)
        #expect(gyms.activeGym?.name == "MI GIMNASIO")
    }

    @Test("SCRUM-238: con un entrenamiento en curso no se cambia de gimnasio")
    func selectIsBlockedDuringWorkout() async throws {
        let root = try makeRoot()
        let gyms = try await coordinator(root)
        await gyms.addGym(named: "Oficina")
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })

        #expect(await gyms.select(office.id, duringWorkout: true) == false)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
        #expect(try await coordinator(root).activeGym?.name == "Mi gimnasio", "Tampoco se guardó")
    }

    @Test("SCRUM-238: un error al elegir avisa y deja el activo de antes")
    func selectWriteFailure() async throws {
        let root = try makeRoot()
        let saved = try await coordinator(root)
        await saved.addGym(named: "Oficina")
        let office = try #require(saved.gyms.first { $0.name == "Oficina" })
        let silent = PersistenceLog { _ in }
        let gyms = GymCoordinator(defaultName: "Mi gimnasio", clock: { now }, log: silent)
        let store = try persistence(root).store(for: .gyms)
        await gyms.load(repository: FileGymRepository(store: ReadOnlyStore(base: store), log: silent))

        #expect(await gyms.select(office.id, duringWorkout: false) == false)
        #expect(gyms.notice == .saveFailed)
        #expect(gyms.activeGym?.name == "Mi gimnasio")
    }

    @Test("SCRUM-238: elegir gimnasio no toca el plan ni el historial")
    func selectLeavesPlanAndHistory() async throws {
        let root = try makeRoot()
        let scoped = try persistence(root)
        let workouts = try scoped.workoutRepository()
        let session = WorkoutSessionRecord(templateID: UUID(), startedAt: now)
        try workouts.persist(session)
        let plans = try scoped.store(for: .plans).readAll()

        let gyms = try await coordinator(root)
        await gyms.addGym(named: "Oficina")
        let office = try #require(gyms.gyms.first { $0.name == "Oficina" })
        await gyms.select(office.id, duringWorkout: false)

        #expect(try await workouts.allSessions().map(\.id) == [session.id])
        #expect(try scoped.store(for: .plans).readAll() == plans)
    }

    @Test("El export incluye los gimnasios del usuario")
    func exportIncludesGyms() async throws {
        let gyms = try await coordinator(try makeRoot())
        await gyms.renameActive(to: "Oficina")

        let file = try DataExportCoordinator().exportJSON(
            sessions: [], exercises: [], blocks: [], gyms: gyms.gyms, restrictions: [], profile: nil, exportedAt: now
        )

        #expect(String(decoding: file.data, as: UTF8.self).contains("Oficina"))
    }

    @Test("Los datos guardados antes siguen igual y el gimnasio no toca el plan")
    func gymLivesApartFromPlanAndHistory() async throws {
        let root = try makeRoot()
        let base = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let workouts = try persistence(root).workoutRepository()
        let session = WorkoutSessionRecord(templateID: UUID(), startedAt: now)
        try workouts.persist(session)

        let gyms = try await coordinator(root)
        await gyms.renameActive(to: "Oficina")

        #expect(try await workouts.allSessions().map(\.id) == [session.id])
        #expect(try base.store(for: .plans).readAll().isEmpty, "El gimnasio no se escribe en el plan")
        #expect(try base.store(for: .gyms).readAll().isEmpty, "Vive por usuario, no en la raíz")
    }
}
