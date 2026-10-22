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

    /// Se encontró más de una sesión activa (error): se retomó la más reciente y las demás
    /// pasaron a `abandoned` con sus series intactas. Sólo el conteo, sin contenido.
    public func recoveredExtraActiveSessions(count: Int) {
        sink("persistence.recovery extraActiveSessions=\(count)")
    }

    public func saveFailed(_ collection: PersistenceCollection) {
        sink("persistence.write failed collection=\(collection.rawValue)")
    }
}

/// Persistencia local de la app: una raíz con un subdirectorio por colección.
public struct LocalPersistence: Sendable {
    public let rootURL: URL
    public let log: PersistenceLog
    /// Clave derivada del usuario (SCRUM-26). Con ella, el historial de entrenamientos y la
    /// cola de pendientes viven en `users/<clave>/<colección>/`: dos cuentas en el mismo
    /// dispositivo no comparten su historial. `nil` = raíz sin usuario.
    private let userKey: String?

    /// Crea la raíz si no existe. No migra: llamar a `migrateLegacyLayout()`.
    public init(rootURL: URL, log: PersistenceLog = .standard) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.rootURL = rootURL
        self.log = log
        self.userKey = nil
    }

    private init(rootURL: URL, log: PersistenceLog, userKey: String?) {
        self.rootURL = rootURL
        self.log = log
        self.userKey = userKey
    }

    /// Colecciones que pertenecen a un usuario (su historial de entrenamientos).
    private static let userScopedCollections: [PersistenceCollection] = [.workouts, .pendingOperations]

    /// Vista de esta persistencia para UN usuario. La primera vez que cualquier usuario
    /// entra, adopta el historial anterior a las cuentas (que estaba sin dueño): se mueve
    /// verificado y una sola vez; los demás usuarios empiezan con historial vacío.
    public func scoped(toUser userID: String) throws -> LocalPersistence {
        let scoped = LocalPersistence(rootURL: rootURL, log: log, userKey: PlanStore.key(forUser: userID))
        try scoped.adoptUnownedHistoryIfNeeded()
        return scoped
    }

    private var adoptionMarker: URL {
        rootURL.appendingPathComponent("users", isDirectory: true).appendingPathComponent(".unowned-history-adopted")
    }

    /// Mueve `workouts/` y `pending-operations/` sin dueño al usuario actual. Idempotente:
    /// copia, verifica que se lee idéntico y recién entonces borra el origen; el marcador
    /// se escribe al final, así un fallo a medias se reintenta sin perder ni duplicar nada.
    private func adoptUnownedHistoryIfNeeded() throws {
        guard userKey != nil, !FileManager.default.fileExists(atPath: adoptionMarker.path) else { return }
        for collection in Self.userScopedCollections {
            let source = try AtomicFileRepositoryStore(directory: rootURL.appendingPathComponent(collection.rawValue, isDirectory: true))
            let destination = try store(for: collection)
            for entry in try source.readAllEntries().entries {
                if let existing = try destination.read(key: entry.key), existing != entry.data { continue }
                try destination.write(key: entry.key, data: entry.data)
                guard try destination.read(key: entry.key) == entry.data else { continue }
                try source.delete(key: entry.key)
            }
        }
        try FileManager.default.createDirectory(at: adoptionMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: adoptionMarker)
    }

    /// Almacén de UNA colección (su subdirectorio).
    public func store(for collection: PersistenceCollection) throws -> AtomicFileRepositoryStore {
        var base = rootURL
        if let userKey, Self.userScopedCollections.contains(collection) {
            base = rootURL.appendingPathComponent("users", isDirectory: true).appendingPathComponent(userKey, isDirectory: true)
        }
        return try AtomicFileRepositoryStore(directory: base.appendingPathComponent(collection.rawValue, isDirectory: true))
    }

    public func workoutRepository() throws -> FileWorkoutRepository {
        FileWorkoutRepository(store: try store(for: .workouts), log: log)
    }

    public func pendingOperationQueue() throws -> PendingOperationQueueStore {
        PendingOperationQueueStore(store: try store(for: .pendingOperations))
    }

    /// Coordinador de WORKOUT MODE cableado a esta persistencia: cola de pendientes,
    /// baselines de PR desde el historial y guardado DURABLE de la sesión al iniciar, en cada
    /// serie y al terminar (SCRUM-24). `restoring` retoma una sesión guardada.
    /// `onPersisted` informa el resultado del guardado final (éxito o fallo, que además se
    /// registra): nunca se descarta en silencio un error de escritura.
    @MainActor
    public func makeWorkoutCoordinator(
        template: SessionTemplate,
        exerciseNames: [ExerciseID: String] = [:],
        dropsetAdvice: [ExerciseID: DropsetAdvice] = [:],
        celebrationPresenter: PRCelebrationPresenter = PRCelebrationPresenter(),
        clock: @escaping () -> Date = { Date() },
        restoring: WorkoutSessionRecord? = nil,
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
        let outcome = PersistOutcome()
        return WorkoutSessionCoordinator(
            template: template,
            exerciseNames: exerciseNames,
            dropsetAdvice: dropsetAdvice,
            recordBaselines: PersonalRecordBaselineBuilder.baselines(from: history),
            celebrationPresenter: celebrationPresenter,
            clock: clock,
            pendingQueue: queue,
            onSessionFinished: { session in
                if let error = outcome.lastError {
                    log.saveFailed(.workouts)
                    await onPersisted(.failure(error))
                } else {
                    await onPersisted(.success(session.id))
                }
            },
            persistSession: { session in
                do {
                    try workouts.persist(session)
                    outcome.record(nil)
                } catch {
                    log.saveFailed(.workouts)
                    outcome.record(error)
                    throw error
                }
            },
            restoring: restoring
        )
    }

    /// Qué encontró la app al abrir respecto de un entrenamiento sin cerrar.
    public enum WorkoutRecoveryOutcome {
        case none
        /// Hay una sesión en curso, lista para continuar ("Tienes un entrenamiento en curso").
        case restored(WorkoutSessionCoordinator)
    }

    /// Recupera el entrenamiento que quedó abierto (SCRUM-24): primero drena la cola de
    /// pendientes (idempotente), luego revisa las sesiones guardadas con
    /// `WorkoutRecoveryPlanner`. Si hay varias activas, retoma la más reciente y abandona las
    /// demás sin tocar sus series. Si la plantilla de la sesión ya no existe, la abandona
    /// conservando sus series (no se puede continuar sin saber qué toca después).
    @MainActor
    public func recoverWorkout(
        templates: [SessionTemplate],
        exerciseNames: [ExerciseID: String] = [:],
        dropsetAdvice: [ExerciseID: DropsetAdvice] = [:],
        celebrationPresenter: PRCelebrationPresenter = PRCelebrationPresenter(),
        clock: @escaping () -> Date = { Date() },
        onPersisted: @escaping @Sendable (Result<WorkoutID, any Error>) async -> Void = { _ in }
    ) async throws -> WorkoutRecoveryOutcome {
        let workouts = try workoutRepository()
        let queue = try pendingOperationQueue()
        _ = await SetPersistenceGuard().drain(queue: queue, workoutRepository: workouts)

        let sessions = try await workouts.loadAllSessions().items
        let plan = WorkoutRecoveryPlanner().plan(for: sessions, now: clock())
        for updated in plan.updates {
            try workouts.persist(updated)
        }
        if plan.extraActiveCount > 0 {
            log.recoveredExtraActiveSessions(count: plan.extraActiveCount)
        }
        guard let record = plan.restore else { return .none }
        guard let template = templates.first(where: { $0.id == record.templateID }) else {
            var abandoned = record
            abandoned.lifecycle = .abandoned
            abandoned.endedAt = abandoned.endedAt ?? clock()
            abandoned.rest = nil
            try workouts.persist(abandoned)
            return .none
        }
        let coordinator = try await makeWorkoutCoordinator(
            template: template,
            exerciseNames: exerciseNames,
            dropsetAdvice: dropsetAdvice,
            celebrationPresenter: celebrationPresenter,
            clock: clock,
            restoring: record,
            onPersisted: onPersisted
        )
        // Si ya estaban todas las series (cierre forzado tras la última), el coordinador la
        // cerró al restaurar y quedó guardada como completada: no hay nada que retomar.
        if case .finished = coordinator.phase { return .none }
        return .restored(coordinator)
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


/// Último resultado de escritura de una sesión, compartido entre el guardado y el aviso final.
private final class PersistOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?

    var lastError: (any Error)? { lock.withLock { error } }

    func record(_ newError: (any Error)?) {
        lock.withLock { error = newError }
    }
}
