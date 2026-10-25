//
//  DemoDataTests.swift
//  PRCoreTests
//
//  SCRUM-188 (S-01): el demo se carga sólo con `-PRDemoData` en Debug (nunca en Release),
//  en un directorio aparte de los datos reales, y entra solo con el usuario simulado. La
//  siembra, con la persistencia real en un directorio temporal, deja un perfil de ejemplo
//  y 2 semanas de historial (8 entrenamientos completos en los días elegidos, sin nada que
//  la restricción prohíba y con avance de la semana 1 a la 2); es determinista e
//  idempotente, y nunca sobrescribe un plan ilegible.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

private let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
private let userID = AuthLaunchMode.simulatedUserIdentifier

/// Domingo 25 de octubre de 2026 a mediodía: las 2 semanas anteriores van del domingo 11
/// al sábado 24 (lunes, martes, jueves y viernes: 8 entrenamientos).
private func sunday() throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
}

private func makePersistence() throws -> (LocalPersistence, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-demo-\(UUID().uuidString)", isDirectory: true)
    return (try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }), root)
}

@MainActor
private func seed(_ persistence: LocalPersistence, now: Date) async throws -> DemoSeedOutcome {
    try await DemoDataSeeder(catalog: try ExerciseCatalogLoader.loadBundled(), timeZone: zone)
        .seedIfNeeded(persistence: persistence, userID: userID, now: now)
}

private func history(_ persistence: LocalPersistence) async throws -> [WorkoutSessionRecord] {
    try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository()).sessions
        .sorted { $0.startedAt < $1.startedAt }
}

/// Lo hecho en cada entrenamiento sin los IDs aleatorios: ejercicio, peso y repeticiones.
private func performed(_ sessions: [WorkoutSessionRecord]) -> [[String]] {
    sessions.map { $0.sets.map { "\($0.exerciseID.rawValue)|\($0.weight)|\($0.reps)" } }
}

@Suite("Ambiente demo con -PRDemoData (SCRUM-188)")
struct DemoDataTests {

    @Test("Sólo en Debug con -PRDemoData; en Release nunca, aunque venga el argumento")
    func launchFlag() {
        #expect(DemoDataLaunch.isRequested(arguments: ["PR", "-PRDemoData"], isDebugBuild: true))
        #expect(!DemoDataLaunch.isRequested(arguments: ["PR", "-PRDemoData"], isDebugBuild: false))
        for arguments in [[String](), ["PR"], ["PR", "-PRDemoDataX"], ["PR", "PRDemoData"]] {
            #expect(!DemoDataLaunch.isRequested(arguments: arguments, isDebugBuild: true), "\(arguments)")
        }
    }

    @Test("El demo entra solo con el usuario simulado, pero sólo en Debug")
    func demoSignsInAutomatically() {
        let debug = AuthLaunchMode.resolve(arguments: ["PR", "-PRDemoData"], isDebugBuild: true)
        #expect(debug == .simulated)
        #expect(debug.signsInAutomatically)
        #expect(AuthLaunchMode.resolve(arguments: ["PR", "-PRDemoData"], isDebugBuild: false) == .appleID)
    }

    @Test("El directorio del demo es otro que el de los datos reales y ninguno está dentro del otro")
    func separateDirectory() {
        let base = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/X/Library/Application Support", isDirectory: true)
        let real = PersistenceLocation.real(in: base).standardizedFileURL.path
        let demo = PersistenceLocation.demo(in: base).standardizedFileURL.path
        #expect(real != demo)
        #expect(!demo.hasPrefix(real + "/"))
        #expect(!real.hasPrefix(demo + "/"))
        #expect(real.hasSuffix("PR/persistence"), "La ruta de los datos reales no cambia")
    }

    @MainActor
    @Test("Siembra un perfil de ejemplo y 2 semanas de historial que la app retoma")
    func seedsProfileAndTwoWeeks() async throws {
        let now = try sunday()
        let (persistence, _) = try makePersistence()
        #expect(try await seed(persistence, now: now) == .seeded(workouts: 8))

        // La app retoma el plan del usuario demo con el perfil de ejemplo.
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), planStore: try persistence.planStore(),
            clock: { now }, timeZone: { zone }
        )
        guard case .restored(let profile) = await coordinator.restore(userID: userID) else {
            Issue.record("El plan demo debía restaurarse")
            return
        }
        #expect(profile.aboutYou?.name == "Alex")
        #expect(profile.experience == .intermediate)
        #expect(profile.trainingWeekdays == [.monday, .tuesday, .thursday, .friday])
        #expect(profile.restrictions.map(\.bodyRegion) == [.knee])
        #expect(profile.restrictionNote == "Me molesta la rodilla al bajar escaleras")

        // 8 entrenamientos completos, en los días elegidos de las 2 semanas anteriores.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sessions = try await history(persistence)
        #expect(sessions.count == 8)
        #expect(sessions.map { calendar.component(.day, from: $0.startedAt) } == [12, 13, 15, 16, 19, 20, 22, 23])
        #expect(sessions.allSatisfy { $0.lifecycle == .completed })
        #expect(sessions.allSatisfy { !$0.sets.isEmpty && $0.sets.allSatisfy { $0.lifecycle == .completed && $0.reps >= 1 } })
        let templates = Dictionary((await coordinator.allKnownTemplates()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            let template = try #require(session.templateID.flatMap { templates[$0] })
            #expect(session.sets.count == template.plannedSets.count, "Cada serie planeada quedó registrada")
        }

        // Nada que la rodilla prohíba (SCRUM-31) y Progreso ve avance de la semana 1 a la 2.
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let done = sessions.flatMap(\.sets).compactMap { byID[$0.exerciseID] }
        #expect(done.allSatisfy { RestrictionPolicyEngine.verdict(for: $0, under: profile.restrictions) == .allowed })
        let firstWeek = sessions.prefix(4).flatMap(\.sets), secondWeek = sessions.suffix(4).flatMap(\.sets)
        func best(_ sets: [SetRecord]) -> [ExerciseID: Double] {
            Dictionary(sets.map { ($0.exerciseID, $0.weight) }, uniquingKeysWith: max)
        }
        let before = best(firstWeek), after = best(secondWeek)
        let repeated = Set(before.keys).intersection(after.keys)
        #expect(!repeated.isEmpty)
        #expect(repeated.allSatisfy { (after[$0] ?? 0) >= (before[$0] ?? 0) })
        #expect(repeated.contains { (after[$0] ?? 0) > (before[$0] ?? 0) }, "La segunda semana sube carga")

        // El bloque empezó con la siembra (reloj de la app, no el de pared): Progreso cuenta
        // los récords del bloque.
        let blockStart = try #require(coordinator.plan?.block.startDate)
        #expect(calendar.component(.day, from: blockStart) == 11)
        #expect(blockStart < (sessions.first?.startedAt ?? now))
        let overview = ProgressOverviewBuilder().overview(
            history: sessions, templateTitles: [:], exerciseNames: [:], plannedPerWeek: 4,
            blockStart: blockStart, date: now, timeZone: zone
        )
        #expect(overview.insights.recordsInBlock > 0)
    }

    @MainActor
    @Test("Determinista: la misma fecha da el mismo historial; reabrir no duplica nada")
    func deterministicAndIdempotent() async throws {
        let now = try sunday()
        let (first, _) = try makePersistence()
        let (second, _) = try makePersistence()
        #expect(try await seed(first, now: now) == .seeded(workouts: 8))
        #expect(try await seed(second, now: now) == .seeded(workouts: 8))
        #expect(performed(try await history(first)) == performed(try await history(second)))

        // Segundo arranque (incluso días después): no se toca el plan ni el historial.
        let before = try await history(first)
        let later = now.addingTimeInterval(3 * 86_400)
        #expect(try await seed(first, now: later) == .alreadySeeded)
        #expect(try await history(first) == before)
    }

    @MainActor
    @Test("Un plan ilegible del usuario demo nunca se sobrescribe")
    func unreadablePlanIsNotOverwritten() async throws {
        let (persistence, root) = try makePersistence()
        let file = root.appendingPathComponent("plans", isDirectory: true)
            .appendingPathComponent("\(PlanStore.key(forUser: userID)).json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{ no es un plan".utf8)
        try garbage.write(to: file)
        guard case .unreadable = await (try persistence.planStore()).loadPlan(userID: userID) else {
            Issue.record("El archivo de prueba debía leerse como plan ilegible")
            return
        }

        #expect(try await seed(persistence, now: try sunday()) == .skippedUnreadable)
        #expect(try Data(contentsOf: file) == garbage, "El archivo queda intacto")
        #expect(try await history(persistence).isEmpty)
    }
}
