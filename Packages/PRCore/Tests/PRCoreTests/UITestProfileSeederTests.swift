//
//  UITestProfileSeederTests.swift
//  PRCoreTests
//
//  SCRUM-228: el perfil sembrado de las pruebas de UI (`-PRUITestProfile intermedio-lmv`) da
//  el mismo perfil y el mismo plan que contestar el cuestionario como lo hace `PRUITests`
//  (`completeOnboarding()` con sus valores por defecto). Coordinadores reales, el inicio de
//  sesión simulado de las pruebas de UI, `LocalPersistence` en un directorio temporal y el
//  catálogo real; el plan lo arma `planCompleted`, lo mismo que hace la app al terminar.
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Lo que la app arma al arrancar con `-PRFakeSignIn -PRUITestReset` (sin la UI).
@MainActor
private struct AppInstance {
    let planStore: PlanStore
    let onboarding: OnboardingCoordinator
    let aiConsent: AIConsentCoordinator
    let todayPlan: TodayPlanCoordinator
    let session: AppSessionCoordinator

    init(root: URL, day: SeedTestDay) throws {
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        planStore = try persistence.planStore()
        let (date, zone) = try day.noon()
        let clock = { date }
        let timeZone = { zone }
        onboarding = OnboardingCoordinator(
            authProvider: AuthLaunchMode.simulated.provider(appleID: FakeAppleIDAuthProvider()),
            clock: clock, timeZone: timeZone
        )
        aiConsent = AIConsentCoordinator(store: try persistence.aiConsentStore(), clock: clock, timeZone: timeZone)
        todayPlan = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), planStore: planStore, clock: clock, timeZone: timeZone
        )
        session = AppSessionCoordinator(
            onboarding: onboarding, todayPlan: todayPlan, planStore: planStore, aiConsent: aiConsent,
            clock: clock, timeZone: timeZone
        )
    }

    var completedProfile: OnboardingProfile? {
        if case .completed(let profile) = onboarding.phase { return profile }
        return nil
    }

    var currentStep: OnboardingStep? {
        if case .onboarding(let step, _, _, _, _) = onboarding.phase { return step }
        return nil
    }
}

/// Los dos "hoy" con los que arrancan las pruebas de UI (`-PRFixedDate`).
enum SeedTestDay: String, CaseIterable, Sendable {
    case monday = "2026-10-19"
    case sunday = "2026-10-25"

    /// Mediodía local en Ciudad de México.
    func noon() throws -> (date: Date, timeZone: TimeZone) {
        let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        try #require(parts.count == 3)
        let date = try #require(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)))
        return (date, timeZone)
    }
}

/// Lo que decide el motor, sin los identificadores al azar del bloque y de las sesiones.
private struct PlanContent: Equatable {
    /// Para comparar el estado de Hoy sin el id de su plantilla.
    private static let noTemplateID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    let block: String
    let goal: TrainingGoal
    let phase: BodyCompositionPhase
    let startDate: Date
    let plannedWeeks: Int
    let muscleTargets: [MuscleVolumeTarget]
    let priorities: [MusclePriority]
    let sessionTitles: [String]
    let sessions: [[PlannedSet]]
    let today: [PlannedSet]?
    let todayExercises: [TodayExerciseLine]
    let estimatedMinutes: Int?
    let todayState: TodayScreenState

    init(_ plan: TodayPlan) {
        block = plan.block.name
        goal = plan.block.goal
        phase = plan.block.phase
        startDate = plan.block.startDate
        plannedWeeks = plan.block.plannedWeeks
        muscleTargets = plan.block.muscleTargets
        priorities = plan.block.priorities
        sessionTitles = plan.sessions.map(\.title)
        sessions = plan.sessions.map(\.plannedSets)
        today = plan.todayTemplate?.plannedSets
        todayExercises = plan.todayExercises
        estimatedMinutes = plan.estimatedMinutes
        switch plan.todayState {
        case .restDay:
            todayState = .restDay
        case .readyToStart(var session):
            session.templateID = Self.noTemplateID
            todayState = .readyToStart(session)
        case .activeWorkout(var session, let isPaused):
            session.templateID = Self.noTemplateID
            todayState = .activeWorkout(session, isPaused: isPaused)
        }
    }
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-seed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Las mismas llamadas que hace la pantalla cuando `PRUITests.completeOnboarding()` la toca con
/// sus valores por defecto, en el mismo orden (si el orden de los pasos cambia, lo dice).
@MainActor
private func answerLikeTheUITests(_ app: AppInstance) {
    let onboarding = app.onboarding
    // Sobre ti: rueda en "30 años", "Hombre" y "72" en el campo (manda "7" y luego "72").
    var about = onboarding.aboutYouAnswer
    about.age = 30
    onboarding.updateAboutYou(about)
    about.sex = .male
    onboarding.updateAboutYou(about)
    for typed in [7.0, 72.0] {
        about.weight = typed
        onboarding.updateAboutYou(about)
    }
    #expect(onboarding.confirmAboutYou(), "Sobre ti con 30 años, hombre y 72 kg")

    #expect(app.currentStep == .experience)
    onboarding.select(.experience(.intermediate)); onboarding.advance()
    #expect(app.currentStep == .goal)
    onboarding.select(.goal(.hypertrophy)); onboarding.advance()
    #expect(app.currentStep == .phase)
    onboarding.select(.phase(.maintenance)); onboarding.advance()
    // Días: por defecto L, M, J y V; la prueba toca martes, miércoles y jueves, en ese orden.
    #expect(app.currentStep == .daysPerWeek)
    onboarding.select(.trainingDays([.monday, .thursday, .friday]))
    onboarding.select(.trainingDays([.monday, .wednesday, .thursday, .friday]))
    onboarding.select(.trainingDays([.monday, .wednesday, .friday]))
    onboarding.advance()
    // Minutos: sube y baja un paso del selector (de 5 en 5).
    #expect(app.currentStep == .sessionMinutes)
    onboarding.select(.sessionMinutes(65))
    onboarding.select(.sessionMinutes(60))
    onboarding.advance()
    #expect(app.currentStep == .variety)
    onboarding.select(.variety(.balanced)); onboarding.advance()
    // Prioritarios y restricciones: "Siguiente" sin elegir; en restricciones dice "Terminar".
    #expect(app.currentStep == .priorityMuscles)
    onboarding.advance()
    #expect(app.currentStep == .restrictions)
    onboarding.complete()
    // "Ahora no" en el consentimiento de la IA.
    app.aiConsent.decline()
}

@MainActor
@Suite("SCRUM-228 · Perfil sembrado de las pruebas de UI")
struct UITestProfileSeederTests {

    @Test("El perfil sembrado y el cuestionario contestado como en las pruebas de UI dan el mismo plan",
          arguments: SeedTestDay.allCases)
    func seededProfileGivesTheSamePlan(day: SeedTestDay) async throws {
        let answered = try AppInstance(root: try makeRoot(), day: day)
        await answered.session.start(autoSignIn: true)
        answerLikeTheUITests(answered)
        let answeredProfile = try #require(answered.completedProfile, "El cuestionario contestado arma el perfil")
        #expect(await answered.session.planCompleted(profile: answeredProfile))

        let seeded = try AppInstance(root: try makeRoot(), day: day)
        await seeded.session.start(autoSignIn: true)
        let outcome = UITestProfileSeeder(profile: .intermediateMondayWednesdayFriday)
            .answer(onboarding: seeded.onboarding, aiConsent: seeded.aiConsent)
        let seededProfile = try #require(seeded.completedProfile, "El perfil sembrado arma el perfil: \(outcome)")
        #expect(outcome == .answered(seededProfile))
        #expect(await seeded.session.planCompleted(profile: seededProfile))

        #expect(seededProfile == answeredProfile, "Mismo perfil, \"Sobre ti\" incluido")
        #expect(seeded.aiConsent.consent == answered.aiConsent.consent, "Mismo consentimiento de la IA (\"Ahora no\")")
        let answeredPlan = try #require(answered.todayPlan.plan)
        let seededPlan = try #require(seeded.todayPlan.plan)
        #expect(PlanContent(seededPlan) == PlanContent(answeredPlan), "Mismo bloque, mismas sesiones y mismo Hoy")

        // Lo guardado es lo mismo: al reabrir, las dos instalaciones recuerdan ese perfil.
        let storedAnswered = await answered.planStore.loadPlan(userID: AuthLaunchMode.simulatedUserIdentifier)
        let storedSeeded = await seeded.planStore.loadPlan(userID: AuthLaunchMode.simulatedUserIdentifier)
        guard case .loaded(let answeredStored, _) = storedAnswered, case .loaded(let seededStored, _) = storedSeeded else {
            Issue.record("Las dos deben guardar el plan: \(storedAnswered) / \(storedSeeded)")
            return
        }
        #expect(seededStored.profile == answeredStored.profile)
    }

    @Test("El perfil sembrado es el que suponen las pruebas de UI: intermedio, L-Mi-V, 60 min, sin restricciones")
    func seededProfileMatchesWhatTheUITestsAssume() async throws {
        let app = try AppInstance(root: try makeRoot(), day: .monday)
        await app.session.start(autoSignIn: true)
        UITestProfileSeeder(profile: .intermediateMondayWednesdayFriday).answer(onboarding: app.onboarding, aiConsent: app.aiConsent)
        let profile = try #require(app.completedProfile)
        #expect(profile.experience == .intermediate)
        #expect(profile.goal == .hypertrophy)
        #expect(profile.phase == .maintenance)
        #expect(profile.trainingWeekdays == [.monday, .wednesday, .friday])
        #expect(profile.usualSessionMinutes == 60)
        #expect(profile.varietyPreference == .balanced)
        #expect(profile.priorityMuscles.isEmpty)
        #expect(profile.restrictions.isEmpty)
        #expect(profile.aboutYou?.sex == .male)
        #expect(profile.aboutYou?.weight == 72)
        let (monday, zone) = try SeedTestDay.monday.noon()
        #expect(profile.aboutYou?.age(on: monday, timeZone: zone) == 30)
        #expect(!app.aiConsent.needsDecision, "Ya contestó la IA: no se vuelve a preguntar")
    }

    @Test("Al reabrir con un plan guardado no contesta nada: se respeta lo guardado")
    func savedPlanIsNotAnsweredAgain() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root, day: .monday)
        await first.session.start(autoSignIn: true)
        let seeder = UITestProfileSeeder(profile: .intermediateMondayWednesdayFriday)
        seeder.answer(onboarding: first.onboarding, aiConsent: first.aiConsent)
        let profile = try #require(first.completedProfile)
        #expect(await first.session.planCompleted(profile: profile))
        let firstPlan = try #require(first.todayPlan.plan)

        let reopened = try AppInstance(root: root, day: .monday)
        await reopened.session.start(autoSignIn: true)
        #expect(reopened.completedProfile == profile, "Reabre directo con el perfil guardado")
        #expect(seeder.answer(onboarding: reopened.onboarding, aiConsent: reopened.aiConsent) == .notInQuestionnaire)
        #expect(reopened.completedProfile == profile)
        #expect(reopened.todayPlan.plan?.block == firstPlan.block, "Mismo bloque, mismos identificadores: no se armó otro")
    }

    @Test("Sin sesión iniciada no contesta nada")
    func signedOutIsNotAnswered() async throws {
        let app = try AppInstance(root: try makeRoot(), day: .monday)
        await app.session.start(autoSignIn: false)
        #expect(app.onboarding.phase == .signedOut)
        let outcome = UITestProfileSeeder(profile: .intermediateMondayWednesdayFriday)
            .answer(onboarding: app.onboarding, aiConsent: app.aiConsent)
        #expect(outcome == .notInQuestionnaire)
        #expect(app.onboarding.phase == .signedOut)
        #expect(app.aiConsent.needsDecision, "No decidió la IA por nadie")
    }
}
