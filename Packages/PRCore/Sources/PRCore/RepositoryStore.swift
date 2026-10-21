//
//  RepositoryStore.swift
//  PRCore
//
//  Created by PR.
//
//  Almacén persistente local (PR-0202, EPIC-02) sin dependencia de SwiftData.
//  Racional: los @Model de SwiftData no pueden vivir en un target de librería
//  SPM compartido (crash SIGTRAP en el runtime de SwiftData al ejercitar el
//  modelo; ver ADR-0001). Esta implementación guarda cada agregado de dominio
//  como blob JSON tras una clave tipada, escribiendo de forma atómica para
//  proteger los datos de workout (invariante del producto).
//
//  El dominio (PRDomain) NO importa este almacén; los contratos de persistencia
//  (PR-0201) son la frontera.
//

import Foundation
import PRDomain

/// Un blob leído de una colección junto con su clave.
public struct StoredEntry: Sendable, Equatable {
    public let key: String
    public let data: Data

    public init(key: String, data: Data) {
        self.key = key
        self.data = data
    }
}

/// Lectura tolerante de una colección (SCRUM-23): los blobs legibles y, aparte, las
/// claves de los archivos que existen pero no se pudieron leer. Un archivo dañado
/// nunca oculta a los demás.
public struct StoreReadResult: Sendable, Equatable {
    public let entries: [StoredEntry]
    public let unreadableKeys: [String]

    public init(entries: [StoredEntry], unreadableKeys: [String] = []) {
        self.entries = entries
        self.unreadableKeys = unreadableKeys
    }
}

/// Operaciones de bajo nivel sobre un almacén de pares clave → blob (Data).
/// `key` es la cadena de persistencia (normalmente `id.rawValue.persistenceKey`).
/// Cada instancia representa UNA colección (ver `LocalPersistence`): `readAll` sólo
/// devuelve los blobs de esa colección.
public protocol RepositoryStore: Sendable {
    func read(key: String) throws -> Data?
    func readAll() throws -> [Data]
    /// Lectura tolerante. Lanza sólo si la colección entera no es accesible.
    func readAllEntries() throws -> StoreReadResult
    func write(key: String, data: Data) throws
    func delete(key: String) throws
}

extension UUID {
    /// Cadena estable para usar de clave de persistencia (minúsculas).
    public var persistenceKey: String { uuidString.lowercased() }
}

/// Almacén respaldado por un diccionario en memoria. Determinista y sin IO:
/// usado por los tests para verificar los contratos de persistencia.
public final class MemoryRepositoryStore: RepositoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var backing: [String: Data]

    public init() {
        self.backing = [:]
    }

    public func read(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return backing[key]
    }

    public func readAll() throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        return Array(backing.values)
    }

    public func readAllEntries() throws -> StoreReadResult {
        lock.lock(); defer { lock.unlock() }
        let entries = backing
            .map { StoredEntry(key: $0.key, data: $0.value) }
            .sorted { $0.key < $1.key }
        return StoreReadResult(entries: entries)
    }

    public func write(key: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        backing[key] = data
    }

    public func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        backing[key] = nil
    }
}

/// Provee el directorio base donde el almacén atómico escribe sus archivos.
public protocol RepositoryDirectoryProviding: Sendable {
    func directoryURL() throws -> URL
}

/// Almacén respaldado por archivos con escritura atómica (temp + rename).
/// Un fallo a mitad de escritura jamás corrompe el archivo previo, garantizando
/// que el save local sea autoritativo frente a cualquier fallo posterior de sync.
public struct AtomicFileRepositoryStore: RepositoryStore {
    private let directory: URL
    private let encoder: JSONEncoder

    public init(directoryProvider: RepositoryDirectoryProviding) throws {
        try self.init(directory: directoryProvider.directoryURL())
    }

    /// Almacén sobre un directorio concreto (una colección).
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        self.encoder = JSONEncoder()
    }

    public func read(key: String) throws -> Data? {
        let url = self.directory.appendingPathComponent(key + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func readAll() throws -> [Data] {
        try readAllEntries().entries.map(\.data)
    }

    /// Sólo `*.json` del propio directorio (no subdirectorios ni `*.json.tmp` de una
    /// escritura interrumpida). Orden estable por clave.
    public func readAllEntries() throws -> StoreReadResult {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        var entries: [StoredEntry] = []
        var unreadable: [String] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "json" {
            let key = url.deletingPathExtension().lastPathComponent
            do {
                entries.append(StoredEntry(key: key, data: try Data(contentsOf: url)))
            } catch {
                unreadable.append(key)
            }
        }
        return StoreReadResult(entries: entries, unreadableKeys: unreadable)
    }

    public func write(key: String, data: Data) throws {
        let url = self.directory.appendingPathComponent(key + ".json")
        let temp = self.directory.appendingPathComponent(key + ".json.tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    public func delete(key: String) throws {
        let url = self.directory.appendingPathComponent(key + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
