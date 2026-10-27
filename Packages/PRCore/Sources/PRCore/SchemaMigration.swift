//
//  SchemaMigration.swift
//  PRCore
//
//  SCRUM-40: versión de formato por colección y migraciones en orden.
//
//  Cada carpeta de colección guarda su versión en un archivo oculto (`.schema-version`);
//  sin marca es la versión 1, el formato de antes de SCRUM-40. Al arrancar, cada
//  colección sube paso a paso (1→2→3) hasta la versión vigente:
//  - la colección migrada se escribe aparte (`.<colección>.migrating`) y se marca al
//    final; solo entonces reemplaza a la original, que queda como respaldo
//    (`.<colección>.backup`) hasta la siguiente migración;
//  - un registro que no se puede migrar se guarda intacto en `.quarantine/v<N>/` y el
//    resto sí migra; las lecturas lo cuentan como "no pude leer";
//  - un corte a mitad se termina al siguiente arranque, sin perder ni duplicar nada;
//  - datos de una versión más nueva, una marca ilegible o un paso faltante: no se toca
//    nada.
//

import Foundation

/// Versión del formato de una colección guardada. Siempre ≥ 1.
public struct SchemaVersion: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: Int

    /// `nil` si no es ≥ 1.
    public init?(rawValue: Int) {
        guard rawValue >= 1 else { return nil }
        self.rawValue = rawValue
    }

    private init(validated rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Formato anterior a SCRUM-40: lo que hay en los dispositivos sin marca.
    public static let initial = SchemaVersion(validated: 1)

    public var next: SchemaVersion { SchemaVersion(validated: rawValue + 1) }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "v\(rawValue)" }
}

/// Un paso de migración: convierte UN registro (su JSON) de `from` a `from.next`. Puro:
/// sin disco, reloj ni red. Lanza si el registro no se puede convertir.
public struct SchemaMigrationStep: Sendable {
    public let from: SchemaVersion
    public let transform: @Sendable (Data) throws -> Data

    public init(from: SchemaVersion, transform: @escaping @Sendable (Data) throws -> Data) {
        self.from = from
        self.transform = transform
    }
}

/// Formato vigente de una colección y los pasos para llegar a él desde la versión 1.
public struct CollectionSchema: Sendable {
    public let current: SchemaVersion
    public let steps: [SchemaMigrationStep]
    /// ¿El registro se lee completo con el modelo vigente?
    public let isReadable: @Sendable (Data) -> Bool

    public init(
        current: SchemaVersion,
        steps: [SchemaMigrationStep],
        isReadable: @escaping @Sendable (Data) -> Bool
    ) {
        self.current = current
        self.steps = steps
        self.isReadable = isReadable
    }

    /// Pasos para ir de `version` a `current`, en orden; `nil` si falta alguno.
    public func chain(from version: SchemaVersion) -> [SchemaMigrationStep]? {
        firstMissingStep(from: version) == nil ? walk(from: version) : nil
    }

    /// La primera versión, desde `version`, que no tiene paso hacia la siguiente.
    public func firstMissingStep(from version: SchemaVersion) -> SchemaVersion? {
        var cursor = version
        while cursor < current {
            guard steps.contains(where: { $0.from == cursor }) else { return cursor }
            cursor = cursor.next
        }
        return nil
    }

    private func walk(from version: SchemaVersion) -> [SchemaMigrationStep] {
        var chain: [SchemaMigrationStep] = []
        var cursor = version
        while cursor < current, let step = steps.first(where: { $0.from == cursor }) {
            chain.append(step)
            cursor = cursor.next
        }
        return chain
    }

    /// Exactamente un paso por versión, de la 1 a la vigente.
    public var isComplete: Bool {
        chain(from: .initial) != nil && steps.count == current.rawValue - SchemaVersion.initial.rawValue
    }
}

/// Archivos y carpetas de control junto a los registros de una colección. Todos son
/// ocultos: `AtomicFileRepositoryStore` y la migración del layout antiguo los ignoran.
enum CollectionLayout {
    static let markerFileName = ".schema-version"
    static let quarantineDirectoryName = ".quarantine"
    /// Dentro de la cuarentena: registros ilegibles guardados antes de escribir encima
    /// (SCRUM-223), aparte de los que no se pudieron migrar (`v<N>/`).
    static let damagedDirectoryName = "damaged"

    /// Qué dice la marca de versión de una carpeta.
    enum Marker: Equatable {
        /// Sin marca: carpeta de antes de SCRUM-40 (versión 1).
        case absent
        case version(SchemaVersion)
        /// Existe pero no se puede leer: no se adivina.
        case unreadable
    }

    private struct MarkerFile: Codable {
        let version: SchemaVersion
    }

    static func stagingURL(for directory: URL) -> URL {
        sibling(of: directory, suffix: "migrating")
    }

    static func backupURL(for directory: URL) -> URL {
        sibling(of: directory, suffix: "backup")
    }

    static func quarantineURL(in directory: URL) -> URL {
        directory.appendingPathComponent(quarantineDirectoryName, isDirectory: true)
    }

    static func readMarker(in directory: URL) -> Marker {
        let url = directory.appendingPathComponent(markerFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MarkerFile.self, from: data) else {
            return .unreadable
        }
        return .version(file.version)
    }

    static func writeMarker(_ version: SchemaVersion, in directory: URL) throws {
        let data = try JSONEncoder().encode(MarkerFile(version: version))
        try data.write(to: directory.appendingPathComponent(markerFileName), options: .atomic)
    }

    private static func sibling(of directory: URL, suffix: String) -> URL {
        directory.deletingLastPathComponent()
            .appendingPathComponent(".\(directory.lastPathComponent).\(suffix)", isDirectory: true)
    }
}

/// Fallas que dejan la colección intacta para reintentar al siguiente arranque.
public enum SchemaMigrationError: Error, Equatable, Sendable {
    /// Hay archivos que existen pero no se pudieron leer (p. ej. disco bloqueado): no se
    /// migra nada para no dejarlos atrás.
    case unreadableRecords(count: Int)
}

/// Lleva la carpeta de UNA colección a su formato vigente.
public struct CollectionSchemaMigrator: Sendable {

    public enum Outcome: Equatable, Sendable {
        /// La carpeta no existe: nada que migrar.
        case absent
        case upToDate(SchemaVersion)
        case migrated(from: SchemaVersion, to: SchemaVersion, records: Int, quarantined: Int)
        /// Datos de una versión más nueva de la app (bajar de versión): no se tocan.
        case newerThanKnown(found: SchemaVersion, known: SchemaVersion)
        /// No se toca nada (ver `UntouchedReason`).
        case untouched(UntouchedReason)
    }

    public enum UntouchedReason: Equatable, Sendable {
        /// Falta el paso que parte de esta versión (error de programación).
        case missingStep(from: SchemaVersion)
        case unreadableMarker
    }

    public init() {}

    /// Migra la colección en `directory`. Idempotente; termina un corte anterior. Lanza
    /// por errores de disco, siempre con los originales intactos.
    public func migrate(collectionAt directory: URL, schema: CollectionSchema) throws -> Outcome {
        try Self.recoverInterruptedSwap(at: directory)
        guard Self.isDirectory(directory) else { return .absent }

        let found: SchemaVersion
        let marker = CollectionLayout.readMarker(in: directory)
        switch marker {
        case .unreadable: return .untouched(.unreadableMarker)
        case .absent: found = .initial
        case .version(let version): found = version
        }
        if found > schema.current {
            return .newerThanKnown(found: found, known: schema.current)
        }
        if found == schema.current {
            if marker == .absent {
                try CollectionLayout.writeMarker(found, in: directory)
            }
            return .upToDate(found)
        }
        guard let chain = schema.chain(from: found) else {
            return .untouched(.missingStep(from: schema.firstMissingStep(from: found) ?? found))
        }
        return try rewrite(directory, from: found, through: chain, schema: schema)
    }

    /// Si un corte dejó la colección fuera de su lugar (entre los dos movimientos del
    /// cambio), la regresa: la migrada si quedó completa; si no, el respaldo.
    static func recoverInterruptedSwap(at directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        let staging = CollectionLayout.stagingURL(for: directory)
        if isDirectory(staging), case .version = CollectionLayout.readMarker(in: staging) {
            try FileManager.default.moveItem(at: staging, to: directory)
            return
        }
        let backup = CollectionLayout.backupURL(for: directory)
        if isDirectory(backup) {
            try FileManager.default.moveItem(at: backup, to: directory)
        }
    }

    // MARK: - Reescritura

    private func rewrite(
        _ directory: URL,
        from found: SchemaVersion,
        through chain: [SchemaMigrationStep],
        schema: CollectionSchema
    ) throws -> Outcome {
        let fileManager = FileManager.default
        let source = try AtomicFileRepositoryStore(directory: directory).readActiveEntries()
        guard source.unreadableKeys.isEmpty else {
            throw SchemaMigrationError.unreadableRecords(count: source.unreadableKeys.count)
        }

        // Lo que quedó de un corte antes del cambio se descarta: los originales siguen intactos.
        let staging = CollectionLayout.stagingURL(for: directory)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        let migratedStore = try AtomicFileRepositoryStore(directory: staging)

        // La cuarentena de migraciones anteriores viaja con la colección.
        let previousQuarantine = CollectionLayout.quarantineURL(in: directory)
        if Self.isDirectory(previousQuarantine) {
            try fileManager.copyItem(at: previousQuarantine, to: CollectionLayout.quarantineURL(in: staging))
        }
        let quarantine = CollectionLayout.quarantineURL(in: staging)
            .appendingPathComponent(found.description, isDirectory: true)

        var migrated = 0
        var quarantined = 0
        for entry in source.entries {
            if let converted = Self.convert(entry.data, through: chain, schema: schema) {
                try migratedStore.write(key: entry.key, data: converted)
                migrated += 1
            } else {
                try AtomicFileRepositoryStore(directory: quarantine).write(key: entry.key, data: entry.data)
                quarantined += 1
            }
        }
        // La marca va al final: una carpeta migrada sin marca está incompleta.
        try CollectionLayout.writeMarker(schema.current, in: staging)

        let backup = CollectionLayout.backupURL(for: directory)
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        try fileManager.moveItem(at: directory, to: backup)
        try fileManager.moveItem(at: staging, to: directory)
        return .migrated(from: found, to: schema.current, records: migrated, quarantined: quarantined)
    }

    /// El registro convertido, o `nil` si un paso falla o el resultado no se lee completo.
    private static func convert(_ data: Data, through chain: [SchemaMigrationStep], schema: CollectionSchema) -> Data? {
        var current = data
        for step in chain {
            guard let next = try? step.transform(current) else { return nil }
            current = next
        }
        return schema.isReadable(current) ? current : nil
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
