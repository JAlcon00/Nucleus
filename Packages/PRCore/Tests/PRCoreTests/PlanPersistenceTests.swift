//
//  PlanPersistenceTests.swift
//  PRCoreTests
//
//  SCRUM-26: recordar el perfil y el plan. Todo sobre `LocalPersistence` real en un
//  directorio temporal y el catálogo real; una "segunda instancia" es un coordinador
//  nuevo sobre el mismo directorio (lo que pasa al cerrar y reabrir la app).
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Apple falso con estado de credencial configurable.
private struct StubApple: AppleIDAuthProviding {
    var userID = "apple-user-1"
    var state: AppleCredentialState = .authorized
    func authenticate() async -> AppleIDAuthResult { .success(userIdentifier: userID) }
    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState { state }
}

/// Apple cuyo estado de credencial cambia mientras la app está abierta.
private final class MutableApple: AppleIDAuthProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: AppleCredentialState = .authorized
    var state: AppleCredentialState {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
    func authenticate() async -> AppleIDAuthResult { .success(userIdentifier: "apple-user-1") }
    func credentialState(forUserIdentifier userIdentifier: String) async -> AppleCredentialState { state }
}

/// Una "instalación" de la app sobre un directorio: se puede recrear para simular reabrir.
@MainActor
private struct AppInstance {
    let persistence: LocalPersistence
    let planStore: PlanStore
    let onboarding: OnboardingCoordinator
    let todayPlan: TodayPlanCoordinator
    let session: AppSessionCoordinator

    init(root: URL, apple: any AppleIDAuthProviding = StubApple()) throws {
        let today = try trainingDay()
        persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        planStore = try persistence.planStore()
        onboarding = OnboardingCoordinator(authProvider: apple)
        todayPlan = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(),
            planStore: planStore,
            clock: { today.date },
            timeZone: { today.timeZone }
        )
        session = AppSessionCoordinator(onboarding: onboarding, todayPlan: todayPlan, planStore: planStore)
    }
}

/// "Hoy" fijo: lunes 19 oct 2026 a mediodía en Ciudad de México. Con 3 días por semana
/// entrenan lunes…miércoles; con el reloj real, de jueves a domingo era descanso y
/// `todayOrder` salía vacío según el día en que corriera el test.
private func trainingDay() throws -> (date: Date, timeZone: TimeZone) {
    let timeZone = try #require(TimeZone(identifier: "America/Mexico_City"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
    return (date, timeZone)
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-plan-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// El registro del plan (los archivos ocultos son de control, p. ej. la marca de versión de SCRUM-40).
private func planFile(in directory: URL) throws -> URL {
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    return try #require(files.first { $0.pathExtension == "json" })
}

private func profile(
    goal: TrainingGoal = .hypertrophy, phase: BodyCompositionPhase = .maintenance,
    days: Int = 3, minutes: Int = 60
) -> OnboardingProfile {
    OnboardingProfile(
        goal: goal, phase: phase, experience: .intermediate, trainingDaysPerWeek: days,
        usualSessionMinutes: minutes, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
    )
}

@MainActor
@Suite("SCRUM-26 · Recordar mi perfil y mi plan")
struct PlanPersistenceTests {

    @Test("Al terminar el cuestionario se guardan perfil y bloque; al reabrir salen los mismos IDs")
    func reopenKeepsTheSameBlock() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        #expect(await first.todayPlan.activate(profile: profile(), userID: "u1"))
        let original = try #require(first.todayPlan.plan)

        let second = try AppInstance(root: root)
        let outcome = await second.todayPlan.restore(userID: "u1")
        #expect(outcome == .restored(profile()))
        let restored = try #require(second.todayPlan.plan)
        #expect(restored.block.id == original.block.id)
        #expect(restored.block.sessions == original.block.sessions)
        #expect(restored.todayOrder == original.todayOrder)
        #expect(!restored.todayOrder.isEmpty)
        #expect(second.todayPlan.notice == nil)
    }

    @Test("Reabrir no regenera: tras varios arranques el blockID no cambia")
    func idsStableAcrossManyLaunches() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.todayPlan.activate(profile: profile(), userID: "u1")
        let id = try #require(first.todayPlan.plan?.block.id)
        for _ in 0..<3 {
            let again = try AppInstance(root: root)
            _ = await again.todayPlan.restore(userID: "u1")
            #expect(again.todayPlan.plan?.block.id == id)
        }
    }

    @Test("La sesión recordada guarda sólo el ID opaco: sin tokens ni correo")
    func sessionStoresOnlyTheUserID() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.session.signIn()
        let store = try app.persistence.store(for: .session)
        let entries = try store.readAllEntries().entries
        #expect(entries.count == 1)
        let data = try #require(entries.first?.data)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["userID", "formatVersion"])
        #expect(app.planStore.loadSession() == "apple-user-1")
    }

    @Test("Ningún nombre de archivo del plan contiene el ID de Apple")
    func fileNamesDoNotLeakTheUserID() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.todayPlan.activate(profile: profile(), userID: "apple-user-secret-123")
        let names = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        #expect(!names.contains { $0.contains("apple-user-secret-123") })
    }

    @Test("Cambiar objetivo, fase o días crea un bloque nuevo y el anterior queda cerrado y conservado")
    func planChangeClosesThePreviousBlock() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.todayPlan.activate(profile: profile(days: 3), userID: "u1")
        let oldID = try #require(app.todayPlan.plan?.block.id)

        for changed in [profile(goal: .strength, days: 3), profile(phase: .deficit, days: 3), profile(days: 4)] {
            let instance = try AppInstance(root: root)
            _ = await instance.todayPlan.restore(userID: "u1")
            let before = try #require(instance.todayPlan.plan?.block.id)
            await instance.todayPlan.activate(profile: changed, userID: "u1")
            let after = try #require(instance.todayPlan.plan?.block.id)
            #expect(after != before, "\(changed)")
        }

        guard case .loaded(let stored, let active) = await app.planStore.loadPlan(userID: "u1") else {
            Issue.record("no hay plan guardado"); return
        }
        #expect(stored.blockHistory.count == 4)
        #expect(stored.blockHistory.first == oldID)
        #expect(active.status == .active)
        let history = await app.planStore.blockHistory(of: stored)
        #expect(history.count == 4)
        #expect(history.dropLast().allSatisfy { $0.status == .completed }, "los anteriores quedan cerrados")
        #expect(history.first?.sessions.isEmpty == false, "y conservan su contenido")
    }

    @Test("Cambiar sólo los minutos regenera el MISMO bloque; el mismo perfil no cambia nada")
    func smallChangesKeepTheBlock() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.todayPlan.activate(profile: profile(minutes: 60), userID: "u1")
        let original = try #require(app.todayPlan.plan?.block)

        let same = try AppInstance(root: root)
        _ = await same.todayPlan.restore(userID: "u1")
        await same.todayPlan.activate(profile: profile(minutes: 60), userID: "u1")
        #expect(same.todayPlan.plan?.block == original)

        let shorter = try AppInstance(root: root)
        _ = await shorter.todayPlan.restore(userID: "u1")
        await shorter.todayPlan.activate(profile: profile(minutes: 30), userID: "u1")
        let regenerated = try #require(shorter.todayPlan.plan?.block)
        #expect(regenerated.id == original.id)
        #expect(regenerated.startDate == original.startDate)
        guard case .loaded(let stored, _) = await shorter.planStore.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        #expect(stored.blockHistory == [original.id])
        #expect(stored.profile.usualSessionMinutes == 30)
    }

    @Test("Dos cuentas en el mismo dispositivo no mezclan sus planes")
    func twoUsersDoNotMix() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.todayPlan.activate(profile: profile(days: 3), userID: "alice")
        let aliceBlock = try #require(app.todayPlan.plan?.block.id)

        let bob = try AppInstance(root: root)
        #expect(await bob.todayPlan.restore(userID: "bob") == .none)
        await bob.todayPlan.activate(profile: profile(goal: .strength, days: 5), userID: "bob")
        let bobBlock = try #require(bob.todayPlan.plan?.block.id)
        #expect(bobBlock != aliceBlock)

        let again = try AppInstance(root: root)
        #expect(await again.todayPlan.restore(userID: "alice") == .restored(profile(days: 3)))
        #expect(again.todayPlan.plan?.block.id == aliceBlock)
    }

    @Test("Perfil corrupto: se ofrece rehacer el cuestionario sin tocar bloques ni historial")
    func corruptProfileOffersRedo() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.todayPlan.activate(profile: profile(), userID: "u1")
        let blocksBefore = try first.persistence.store(for: .blocks).readAllEntries().entries.map(\.data)

        // Corrompe el registro del plan.
        let plans = root.appendingPathComponent("plans", isDirectory: true)
        let file = try planFile(in: plans)
        try Data("{ roto".utf8).write(to: file)

        let app = try AppInstance(root: root)
        #expect(await app.todayPlan.restore(userID: "u1") == .unreadable)
        #expect(app.todayPlan.plan == nil)
        let blocksAfter = try app.persistence.store(for: .blocks).readAllEntries().entries.map(\.data)
        #expect(blocksAfter == blocksBefore)
    }

    @Test("Un plan inflado de una versión anterior se regenera conservando el ID y avisa")
    func inflatedPlanIsMigrated() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.todayPlan.activate(profile: profile(), userID: "u1")
        guard case .loaded(var stored, var block) = await first.planStore.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        let realistic = block.sessions.map(\.plannedSets.count).reduce(0, +)
        // Simula el bug viejo: cada serie repetida 6 veces, plan de generador 1.
        for index in block.sessions.indices {
            block.sessions[index].plannedSets = block.sessions[index].plannedSets.flatMap { Array(repeating: $0, count: 6) }
        }
        stored.generatorVersion = 1
        try await first.planStore.save(plan: stored, block: block)
        #expect(block.sessions.map(\.plannedSets.count).reduce(0, +) == realistic * 6)

        let app = try AppInstance(root: root)
        #expect(await app.todayPlan.restore(userID: "u1") == .restored(profile()))
        let migrated = try #require(app.todayPlan.plan?.block)
        #expect(migrated.id == block.id)
        #expect(migrated.startDate == block.startDate)
        #expect(migrated.sessions.map(\.plannedSets.count).reduce(0, +) == realistic)
        #expect(app.todayPlan.notice == .planUpdated)

        // Quedó guardado: la siguiente vez ya no avisa.
        let next = try AppInstance(root: root)
        _ = await next.todayPlan.restore(userID: "u1")
        #expect(next.todayPlan.notice == nil)
        #expect(next.todayPlan.plan?.block.id == block.id)
    }

    @Test("Un plan del generador 4 (sin pantorrilla ni core) se regenera con el mismo bloque y avisa (SCRUM-215)")
    func planWithoutMaintenanceIsRegenerated() async throws {
        let root = try makeRoot()
        let roomy = profile(days: 4, minutes: 120)
        let first = try AppInstance(root: root)
        await first.todayPlan.activate(profile: roomy, userID: "u1")
        guard case .loaded(var stored, var block) = await first.planStore.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func isMaintenance(_ id: ExerciseID) -> Bool {
            guard let muscle = byID[id]?.primaryMuscles.first?.muscleGroupID else { return false }
            return muscle == .calves || muscle == .core
        }
        func hasMaintenance(_ block: TrainingBlock) -> Bool {
            block.sessions.contains { $0.plannedSets.contains { isMaintenance($0.exerciseID) } }
        }
        #expect(hasMaintenance(block))
        // Como lo guardaba el generador 4: sin ejercicios de pantorrilla ni de core.
        for index in block.sessions.indices {
            block.sessions[index].plannedSets.removeAll { isMaintenance($0.exerciseID) }
        }
        stored.generatorVersion = 4
        try await first.planStore.save(plan: stored, block: block)

        let app = try AppInstance(root: root)
        #expect(await app.todayPlan.restore(userID: "u1") == .restored(roomy))
        let migrated = try #require(app.todayPlan.plan?.block)
        #expect(migrated.id == block.id)
        #expect(hasMaintenance(migrated))
        #expect(app.todayPlan.notice == .planUpdated)
    }

    @Test("SCRUM-37: un plan del generador 5 con un ejercicio que carga el codo se regenera sin él")
    func planWithElbowLoadingExerciseIsRegenerated() async throws {
        let root = try makeRoot()
        var restricted = profile(days: 4, minutes: 90)
        restricted.restrictions = BodyRegionRestrictionRule.restrictions(
            for: RestrictionsAnswer(zones: [.elbow]), now: Date(timeIntervalSince1970: 1_792_670_400)
        )
        let first = try AppInstance(root: root)
        await first.todayPlan.activate(profile: restricted, userID: "u1")
        guard case .loaded(var stored, var block) = await first.planStore.loadPlan(userID: "u1") else {
            Issue.record("no hay plan"); return
        }
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func loadsElbow(_ id: ExerciseID) -> Bool {
            byID[id]?.primaryMuscles.contains { [.triceps, .biceps, .forearms].contains($0.muscleGroupID) } ?? false
        }
        func hasElbowWork(_ block: TrainingBlock) -> Bool {
            block.sessions.contains { $0.plannedSets.contains { loadsElbow($0.exerciseID) } }
        }
        #expect(!hasElbowWork(block))
        // Como lo guardaba el generador 5: el jalón con cuerda contaba como cardio y pasaba.
        let rope = try #require(catalog.exercises.first { $0.aliases.first == "Triceps Pushdown - Rope Attachment" })
        let prescription = try #require(block.sessions[0].plannedSets.first?.prescription)
        block.sessions[0].plannedSets.append(contentsOf: Array(
            repeating: PlannedSet(exerciseID: rope.id, prescription: prescription), count: 2
        ))
        stored.generatorVersion = 5
        try await first.planStore.save(plan: stored, block: block)

        let app = try AppInstance(root: root)
        #expect(await app.todayPlan.restore(userID: "u1") == .restored(restricted))
        let migrated = try #require(app.todayPlan.plan?.block)
        #expect(migrated.id == block.id)
        #expect(!hasElbowWork(migrated))
        #expect(app.todayPlan.notice == .planUpdated)
    }
}

@MainActor
@Suite("SCRUM-26 · Arranque, sesión de Apple y rehacer cuestionario")
struct AppSessionTests {

    @Test("Primer arranque: sin sesión se queda en el login")
    func firstLaunchShowsSignIn() async throws {
        let app = try AppInstance(root: try makeRoot())
        await app.session.start(autoSignIn: false)
        #expect(app.onboarding.phase == .signedOut)
    }

    @Test("Iniciar sesión sin plan lleva al cuestionario; reabrir con plan lleva directo a Hoy")
    func signInThenReopenGoesToToday() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.session.signIn()
        guard case .onboarding = first.onboarding.phase else {
            Issue.record("debía mostrar el cuestionario: \(first.onboarding.phase)"); return
        }
        #expect(await first.session.planCompleted(profile: profile()))

        let second = try AppInstance(root: root)
        await second.session.start(autoSignIn: false)
        #expect(second.onboarding.phase == .completed(profile()))
        #expect(second.todayPlan.plan?.block.id == first.todayPlan.plan?.block.id)
    }

    @Test("Sin internet (credencial no verificable) se conserva la sesión y entra a Hoy")
    func offlineKeepsTheSession() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.session.signIn()
        await first.session.planCompleted(profile: profile())

        let offline = try AppInstance(root: root, apple: StubApple(state: .unavailable))
        await offline.session.start(autoSignIn: false)
        #expect(offline.onboarding.phase == .completed(profile()))
    }

    @Test("Credencial revocada: vuelve al login, olvida la sesión y NO borra datos")
    func revokedCredentialReturnsToSignInKeepingData() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.session.signIn()
        await first.session.planCompleted(profile: profile())
        let blocksBefore = try first.persistence.store(for: .blocks).readAllEntries().entries.count
        let plansBefore = try first.persistence.store(for: .plans).readAllEntries().entries.count

        let revoked = try AppInstance(root: root, apple: StubApple(state: .revoked))
        await revoked.session.start(autoSignIn: false)
        #expect(revoked.onboarding.phase == .signedOut)
        #expect(revoked.planStore.loadSession() == nil)
        #expect(try revoked.persistence.store(for: .blocks).readAllEntries().entries.count == blocksBefore)
        #expect(try revoked.persistence.store(for: .plans).readAllEntries().entries.count == plansBefore)

        // Al volver a entrar la misma cuenta, recupera su plan.
        await revoked.session.signIn()
        #expect(revoked.onboarding.phase == .completed(profile()))
    }

    @Test("Revocada mientras la app está abierta: verifyCredential vuelve al login sin borrar datos")
    func revokedWhileRunning() async throws {
        let apple = MutableApple()
        let app = try AppInstance(root: try makeRoot(), apple: apple)
        await app.session.signIn()
        await app.session.planCompleted(profile: profile())
        await app.session.verifyCredential()
        #expect(app.onboarding.phase != .signedOut, "autorizada: sigue dentro")

        apple.state = .unavailable
        await app.session.verifyCredential()
        #expect(app.onboarding.phase != .signedOut, "sin internet no es revocación")

        apple.state = .revoked
        await app.session.verifyCredential()
        #expect(app.onboarding.phase == .signedOut)
        #expect(app.planStore.loadSession() == nil)
        #expect(app.todayPlan.plan == nil)
        #expect(try app.persistence.store(for: .plans).readAllEntries().entries.count == 1)
        #expect(try app.persistence.store(for: .blocks).readAllEntries().entries.count == 1)
    }

    @Test("Cerrar sesión (SCRUM-208): vuelve al login sin borrar nada y la misma cuenta recupera su plan")
    func signOutKeepsData() async throws {
        let app = try AppInstance(root: try makeRoot())
        await app.session.signIn()
        await app.session.planCompleted(profile: profile())
        let block = try #require(app.todayPlan.plan?.block.id)

        app.session.signOut()
        #expect(app.onboarding.phase == .signedOut)
        #expect(app.planStore.loadSession() == nil, "Al reabrir no entra sola")
        #expect(app.todayPlan.plan == nil, "Nada del usuario queda en memoria")
        #expect(try app.persistence.store(for: .plans).readAllEntries().entries.count == 1)
        #expect(try app.persistence.store(for: .blocks).readAllEntries().entries.count == 1)

        await app.session.signIn()
        #expect(app.onboarding.phase == .completed(profile()))
        #expect(app.todayPlan.plan?.block.id == block, "Mismo bloque: nada se regeneró")
    }

    @Test("Perfil ilegible: la fase ofrece rehacer, y rehacer deja un plan nuevo sin perder bloques")
    func unreadableProfileThenRedo() async throws {
        let root = try makeRoot()
        let first = try AppInstance(root: root)
        await first.session.signIn()
        await first.session.planCompleted(profile: profile())
        let oldBlock = try #require(first.todayPlan.plan?.block.id)

        let plans = root.appendingPathComponent("plans", isDirectory: true)
        let file = try planFile(in: plans)
        try Data("basura".utf8).write(to: file)

        let app = try AppInstance(root: root)
        await app.session.start(autoSignIn: false)
        #expect(app.onboarding.phase == .planUnreadable)

        app.onboarding.redo()
        guard case .onboarding(let step, _, _, _, _) = app.onboarding.phase else {
            Issue.record("rehacer debe abrir el cuestionario"); return
        }
        #expect(step == .experience)
        #expect(await app.session.planCompleted(profile: profile(days: 4)))
        #expect(try app.persistence.store(for: .blocks).readAllEntries().entries.count == 2)
        #expect(app.todayPlan.plan?.block.id != oldBlock)
    }

    @Test("Rehacer cuestionario desde Hoy parte de las respuestas guardadas y reutiliza el cambio de plan")
    func redoFromTodayPrefillsAnswers() async throws {
        let root = try makeRoot()
        let app = try AppInstance(root: root)
        await app.session.signIn()
        await app.session.planCompleted(profile: profile(days: 4))
        app.onboarding.showCompleted(profile(days: 4))
        let before = try #require(app.todayPlan.plan?.block.id)

        app.session.redoQuestionnaire()
        guard case .onboarding(let step, _, _, _, _) = app.onboarding.phase else {
            Issue.record("debía abrir el cuestionario"); return
        }
        #expect(step == .experience)
        #expect(app.onboarding.currentAnswer == .experience(.intermediate), "Parte de las respuestas guardadas")

        // Mismo flujo que un cambio de plan: cambiar los días crea un bloque nuevo.
        await app.session.planCompleted(profile: profile(days: 5))
        #expect(app.todayPlan.plan?.block.id != before)
    }

    @Test("Credencial: sólo revocada/no encontrada exigen login")
    func credentialStateRequiresSignIn() {
        #expect(AppleCredentialState.revoked.requiresSignIn)
        #expect(AppleCredentialState.notFound.requiresSignIn)
        #expect(!AppleCredentialState.authorized.requiresSignIn)
        #expect(!AppleCredentialState.unavailable.requiresSignIn)
    }
}

@Suite("SCRUM-26 · Directorio aislado de pruebas de UI")
struct UITestStoreIDTests {
    @Test("Con -PRUITestStoreID el directorio es estable; sin él es nuevo cada vez")
    func stableDirectory() {
        let withID = UITestLaunchOptions.resolve(
            arguments: ["-PRUITestReset", "-PRUITestStoreID", "abc-123"], isDebugBuild: true
        )
        #expect(withID.isolatedDirectoryName == "pr-uitest-abc-123")
        let without = UITestLaunchOptions.resolve(arguments: ["-PRUITestReset"], isDebugBuild: true)
        #expect(without.isolatedDirectoryName != without.isolatedDirectoryName)
    }

    @Test("Un id con ruta o símbolos se ignora y en Release no existe")
    func unsafeIDIgnored() {
        let unsafe = UITestLaunchOptions.resolve(
            arguments: ["-PRUITestReset", "-PRUITestStoreID", "../../etc"], isDebugBuild: true
        )
        #expect(unsafe.storeID == nil)
        let release = UITestLaunchOptions.resolve(
            arguments: ["-PRUITestReset", "-PRUITestStoreID", "abc"], isDebugBuild: false
        )
        #expect(release == .none)
    }
}
