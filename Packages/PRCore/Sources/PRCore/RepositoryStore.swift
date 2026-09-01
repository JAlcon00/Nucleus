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

/// Operaciones de bajo nivel sobre un almacén de pares clave → blob (Data).
/// `key` es la cadena de persistencia (normalmente `id.rawValue.persistenceKey`).
public protocol RepositoryStore: Sendable {
    func read(key: String) throws -> Data?
    func readAll() throws -> [Data]
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
        let dir = try directoryProvider.directoryURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        self.encoder = JSONEncoder()
    }

    public func read(key: String) throws -> Data? {
        let url = self.directory.appendingPathComponent(key + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func readAll() throws -> [Data] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return try urls.filter { $0.pathExtension == "json" }.map { try Data(contentsOf: $0) }
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
