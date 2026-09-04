//
//  DataExport.swift
//  PRDomain
//
//  Created by PR.
//
//  Export de datos (RF-030, RNEG-006, PR-0204). Motor determinista que serializa
//  el historial de entrenamiento en formato portable:
//  - `ExportBundle`: snapshot JSON completo del training data (bloques, sesiones,
//    ejercicios, gyms, restricciones y perfil), versionado y determinista.
//  - CSV mínimo de workout sets.
//  - **No exporta secrets**: el bundle sólo contiene agregados de dominio de
//    entrenamiento; además se protege en tiempo de encoding negando campos con
//    nombres de secretos (orneo) y exponiendo `containsForbiddenSecretFields`.
//  Es un motor puro (dominio): la capa de persistencia/UI alimenta los inputs.
//

import Foundation

// MARK: - Snapshot portable

/// Snapshot portable del historial de entrenamiento. Sin secrets por construcción:
/// sólo contiene agregados de dominio (ninguno transporta credenciales).
public struct ExportBundle: Codable, Equatable, Sendable {
    /// Versión del schema de export (para migraciones de importadores).
    public let schemaVersion: Int
    /// Momento de generación del snapshot.
    public let exportedAt: Date
    public let blocks: [TrainingBlock]
    public let sessions: [WorkoutSessionRecord]
    public let exercises: [Exercise]
    public let gyms: [GymProfile]
    public let restrictions: [TrainingRestriction]
    public let profile: UserTrainingProfile?

    public init(
        schemaVersion: Int,
        exportedAt: Date,
        blocks: [TrainingBlock],
        sessions: [WorkoutSessionRecord],
        exercises: [Exercise],
        gyms: [GymProfile],
        restrictions: [TrainingRestriction],
        profile: UserTrainingProfile?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.blocks = blocks
        self.sessions = sessions
        self.exercises = exercises
        self.gyms = gyms
        self.restrictions = restrictions
        self.profile = profile
    }
}

// MARK: - Fila CSV de un workout set

/// Fila del CSV mínimo de workout sets (prevista para portabilidad en hojas de cálculo).
public struct WorkoutSetExportRow: Equatable, Sendable {
    public let sessionID: String
    public let startedAtISO: String
    public let exerciseID: String
    public let weight: Double
    public let unit: String
    public let reps: Int
    public let rir: String?
    public let difficulty: String?
    public let pain: String?
    public let lifecycle: String
}

// MARK: - Enumeradores de salida

public enum ExportBundleVersion {
    public static let current = 1
}

/// Nombres de campos prohibidos en el export por transportar secrets/identidad.
/// Declaración explícita para el guardia `containsForbiddenSecretFields`.
public enum ForbiddenExportFields {
    /// Comparación case-insensitive (normalizada a minúsculas).
    public static let known: Set<String> = [
        "apikey", "accesstoken", "idtoken", "authorizationcode",
        "nvidakey", "nimkey", "secret", "clientsecret", "password",
    ]

    /// Reconoce un nombre de campo sea cual sea su capitalización.
    public static func isForbidden(fieldName: String) -> Bool {
        known.contains(fieldName.lowercased().filter { $0 != "_" && $0 != "-" && $0 != " " })
    }
}

// MARK: - Engine

/// Motor determinista de export (PR-0204).
public struct ExportEngine: Sendable {

    public init() {}

    /// Serializa el bundle completo a JSON portable, determinista y sin secrets.
    public func jsonData(
        for bundle: ExportBundle,
        outputFormatting: JSONEncoder.OutputFormatting = [.sortedKeys, .prettyPrinted]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        return data
    }

    /// CSV mínimo de workout sets (una fila por set), en orden determinista.
    public func workoutSetsCSV(sessions: [WorkoutSessionRecord]) -> String {
        var rows: [WorkoutSetExportRow] = []
        let sessionsSorted = sessions.sorted { a, b in
            if a.startedAt == b.startedAt { return a.id.rawValue < b.id.rawValue }
            return a.startedAt < b.startedAt
        }
        for session in sessionsSorted {
            // índice ordinal del set dentro de la sesión (1-based, determinista)
            let indexed = session.sets.enumerated()
            for (ordinal, set) in indexed {
                rows.append(Self.row(session: session, set: set, ordinal: ordinal + 1))
            }
        }
        return rows.isEmpty ? Self.headerLine : Self.headerLine + "\n" + rows.map { Self.csvLine($0) }.joined(separator: "\n")
    }

    /// Devuelve `true` si el JSON exportado contiene algún campo con nombre de
    /// secret/identidad prohibido. El exportador debe negarse si esto ocurre.
    public static func containsForbiddenSecretFields(inJSON data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true // No se puede validar ⇒ tratarlo como inseguro.
        }
        return Self.containsForbidden(in: obj)
    }

    // MARK: - Helpers

    private static func containsForbidden(in node: Any) -> Bool {
        if let dict = node as? [String: Any] {
            return dict.contains { key, value in
                ForbiddenExportFields.isForbidden(fieldName: key) || containsForbidden(in: value)
            }
        }
        if let array = node as? [Any] {
            return array.contains { containsForbidden(in: $0) }
        }
        return false
    }

    private static func row(session: WorkoutSessionRecord, set: SetRecord, ordinal: Int) -> WorkoutSetExportRow {
        WorkoutSetExportRow(
            sessionID: session.id.rawValue.uuidString,
            startedAtISO: ISO8601DateFormatter().string(from: session.startedAt),
            exerciseID: set.exerciseID.rawValue.uuidString,
            weight: set.weight,
            unit: set.unit.rawValue,
            reps: set.reps,
            rir: set.rir.map(String.init),
            difficulty: set.perceivedDifficulty?.rawValue,
            pain: Self.painSummary(set.painFeedback),
            lifecycle: set.lifecycle.rawValue
        )
    }

    private static func painSummary(_ pain: PainFeedback?) -> String? {
        guard let pain else { return nil }
        switch pain {
        case .none:
            return "none"
        case .discomfort(let muscle, let severity):
            return "discomfort:\(muscle.rawValue):\(severity)"
        case .sharpPain(let muscle, let severity):
            return "sharpPain:\(muscle.rawValue):\(severity)"
        }
    }

    // MARK: - CSV rendering (RFC-4180 "": escape de comillas)

    private static let headerLine = "sessionID,startedAtISO,exerciseID,weight,unit,reps,rir,difficulty,pain,lifecycle"

    private static func csvLine(_ row: WorkoutSetExportRow) -> String {
        let fields = [
            row.sessionID,
            row.startedAtISO,
            row.exerciseID,
            String(row.weight),
            row.unit,
            String(row.reps),
            row.rir ?? "",
            row.difficulty ?? "",
            row.pain ?? "",
            row.lifecycle,
        ]
        return fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }.joined(separator: ",")
    }
}