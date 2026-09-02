//
//  NVIDIAKeyLoaderTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del loader de API key en runtime (PR-1608, Phase N1): parseo de `.env`,
//  precedencia de variable de entorno y ausencia de key sin red. Refuerza la
//  invariante "no store secrets in client": la key se lee, nunca se embebe.
//

import Foundation
import Testing
@testable import PRCore

@Suite("NVIDIA key loader (PR-1608, runtime only)")
struct NVIDIAKeyLoaderTests {

    @Test("Parsea NVIDIA_API_KEY de un .env")
    func parsesDotEnv() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-parse-\(UUID().uuidString).env")
        try! """
        # comentario
        OTRA_VAR=1
        NVIDIA_API_KEY=nvapi-runtime-123

        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NVIDIAKeyLoader.parseKey(from: url) == "nvapi-runtime-123")
    }

    @Test("Quita comillas simples/dobles y espacios del valor")
    func stripsQuotesAndWhitespace() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-quote-\(UUID().uuidString).env")
        try! "NVIDIA_API_KEY=\"nvapi-quoted \"\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NVIDIAKeyLoader.parseKey(from: url) == "nvapi-quoted")
    }

    @Test("Devuelve nil si el .env no define la key")
    func nilWhenMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-absent-\(UUID().uuidString).env")
        try! "OTRA_VAR=1\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NVIDIAKeyLoader.parseKey(from: url) == nil)
    }

    @Test("Archivo inexistente produce nil")
    func nilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-\(UUID().uuidString).env")
        #expect(NVIDIAKeyLoader.parseKey(from: url) == nil)
    }
}
