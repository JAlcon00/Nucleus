//
//  TrainingVocabularyPresenterTests.swift
//  PRCoreTests
//
//  SCRUM-195 (U6): los títulos estables del planificador se ven con el vocabulario de
//  gimnasio en español (Push, Pull, Pierna, Torso, Cuerpo completo), conservando la letra
//  de rotación; un título desconocido no se reemplaza por otro inventado.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Vocabulario de sesión y músculos (SCRUM-195)")
struct TrainingVocabularyPresenterTests {

    private let spanish = TrainingVocabularyPresenter(locale: Locale(identifier: "es_MX"))
    private let english = TrainingVocabularyPresenter(locale: Locale(identifier: "en_US"))

    @Test("Push/Pull/Legs: Push, Pull y Pierna")
    func pushPullLegs() {
        #expect(spanish.sessionName("Push") == "Push")
        #expect(spanish.sessionName("Pull") == "Pull")
        #expect(spanish.sessionName("Legs") == "Pierna")
    }

    @Test("Upper/Lower: Torso y Pierna, con su letra de rotación")
    func upperLowerKeepsRotationLetter() {
        #expect(spanish.sessionName("Upper A") == "Torso A")
        #expect(spanish.sessionName("Lower B") == "Pierna B")
    }

    @Test("Full Body: Cuerpo completo, con y sin letra")
    func fullBody() {
        #expect(spanish.sessionName("Full Body") == "Cuerpo completo")
        #expect(spanish.sessionName("Full Body C") == "Cuerpo completo C")
    }

    @Test("Títulos que no son del planificador se muestran tal cual")
    func unknownTitlesPassThrough() {
        #expect(spanish.sessionName("Torso y tríceps") == "Torso y tríceps")
        #expect(spanish.sessionName("Push day") == "Push day")
        #expect(spanish.sessionName("Legs b") == "Legs b")
        #expect(spanish.sessionName("") == "")
    }

    @Test("Cada título que genera el planificador tiene nombre en español")
    func everyPlannerTitleIsTranslated() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        for days in TrainingWeek.allowedTrainingDays {
            let profile = OnboardingProfile(
                goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
                trainingDaysPerWeek: days, usualSessionMinutes: 60, varietyPreference: .balanced
            )
            let block = try TodayPlanBuilder().generate(
                profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()
            ).block
            for session in block.sessions {
                let name = spanish.sessionName(session.title)
                #expect(!["Legs", "Upper", "Lower", "Full Body"].contains { name.hasPrefix($0) },
                        "'\(session.title)' (\(days) días) quedó en inglés: '\(name)'")
            }
        }
    }

    @Test("Músculos en español, sin nombres internos")
    func muscleNames() {
        #expect(spanish.muscleName(.back) == "Espalda")
        #expect(spanish.muscleName(.biceps) == "Bíceps")
        #expect(spanish.muscleName(.forearms) == "Antebrazo")
        for muscle in MuscleGroup.allCases {
            let name = spanish.muscleName(muscle)
            #expect(!name.isEmpty)
            #expect(name.lowercased() != muscle.rawValue.lowercased() || muscle == .biceps)
        }
    }

    @Test("Días: inicial distinta para martes y miércoles, nombre completo para VoiceOver (SCRUM-196)")
    func weekdays() {
        #expect(WeekDay.allCases.map(spanish.weekdayInitial) == ["L", "M", "Mi", "J", "V", "S", "D"])
        #expect(WeekDay.allCases.map(spanish.weekdayName) == ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"])
        #expect(Set(WeekDay.allCases.map(spanish.weekdayInitial)).count == 7, "Las iniciales no deben repetirse")
    }

    @Test("En inglés el catálogo trae su traducción")
    func englishTranslation() {
        #expect(english.sessionName("Legs") == "Legs")
        #expect(english.sessionName("Upper A") == "Upper body A")
        #expect(english.muscleName(.chest) == "Chest")
    }
}
