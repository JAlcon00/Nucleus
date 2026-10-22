//
//  AboutYouExportTests.swift
//  PRCoreTests
//
//  SCRUM-198 (U5): "Sobre ti" sólo entra al export si la persona lo elige; por defecto la
//  clave ni siquiera aparece en el JSON.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Export de 'Sobre ti' (SCRUM-198)")
struct AboutYouExportTests {

    @Test("Export: 'Sobre ti' sólo aparece si la persona lo elige")
    func exportIncludesAboutYouOnlyWhenChosen() throws {
        let aboutYou = try AboutYou(name: "Ana", birthYear: 1992, sex: .female, heightCentimeters: 165, weight: 61.5, weightUnit: .kilograms)
        let coordinator = DataExportCoordinator()
        let without = try coordinator.exportJSON(sessions: [], exercises: [], blocks: [], gyms: [], restrictions: [], profile: nil)
        let withAboutYou = try coordinator.exportJSON(
            sessions: [], exercises: [], blocks: [], gyms: [], restrictions: [], profile: nil, aboutYou: aboutYou
        )
        let plain = String(decoding: without.data, as: UTF8.self)
        let chosen = String(decoding: withAboutYou.data, as: UTF8.self)
        #expect(!plain.contains("aboutYou"))
        #expect(!plain.contains("birthYear"))
        #expect(chosen.contains("\"aboutYou\""))
        #expect(chosen.contains("1992"))
    }
}
