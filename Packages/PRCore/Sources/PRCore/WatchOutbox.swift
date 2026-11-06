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

/// En qué va la sesión de Salud del reloj.
public enum WatchHealthSessionState: String, Codable, Sendable, Equatable {
    case running
    case paused
    case ended
    /// Falló: las series siguen y el iPhone escribe por su cuenta.
    case failed
}

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
    /// La última serie hecha aquí: sobre ella se reporta dolor (SCRUM-260).
    public var lastSet: SetRecord?
    /// Lo que se pidió aquí y el iPhone aún no confirma (SCRUM-259). Manda sobre lo recibido.
    public var localStage: WatchSessionStage?
    /// Hora en que se terminó aquí.
    public var finishedAt: Date?
    /// Sesión de Salud de este reloj: se recuerda para no abrir otra al reabrir la app.
    public var healthSession: WatchHealthSessionState?

    public init(
        snapshot: WatchSessionSnapshot? = nil,
        done: [WatchDoneSet] = [],
        outbox: [WatchMessage] = [],
        restEndsAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        lastSet: SetRecord? = nil,
        localStage: WatchSessionStage? = nil,
        finishedAt: Date? = nil,
        healthSession: WatchHealthSessionState? = nil
    ) {
        self.snapshot = snapshot
        self.done = done
        self.outbox = outbox
        self.restEndsAt = restEndsAt
        self.lastCompletedAt = lastCompletedAt
        self.lastSet = lastSet
        self.localStage = localStage
        self.finishedAt = finishedAt
        self.healthSession = healthSession
    }

    public static let empty = WatchLocalState()

    /// En qué va la sesión: lo pedido aquí manda hasta que el iPhone lo confirme.
    public var stage: WatchSessionStage? { localStage ?? snapshot?.stage }

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
        next.lastSet = record
        return (next, message)
    }

    /// El estado con el dolor reportado en la última serie. Viaja como la misma serie: al
    /// iPhone le llega el mismo id con el reporte, y gana el último nivel elegido.
    public static func reportingPain(_ level: PainLevel, in state: WatchLocalState) throws -> (state: WatchLocalState, message: WatchMessage) {
        guard let snapshot = state.snapshot, var set = state.lastSet else { throw WatchSessionError.noSession }
        set.painFeedback = PainFeedback(level: level)
        var slotOfSet: SetSlot?
        for message in state.outbox {
            if case .event(let event) = message, case .recorded(let record) = event.action, record.id == set.id {
                slotOfSet = event.slot
            }
        }
        let slot = slotOfSet ?? state.done.last?.slot
        let message = WatchMessage.event(SetEvent(
            device: WorkoutDevice.watch, emittedAt: set.performedAt, slot: slot,
            action: .recorded(set), sessionID: snapshot.sessionID
        ))
        var next = state
        next.lastSet = set
        next.outbox.append(message)
        return (next, message)
    }

    /// El estado con un comando pedido en el reloj. Funciona sin conexión.
    public static func commanding(
        _ kind: WatchSessionCommandKind,
        at now: Date,
        in state: WatchLocalState
    ) throws -> (state: WatchLocalState, message: WatchMessage) {
        guard let snapshot = state.snapshot else { throw WatchSessionError.noSession }
        let message = WatchMessage.command(WatchSessionCommand(sessionID: snapshot.sessionID, kind: kind, issuedAt: now))
        var next = state
        next.outbox.append(message)
        switch kind {
        case .pause:
            next.localStage = .paused
        case .resume:
            next.localStage = .active
        case .finish:
            next.localStage = .finished
            next.finishedAt = now
            next.restEndsAt = nil
        }
        return (next, message)
    }

    /// El estado tras recibir uno del iPhone. Uno viejo no reemplaza a uno nuevo. Lo confirmado
    /// sale del buzón, y las series locales siguen mandando sobre qué toca.
    public static func receiving(_ snapshot: WatchSessionSnapshot, in state: WatchLocalState) -> WatchLocalState {
        var next = state
        next.outbox = pruned(state.outbox, confirmedBy: snapshot)
        if !hasPendingCommand(next.outbox) { next.localStage = nil }
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
        state.stage == .finished && state.outbox.isEmpty
    }

    /// Una serie con reporte de dolor sólo sale cuando el iPhone ya guardó ese reporte: estar
    /// confirmada no basta, y perderlo dejaría subir la carga con dolor.
    private static func pruned(_ outbox: [WatchMessage], confirmedBy snapshot: WatchSessionSnapshot) -> [WatchMessage] {
        let confirmed = Set(snapshot.confirmedSetIDs)
        let annotated = Set(snapshot.annotatedSetIDs)
        let commands = Set(snapshot.confirmedCommandIDs)
        return outbox.filter { message in
            switch message {
            case .event(let event):
                guard case .recorded(let record) = event.action else { return true }
                return !(record.painFeedback == nil ? confirmed : annotated).contains(record.id)
            case .command(let command):
                return !commands.contains(command.id)
            case .health(let notice):
                return !commands.contains(notice.id)
            }
        }
    }

    private static func hasPendingCommand(_ outbox: [WatchMessage]) -> Bool {
        outbox.contains { message in
            switch message {
            case .event, .health: return false
            case .command: return true
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

/// El resumen corto al terminar: sin análisis.
public struct WatchFinishedSummary: Equatable, Sendable {
    public let sets: Int
    public let durationSeconds: Int?
    /// `false` mientras haya algo por confirmar: el reloj no dice "guardado" antes de tiempo.
    public let isSaved: Bool

    public init(sets: Int, durationSeconds: Int?, isSaved: Bool) {
        self.sets = sets
        self.durationSeconds = durationSeconds
        self.isSaved = isSaved
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
    /// Qué recomienda el motor de dolor para lo último reportado (el mismo que el iPhone).
    public private(set) var painRecommendation: PainRecommendation?
    /// Peso y reps en pantalla. Son de la persona: un estado nuevo no los pisa.
    public var draftWeight: Double?
    public var draftReps: Int = 0

    @ObservationIgnored private let store: WatchLocalStore
    @ObservationIgnored private let link: any WatchWorkoutLink
    @ObservationIgnored private let health: HealthLiveWorkoutCoordinator?
    @ObservationIgnored private var healthMachine = HealthLiveWorkoutStateMachine()
    @ObservationIgnored private var isStartingHealth = false
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let makeSetID: () -> SetRecordID
    @ObservationIgnored private var draftSlot: SetSlot?
    @ObservationIgnored private var listening: [Task<Void, Never>] = []
    private var loadFailed = false

    public init(
        store: WatchLocalStore,
        link: any WatchWorkoutLink,
        health: HealthLiveWorkoutCoordinator? = nil,
        clock: @escaping () -> Date = { Date() },
        makeSetID: @escaping () -> SetRecordID = { SetRecordID() }
    ) {
        self.store = store
        self.link = link
        self.health = health
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
        if state.stage == .finished { return .finished }
        guard let set = state.currentSet else { return .allDone }
        let view = WatchSetScreen(set: set, remaining: WatchSessionCursor.remainingCount(in: snapshot, done: state.done))
        if state.stage == .paused { return .paused(view) }
        if let endsAt = state.restEndsAt, endsAt > clock() { return .resting(view, endsAt: endsAt) }
        return .active(view)
    }

    /// Sin peso no se puede completar: nunca se inventa uno.
    public var canComplete: Bool {
        guard state.currentSet != nil, state.stage == .active, let draftWeight else { return false }
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

    /// El resumen corto, cuando la sesión ya terminó.
    public var finishedSummary: WatchFinishedSummary? {
        guard state.stage == .finished, let snapshot = state.snapshot else { return nil }
        let unconfirmed = state.outbox.filter { message in
            guard case .event(let event) = message, case .recorded(let set) = event.action else { return false }
            return set.painFeedback == nil
        }.count
        let end = snapshot.endedAt ?? state.finishedAt
        return WatchFinishedSummary(
            sets: snapshot.confirmedSetIDs.count + unconfirmed,
            durationSeconds: snapshot.startedAt.flatMap { start in end.map { Int(max(0, $0.timeIntervalSince(start))) } },
            isSaved: state.outbox.isEmpty
        )
    }

    public func pause() async { await command(.pause) }
    public func resume() async { await command(.resume) }

    /// Termina la sesión desde el reloj, también sin iPhone: se cierra al reconectar, con esta hora.
    public func finish() async { await command(.finish) }

    /// Primero el disco, después el envío, igual que una serie.
    private func command(_ kind: WatchSessionCommandKind) async {
        let result: (state: WatchLocalState, message: WatchMessage)
        do {
            result = try WatchOutbox.commanding(kind, at: clock(), in: state)
            try store.save(result.state)
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        state = result.state
        await link.send(result.message)
        await syncHealth()
    }

    // MARK: - Sesión de Salud (SCRUM-258)

    /// Deja la sesión de Salud como pide la sesión de entrenamiento. La abre el iPhone al
    /// empezar, o el reloj si se abre con una sesión activa. Nada de esto toca las series: si
    /// Salud falla, se sigue entrenando y el iPhone escribe por su cuenta.
    public func syncHealth() async {
        guard let health, let snapshot = state.snapshot, snapshot.opensWorkoutSession else { return }
        switch (state.stage, healthMachine.state) {
        case (.active?, .idle), (.paused?, .idle):
            await startHealth(health, session: snapshot.sessionID)
        case (.paused?, .running):
            await changeHealth(.paused) { try await health.pause(stateMachine: $0) }
        case (.active?, .paused):
            await changeHealth(.running) { try await health.resume(stateMachine: $0) }
        case (.finished?, .running), (.finished?, .paused):
            await endHealth(health, session: snapshot.sessionID)
        default:
            break
        }
    }

    private func startHealth(_ health: HealthLiveWorkoutCoordinator, session: WorkoutID) async {
        guard !isStartingHealth, state.healthSession == nil || state.healthSession == .running else { return }
        isStartingHealth = true
        defer { isStartingHealth = false }
        do {
            await health.builder.tag(sessionID: session.rawValue)
            healthMachine = try await health.recoverOrStart(stateMachine: healthMachine)
            await record(.running, notify: SessionHealthRecording(state: .recording), session: session)
        } catch {
            await record(.failed, notify: SessionHealthRecording(state: .failed), session: session)
        }
    }

    private func changeHealth(
        _ next: WatchHealthSessionState,
        _ change: (HealthLiveWorkoutStateMachine) async throws -> HealthLiveWorkoutStateMachine
    ) async {
        do {
            healthMachine = try await change(healthMachine)
            persistHealth(next)
        } catch {
            // Salud no pudo pausar o reanudar: el entrenamiento sigue igual.
            persistHealth(next)
        }
    }

    private func endHealth(_ health: HealthLiveWorkoutCoordinator, session: WorkoutID) async {
        do {
            let (metrics, machine) = try await health.end(stateMachine: healthMachine)
            healthMachine = machine
            let heartRate = await health.builder.averageHeartRate()
            await record(.ended, notify: SessionHealthRecording(
                state: .saved, activeKilocalories: metrics.activeKilocalories, averageHeartRateBPM: heartRate
            ), session: session)
        } catch {
            healthMachine = HealthLiveWorkoutStateMachine(state: .failed(reason: "end"))
            await record(.failed, notify: SessionHealthRecording(state: .failed), session: session)
        }
    }

    private func persistHealth(_ value: WatchHealthSessionState) {
        var next = state
        next.healthSession = value
        persist(next)
    }

    /// Avisa al iPhone quién escribe el entrenamiento. Viaja por el buzón: no se puede perder.
    private func record(_ value: WatchHealthSessionState, notify recording: SessionHealthRecording, session: WorkoutID) async {
        let message = WatchMessage.health(WatchHealthNotice(sessionID: session, recording: recording))
        var next = state
        next.healthSession = value
        next.outbox.append(message)
        persist(next)
        await link.send(message)
    }

    /// ¿Hay una serie sobre la cual reportar? Reportar es opcional: no estorba al completar.
    public var canReportPain: Bool { state.lastSet != nil }

    /// El nivel ya reportado en la última serie.
    public var reportedPain: PainLevel? { state.lastSet?.painFeedback?.level }

    /// Reporta el dolor de la última serie. Se guarda antes que nada, como una serie, y el
    /// reloj no decide: la recomendación sale del mismo motor que usa el iPhone.
    public func reportPain(_ level: PainLevel) async {
        let result: (state: WatchLocalState, message: WatchMessage)
        do {
            result = try WatchOutbox.reportingPain(level, in: state)
            try store.save(result.state)
        } catch {
            saveFailed = true
            return
        }
        saveFailed = false
        state = result.state
        painRecommendation = recommendation(for: level)
        await link.send(result.message)
    }

    /// Si el motor no pudiera responder, lo más seguro: moderado o alto se tratan como alto.
    private func recommendation(for level: PainLevel) -> PainRecommendation {
        do {
            let engine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
            return try engine.evaluate(PainFeedbackInput(level: level, exerciseName: nil)).recommendation
        } catch {
            return level.isConservativeDisruptive ? .stopAndRest : .continueNormal
        }
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
        await syncHealth()
        if WatchOutbox.isFinishedAndConfirmed(state) {
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
