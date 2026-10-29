//
//  RestrictionEditingFlowTests.swift
//  PRCoreTests
//
//  SCRUM-36 de punta a punta con la infraestructura real (`LocalPersistence` en un directorio
//  temporal y el catálogo real), como lo hace Perfil › Restricciones:
//  - agregar una zona regenera el mismo bloque sin lo que la carga, y al reabrir sigue igual;
//  - resolverla devuelve lo que se había quitado y la deja en el historial;
//  - un cambio inválido o un plan imposible no cambian nada;
//  - si el disco falla, el plan de hoy ya la respeta, se avisa y en disco no queda nada a medias;
//  - un entrenamiento en curso se retoma igual aunque el plan cambie a la mitad;
//  - rehacer el cuestionario sólo marca las zonas en vigor;
//  - la nota de una restricción nunca llega a la IA.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let editor = RestrictionEditor()

private struct StubApple: AppleIDAuthProviding {
    func authenticate() async -> AppleIDAuthResult { .success(userIdentifier: "apple-user-1") }
    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState { .authorized }
}

/// Almacén en memoria cuya escritura se puede hacer fallar a mitad de la prueba.
private final class SwitchableStore: RepositoryStore, @unchecked Sendable {
    struct WriteFailed: Error {}
    private let lock = NSLock()
    private let base = MemoryRepositoryStore()
    private var failing = false
    var failWrites: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }
    func read(key: String) throws -> Data? { try base.read(key: key) }
    func readAll() throws -> [Data] { try base.readAll() }
    func readAllEntries() throws -> StoreReadResult { try base.readAllEntries() }
    func write(key: String, data: Data) throws {
        if failWrites { throw WriteFailed() }
        try base.write(key: key, data: data)
    }
    func delete(key: String) throws { try base.delete(key: key) }
}

/// Lunes 19 oct 2026 a mediodía en Ciudad de México: día de entrenamiento.
private func trainingDay() throws -> (date: Date, timeZone: TimeZone) {
    let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    return (date, timeZone)
}

private func profile() throws -> OnboardingProfile {
    try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
    )
}

/// Una "instalación" de la app sobre unos almacenes: se recrea para simular reabrir.
@MainActor
private struct App {
    let onboarding: OnboardingCoordinator
    let todayPlan: TodayPlanCoordinator
    let session: AppSessionCoordinator
    let catalog: ExerciseCatalog
    let now: Date

    init(planStore: PlanStore) throws {
        let today = try trainingDay()
        now = today.date
        catalog = try ExerciseCatalogLoader.loadBundled()
        onboarding = OnboardingCoordinator(authProvider: StubApple(), clock: { today.date }, timeZone: { today.timeZone })
        todayPlan = TodayPlanCoordinator(catalog: catalog, planStore: planStore, clock: { today.date }, timeZone: { today.timeZone })
        session = AppSessionCoordinator(onboarding: onboarding, todayPlan: todayPlan, planStore: planStore)
    }

    /// Primera vez: inicia sesión y activa el plan del cuestionario.
    func completeQuestionnaire(_ answered: OnboardingProfile) async {
        await session.signIn()
        onboarding.showCompleted(answered)
        await session.planCompleted(profile: answered)
    }

    var profile: OnboardingProfile? {
        if case .completed(let profile) = onboarding.phase { return profile }
        return nil
    }

    var byID: [ExerciseID: Exercise] {
        Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// ¿El plan trae algo que trabaje bíceps, tríceps o antebrazo como principal (lo que el
    /// codo cuida)?
    func loadsElbow() -> Bool {
        let byID = byID
        return (todayPlan.plan?.block.sessions ?? []).contains { session in
            session.plannedSets.contains { set in
                byID[set.exerciseID]?.primaryMuscles.contains { [.biceps, .triceps, .forearms].contains($0.muscleGroupID) } ?? false
            }
        }
    }
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-restrictions-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Suite("SCRUM-36 · Restricciones editables, de punta a punta")
struct RestrictionEditingFlowTests {

    @Test("Agregar codo desde Perfil: el mismo bloque se regenera sin lo que lo carga, y al reabrir sigue igual")
    func addingRestrictsThePlanAndPersists() async throws {
        let root = try makeRoot()
        let first = try App(planStore: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).planStore())
        await first.completeQuestionnaire(try profile())
        let blockID = try #require(first.todayPlan.plan?.block.id)
        #expect(first.loadsElbow(), "Sin restricción el plan trabaja los brazos")

        let outcome = await first.session.updateRestrictions { try editor.adding(.elbow, details: RestrictionDetails(), to: $0, explicitlyConfirmed: false, now: first.now) }
        #expect(outcome == .saved)
        #expect(!first.loadsElbow())
        #expect(first.todayPlan.plan?.block.id == blockID, "Se regenera el mismo bloque")
        #expect(first.profile?.restrictions.map(\.bodyRegion) == [.elbow])

        let reopened = try App(planStore: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).planStore())
        await reopened.session.start(autoSignIn: false)
        #expect(reopened.profile?.restrictions.map(\.bodyRegion) == [.elbow])
        #expect(reopened.todayPlan.plan?.block.id == blockID)
        #expect(!reopened.loadsElbow())
    }

    @Test("Resolver devuelve lo que se había quitado y la restricción queda en el historial con su fecha")
    func resolvingRestoresThePlan() async throws {
        let app = try App(planStore: try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in }).planStore())
        await app.completeQuestionnaire(try profile())
        _ = await app.session.updateRestrictions { try editor.adding(.elbow, details: RestrictionDetails(), to: $0, explicitlyConfirmed: false, now: app.now) }
        let id = try #require(app.profile?.restrictions.first?.id)

        #expect(await app.session.updateRestrictions { try editor.resolving(id, in: $0, explicitlyConfirmed: false, now: app.now) }
                == .rejected(.needsExplicitConfirmation), "Sin confirmar no se resuelve")
        #expect(!app.loadsElbow())

        #expect(await app.session.updateRestrictions { try editor.resolving(id, in: $0, explicitlyConfirmed: true, now: app.now) } == .saved)
        #expect(app.loadsElbow())
        let resolved = try #require(app.profile?.restrictions.first)
        #expect(resolved.status == .resolved)
        #expect(resolved.resolvedDate == app.now)
        guard case .loaded(let current, let history, _) = RestrictionListPresenter().state(for: app.profile, now: app.now) else {
            Issue.record("Debía haber historial"); return
        }
        #expect(current.isEmpty)
        #expect(history.map(\.bodyRegion) == [.elbow])
    }

    @Test("Un cambio inválido no toca ni el perfil ni el plan")
    func invalidChangeChangesNothing() async throws {
        let app = try App(planStore: try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in }).planStore())
        await app.completeQuestionnaire(try profile())
        let before = app.todayPlan.plan?.block
        let outcome = await app.session.updateRestrictions {
            try editor.adding(.lumbar, details: RestrictionDetails(source: .professionalGuidance), to: $0, explicitlyConfirmed: false, now: app.now)
        }
        #expect(outcome == .rejected(.needsExplicitConfirmation))
        #expect(app.profile?.restrictions.isEmpty == true)
        #expect(app.todayPlan.plan?.block == before)
    }

    @Test("Si el disco falla: el plan de hoy ya la respeta, se avisa y en disco no queda nada a medias")
    func saveFailureLeavesNothingHalfDone() async throws {
        let plans = SwitchableStore(), blocks = SwitchableStore(), sessions = MemoryRepositoryStore()
        let store = PlanStore(plans: plans, sessions: sessions, blocks: blocks)
        let app = try App(planStore: store)
        await app.completeQuestionnaire(try profile())
        let saved = try #require(app.todayPlan.plan?.block)

        plans.failWrites = true
        blocks.failWrites = true
        let outcome = await app.session.updateRestrictions { try editor.adding(.elbow, details: RestrictionDetails(), to: $0, explicitlyConfirmed: false, now: app.now) }
        #expect(outcome == .notSaved)
        #expect(RestrictionListPresenter(locale: Locale(identifier: "es_MX")).message(for: outcome)?.hasPrefix("Tu plan de hoy ya lo respeta") == true)
        #expect(!app.loadsElbow(), "Mientras la app sigue abierta, el plan ya la cuida")

        // Al reabrir: lo último que sí se guardó, completo (perfil y bloque de antes).
        guard case .loaded(let stored, let block) = await store.loadPlan(userID: "apple-user-1") else {
            Issue.record("El plan anterior debía seguir guardado"); return
        }
        #expect(stored.profile.restrictions.isEmpty)
        #expect(block == saved)
    }

    @Test("Un entrenamiento en curso se retoma igual aunque una restricción regenere el plan a la mitad")
    func workoutInProgressSurvivesTheChange() async throws {
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let app = try App(planStore: try persistence.planStore())
        await app.completeQuestionnaire(try profile())
        let template = try #require(app.todayPlan.plan?.todayTemplate)
        let workout = try await persistence.makeWorkoutCoordinator(template: template, clock: { app.now })
        _ = workout.start(now: app.now)
        _ = try workout.recordEditedSet(weight: 40, reps: 10, unit: .kilograms, now: app.now.addingTimeInterval(120))

        #expect(await app.session.updateRestrictions { try editor.adding(.elbow, details: RestrictionDetails(), to: $0, explicitlyConfirmed: false, now: app.now) } == .saved)
        let known = await app.todayPlan.allKnownTemplates()
        #expect(!known.contains { $0.id == template.id }, "El plan regenerado ya no tiene la plantilla con la que empezó")

        // Se cierra la app a la mitad y se reabre.
        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        guard case .restored(let restored) = try await reopened.recoverWorkout(templates: known, clock: { app.now }) else {
            Issue.record("El entrenamiento en curso debía retomarse"); return
        }
        #expect(restored.template == template, "Sigue con la plantilla con la que empezó")
        #expect(try restored.snapshot().session.sets.count == 1, "Sin perder la serie hecha")
    }

    @Test("Si el plan no se puede armar con el cambio, se vuelve al anterior y no se aplica nada")
    func impossiblePlanChangesNothing() async throws {
        let app = try App(planStore: try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in }).planStore())
        await app.completeQuestionnaire(try profile())
        let before = try #require(app.todayPlan.plan?.block)
        // Una restricción que prohíbe todos los patrones deja a todos los músculos sin ejercicios.
        let outcome = await app.session.updateRestrictions { restrictions in
            restrictions + [TrainingRestriction(bodyRegion: .core, startDate: app.now, forbiddenPatterns: Set(MovementPattern.allCases))]
        }
        #expect(outcome == .planFailed)
        #expect(app.profile?.restrictions.isEmpty == true)
        #expect(app.todayPlan.plan?.block.id == before.id)
        #expect(app.todayPlan.plan?.block.sessions.map { $0.plannedSets.map(\.exerciseID) } == before.sessions.map { $0.plannedSets.map(\.exerciseID) })
    }

    @Test("Rehacer el cuestionario sólo marca las zonas en vigor; una resuelta no vuelve sola")
    func redoMarksOnlyZonesInForce() throws {
        let today = try trainingDay()
        var answered = try profile()
        answered.restrictions = [
            TrainingRestriction(bodyRegion: .elbow, startDate: today.date, status: .resolved, forbiddenPatterns: [.elbowFlexion], resolvedDate: today.date),
            TrainingRestriction(bodyRegion: .knee, startDate: today.date, forbiddenPatterns: [.lunge]),
        ]
        let onboarding = OnboardingCoordinator(authProvider: StubApple(), clock: { today.date }, timeZone: { today.timeZone })
        onboarding.redo(from: answered)
        guard case .restrictions(let answer)? = onboarding.flowController.draft.answer(for: .restrictions) else {
            Issue.record("El paso Restricciones debía venir contestado"); return
        }
        #expect(answer.zones == [.knee])
        let rebuilt = BodyRegionRestrictionRule.restrictions(for: answer, now: today.date)
        #expect(rebuilt.filter(\.isInForce).map(\.bodyRegion) == [.knee])
        #expect(rebuilt.contains { $0.bodyRegion == .elbow && $0.status == .resolved }, "La resuelta sigue en el historial")
    }

    @Test("La nota de una restricción nunca llega a la IA; las resueltas tampoco")
    func notesNeverReachTheAI() throws {
        let today = try trainingDay()
        var answered = try profile()
        answered.aboutYou = try AboutYou(name: nil, birthYear: 1994, sex: .female, heightCentimeters: 165, weight: 60, weightUnit: .kilograms)
        answered.restrictions = try editor.adding(
            .shoulder, details: RestrictionDetails(notes: "Me lo dijo mi fisio el martes"), to: [], explicitlyConfirmed: false, now: today.date
        )
        answered.restrictions += [TrainingRestriction(bodyRegion: .wrist, startDate: today.date, status: .resolved, forbiddenPatterns: [.carry])]
        let context = try #require(AgentProfileContextBuilder().context(profile: answered, consent: .granted(at: today.date), now: today.date, timeZone: today.timeZone))
        let encoded = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
        #expect(!encoded.contains("fisio"))
        #expect(context.restrictions.map(\.bodyRegion) == [.shoulder])
    }
}
