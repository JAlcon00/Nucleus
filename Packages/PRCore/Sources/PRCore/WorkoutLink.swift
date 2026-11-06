//
//  WorkoutLink.swift
//  PRCore
//
//  SCRUM-255 (PR-G004): el puente iPhone ⇄ reloj. PRCore no importa WatchConnectivity: aquí
//  vive el contrato y lo que hace el iPhone con cada mensaje; los adaptadores están en la app
//  y en el reloj (DG-1). El iPhone guarda la sesión final; cada serie del reloj se escribe en
//  la cola ANTES de aplicarse, y un estado nuevo confirma al reloj lo que ya está guardado.
//

import Foundation
import PRDomain

/// Lo que el reloj le manda al iPhone. Viaja por una cola que se entrega aunque el otro esté
/// apagado: nada de esto puede perderse.
public enum WatchMessage: Codable, Sendable, Hashable {
    case event(SetEvent)
}

/// El lado del iPhone.
public protocol PhoneWorkoutLink: Sendable {
    /// Publica el estado más reciente (el anterior ya no importa).
    func publish(_ snapshot: WatchSessionSnapshot) async
    /// Los mensajes del reloj, en orden de llegada.
    var messages: AsyncStream<WatchMessage> { get }
}

/// El lado del reloj.
public protocol WatchWorkoutLink: Sendable {
    /// Encola un mensaje para el iPhone. Se entrega al reconectar.
    func send(_ message: WatchMessage) async
    /// Los estados que publica el iPhone.
    var snapshots: AsyncStream<WatchSessionSnapshot> { get }
}

/// Qué hizo el iPhone con un mensaje del reloj.
public enum WatchMessageOutcome: Equatable, Sendable {
    /// Se aplicó a la sesión en pantalla.
    case appliedLive
    /// Se aplicó a la sesión guardada.
    case appliedStored
    /// Ya estaba, o queda en la cola para más tarde (por ejemplo, otra cuenta activa).
    case noChange
}

/// Dónde se guarda lo que manda el reloj: el almacén de la cuenta activa.
public struct WatchBridgeStorage: Sendable {
    public let queue: PendingOperationQueueStore
    public let workouts: any WorkoutRepository

    public init(queue: PendingOperationQueueStore, workouts: any WorkoutRepository) {
        self.queue = queue
        self.workouts = workouts
    }
}

/// Problemas del puente.
public enum WatchBridgeError: Error, Equatable, Sendable {
    /// Todavía no hay cuenta ni almacén. El reloj conserva la serie y la vuelve a mandar.
    case storageUnavailable
}

/// Recibe lo que manda el reloj y le publica el estado de la sesión.
@MainActor
public final class PhoneWatchBridge {
    private let link: any PhoneWorkoutLink
    private let storage: @MainActor () throws -> WatchBridgeStorage?
    private let setGuard = SetPersistenceGuard()
    private let logger = PRLogger(category: .sync)
    private let clock: () -> Date
    private var coordinator: WorkoutSessionCoordinator?
    private var listening: Task<Void, Never>?
    private var lastPublished: WatchSessionSnapshot?

    public init(
        link: any PhoneWorkoutLink,
        clock: @escaping () -> Date = { Date() },
        storage: @escaping @MainActor () throws -> WatchBridgeStorage?
    ) {
        self.link = link
        self.clock = clock
        self.storage = storage
    }

    /// Empieza a escuchar al reloj. Llamarlo otra vez no abre otra escucha.
    public func start() {
        guard listening == nil else { return }
        let messages = link.messages
        listening = Task { [weak self] in
            for await message in messages {
                do {
                    _ = try await self?.handle(message)
                } catch {
                    // No se pierde: el reloj la conserva hasta que un estado la confirme.
                    self?.logger.diagnostic("watch.message.notStored", level: .error)
                }
            }
        }
    }

    /// Conecta la sesión en pantalla: desde aquí, cada cambio se publica al reloj.
    public func attach(_ coordinator: WorkoutSessionCoordinator) {
        self.coordinator = coordinator
        coordinator.onWatchStateChange = { [weak self] snapshot in self?.publish(snapshot) }
        if let snapshot = coordinator.watchSnapshot() { publish(snapshot) }
    }

    /// Guarda primero y aplica después. Si la escritura falla no se confirma nada: el reloj
    /// conserva la serie y la vuelve a mandar.
    @discardableResult
    public func handle(_ message: WatchMessage) async throws -> WatchMessageOutcome {
        switch message {
        case .event(let event):
            return try await handle(event)
        }
    }

    private func handle(_ event: SetEvent) async throws -> WatchMessageOutcome {
        guard case .recorded(let set) = event.action, let slot = event.slot, let session = event.sessionID else {
            return .noChange
        }
        guard let storage = try storage() else { throw WatchBridgeError.storageUnavailable }
        _ = try setGuard.enqueueRemoteSet(set, slot: slot, device: event.device, in: session, queue: storage.queue, now: clock())
        if let coordinator, coordinator.isLive(session: session) {
            coordinator.applyRemoteSet(set, slot: slot, device: event.device)
            if let snapshot = coordinator.watchSnapshot() { publish(snapshot) }
            return .appliedLive
        }
        let result = await setGuard.drain(queue: storage.queue, workoutRepository: storage.workouts)
        await confirmStored(session, in: storage.workouts)
        return result.applied > 0 ? .appliedStored : .noChange
    }

    /// Sin pantalla abierta, el reloj igual tiene que saber que ya puede soltar una sesión
    /// terminada. Una activa se publica al abrir la app, con sus nombres y su precarga.
    private func confirmStored(_ id: WorkoutID, in workouts: any WorkoutRepository) async {
        guard let session = try? await workouts.session(id: id), let template = session.template else { return }
        switch session.lifecycle {
        case .completed, .abandoned:
            publish(WatchSessionSnapshotBuilder.snapshot(WatchSessionSnapshotInput(
                session: session,
                template: template,
                revision: Int(clock().timeIntervalSince1970 * 1_000),
                exerciseName: { _ in "" },
                draft: { SetCompleter().preload(for: $0) }
            )))
        case .planned, .preparing, .active, .paused, .finishing:
            break
        }
    }

    private func publish(_ snapshot: WatchSessionSnapshot) {
        if let lastPublished, lastPublished.hasSameContent(as: snapshot) { return }
        lastPublished = snapshot
        let link = self.link
        Task { await link.publish(snapshot) }
    }
}

/// Fake de los dos lados del puente, para pruebas. Puede retrasar y duplicar.
public final class FakeWorkoutLink: PhoneWorkoutLink, WatchWorkoutLink, @unchecked Sendable {
    private let lock = NSLock()
    private var published: [WatchSessionSnapshot] = []
    private var sent: [WatchMessage] = []
    private let messageStream: AsyncStream<WatchMessage>
    private let messageContinuation: AsyncStream<WatchMessage>.Continuation
    private let snapshotStream: AsyncStream<WatchSessionSnapshot>
    private let snapshotContinuation: AsyncStream<WatchSessionSnapshot>.Continuation

    public init() {
        (messageStream, messageContinuation) = AsyncStream.makeStream(of: WatchMessage.self)
        (snapshotStream, snapshotContinuation) = AsyncStream.makeStream(of: WatchSessionSnapshot.self)
    }

    public var messages: AsyncStream<WatchMessage> { messageStream }
    public var snapshots: AsyncStream<WatchSessionSnapshot> { snapshotStream }

    public func publish(_ snapshot: WatchSessionSnapshot) async {
        lock.withLock { published.append(snapshot) }
        snapshotContinuation.yield(snapshot)
    }

    public func send(_ message: WatchMessage) async {
        lock.withLock { sent.append(message) }
        messageContinuation.yield(message)
    }

    public var publishedSnapshots: [WatchSessionSnapshot] { lock.withLock { published } }
    public var sentMessages: [WatchMessage] { lock.withLock { sent } }
}
