//
//  NVIDIAKeyLoader.swift
//  PRCore
//
//  Created by PR.
//
//  Carga la API key de NVIDIA en RUNTIME para prototipado (PR-1608, Phase N1).
//
//  SEGURIDAD (spec §22/§42, AGENTS "no store secrets in client"): la key NUNCA se
//  embebe en el binario ni en el repo. Se lee en runtime desde:
//    1) variable de entorno NVIDIA_API_KEY
//    2) archivo `.env` (gitignored) en el cwd o en la raíz del repo
//  y se inyecta vía `NVIDIAHostedConfig(apiKeyProvider:)`.
//
//  Esto es un shim de prototipado: en producción la app debe hablar con NUESTRO
//  backend y esta ruta no debe usarse (spec §21/§22).
//

import Foundation

/// Carga la API key de NVIDIA en runtime. Determinista y sin red.
public enum NVIDIAKeyLoader {
    /// Nombre de la variable de entorno.
    public static let environmentVariable = "NVIDIA_API_KEY"
    static let envKey = "NVIDIA_API_KEY"

    /// Key en runtime, o nil si no está disponible en el entorno ni en `.env`.
    public static func load() -> String? {
        let processEnv = ProcessInfo.processInfo.environment[environmentVariable]
        if let key = processEnv, !key.isEmpty { return key }

        if let fromFile = loadFromDotEnv() { return fromFile }

        return nil
    }

    /// Lee `NVIDIA_API_KEY=` de un archivo `.env`.
    static func loadFromDotEnv() -> String? {
        for candidate in dotEnvCandidates {
            guard let value = parseKey(from: candidate) else { continue }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Candidatos de ubicación para `.env`, desde el más específico.
    static var dotEnvCandidates: [URL] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NVIDIAKeyLoader.swift
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // PRCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
        return [
            cwd.appendingPathComponent(".env"),
            repoRoot.appendingPathComponent(".env"),
        ]
    }

    static func parseKey(from url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in contents.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("NVIDIA_API_KEY=") else { continue }
            let value = line.dropFirst("NVIDIA_API_KEY=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value
        }
        return nil
    }
}
