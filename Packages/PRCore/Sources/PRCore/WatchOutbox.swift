//
//  WatchOutbox.swift
//  PRCore
//
//  SCRUM-256 (PR-G005): el reloj guarda primero en el reloj (RNF-001). Cada serie se escribe en
//  disco antes del háptico de confirmación y se queda en el buzón hasta que el iPhone la
//  confirme. Sin iPhone, la sesión se termina con lo que ya se recibió.
//
//  `WatchSessionController` es todo lo que hace el reloj: la pantalla sólo muestra y manda
//  intenciones. Vive aquí, y no en el target del reloj, para poder probarlo.
//

import Foundation
import Observation
import PRDomain

/// Todo lo que el reloj guarda de la sesión en curso.
public struct WatchLocalState: Codable, Sendable, Equatable {
    /// Lo último que publicó el iPhone.
    public var snapshot: WatchSessionSnapshot?
    /// Series hechas en este reloj en la sesión: dicen qué sigue sin conexión.
    public var done: [WatchDoneSet]
    /// Mensajes que el iPhone todavía no confirma. Sólo un estado nuevo los quita.
    public var outbox: [WatchMessage]
    /// Fin del descanso en curso.
    public var restEndsAt: Date?
    /// Hora de la última serie: un doble toque no registra dos.
    public var lastCompletedAt: Date?

    public init(
        snapshot: WatchSessionSnapshot? = nil,
        done: [WatchDoneSet] = [],
        outbox: [WatchMessage] = [],
        restEndsAt: Date? = nil,
        lastCompletedAt: Date? = nil
    ) {
        self.snapshot = snapshot
        self.done = done
        self.outbox = outbox
        self.restEndsAt = restEndsAt
        self.lastCompletedAt = lastCompletedAt
    }

    public static let empty = WatchLocalState()

    /// Lo que falta confirmar.
    public var pendingCount: Int { outbox.count }

    /// La serie que toca.
    public var currentSet: WatchPlannedSet? {
        snapshot.flatMap { WatchSessionCursor.current(in: $0, done: done) }
    }
}

/// Guarda el estado del reloj: un archivo atómico con la sesión en curso.
public struct WatchLocalStore: Sendable {
    static let key = "session"
    private let store: any RepositoryStore

    public init(store: any RepositoryStore) {
        self.store = store
    }

    public func load() throws -> WatchLocalState {
        guard let data = try store.read(key: Self.key) else { return .empty }
        return try JSONDecoder().decode(WatchLocalState.self, from: data)
    }

    public func save(_ state: WatchLocalState) throws {
        try store.write(key: Self.key, data: JSONEncoder().encode(state))
    }

    public func clear() throws {
        try store.delete(key: Self.key)
    }
}

/// Cómo cambia el estado del reloj. Sin efectos: decide, no guarda ni manda.
public enum WatchOutbox {

    /// El estado con la serie hecha y el mensaje para el iPhone.
    public static func completing(
        _ set: WatchPlannedSet,
        weight: Double,
        reps: Int,
        at now: Date,
        id: SetRecordID,
        in state: WatchLocalState
    ) throws -> (state: WatchLocalState, message: WatchMessage) {
        guard let snapshot = state.snapshot else { throw WatchSessionError.noSession }
        let record = try SetRecord(
            id: id, exerciseID: set.slot.exerciseID, performedAt: now,
            weight: weight, unit: set.unit, reps: reps, lifecycle: .completed
        )
        let message = WatchMessage.event(SetEvent(
            id: id, device: WorkoutDevice.watch, emittedAt: now, slot: set.slot,
            action: .recorded(record), sessionID: snapshot.sessionID
        ))
        var next = state
        next.done.append(WatchDoneSet(slot: set.slot, weight: weight, unit: set.unit))
        next.outbox.append(message)
        next.restEndsAt = set.restSecondsAfter.map { now.addingTimeInterval(TimeInterval($0)) }
        next.lastCompletedAt = now
        return (next, message)
    }

    /// El estado tras recibir uno del iPhone. Uno viejo no reemplaza a uno nuevo. Lo confirmado
    /// sale del buzón, y las series locales siguen mandando sobre qué toca.
    public static func receiving(_ snapshot: WatchSessionSnapshot, in state: WatchLocalState) -> WatchLocalState {
        var next = state
        next.outbox = pruned(state.outbox, confirmedBy: snapshot)
        guard let current = state.snapshot, current.sessionID == snapshot.sessionID else {
            // Una sesión terminada de antes sólo confirma lo suyo: no reemplaza a la de hoy.
            if state.snapshot != nil, snapshot.stage == .finished { return next }
            next.snapshot = snapshot
            next.done = []
            next.restEndsAt = snapshot.restEndsAt
            next.lastCompletedAt = nil
            return next
        }
        guard snapshot.revision >= current.revision else { return next }
        next.snapshot = snapshot
        if next.outbox.isEmpty { next.restEndsAt = snapshot.restEndsAt }
        return next
    }

    /// ¿Ya se puede olvidar la sesión? Terminada y sin nada por confirmar.
    public static func isFinishedAndConfirmed(_ state: WatchLocalState) -> Bool {
        state.snapshot?.stage == .finished && state.outbox.isEmpty
    }

    private static func pruned(_ outbox: [WatchMessage], confirmedBy snapshot: WatchSessionSnapshot) -> [WatchMessage] {
        let confirmed = Set(snapshot.confirmedSetIDs)
        return outbox.filter { message in
            switch message {
            case .event(let event):
                guard case .recorded(let record) = event.action else { return true }
                return !confirmed.contains(record.id)
            }
        }
    }
}

/// Problemas del reloj.
public enum WatchSessionError: Error, Equatable, Sendable {
    case noSession
}

/// Lo que la pantalla del reloj muestra de una serie.
public struct WatchSetScreen: Equatable, Sendable {
    public let set: WatchPlannedSet
    /// Series que faltan, contando ésta.
    public let remaining: Int

    public init(set: WatchPlannedSet, remaining: Int) {
        self.set = set
        self.remaining = remaining
    }
}

/// Estado de la pantalla del reloj. Cada caso tiene su diseño.
public enum WatchScreen: Equatable, Sendable {
    /// Sin sesión: se empieza en el iPhone (DG-4).
    case idle
    case active(WatchSetScreen)
    case resting(WatchSetScreen, endsAt: Date)
    case paused(WatchSetScreen)
    /// No queda nada por hacer: falta cerrar la sesión.
    case allDone
    case finished
    /// No se pudo leer lo guardado.
    case failed
}

/// Todo lo que hace el reloj. La pantalla muestra `screen` y manda intenciones.
@MainActor
@Observable
public final class WatchSessionController {
    /// Menos que esto entre dos series es un doble toque, no una serie.
    public static let doubleTapGuardSeconds: TimeInterval = 2

    public private(set) var state: WatchLocalState
    /// Falló la última escritura: esa serie NO quedó hecha y la pantalla lo dice.
    public private(set) var saveFailed = false
    public private(set) var isPhoneReachable = false
    /// Sube con cada serie guardada: dispara el háptico de confirmación.
    public private(set) var confirmedTaps = 0
    /// Peso y reps en pantalla. Son de la persona: un estado nuevo no los pisa.
    public var draftWeight: Double?
    public var draftReps: Int = 0

    @ObservationIgnored private let store: WatchLocalStore
    @ObservationIgnored private let link: any WatchWorkoutLink
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let makeSetID: () -> SetRecordID
    @ObservationIgnored private var draftSlot: SetSlot?
    @ObservationIgnored private var listening: [Task<Void, Never>] = []
    private var loadFailed = false

    public init(
        store: WatchLocalStore,
        link: any WatchWorkoutLink,
        clock: @escaping () -> Date = { Date() },
        makeSetID: @escaping () -> SetRecordID = { SetRecordID() }
    ) {
        self.store = store
        self.link = link
        self.clock = clock
        self.makeSetID = makeSetID
        do {
            self.state = try store.load()
        } catch {
            // No se borra: el archivo se conserva y la pantalla lo dice.
            self.state = .empty
            self.loadFailed = true
        }
        syncDraft()
    }

    /// Escucha al iPhone y reenvía lo que quedó sin confirmar.
    public func start() {
        guard listening.isEmpty else { return }
        let snapshots = link.snapshots
        let reachability = link.reachability
        listening.append(Task { [weak self] in
            for await snapshot in snapshots { await self?.receive(snapshot) }
        })
        listening.append(Task { [weak self] in
            for await reachable in reachability { await self?.phoneReachabilityChanged(reachable) }
        })
        Task { await resendPending() }
    }

    /// Cambió la conexión. Al volver, se reenvía lo pendiente: repetir no duplica.
    public func phoneReachabilityChanged(_ reachable: Bool) async {
        isPhoneReachable = reachable
        if reachable { await resendPending() }
    }

    public var screen: WatchScreen {
        if loadFailed { return .failed }
        guard let snapshot = state.snapshot else { return .idle }
        if snapshot.stage == .finished { return .finished }
        guard let set = state.currentSet else { return .allDone }
        let view = WatchSetScreen(set: set, remaining: WatchSessionCursor.remainingCount(in: snapshot, done: state.done))
        if snapshot.stage == .paused { return .paused(view) }
        if let endsAt = state.restEndsAt, endsAt > clock() { return .resting(view, endsAt: endsAt) }
        return .active(view)
    }

    /// Sin peso no se puede completar: nunca se inventa uno.
    public var canComplete: Bool {
        guard state.currentSet != nil, state.snapshot?.stage == .active, let draftWeight else { return false }
        return draftWeight >= 0 && draftReps >= 1
    }

    /// Cuánto cambia el peso con cada paso de la Corona.
    public var weightStep: Double {
        switch state.currentSet?.unit {
        case .pounds: return 5
        case .kilograms, nil: return 2.5
        }
    }

    /// Ajusta las reps. Nunca baja de 1: una serie sin reps no es una serie.
    public func adjustReps(by delta: Int) {
        draftReps = max(1, draftReps + delta)
    }

    /// Completa la serie: primero el disco, después la confirmación y el envío. Si no se pudo
    /// guardar, la serie no cuenta y la pantalla lo dice.
    public func completeCurrentSet() async {
        guard canComplete, let set = state.currentSet, let weight = draftWeight else { return }
        let now = clock()
        if let last = state.lastCompletedAt, now.timeIntervalSince(last) < Self.doubleTapGuardSeconds { return }
        let result: (state: WatchLocalState, message: WatchMessage)
        do {
            result = try WatchOutbox.completing(set, weight: weight, reps: draftReps, at: now, id: makeSetID(), in: state)
            try store.save(result.state)
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        state = result.state
        confirmedTaps += 1
        syncDraft()
        await link.send(result.message)
    }

    public func skipRest() {
        guard state.restEndsAt != nil else { return }
        var next = state
        next.restEndsAt = nil
        persist(next)
    }

    /// Recibe un estado del iPhone.
    public func receive(_ snapshot: WatchSessionSnapshot) async {
        let next = WatchOutbox.receiving(snapshot, in: state)
        guard next != state else { return }
        persist(next)
        if WatchOutbox.isFinishedAndConfirmed(next) {
            do {
                try store.clear()
            } catch {
                saveFailed = true
            }
        }
        await resendPending()
    }

    /// Reenvía todo lo que falta confirmar. El iPhone descarta lo repetido.
    public func resendPending() async {
        for message in state.outbox { await link.send(message) }
    }

    private func persist(_ next: WatchLocalState) {
        do {
            try store.save(next)
            saveFailed = false
        } catch {
            saveFailed = true
        }
        state = next
        syncDraft()
    }

    /// Al cambiar de serie se precarga la nueva; en la misma serie se respeta lo que la persona
    /// ya ajustó, aunque llegue un estado nuevo.
    private func syncDraft() {
        guard let set = state.currentSet else {
            draftSlot = nil
            return
        }
        guard draftSlot != set.slot else { return }
        draftSlot = set.slot
        draftWeight = set.weight
        draftReps = set.targetReps
    }
}
