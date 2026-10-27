//
//  PersistenceMigration.swift
//  PRCore
//
//  Created by PR.
//
//  Migración única del layout antiguo (SCRUM-23): antes todas las colecciones
//  escribían sus `*.json` directamente en la raíz de persistencia. Esta migración
//  mueve cada archivo de la raíz a su colección (`LocalPersistence`).
//
//  Reglas:
//  - clasifica por CONTENIDO: un archivo va a una colección sólo si decodifica como
//    exactamente un tipo; si encaja con ninguno o con varios se deja en la raíz
//    (nunca se adivina);
//  - nunca borra antes de haber escrito el destino y verificado que lo leído es igual;
//  - si el destino ya tiene el mismo contenido (migración interrumpida), sólo borra el
//    origen; si tiene contenido distinto, conserva ambos (conflicto);
//  - idempotente: sin archivos en la raíz, no hace nada.
//

import Foundation
import PRDomain

public struct LegacyPersistenceMigration: Sendable {

    /// Resultado de una ejecución (conteos, sin datos personales).
    public struct Report: Equatable, Sendable {
        public var moved = 0
        public var alreadyMigrated = 0
        public var unclassified = 0
        public var conflicts = 0

        public init() {}

        public var didWork: Bool { moved + alreadyMigrated + unclassified + conflicts > 0 }
    }

    public init() {}

    /// Colección a la que pertenece un blob, decidida por el tipo que decodifica.
    /// `nil` si no decodifica como ningún tipo o como más de uno (ambiguo).
    public static func classify(_ data: Data) -> PersistenceCollection? {
        let matches = PersistenceCollection.allCases.filter { $0.decodes(data) }
        return matches.count == 1 ? matches.first : nil
    }

    /// Mueve los `*.json` de `root` (sólo el primer nivel) a su colección.
    public func run(
        root: URL,
        store: (PersistenceCollection) throws -> any RepositoryStore
    ) throws -> Report {
        var report = Report()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "json" && Self.isRegularFile(url) {
            let key = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let collection = Self.classify(data) else {
                // Ilegible o sin tipo único: se conserva intacto en la raíz.
                report.unclassified += 1
                continue
            }
            let destination = try store(collection)
            if let existing = try destination.read(key: key) {
                if existing == data {
                    try FileManager.default.removeItem(at: url)
                    report.alreadyMigrated += 1
                } else {
                    report.conflicts += 1
                }
                continue
            }
            try destination.write(key: key, data: data)
            // Verificación antes de borrar el origen: el destino debe leerse idéntico.
            guard try destination.read(key: key) == data else {
                report.conflicts += 1
                continue
            }
            try FileManager.default.removeItem(at: url)
            report.moved += 1
        }
        return report
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
