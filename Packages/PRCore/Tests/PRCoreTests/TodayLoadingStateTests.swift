//
//  TodayLoadingStateTests.swift
//  PRCoreTests
//
//  SCRUM-193 (U2): "Hoy" distingue entre cargando, listo y fallido. Mientras el plan no
//  existe nunca se presenta como día de descanso, y un plan que no se puede generar se
//  dice (con reintento) en vez de quedarse en descanso. También: "Reintentar" en el
//  inicio de sesión cancela el intento colgado antes de lanzar otro (nunca dos a la vez).
//

import Foundation
import Testing
import PRCore
import PRDomain

private func profile(days: Int = 3) -> OnboardingProfile {
    OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: days,
        usualSessionMinutes: 60, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
    )
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-loading-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Apple que se queda colgado en el primer intento hasta que lo cancelan.
@MainActor
private final class HangingApple: AppleIDAuthProviding {
    private(set) var attempts = 0
    private var pending: CheckedContinuation<AppleIDAuthResult, Never>?
    var isWaiting: Bool { pending != nil }

    func authenticate() async -> AppleIDAuthResult {
        attempts += 1
        if attempts == 1 {
            return await withCheckedContinuation { pending = $0 }
        }
        return .success(userIdentifier: "apple-user-retry")
    }

    func cancelAuthentication() async {
        pending?.resume(returning: .canceled)
        pending = nil
    }
}

@MainActor
@Suite("Hoy: estados de carga reales (SCRUM-193)")
struct TodayLoadingStateTests {

    @Test("Sin plan todavía, Hoy está cargando: nunca descanso por defecto")
    func noPlanIsLoadingNotRest() throws {
        let coordinator = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled())
        #expect(coordinator.plan == nil)
        #expect(coordinator.screen == .loading)
        #expect(coordinator.screen != .ready(.restDay))
    }

    @Test("Con el plan listo, Hoy muestra el estado derivado del día")
    func readyPlanShowsDerivedState() throws {
        let coordinator = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled())
        #expect(coordinator.load(profile: profile()))
        let plan = try #require(coordinator.plan)
        #expect(coordinator.screen == .ready(plan.todayState))
        #expect(coordinator.generation == .idle)
    }

    @Test("Un plan que no se puede generar es 'failed', no descanso")
    func unbuildablePlanIsFailed() throws {
        let coordinator = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled())
        #expect(coordinator.load(profile: profile(days: 9)) == false)
        #expect(coordinator.plan == nil)
        #expect(coordinator.screen == .failed)
    }

    @Test("Activar con almacén real termina listo y sin generación pendiente")
    func activateWithStoreEndsReady() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(),
            planStore: try persistence.planStore()
        )
        #expect(await coordinator.activate(profile: profile(), userID: "user-1"))
        let plan = try #require(coordinator.plan)
        #expect(coordinator.generation == .idle)
        #expect(coordinator.screen == .ready(plan.todayState))
    }

    @Test("Activar un perfil imposible con almacén real es 'failed' y se puede reintentar")
    func failedActivationCanBeRetried() async throws {
        let persistence = try LocalPersistence(rootURL: try makeRoot(), log: PersistenceLog { _ in })
        let coordinator = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(),
            planStore: try persistence.planStore()
        )
        #expect(await coordinator.activate(profile: profile(days: 9), userID: "user-1") == false)
        #expect(coordinator.screen == .failed)
        // Reintento con un perfil válido: vuelve a estar listo.
        #expect(await coordinator.activate(profile: profile(), userID: "user-1"))
        #expect(coordinator.plan != nil)
        #expect(coordinator.generation == .idle)
    }

    @Test("Olvidar el plan (cambio de sesión) vuelve a cargando")
    func resetReturnsToLoading() throws {
        let coordinator = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled())
        #expect(coordinator.load(profile: profile()))
        coordinator.reset()
        #expect(coordinator.screen == .loading)
    }

    @Test("Reintentar el inicio de sesión cancela el intento colgado y lanza uno nuevo")
    func retrySignInCancelsThenRetries() async throws {
        let apple = HangingApple()
        let onboarding = OnboardingCoordinator(authProvider: apple)
        let session = AppSessionCoordinator(
            onboarding: onboarding,
            todayPlan: TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled()),
            planStore: nil
        )
        let signIn = Task { await session.signIn() }
        while !apple.isWaiting { await Task.yield() }
        #expect(onboarding.phase == .signingIn)

        await session.retrySignIn()
        await signIn.value

        #expect(apple.attempts == 2)
        #expect(onboarding.auth.profile?.userIdentifier == "apple-user-retry")
        guard case .onboarding = onboarding.phase else {
            Issue.record("Tras reintentar debía empezar el cuestionario; fase \(onboarding.phase)")
            return
        }
    }

    @Test("Reintentar fuera de un inicio de sesión en curso no hace nada")
    func retryOutsideSigningInIsNoOp() async throws {
        let apple = HangingApple()
        let onboarding = OnboardingCoordinator(authProvider: apple)
        let session = AppSessionCoordinator(
            onboarding: onboarding,
            todayPlan: TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled()),
            planStore: nil
        )
        await session.retrySignIn()
        #expect(apple.attempts == 0)
        #expect(onboarding.phase == .signedOut)
    }
}
