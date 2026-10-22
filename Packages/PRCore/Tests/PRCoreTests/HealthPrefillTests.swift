//
//  HealthPrefillTests.swift
//  PRCoreTests
//
//  SCRUM-206 (IA-5): Salud sólo prellena "Sobre ti" con valores que pasan las mismas
//  validaciones de `AboutYou`; sin datos, sin permiso o sin Salud el formulario sigue a
//  mano. Proveedor simulado: nunca toca HealthKit.
//

import Foundation
import Testing
import PRCore
import PRDomain

/// 2026-10-22 al mediodía UTC.
private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let utc = TimeZone(identifier: "UTC") ?? .gmt

private struct FakeReader: HealthProfileReading {
    let result: HealthReadResult
    func readProfile() async -> HealthReadResult { result }
}

private func birth(_ year: Int, _ month: Int = 6, _ day: Int = 15) -> DateComponents {
    DateComponents(year: year, month: month, day: day)
}

@Suite("Apple Salud prellena \"Sobre ti\" (SCRUM-206)")
struct HealthPrefillMapperTests {
    let mapper = HealthPrefillMapper()

    @Test("Con datos válidos llena edad, sexo, estatura y peso; el nombre no se toca")
    func fillsValidData() throws {
        let sample = HealthProfileSample(birthDate: birth(1994), biologicalSex: .female, heightMeters: 1.654, weightKilograms: 61.27)
        let result = mapper.prefill(AboutYouAnswer(name: "Ana"), with: sample, on: now, timeZone: utc)

        #expect(result.filled == Set(AboutYouHealthField.allCases))
        #expect(result.ignored.isEmpty)
        #expect(result.answer == AboutYouAnswer(name: "Ana", age: 32, sex: .female, heightCentimeters: 165, weight: 61.3))
        let aboutYou = try result.answer.aboutYou(on: now, timeZone: utc)
        #expect(aboutYou.birthYear == 1994, "El año guardado es el de Salud")
    }

    @Test("En libras convierte el peso con el factor exacto")
    func poundsConversion() {
        let sample = HealthProfileSample(weightKilograms: 80)
        let result = mapper.prefill(AboutYouAnswer(weightUnit: .pounds), with: sample, on: now, timeZone: utc)
        #expect(result.answer.weight == 176.4)
        #expect(result.answer.weightUnit == .pounds)
    }

    @Test("Fuera de rango se ignora y el campo queda como estaba")
    func outOfRangeIsIgnored() {
        let typed = AboutYouAnswer(age: 30, heightCentimeters: 170, weight: 70)
        let sample = HealthProfileSample(birthDate: birth(2020), heightMeters: 0.9, weightKilograms: 500)
        let result = mapper.prefill(typed, with: sample, on: now, timeZone: utc)

        #expect(result.filled.isEmpty)
        #expect(result.ignored == [.age, .height, .weight])
        #expect(result.answer == typed)
    }

    @Test("Sexo \"otro\" o sin indicar no se adivina")
    func sexIsNotGuessed() {
        for sex in [HealthBiologicalSex.other, .notSet] {
            let result = mapper.prefill(AboutYouAnswer(), with: HealthProfileSample(biologicalSex: sex), on: now, timeZone: utc)
            #expect(result.answer.sex == nil)
            #expect(result.filled.isEmpty)
        }
    }

    @Test("Menor de edad: se llena la edad y el formulario explica que no puede continuar (misma regla)")
    func underageFollowsSameRule() {
        let result = mapper.prefill(AboutYouAnswer(), with: HealthProfileSample(birthDate: birth(2009)), on: now, timeZone: utc)
        #expect(result.answer.age == 17)
        #expect(result.answer.isUnderMinimumAge)
        #expect(!result.answer.isComplete)
    }
}

@MainActor
@Suite("Botón \"Usar datos de Salud\" (SCRUM-206)")
struct HealthPrefillCoordinatorTests {

    private func coordinator(_ result: HealthReadResult?) -> HealthPrefillCoordinator {
        HealthPrefillCoordinator(reader: result.map { FakeReader(result: $0) }, clock: { now }, timeZone: { utc })
    }

    @Test("Con datos: devuelve el borrador lleno y dice cuántos campos")
    func withData() async {
        let sut = coordinator(.sample(HealthProfileSample(birthDate: birth(1990), biologicalSex: .male, weightKilograms: 300.4)))
        let answer = await sut.prefill(AboutYouAnswer())
        #expect(answer.age == 36)
        #expect(answer.sex == .male)
        #expect(answer.weight == nil, "300.4 kg queda fuera de rango")
        #expect(sut.state == .filled(filled: 2, ignored: 1))
    }

    @Test("Sin datos: el borrador no cambia y el aviso es \"sin datos\"")
    func withoutData() async {
        let typed = AboutYouAnswer(name: "Leo", age: 40)
        let sut = coordinator(.sample(.empty))
        #expect(await sut.prefill(typed) == typed)
        #expect(sut.state == .noData)
    }

    @Test("Permiso negado o Salud no disponible: el borrador no cambia y se avisa")
    func deniedAndUnavailable() async {
        let typed = AboutYouAnswer(age: 40)
        let denied = coordinator(.denied)
        #expect(await denied.prefill(typed) == typed)
        #expect(denied.state == .denied)
        let unavailable = coordinator(.unavailable)
        #expect(await unavailable.prefill(typed) == typed)
        #expect(unavailable.state == .unavailable)
    }

    @Test("Sin lector no se ofrece el botón y no hace nada")
    func notOffered() async {
        let sut = coordinator(nil)
        #expect(!sut.isOffered)
        #expect(await sut.prefill(AboutYouAnswer(age: 30)) == AboutYouAnswer(age: 30))
        #expect(sut.state == .idle)
    }
}
