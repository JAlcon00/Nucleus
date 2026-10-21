//
//  PRCelebrationPresenterTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests del presentador de PR-1004: textos localizados desde el String Catalog de
//  PRCore (RNF-013), unidad real sin conversión, singular/plural, nombre genérico si
//  el ejercicio no está en el catálogo y anuncio VoiceOver. Locale inyectado.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("PR celebration presenter (PR-1004)")
struct PRCelebrationPresenterTests {

    private let bench = ExerciseID()
    private let row = ExerciseID()
    private let spanish = PRCelebrationPresenter(locale: Locale(identifier: "es_MX"))
    private let englishPresenter = PRCelebrationPresenter(locale: Locale(identifier: "en_US"))

    private struct Record {
        let id: ExerciseID
        let name: String?
        let weight: Double
        var unit: LoadUnit = .kilograms
        var reps: Int = 8
    }

    /// La celebración la decide siempre el dominio (`PRCelebrationBuilder`); el test sólo
    /// verifica cómo se dice. Los récords van en orden: el índice fija `achievedAt`.
    private func celebration(_ records: [Record], level: CoachingDetailLevel = .advanced) throws -> PRCelebration {
        var names: [ExerciseID: String] = [:]
        let personalRecords = records.enumerated().map { index, record in
            names[record.id] = record.name
            return PersonalRecord(
                exerciseID: record.id,
                weight: record.weight,
                unit: record.unit,
                reps: record.reps,
                achievedAt: Date(timeIntervalSinceReferenceDate: Double(index))
            )
        }
        return try #require(PRCelebrationBuilder().celebration(for: personalRecords, exerciseNames: names, level: level))
    }

    @Test("Un récord: titular, fila con carga y reps, y anuncio en español")
    func singleRecordSpanish() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: "Press banca", weight: 85)]))
        #expect(presentation.headline == "Nuevo récord")
        #expect(presentation.rows.map(\.exerciseName) == ["Press banca"])
        #expect(presentation.rows.map(\.loadText) == ["85 kg × 8"])
        #expect(presentation.detail == nil)
        #expect(presentation.accessibilityAnnouncement == "Nuevo récord: Press banca, 85 kilogramos por 8 repeticiones.")
    }

    @Test("Singular: 1 repetición y 1 kilogramo")
    func singular() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: "Press banca", weight: 1, reps: 1)]))
        #expect(presentation.accessibilityAnnouncement == "Nuevo récord: Press banca, 1 kilogramo por 1 repetición.")
    }

    @Test("Libras: se muestra la unidad registrada, sin convertir")
    func poundsNotConverted() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: "Press banca", weight: 185, unit: .pounds, reps: 6)]))
        #expect(presentation.rows.first?.loadText == "185 lb × 6")
        #expect(presentation.accessibilityAnnouncement.contains("185 libras"))
    }

    @Test("Decimal con una cifra")
    func decimal() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: "Press banca", weight: 82.5)]))
        #expect(presentation.rows.first?.loadText == "82.5 kg × 8")
    }

    @Test("Varios récords: titular con número y lista con 'y'")
    func multipleRecords() throws {
        let presentation = spanish.present(try celebration(
            [Record(id: bench, name: "Press banca", weight: 85), Record(id: row, name: "Remo", weight: 70)],
            level: .balanced
        ))
        #expect(presentation.headline == "2 nuevos récords")
        #expect(presentation.detail == "Superaste tu mejor carga registrada.")
        #expect(presentation.accessibilityAnnouncement
            == "2 nuevos récords: Press banca, 85 kilogramos por 8 repeticiones y Remo, 70 kilogramos por 8 repeticiones.")
    }

    @Test("Guided: la explicación menciona sobrecarga progresiva")
    func guidedDetail() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: "Press banca", weight: 85)], level: .guided))
        #expect(presentation.detail?.contains("sobrecarga progresiva") == true)
    }

    @Test("Ejercicio sin nombre en catálogo: nombre genérico localizado")
    func genericName() throws {
        let presentation = spanish.present(try celebration([Record(id: bench, name: nil, weight: 85)]))
        #expect(presentation.rows.first?.exerciseName == "Ejercicio")
    }

    @Test("Locale de presentación: idioma de la app con región del usuario")
    func presentationLocaleUsesAppLanguageAndUserRegion() throws {
        let locale = PRCelebrationPresenter.presentationLocale(appLanguage: "es", userLocale: Locale(identifier: "en_US"))
        #expect(locale.language.languageCode?.identifier == "es")
        #expect(locale.region?.identifier == "US")
        let presentation = PRCelebrationPresenter(locale: locale)
            .present(try celebration([Record(id: bench, name: "Press banca", weight: 85)]))
        #expect(presentation.headline == "Nuevo récord")
    }

    @Test("Formato regional del usuario aunque el idioma sea el de la app")
    func presentationLocaleKeepsRegionalFormatting() throws {
        let locale = PRCelebrationPresenter.presentationLocale(appLanguage: "es", userLocale: Locale(identifier: "de_DE"))
        let presentation = PRCelebrationPresenter(locale: locale)
            .present(try celebration([Record(id: bench, name: "Press banca", weight: 82.5)]))
        #expect(presentation.rows.first?.loadText == "82,5 kg × 8")
    }

    @Test("Sin idioma de app resuelto se usa el locale del usuario tal cual")
    func presentationLocaleWithoutAppLanguage() {
        let user = Locale(identifier: "es_MX")
        #expect(PRCelebrationPresenter.presentationLocale(appLanguage: nil, userLocale: user) == user)
        #expect(PRCelebrationPresenter.presentationLocale(appLanguage: "", userLocale: user) == user)
    }

    @Test("Inglés desde el mismo catálogo (preparado para RNF-013)")
    func englishFromCatalog() throws {
        let presentation = englishPresenter.present(try celebration(
            [Record(id: bench, name: "Bench press", weight: 185, unit: .pounds, reps: 1)],
            level: .balanced
        ))
        #expect(presentation.headline == "New record")
        #expect(presentation.detail == "You beat your best recorded load.")
        #expect(presentation.accessibilityAnnouncement == "New record: Bench press, 185 pounds for 1 repetition.")
    }
}
