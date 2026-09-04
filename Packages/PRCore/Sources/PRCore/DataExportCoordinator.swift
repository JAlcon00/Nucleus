//
//  DataExportCoordinator.swift
//  PRCore
//
//  Created by PR.
//
//  Caso de uso de export de datos (PR-0204, RF-030 / RNEG-006). Orquesta los
//  repositorios de entrenamiento y el motor de dominio `ExportEngine` para producir
//  artefactos portables (JSON completo / CSV de sets) listos para el share sheet
//  del usuario. No contiene reglas de negocio: delega en `ExportEngine`. Garantiza
//  que nunca se exportan secrets: si el JSON contuviera campos con nombres de
//  secretos, se lanza `DataExportError.secretDetected` y se niega el export.
//

import Foundation
import PRDomain

/// Error del caso de uso de export.
public enum DataExportError: Error, Equatable, Sendable {
    case secretDetected
    case sourceUnavailable(String)
}

/// Artifact listo para compartir (contenido + nombre de archivo + tipo MIME).
public struct DataExportFile: Sendable {
    public let fileName: String
    public let data: Data
    public let mimeType: String

    public init(fileName: String, data: Data, mimeType: String) {
        self.fileName = fileName
        self.data = data
        self.mimeType = mimeType
    }
}

/// Caso de uso de export. Acepta fuentes de datos agregadas (por defecto los
/// repositorios de PRCore) y produce los archivos de export seguros.
public struct DataExportCoordinator: Sendable {

    private let engine: ExportEngine
    private let schemaVersion: Int

    public init(
        engine: ExportEngine = ExportEngine(),
        schemaVersion: Int = ExportBundleVersion.current
    ) {
        self.engine = engine
        self.schemaVersion = schemaVersion
    }

    /// Snapshot + JSON completo de training data.
    public func exportJSON(
        sessions: [WorkoutSessionRecord],
        exercises: [Exercise],
        blocks: [TrainingBlock],
        gyms: [GymProfile],
        restrictions: [TrainingRestriction],
        profile: UserTrainingProfile?,
        exportedAt: Date = Date()
    ) throws -> DataExportFile {
        let bundle = ExportBundle(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            blocks: blocks,
            sessions: sessions,
            exercises: exercises,
            gyms: gyms,
            restrictions: restrictions,
            profile: profile
        )
        let data = try engine.jsonData(for: bundle)
        guard !ExportEngine.containsForbiddenSecretFields(inJSON: data) else {
            throw DataExportError.secretDetected
        }
        return DataExportFile(
            fileName: "pr-training-export.json",
            data: data,
            mimeType: "application/json"
        )
    }

    /// CSV mínimo de workout sets.
    public func exportSetsCSV(sessions: [WorkoutSessionRecord]) -> DataExportFile {
        let csv = engine.workoutSetsCSV(sessions: sessions)
        return DataExportFile(
            fileName: "pr-workout-sets.csv",
            data: Data(csv.utf8),
            mimeType: "text/csv"
        )
    }

    /// Exporta añadiendo solo las sesiones existentes (cobertura de la fuente por
    /// repositorio): falla si la fuente de sesiones está indisponible.
    public func exportJSON(from repository: any WorkoutRepository,
                           exercises: [Exercise],
                           blocks: [TrainingBlock],
                           gyms: [GymProfile],
                           restrictions: [TrainingRestriction],
                           profile: UserTrainingProfile?) async throws -> DataExportFile {
        let sessions: [WorkoutSessionRecord]
        do {
            sessions = try await repository.allSessions()
        } catch {
            throw DataExportError.sourceUnavailable("sessions")
        }
        return try exportJSON(
            sessions: sessions,
            exercises: exercises,
            blocks: blocks,
            gyms: gyms,
            restrictions: restrictions,
            profile: profile
        )
    }
}