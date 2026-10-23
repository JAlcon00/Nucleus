//
//  WeekEndToEndTests.swift
//  PRCoreTests
//
//  Integración de punta a punta sobre `LocalPersistence` real:
//  - SCRUM-196 (U3): cuestionario real con lunes, miércoles y viernes → "Hoy" correcto los
//    7 días de la semana (entrena L/Mi/V con sesiones distintas; el resto descansa).
//  - SCRUM-197 (U4): con un plan real de 3 días, "Tu semana" coincide con "Hoy" los 7 días.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

/// Día de la semana del 19 de octubre de 2026 (lunes = 0), a mediodía en UTC.
private func day(_ mondayIndex: Int) throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 19 + mondayIndex
    components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-week-e2e-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Una "instalación" de la app en `root` con el reloj fijo en `date`.
@MainActor
private struct App {
    let onboarding: OnboardingCoordinator
    let todayPlan: TodayPlanCoordinator
    let session: AppSessionCoordinator

    init(root: URL, on date: Date) throws {
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let planStore = try persistence.planStore()
        onboarding = OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider(), clock: { date }, timeZone: { utc })
        todayPlan = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), planStore: planStore, clock: { date }, timeZone: { utc }
        )
        session = AppSessionCoordinator(
            onboarding: onboarding, todayPlan: todayPlan, planStore: planStore, clock: { date }, timeZone: { utc }
        )
    }
}

/// Recorre el cuestionario como la UI, con los días elegidos.
@MainActor
private func answerQuestionnaire(_ onboarding: OnboardingCoordinator, days: Set<WeekDay>) {
    onboarding.updateAboutYou(AboutYouAnswer(age: 30, sex: .female, weight: 62))
    onboarding.confirmAboutYou()
    let answers: [OnboardingAnswer] = [
        .goal(.hypertrophy), .phase(.maintenance), .experience(.intermediate),
        .trainingDays(days), .sessionMinutes(60), .variety(.balanced), .restrictions(.none),
    ]
    for answer in answers {
        onboarding.select(answer)
        if case .onboarding(_, _, _, _, let isAtEnd) = onboarding.phase, !isAtEnd {
            onboarding.advance()
        }
    }
}

@MainActor
@Suite("Semana de punta a punta (SCRUM-196, SCRUM-197)")
struct WeekEndToEndTests {

    @Test("Cuestionario real con L/Mi/V: Hoy entrena L, Mi y V con sesiones distintas y descansa el resto")
    func onboardingWithChosenDaysDrivesTodayAllWeek() async throws {
        let root = try makeRoot()
        let first = try App(root: root, on: try day(0))
        await first.session.signIn()
        answerQuestionnaire(first.onboarding, days: [.monday, .wednesday, .friday])
        first.onboarding.complete()
        guard case .completed(let profile) = first.onboarding.phase else {
            Issue.record("El cuestionario debía completarse, fase \(first.onboarding.phase)"); return
        }
        #expect(profile.trainingWeekdays == [.monday, .wednesday, .friday])
        #expect(await first.session.planCompleted(profile: profile))
        let sessions = try #require(first.todayPlan.plan?.sessions)

        var trainedTemplates: [SessionTemplate.ID] = []
        for index in 0..<TrainingWeek.daysInWeek {
            // Cada día es una app reabierta sobre el mismo disco (como el usuario real).
            let app = try App(root: root, on: try day(index))
            await app.session.start(autoSignIn: false)
            let plan = try #require(app.todayPlan.plan, "Día \(index): debía recuperar el plan")
            switch index {
            case 0, 2, 4:
                guard case .readyToStart = plan.todayState else {
                    Issue.record("Día \(index) debía entrenar, estado \(plan.todayState)"); continue
                }
                trainedTemplates.append(try #require(plan.todayTemplate?.id))
            default:
                #expect(plan.todayState == .restDay, "Día \(index) debía descansar")
            }
        }
        #expect(trainedTemplates == Array(sessions.prefix(3)).map(\.id), "L, Mi y V llevan las sesiones 1, 2 y 3 en orden")
        #expect(Set(trainedTemplates).count == 3, "Ningún día repite la sesión de otro")
    }

    @Test("Plan real de 3 días: 'Tu semana' coincide con Hoy los 7 días")
    func weekMatchesTodayAllWeek() async throws {
        let root = try makeRoot()
        let profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        let first = try App(root: root, on: try day(0))
        await first.session.signIn()
        #expect(await first.session.planCompleted(profile: profile))

        for index in 0..<TrainingWeek.daysInWeek {
            let app = try App(root: root, on: try day(index))
            await app.session.start(autoSignIn: false)
            let plan = try #require(app.todayPlan.plan)
            let week = try #require(app.todayPlan.week)
            let today = try #require(week.today, "Día \(index): la semana debía marcar hoy")
            #expect(today.day.mondayBasedIndex == index)
            #expect(today.session?.templateID == plan.todayTemplate?.id, "Día \(index): la semana y Hoy no coinciden")
            #expect((plan.todayState == .restDay) == (today.session == nil))
        }
    }
}
