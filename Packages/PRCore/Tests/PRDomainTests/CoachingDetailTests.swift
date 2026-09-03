import Testing
import Foundation
@testable import PRDomain

@Suite("Coaching detail initial mapping (PR-0403)")
struct CoachingDetailTests {

    private let mapper = CoachingDetailMapper()

    @Test("novice y beginner mapean a guided")
    func noviceBeginnerToGuided() {
        #expect(mapper.initialDefault(for: .novice) == .guided)
        #expect(mapper.initialDefault(for: .beginner) == .guided)
    }

    @Test("intermediate mapea a balanced")
    func intermediateToBalanced() {
        #expect(mapper.initialDefault(for: .intermediate) == .balanced)
    }

    @Test("advanced y competitive mapean a advanced")
    func advancedCompetitiveToAdvanced() {
        #expect(mapper.initialDefault(for: .advanced) == .advanced)
        #expect(mapper.initialDefault(for: .competitive) == .advanced)
    }

    @Test("el mapping es cubierto y determinista para todas las experiencias")
    func mappingIsExhaustiveAndDeterministic() {
        let results = ExperienceLevel.allCases.map { mapper.initialDefault(for: $0) }
        // Todos los niveles producen un resultado válido y estable.
        #expect(results.count == ExperienceLevel.allCases.count)
        #expect(results == ExperienceLevel.allCases.map { mapper.initialDefault(for: $0) })
    }

    @Test("defaulted produce nivel por experiencia y source defaultByExperience")
    func defaultedUsesExperience() {
        let prefs = CoachingDetailPrefs.defaulted(for: .novice, mapper: mapper)
        #expect(prefs.level == .guided)
        #expect(prefs.source == .defaultByExperience)
        #expect(prefs.isUserChosen == false)
    }

    @Test("override manual manda sobre el default y se marca como userChosen")
    func manualOverrideWins() {
        var prefs = CoachingDetailPrefs.defaulted(for: .novice, mapper: mapper) // guided
        prefs.applyManualOverride(.advanced)

        #expect(prefs.level == .advanced)
        #expect(prefs.source == .manualOverride)
        #expect(prefs.isUserChosen == true)
    }

    @Test("aplicar un override igual al default sí lo marca como manual (elección explícita)")
    func overrideWithSameLevelMarksManual() {
        // novice → guided; el usuario elige guided explícitamente → se registra como manual.
        var prefs = CoachingDetailPrefs.defaulted(for: .novice, mapper: mapper)
        prefs.applyManualOverride(.guided)

        #expect(prefs.level == .guided)
        #expect(prefs.source == .manualOverride)
        #expect(prefs.isUserChosen == true)
    }

    @Test("aplicando override de forma inmutable devuelve nueva instancia sin mutar la original")
    func immutableOverrideDoesNotMutate() {
        let original = CoachingDetailPrefs.defaulted(for: .intermediate, mapper: mapper) // balanced
        let overridden = original.applyingManualOverride(.guided)

        #expect(original.level == .balanced)
        #expect(original.source == .defaultByExperience)
        #expect(overridden.level == .guided)
        #expect(overridden.source == .manualOverride)
    }

    @Test("resetting vuelve al default por nueva experiencia y limpia el override")
    func resettingReturnsToDefaultForNewExperience() {
        var prefs = CoachingDetailPrefs.defaulted(for: .novice, mapper: mapper)
        prefs.applyManualOverride(.advanced)

        let reset = prefs.resetting(toDefaultFor: .advanced, mapper: mapper)
        #expect(reset.level == .advanced)
        #expect(reset.source == .defaultByExperience)
        #expect(reset.isUserChosen == false)
    }

    @Test("el usuario puede cambiar manualmente desde cualquier default (PR-0403)")
    func manualChangeFromAnyDefault() {
        for experience in ExperienceLevel.allCases {
            let prefs = CoachingDetailPrefs.defaulted(for: experience, mapper: mapper)
            let overridden = prefs.applyingManualOverride(.balanced)
            #expect(overridden.source == .manualOverride)
            #expect(overridden.level == .balanced)
        }
    }
}