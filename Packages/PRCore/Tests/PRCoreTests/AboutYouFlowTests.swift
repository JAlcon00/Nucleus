//
//  AboutYouFlowTests.swift
//  PRCoreTests
//
//  SCRUM-198 (U5): "Sobre ti" va antes del primer paso del cuestionario; sin edad (≥ 18),
//  sexo y peso no se continúa. Lo contestado queda en el perfil (sólo en el dispositivo)
//  y se edita desde Perfil sin regenerar el bloque ni pasar Hoy por "cargando".
//

import Foundation
import Testing
import PRCore
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current

private func today() throws -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 21
    components.hour = 12
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return try #require(calendar.date(from: components))
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-aboutyou-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let validAnswer = AboutYouAnswer(name: "Ana", age: 34, sex: .female, heightCentimeters: 165, weight: 61.2)

@MainActor
private func answerQuestionnaire(_ coordinator: OnboardingCoordinator) {
    let answers: [OnboardingAnswer] = [
        .goal(.hypertrophy), .phase(.maintenance), .experience(.intermediate),
        .trainingDays([.monday, .wednesday, .friday]), .sessionMinutes(60),
        .variety(.balanced), .restrictions(.none),
    ]
    for answer in answers {
        coordinator.select(answer)
        if case .onboarding(_, _, _, _, let isAtEnd) = coordinator.phase, !isAtEnd {
            coordinator.advance()
        }
    }
}

@MainActor
@Suite("Sobre ti en el cuestionario y en Perfil (SCRUM-198)")
struct AboutYouFlowTests {

    private func coordinator() throws -> OnboardingCoordinator {
        let date = try today()
        return OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider(), clock: { date }, timeZone: { utc })
    }

    @Test("Tras iniciar sesión, primero va 'Sobre ti'")
    func aboutYouComesFirst() async throws {
        let onboarding = try coordinator()
        await onboarding.signIn()
        #expect(onboarding.needsAboutYou)
        guard case .onboarding(let step, _, _, _, _) = onboarding.phase else {
            Issue.record("Debía estar en el cuestionario"); return
        }
        #expect(step == .goal, "El cuestionario sigue empezando en el objetivo")
    }

    @Test("El nombre que Apple entrega en el primer inicio de sesión prellena 'Sobre ti'")
    func appleNamePrefillsName() async throws {
        let date = try today()
        let onboarding = OnboardingCoordinator(
            authProvider: FakeAppleIDAuthProvider(behavior: .success(userIdentifier: "apple-user", givenName: "  Jesús ")),
            clock: { date }, timeZone: { utc }
        )
        await onboarding.signIn()
        #expect(onboarding.aboutYouAnswer.name == "Jesús")
        #expect(onboarding.auth.profile?.displayName == "Jesús")

        let withoutName = OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider(), clock: { date }, timeZone: { utc })
        await withoutName.signIn()
        #expect(withoutName.aboutYouAnswer.name.isEmpty, "Sin nombre de Apple no se inventa uno")
    }

    @Test("Sin datos completos o con menos de 18 no se continúa")
    func confirmNeedsCompleteAdultAnswer() async throws {
        let onboarding = try coordinator()
        await onboarding.signIn()
        #expect(!onboarding.confirmAboutYou(), "Vacío no")
        onboarding.updateAboutYou(AboutYouAnswer(age: 17, sex: .male, weight: 70))
        #expect(!onboarding.confirmAboutYou(), "Menor de 18 no")
        #expect(onboarding.needsAboutYou)
        onboarding.updateAboutYou(validAnswer)
        #expect(onboarding.confirmAboutYou())
        #expect(!onboarding.needsAboutYou)
    }

    @Test("Al terminar, el perfil lleva 'Sobre ti' con el año de nacimiento")
    func completedProfileCarriesAboutYou() async throws {
        let onboarding = try coordinator()
        await onboarding.signIn()
        onboarding.updateAboutYou(validAnswer)
        onboarding.confirmAboutYou()
        answerQuestionnaire(onboarding)
        onboarding.complete()
        guard case .completed(let profile) = onboarding.phase else {
            Issue.record("Debía completarse, fase \(onboarding.phase)"); return
        }
        #expect(profile.aboutYou?.birthYear == 1992)
        #expect(profile.aboutYou?.name == "Ana")
        #expect(profile.aboutYou?.sex == .female)
    }

    @Test("Rehacer: con 'Sobre ti' guardado no se vuelve a pedir; sin él, sí")
    func redoAsksOnlyWhenMissing() async throws {
        let onboarding = try coordinator()
        var profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced
        )
        onboarding.redo(from: profile)
        #expect(onboarding.needsAboutYou, "Perfil anterior sin 'Sobre ti': se pide")

        profile.aboutYou = try validAnswer.aboutYou(on: try today(), timeZone: utc)
        onboarding.redo(from: profile)
        #expect(!onboarding.needsAboutYou)
        #expect(onboarding.aboutYouAnswer.age == 34)
    }

    @Test("Editar 'Sobre ti' desde Perfil guarda el perfil sin tocar el bloque ni pasar por cargando")
    func editFromProfileKeepsBlock() async throws {
        let root = try makeRoot()
        let date = try today()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let planStore = try persistence.planStore()
        let onboarding = OnboardingCoordinator(authProvider: FakeAppleIDAuthProvider(), clock: { date }, timeZone: { utc })
        let todayPlan = TodayPlanCoordinator(
            catalog: try ExerciseCatalogLoader.loadBundled(), planStore: planStore, clock: { date }, timeZone: { utc }
        )
        let session = AppSessionCoordinator(
            onboarding: onboarding, todayPlan: todayPlan, planStore: planStore, clock: { date }, timeZone: { utc }
        )
        await session.signIn()
        answerQuestionnaire(onboarding)
        onboarding.complete()
        guard case .completed(let profile) = onboarding.phase else { Issue.record("sin perfil"); return }
        #expect(profile.aboutYou == nil, "No se confirmó 'Sobre ti': queda sin datos")
        #expect(await session.planCompleted(profile: profile))
        let blockID = try #require(todayPlan.plan?.block.id)

        #expect(await session.updateAboutYou(AboutYouAnswer(age: 15, sex: .male, weight: 50)) == false)
        #expect(await session.updateAboutYou(validAnswer))
        #expect(todayPlan.plan?.block.id == blockID, "El bloque no cambia")
        #expect(todayPlan.generation == .idle)
        guard case .loaded(let stored, let block) = await planStore.loadPlan(userID: "apple-user") else {
            Issue.record("No se leyó el plan guardado"); return
        }
        #expect(stored.profile.aboutYou?.name == "Ana")
        #expect(block.id == blockID)
    }
}
