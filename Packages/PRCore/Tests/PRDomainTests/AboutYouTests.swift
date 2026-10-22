//
//  AboutYouTests.swift
//  PRDomainTests
//
//  SCRUM-198 (U5): "Sobre ti". Edad (guardada como año de nacimiento), sexo con opción
//  neutral y peso son obligatorios; nombre y estatura, opcionales. Con menos de 18 años
//  no se puede continuar (política v1). Un perfil guardado antes no tiene "Sobre ti" y se
//  sigue leyendo; cambiar sólo "Sobre ti" no toca el bloque.
//

import Foundation
import Testing
@testable import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

/// 21 de octubre de 2026, mediodía UTC.
private func today() throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 21
    components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private func complete(age: Int = 30) -> AboutYouAnswer {
    AboutYouAnswer(name: "  Jesús ", age: age, sex: .male, heightCentimeters: 175, weight: 72.46, weightUnit: .kilograms)
}

@Suite("Sobre ti (SCRUM-198)")
struct AboutYouTests {

    // MARK: - Respuesta en curso

    @Test("Con edad, sexo y peso se puede continuar; nombre y estatura son opcionales")
    func requiredFields() {
        #expect(complete().isComplete)
        #expect(AboutYouAnswer(age: 30, sex: .undisclosed, weight: 60).isComplete, "'Prefiero no decir' es válido y lo demás es opcional")
        #expect(!AboutYouAnswer(sex: .female, weight: 60).isComplete, "Sin edad no")
        #expect(!AboutYouAnswer(age: 30, weight: 60).isComplete, "Sin sexo no")
        #expect(!AboutYouAnswer(age: 30, sex: .female).isComplete, "Sin peso no")
    }

    @Test("Menos de 18 años: no se puede continuar y se explica", arguments: [16, 17])
    func underMinimumAge(age: Int) {
        let answer = complete(age: age)
        #expect(answer.isUnderMinimumAge)
        #expect(!answer.isComplete)
        #expect(throws: AboutYouError.underMinimumAge(age)) {
            _ = try answer.aboutYou(on: try today(), timeZone: utc)
        }
    }

    @Test("18 años exactos sí puede continuar")
    func minimumAgeIsAllowed() {
        #expect(AboutYou.minimumAge == 18)
        #expect(complete(age: 18).isComplete)
        #expect(!complete(age: 18).isUnderMinimumAge)
    }

    @Test("Estatura o peso fuera de rango no dejan continuar")
    func outOfRangeValues() {
        var tall = complete()
        tall.heightCentimeters = 260
        #expect(!tall.isComplete)
        var light = complete()
        light.weight = 10
        #expect(!light.isComplete)
        var pounds = complete()
        pounds.weight = 160
        pounds.weightUnit = .pounds
        #expect(pounds.isComplete, "160 lb es un peso válido")
    }

    // MARK: - Conversión

    @Test("La edad se guarda como año de nacimiento; nombre recortado; peso con un decimal")
    func conversion() throws {
        let aboutYou = try complete(age: 30).aboutYou(on: try today(), timeZone: utc)
        #expect(aboutYou.birthYear == 1996)
        #expect(aboutYou.age(on: try today(), timeZone: utc) == 30)
        #expect(aboutYou.name == "Jesús")
        #expect(aboutYou.weight == 72.5)
        #expect(aboutYou.sex == .male)
        #expect(aboutYou.heightCentimeters == 175)
    }

    @Test("Nombre vacío queda sin nombre; demasiado largo se rechaza")
    func names() throws {
        let blank = try AboutYou(name: "   ", birthYear: 1990, sex: .female, heightCentimeters: nil, weight: 60, weightUnit: .kilograms)
        #expect(blank.name == nil)
        let long = String(repeating: "a", count: AboutYou.maxNameLength + 1)
        #expect(throws: AboutYouError.nameTooLong(AboutYou.maxNameLength + 1)) {
            _ = try AboutYou(name: long, birthYear: 1990, sex: .female, heightCentimeters: nil, weight: 60, weightUnit: .kilograms)
        }
    }

    @Test("Volver a editar parte de lo guardado")
    func answerFromStored() throws {
        let stored = try complete(age: 41).aboutYou(on: try today(), timeZone: utc)
        let answer = AboutYouAnswer(stored, on: try today(), timeZone: utc)
        #expect(answer.age == 41)
        #expect(answer.name == "Jesús")
        #expect(answer.isComplete)
    }

    // MARK: - Perfil guardado

    @Test("Perfil de la versión anterior (sin 'Sobre ti'): se lee igual y queda sin datos")
    func previousVersionProfileHasNoAboutYou() throws {
        let json = """
        {"goal":"hypertrophy","phase":"maintenance","experience":"intermediate","trainingDaysPerWeek":3,\
        "trainingWeekdays":["monday","wednesday","friday"],"usualSessionMinutes":60,"varietyPreference":"balanced","restrictions":[]}
        """
        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: Data(json.utf8))
        #expect(profile.aboutYou == nil)
        #expect(profile.trainingWeekdays == [.monday, .wednesday, .friday])
    }

    @Test("Ida y vuelta con 'Sobre ti'")
    func roundTrip() throws {
        var profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .thursday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        profile.aboutYou = try complete().aboutYou(on: try today(), timeZone: utc)
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test("Un 'Sobre ti' guardado dañado (peso imposible) no se acepta al leer")
    func corruptStoredAboutYouIsRejected() {
        let json = """
        {"birthYear":1990,"sex":"female","weight":5000,"weightUnit":"kilograms"}
        """
        #expect(throws: AboutYouError.self) {
            _ = try JSONDecoder().decode(AboutYou.self, from: Data(json.utf8))
        }
    }

    // MARK: - Cambio de plan

    @Test("Cambiar sólo 'Sobre ti' guarda el perfil sin tocar el bloque")
    func aboutYouChangeKeepsBlock() throws {
        let base = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        var withData = base
        withData.aboutYou = try complete().aboutYou(on: try today(), timeZone: utc)
        #expect(PlanChangeDecider.decide(old: base, new: withData) == .updateProfileOnly)
        #expect(PlanChangeDecider.decide(old: withData, new: withData) == .unchanged)
        var moreMinutes = withData
        moreMinutes.usualSessionMinutes = 75
        #expect(PlanChangeDecider.decide(old: base, new: moreMinutes) == .regenerateInPlace)
    }
}
