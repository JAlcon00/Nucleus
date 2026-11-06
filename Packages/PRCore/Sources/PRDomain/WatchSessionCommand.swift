//
//  WatchSessionCommand.swift
//  PRDomain
//
//  SCRUM-259 (PR-G008): pausar y terminar desde el reloj, también sin conexión. Cada comando
//  tiene id: repetirlo no hace nada, y entre pausar y reanudar gana el más reciente aunque
//  lleguen en otro orden. Terminar gana sobre todo lo demás.
//

import Foundation

/// Qué pide el reloj.
public enum WatchSessionCommandKind: String, Codable, Sendable, Hashable {
    case pause
    case resume
    case finish
}

/// Un comando del reloj sobre la sesión.
public struct WatchSessionCommand: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sessionID: WorkoutID
    public let kind: WatchSessionCommandKind
    /// Hora del reloj: es la hora real de la pausa o del fin, aunque llegue después.
    public let issuedAt: Date

    public init(id: UUID = UUID(), sessionID: WorkoutID, kind: WatchSessionCommandKind, issuedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.issuedAt = issuedAt
    }
}

/// Lo que el reloj avisa de su sesión de Salud (SCRUM-258).
public struct WatchHealthNotice: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sessionID: WorkoutID
    public let recording: SessionHealthRecording

    public init(id: UUID = UUID(), sessionID: WorkoutID, recording: SessionHealthRecording) {
        self.id = id
        self.sessionID = sessionID
        self.recording = recording
    }

    /// La sesión con el aviso anotado. Lo guardado gana sobre "grabando": un aviso que llega
    /// tarde no deshace que el entrenamiento ya esté en Salud. Idempotente.
    public func applied(to session: WorkoutSessionRecord) -> WorkoutSessionRecord {
        guard !(session.appliedCommandIDs ?? []).contains(id) else { return session }
        var updated = session
        updated.appliedCommandIDs = (session.appliedCommandIDs ?? []) + [id]
        if session.healthRecording?.state != .saved { updated.healthRecording = recording }
        return updated
    }
}

/// Decide qué hacer con un comando: lo usan la sesión en pantalla y la sesión guardada.
public enum SessionCommandPolicy {

    /// ¿El comando todavía cambia algo? No si ya se aplicó, si la sesión terminó o si es una
    /// pausa o reanudación más vieja que la última.
    public static func shouldApply(_ command: WatchSessionCommand, to session: WorkoutSessionRecord) -> Bool {
        guard !(session.appliedCommandIDs ?? []).contains(command.id) else { return false }
        switch session.lifecycle {
        case .completed, .abandoned:
            return false
        case .planned, .preparing, .active, .paused, .finishing:
            break
        }
        switch command.kind {
        case .finish:
            return true
        case .pause, .resume:
            guard let last = session.lastRemoteCommandAt else { return true }
            return command.issuedAt >= last
        }
    }

    /// La sesión con el comando anotado: así se confirma al reloj y no se aplica dos veces.
    public static func recording(_ command: WatchSessionCommand, in session: WorkoutSessionRecord) -> WorkoutSessionRecord {
        var updated = session
        updated.appliedCommandIDs = (session.appliedCommandIDs ?? []) + [command.id]
        updated.lastRemoteCommandAt = max(session.lastRemoteCommandAt ?? command.issuedAt, command.issuedAt)
        return updated
    }

    /// Aplica el comando a una sesión guardada (la app estaba cerrada). Idempotente. Terminar
    /// sin ninguna serie abandona: no hay entrenamiento que cerrar (DF-4).
    public static func applying(_ command: WatchSessionCommand, to session: WorkoutSessionRecord) -> WorkoutSessionRecord {
        guard !(session.appliedCommandIDs ?? []).contains(command.id) else { return session }
        guard shouldApply(command, to: session) else { return recording(command, in: session) }
        var controller = ActiveWorkoutController(state: ActiveWorkoutState(session: session, lastTransitionAt: command.issuedAt))
        do {
            switch command.kind {
            case .pause:
                try controller.pause(at: command.issuedAt)
            case .resume:
                try controller.resume(at: command.issuedAt)
            case .finish:
                if session.lifecycle == .paused { try controller.resume(at: command.issuedAt) }
                if session.sets.isEmpty {
                    try controller.abandon(at: command.issuedAt)
                } else {
                    try controller.finish(at: command.issuedAt)
                    try controller.complete(at: command.issuedAt)
                }
            }
        } catch {
            // Una transición que no aplica (pausar lo pausado) no cambia la sesión.
            return recording(command, in: session)
        }
        return recording(command, in: controller.current?.session ?? session)
    }
}

/// Qué hacer con una serie en conflicto. Si nadie elige, las dos siguen guardadas (DG-3).
public enum SetConflictChoice: String, Sendable, Hashable, CaseIterable {
    /// Se queda la que cuenta y la otra se descarta.
    case keepCurrent
    /// Se queda la otra en lugar de la que cuenta.
    case keepOther
    /// Las dos cuentan: fueron dos series de verdad.
    case keepBoth
}

public enum SessionSetConflictResolver {

    /// Resuelve un conflicto por decisión de la persona. Es lo único que puede descartar una
    /// serie, y sólo la que ella eligió. Sin ese conflicto no cambia nada.
    public static func resolving(
        _ id: SetRecordID,
        choice: SetConflictChoice,
        in session: WorkoutSessionRecord
    ) -> WorkoutSessionRecord {
        guard let conflict = session.setConflicts?.first(where: { $0.set.id == id }) else { return session }
        var updated = session
        let remaining = (session.setConflicts ?? []).filter { $0.set.id != id }
        updated.setConflicts = remaining.isEmpty ? nil : remaining
        switch choice {
        case .keepCurrent:
            break
        case .keepBoth:
            updated.sets = (session.sets + [conflict.set]).enumerated().sorted { first, second in
                first.element.performedAt == second.element.performedAt
                    ? first.offset < second.offset
                    : first.element.performedAt < second.element.performedAt
            }.map(\.element)
        case .keepOther:
            let slots = SessionSetMerger.slots(of: session.sets)
            if let index = session.sets.firstIndex(where: { slots[$0.id] == conflict.slot }) {
                updated.sets[index] = conflict.set
            } else {
                updated.sets.append(conflict.set)
            }
        }
        return updated
    }
}
