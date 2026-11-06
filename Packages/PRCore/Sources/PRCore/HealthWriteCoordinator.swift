//
//  HealthWriteCoordinator.swift
//  PRCore
//
//  SCRUM-246 (PR-F003): que un entrenamiento llegue a Salud una vez y sólo una, aunque la
//  app se cierre o Salud falle. La sesión queda "pendiente" en disco antes de llamar a Salud,
//  y "guardada" después. Si se pierde algo en medio, el reintento repite la misma escritura
//  con el mismo identificador y Salud se queda con uno solo. Sólo cambia `healthWriteStatus`
//  y `healthWorkoutReferenceID`: series, horas y resumen no se tocan.
//

import Foundation
import PRDomain

/// Escribe en Salud las sesiones de un usuario. Es un actor, y se crea uno por cuenta: sólo
/// ve el repositorio de esa cuenta.
public actor HealthWriteCoordinator {
    private let repository: any WorkoutRepository
    private let writer: any HealthWorkoutWriting
    private let canWrite: @Sendable () async -> Bool
    /// Sesiones con una escritura en curso: dos reintentos a la vez no la repiten.
    private var inFlight: Set<WorkoutID> = []

    /// `canWrite` responde si la escritura está activa ahora: se pregunta en cada paso,
    /// porque el permiso se puede quitar desde Ajustes.
    public init(
        repository: any WorkoutRepository,
        writer: any HealthWorkoutWriting,
        canWrite: @escaping @Sendable () async -> Bool
    ) {
        self.repository = repository
        self.writer = writer
        self.canWrite = canWrite
    }

    /// Una sesión acaba de terminar: si va a Salud, queda pendiente y se intenta escribir.
    /// Lanza si no se pudo guardar el estado; un fallo de Salud no lanza, queda pendiente.
    public func sessionFinished(id: WorkoutID) async throws {
        guard var session = try await repository.session(id: id),
              session.healthWriteStatus == nil,
              HealthWorkoutWrite(session: session) != nil,
              await canWrite()
        else { return }
        session.healthWriteStatus = .pending
        try await repository.save(session)
        try await write(id: id)
    }

    /// Reintenta lo pendiente de esta cuenta. Sin permiso no hace nada ni pierde nada: se
    /// queda pendiente para cuando vuelva.
    public func retryPending() async throws {
        guard await canWrite() else { return }
        let pending = try await repository.loadAllSessions().items
            .filter { $0.healthWriteStatus == .pending }
            .sorted { $0.startedAt < $1.startedAt }
        for session in pending {
            try await write(id: session.id)
        }
    }

    /// Escribe una sesión pendiente. Relee del disco: lo guardado manda sobre lo que se tenía.
    private func write(id: WorkoutID) async throws {
        guard inFlight.insert(id).inserted else { return }
        defer { inFlight.remove(id) }
        guard let session = try await repository.session(id: id),
              session.healthWriteStatus == .pending,
              let workout = HealthWorkoutWrite(session: session)
        else { return }
        let reference: HealthWorkoutHandle.ID
        do {
            reference = try await writer.saveFinishedWorkout(workout)
        } catch {
            // Sigue pendiente: se reintenta al abrir la app y al volver a primer plano.
            return
        }
        guard var saved = try await repository.session(id: id) else { return }
        saved.healthWriteStatus = .saved
        saved.healthWorkoutReferenceID = reference.rawValue
        try await repository.save(saved)
    }
}
