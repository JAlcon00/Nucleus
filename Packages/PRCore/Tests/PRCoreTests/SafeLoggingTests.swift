//
//  SafeLoggingTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de PR-0003 (Logging seguro): el wrapper usa `Logger`, expone las seis
//  categorías y la redacción (formateo propio) NUNCA deja notas de lesión, samples
//  de salud, tokens ni Apple identifiers; los valores no sensibles se conservan.
//

import Foundation
import Testing
@testable import PRCore

@Suite("Safe logging (PR-0003)")
struct SafeLoggingTests {

    let redactor = LogRedactor()

    // MARK: - Categorías

    @Test("El wrapper expone las seis categorías del spec")
    func exposesSixCategories() {
        #expect(LogCategory.allCases == [.app, .workout, .health, .sync, .agent, .persistence])
        #expect(LogCategory.allCases.count == 6)
    }

    @Test("PRLogger construye un logger sobre os.Logger con la categoría correcta")
    func buildsLoggerPerCategory() {
        for category in LogCategory.allCases {
            let logger = PRLogger(category: category)
            #expect(logger.category == category)
        }
    }

    // MARK: - Prohibido loggear payloads sensibles (redacción)

    @Test("La nota de lesión se redacta")
    func redactsInjuryNote() {
        let note = "nota de lesión: dolor agudo en hombro derecho al press"
        #expect(redactor.wouldExpose(note))
        let safe = redactor.redact(note)
        #expect(safe.contains(LogRedactor.placeholder))
        #expect(!safe.localizedCaseInsensitiveContains("hombro"))
        #expect(!safe.localizedCaseInsensitiveContains("manguito"))
    }

    @Test("La entrada de dolor/lesión por clave prohibida se oculta entera")
    func redactsForbiddenEntryByKey() {
        #expect(redactor.redactEntry(key: "injuryNote", value: "calcificación en manguito rotador") == LogRedactor.placeholder)
        #expect(redactor.redactEntry(key: "painFeedback", value: "sharpPain en muñeca") == LogRedactor.placeholder)
        #expect(redactor.redactEntry(key: "healthSampleID", value: "uuid") == LogRedactor.placeholder)
    }

    @Test("El sample de salud (id UUID) se redacta")
    func redactsHealthSampleID() {
        let sampleId = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let raw = "Guardado sample de salud \(sampleId)"
        let safe = redactor.redact(raw)
        #expect(!safe.contains(sampleId))
        #expect(safe.contains(LogRedactor.placeholder))
    }

    @Test("El token se redacta por prefijo conocido (Bearer / sk- / tok_)")
    func redactsTokens() {
        #expect(redactor.redact("Authorization: Bearer \(String(repeating: "a", count: 24))") == "Authorization: \(LogRedactor.placeholder)")
        #expect(redactor.redact("apiKey sk-ABCDEFGHIJKLMNOP") == "apiKey \(LogRedactor.placeholder)")
        #expect(redactor.redact("token= tok_\(String(describing: UUID().uuidString))") == "token= \(LogRedactor.placeholder)")
    }

    @Test("El valor sensible explícito (p. ej. JWT) se reemplaza entero")
    func redactsExplicitSensitiveValue() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let safe = redactor.redact("sesión JWT \(jwt) iniciada", sensitiveValues: [jwt])
        #expect(!safe.contains(jwt))
        #expect(safe.contains(LogRedactor.placeholder))
    }

    @Test("El Apple identifier etiquetado se redacta")
    func redactsAppleIdentifier() {
        let user = "000524.93a3f4f5c48c4b4b8a2e9f0d1e2f3a4b.1122"
        let safe = redactor.redact("login firmado userIdentifier=\(user)")
        #expect(!safe.contains(user))
        #expect(safe.contains(LogRedactor.placeholder))
    }

    @Test("La entrada con clave token/secret se oculta entera aunque el valor parezca inocuo")
    func redactsTokenEntryWhole() {
        #expect(redactor.redactEntry(key: "authorizationCode", value: "abc") == LogRedactor.placeholder)
        #expect(redactor.redactEntry(key: "secret", value: "valor") == LogRedactor.placeholder)
    }

    @Test("Los datos no sensibles se conservan")
    func preservesNonSensitiveData() {
        let raw = "workout #12 finalizado: 5 series de Press Banca, 42.5 kg"
        #expect(!redactor.wouldExpose(raw))
        #expect(redactor.redact(raw) == raw)
        #expect(redactor.redactEntry(key: "sets", value: "5") == "5")
        #expect(redactor.redactEntry(key: "durationMinutes", value: "48") == "48")
    }
}