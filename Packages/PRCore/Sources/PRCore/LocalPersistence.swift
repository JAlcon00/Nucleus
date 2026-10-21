//
//  LocalPersistence.swift
//  PRCore
//
//  Created by PR.
//
//  Composición de la persistencia local (SCRUM-23). Cada colección vive en su propio
//  subdirectorio bajo una raíz (`…/PR/persistence/<colección>/`), de modo que leer una
//  colección sólo lee sus archivos. Antes todo compartía un directorio: la cola de
//  pendientes se leía como si fuera un workout, el decode fallaba y Export mostraba
//  0 sesiones en silencio.
//
//  `AppEnvironment` (app) la construye sobre Application Support; los tests, sobre un
//  directorio temporal, con la misma infraestructura real.
//

import Foundation
import PRDomain

/// Colecciones persistidas. El `rawValue` es el nombre del subdirectorio: no cambiarlo
/// sin migración (los datos del usuario viven ahí).
public enum PersistenceCollection: String, CaseIterable, Sendable, Hashable {
    case workouts
    case pendingOperations = "pending-operations"
    case profile
    case blocks
    case exercises
    case gyms
    case restrictions
    case decisions
    case agentAudit = "agent-audit"
    /// Plan por usuario (perfil + bloque activo + historial de bloques). SCRUM-26.
    case plans
    /// Sesión recordada: sólo el identificador opaco del usuario. SCRUM-26.
    case session
}

/// Registro de eventos de persistencia SIN datos personales: sólo colección y
/// conteos, nunca claves, rutas ni contenido de archivos. El `sink` se inyecta para
/// poder verificarlo en tests.
public struct PersistenceLog: Sendable {
    private let sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    /// Producción: `os.Logger` (categoría persistence) con privacidad por defecto.
    public static let standard = PersistenceLog { message in
        PRLogger(category: .persistence).error(message)
    }

    func unreadableRecords(_ collection: PersistenceCollection, count: Int) {
        sink("persistence.read unreadable collection=\(collection.rawValue) count=\(count)")
    }

    func migration(_ report: LegacyPersistenceMigration.Report) {
        sink(
            "persistence.migration moved=\(report.moved) alreadyMigrated=\(report.alreadyMigrated) "
                + "unclassified=\(report.unclassified) conflicts=\(report.conflicts)"
        )
    }

    public func migrationFailed() {
        sink("persistence.migration failed")
    }

    public func saveFailed(_ collection: PersistenceCollection) {
        sink("persistence.write failed collection=\(collection.rawValue)")
    }
}

/// Persistencia local de la app: una raíz con un subdirectorio por colección.
public struct LocalPersistence: Sendable {
    public let rootURL: URL
    public let log: PersistenceLog

    /// Crea la raíz si no existe. No migra: llamar a `migrateLegacyLayout()`.
    public init(rootURL: URL, log: PersistenceLog = .standard) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.rootURL = rootURL
        self.log = log
    }

    /// Almacén de UNA colección (su subdirectorio).
    public func store(for collection: PersistenceCollection) throws -> AtomicFileRepositoryStore {
        try AtomicFileRepositoryStore(directory: rootURL.appendingPathComponent(collection.rawValue, isDirectory: true))
    }

    public func workoutRepository() throws -> FileWorkoutRepository {
        FileWorkoutRepository(store: try store(for: .workouts), log: log)
    }

    public func pendingOperationQueue() throws -> PendingOperationQueueStore {
        PendingOperationQueueStore(store: try store(for: .pendingOperations))
    }

    /// Coordinador de WORKOUT MODE cableado a esta persistencia: cola de pendientes,
    /// baselines de PR desde el historial y guardado de la sesión al terminar.
    /// `onPersisted` informa el resultado de cada guardado (éxito o fallo, que además
    /// se registra): nunca se descarta en silencio un error de escritura.
    @MainActor
    public func makeWorkoutCoordinator(
        template: SessionTemplate,
        exerciseNames: [ExerciseID: String] = [:],
        celebrationPresenter: PRCelebrationPresenter = PRCelebrationPresenter(),
        clock: @escaping () -> Date = { Date() },
        onPersisted: @escaping @Sendable (Result<WorkoutID, any Error>) async -> Void = { _ in }
    ) async throws -> WorkoutSessionCoordinator {
        let workouts = try workoutRepository()
        let queue = try pendingOperationQueue()
        let history: [WorkoutSessionRecord]
        do {
            history = try await workouts.loadAllSessions().items
        } catch {
            // Sin historial legible el workout arranca igual; sólo no hay baselines de PR.
            history = []
        }
        let log = self.log
        return WorkoutSessionCoordinator(
            template: template,
            exerciseNames: exerciseNames,
            recordBaselines: PersonalRecordBaselineBuilder.baselines(from: history),
            celebrationPresenter: celebrationPresenter,
            clock: clock,
            pendingQueue: queue,
            onSessionFinished: { session in
                do {
                    try await workouts.save(session)
                    await onPersisted(.success(session.id))
                } catch {
                    log.saveFailed(.workouts)
                    await onPersisted(.failure(error))
                }
            }
        )
    }

    /// Mueve los archivos del layout antiguo (todo en la raíz) a su colección. Segura de
    /// repetir: la segunda vez no hace nada. Registra el resultado sin datos personales.
    @discardableResult
    public func migrateLegacyLayout() throws -> LegacyPersistenceMigration.Report {
        let report = try LegacyPersistenceMigration().run(root: rootURL) { collection in
            try store(for: collection)
        }
        if report.didWork {
            log.migration(report)
        }
        return report
    }
}
