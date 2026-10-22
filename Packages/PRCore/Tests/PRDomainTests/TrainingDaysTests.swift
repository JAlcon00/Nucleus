//
//  TrainingDaysTests.swift
//  PRDomainTests
//
//  SCRUM-196 (U3): la persona elige qué días entrena (L, Mi, V…) y el descanso queda
//  intercalado. Los slots de sesión se asignan en orden a los días elegidos. Un perfil
//  guardado antes (sólo "N días") se lee como los primeros N días desde el lunes, que era
//  el comportamiento anterior: ningún plan cambia en silencio.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Días de entrenamiento elegidos (SCRUM-196)")
struct TrainingDaysTests {

    // MARK: - Reparto por defecto

    @Test("Por defecto los días van espaciados según cuántos son", arguments: [
        (2, [WeekDay.monday, .thursday]),
        (3, [.monday, .wednesday, .friday]),
        (4, [.monday, .tuesday, .thursday, .friday]),
        (5, [.monday, .tuesday, .wednesday, .friday, .saturday]),
        (6, [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]),
        (7, WeekDay.allCases),
    ])
    func spacedDefaults(count: Int, expected: [WeekDay]) throws {
        let days = try TrainingWeek.spacedDays(count: count)
        #expect(days == Set(expected))
        #expect(try TrainingWeek(trainingDays: days).orderedDays == expected)
    }

    @Test("Un número de días fuera de 2...7 no tiene reparto por defecto")
    func spacedDefaultsRejectOutOfRange() {
        for count in [0, 1, 8] {
            #expect(throws: TrainingWeekError.invalidTrainingDays(count)) {
                _ = try TrainingWeek.spacedDays(count: count)
            }
        }
    }

    // MARK: - Slots en orden a los días elegidos

    @Test("Lunes, miércoles y viernes: slots 0, 1 y 2; el resto descansa")
    func slotsFollowChosenDays() throws {
        let week = try TrainingWeek(trainingDays: [.monday, .wednesday, .friday])
        let slots = (0..<TrainingWeek.daysInWeek).map { week.sessionSlot(dayIndex: $0) }
        #expect(slots == [0, nil, 1, nil, 2, nil, nil])
        #expect(week.trainingDaysPerWeek == 3)
        #expect(!week.isTrainingDay(dayIndex: 1))
        #expect(week.isTrainingDay(dayIndex: 4))
    }

    @Test("Sólo fin de semana: sábado es el slot 0 y domingo el 1")
    func weekendOnly() throws {
        let week = try TrainingWeek(trainingDays: [.sunday, .saturday])
        #expect(week.sessionSlot(dayIndex: 5) == 0)
        #expect(week.sessionSlot(dayIndex: 6) == 1)
        #expect(week.sessionSlot(dayIndex: 0) == nil)
    }

    @Test("Menos de 2 días elegidos se rechaza (nunca se inventa otro día)")
    func tooFewDaysThrow() {
        #expect(throws: TrainingWeekError.invalidTrainingDays(0)) {
            _ = try TrainingWeek(trainingDays: [])
        }
        #expect(throws: TrainingWeekError.invalidTrainingDays(1)) {
            _ = try TrainingWeek(trainingDays: [.monday])
        }
    }

    @Test("Un índice de día inválido no tiene slot")
    func invalidDayIndexHasNoSlot() throws {
        let week = try TrainingWeek(trainingDays: Set(WeekDay.allCases))
        #expect(week.sessionSlot(dayIndex: -1) == nil)
        #expect(week.sessionSlot(dayIndex: 7) == nil)
    }

    @Test("Índice lunes = 0 … domingo = 6 de ida y vuelta")
    func weekdayIndexRoundTrip() {
        for (index, day) in WeekDay.allCases.enumerated() {
            #expect(day.mondayBasedIndex == index)
            #expect(WeekDay(mondayBasedIndex: index) == day)
        }
        #expect(WeekDay(mondayBasedIndex: 7) == nil)
        #expect(WeekDay(mondayBasedIndex: -1) == nil)
    }

    // MARK: - Compatibilidad (perfiles con "N días")

    @Test("Semana antigua de N días = los primeros N días desde el lunes")
    func legacyWeekIsFirstDays() throws {
        let week = try TrainingWeek(trainingDaysPerWeek: 3)
        #expect(week.trainingDays == [.monday, .tuesday, .wednesday])
        #expect(week.sessionSlot(dayIndex: 2) == 2)
        #expect(week.sessionSlot(dayIndex: 3) == nil)
    }

    @Test("Perfil con el constructor de N días: mismos días que antes")
    func legacyProfileInitKeepsFirstDays() throws {
        let profile = makeProfile(days: 4)
        #expect(profile.trainingWeekdays == [.monday, .tuesday, .wednesday, .thursday])
        #expect(try profile.trainingWeek().trainingDays == [.monday, .tuesday, .wednesday, .thursday])
    }

    @Test("Perfil con N fuera de rango sigue siendo inválido (no se recorta a 7)")
    func legacyProfileOutOfRangeStaysInvalid() {
        let profile = makeProfile(days: 9)
        #expect(profile.trainingWeekdays == nil)
        #expect(throws: TrainingWeekError.invalidTrainingDays(9)) {
            _ = try profile.trainingWeek()
        }
    }

    @Test("Perfil con días elegidos: el número sale de los días")
    func chosenDaysProfile() throws {
        let profile = try makeProfile(chosen: [.monday, .wednesday, .friday])
        #expect(profile.trainingDaysPerWeek == 3)
        #expect(profile.trainingWeekdays == [.monday, .wednesday, .friday])
    }

    // MARK: - Migración del perfil guardado (fixture de la versión anterior)

    /// Así guardaba la versión anterior el perfil (sin `trainingWeekdays`).
    private static let previousVersionProfileJSON = """
    {"goal":"hypertrophy","phase":"maintenance","experience":"intermediate","trainingDaysPerWeek":3,\
    "usualSessionMinutes":60,"varietyPreference":"balanced","restrictions":[]}
    """

    @Test("Fixture anterior: se lee como los primeros N días desde el lunes")
    func previousVersionProfileMigratesToFirstDays() throws {
        let data = Data(Self.previousVersionProfileJSON.utf8)
        let profile = try JSONDecoder().decode(OnboardingProfile.self, from: data)
        #expect(profile.trainingDaysPerWeek == 3)
        #expect(profile.trainingWeekdays == [.monday, .tuesday, .wednesday])
        #expect(profile.goal == .hypertrophy)
        #expect(profile.usualSessionMinutes == 60)
        #expect(profile.defaultGymID == nil)
    }

    @Test("Ida y vuelta: los días elegidos se guardan y se leen iguales")
    func chosenDaysRoundTrip() throws {
        let profile = try makeProfile(chosen: [.tuesday, .thursday, .saturday])
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
        #expect(decoded.trainingWeekdays == [.tuesday, .thursday, .saturday])
    }

    @Test("Días guardados que no cuadran con N: el perfil es ilegible (no se adivina)")
    func inconsistentStoredDaysAreUnreadable() {
        let json = """
        {"goal":"hypertrophy","phase":"maintenance","experience":"intermediate","trainingDaysPerWeek":4,\
        "trainingWeekdays":["monday","friday"],"usualSessionMinutes":60,"varietyPreference":"balanced","restrictions":[]}
        """
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(OnboardingProfile.self, from: Data(json.utf8))
        }
    }

    // MARK: - Cambio de plan

    @Test("Mismos N días en otros días de la semana: se regenera el mismo bloque")
    func movingDaysKeepsTheBlock() throws {
        let old = try makeProfile(chosen: [.monday, .tuesday, .wednesday])
        let new = try makeProfile(chosen: [.monday, .wednesday, .friday])
        #expect(PlanChangeDecider.decide(old: old, new: new) == .regenerateInPlace)
    }

    @Test("Otro número de días: bloque nuevo (como antes)")
    func differentCountIsNewBlock() throws {
        let old = try makeProfile(chosen: [.monday, .wednesday, .friday])
        let new = try makeProfile(chosen: [.monday, .tuesday, .thursday, .friday])
        #expect(PlanChangeDecider.decide(old: old, new: new) == .newBlock)
    }

    @Test("Perfil anterior vs los mismos días elegidos: sin cambios")
    func legacyEqualsSameChosenDays() throws {
        let legacy = makeProfile(days: 3)
        let chosen = try makeProfile(chosen: [.monday, .tuesday, .wednesday])
        #expect(PlanChangeDecider.decide(old: legacy, new: chosen) == .unchanged)
    }

    // MARK: - Onboarding

    @Test("El paso de días registra los días elegidos y el número sale de ellos")
    func builderUsesChosenDays() throws {
        var draft = OnboardingDraft()
        draft = draft.settingAnswer(.goal(.hypertrophy), for: .goal)
        draft = draft.settingAnswer(.phase(.maintenance), for: .phase)
        draft = draft.settingAnswer(.experience(.intermediate), for: .experience)
        draft = draft.settingAnswer(.trainingDays([.monday, .wednesday, .friday]), for: .daysPerWeek)
        draft = draft.settingAnswer(.sessionMinutes(60), for: .sessionMinutes)
        draft = draft.settingAnswer(.gym(nil), for: .gym)
        draft = draft.settingAnswer(.variety(.balanced), for: .variety)
        draft = draft.settingAnswer(.restrictions([]), for: .restrictions)
        let profile = try OnboardingProfileBuilder().build(from: draft)
        #expect(profile.trainingWeekdays == [.monday, .wednesday, .friday])
        #expect(profile.trainingDaysPerWeek == 3)
    }

    @Test("Con un solo día elegido no se puede avanzar del paso")
    func cannotAdvanceWithOneDay() {
        var flow = OnboardingFlowController(startingIndex: OnboardingStep.ordered.firstIndex(of: .daysPerWeek) ?? 0)
        flow = flow.answering(.trainingDays([.monday]))
        #expect(!flow.canAdvance)
        flow = flow.answering(.trainingDays([.monday, .thursday]))
        #expect(flow.canAdvance)
    }

    @Test("El valor por defecto del paso son 4 días espaciados (L, M, J, V)")
    func defaultAnswerIsSpaced() {
        #expect(OnboardingDefaults.answer(for: .daysPerWeek) == .trainingDays([.monday, .tuesday, .thursday, .friday]))
    }

    // MARK: - Helpers

    private func makeProfile(days: Int) -> OnboardingProfile {
        OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDaysPerWeek: days, usualSessionMinutes: 60, varietyPreference: .balanced
        )
    }

    private func makeProfile(chosen: Set<WeekDay>) throws -> OnboardingProfile {
        try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: chosen, usualSessionMinutes: 60, varietyPreference: .balanced
        )
    }
}
