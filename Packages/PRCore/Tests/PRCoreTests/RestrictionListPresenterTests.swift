//
//  RestrictionListPresenterTests.swift
//  PRCoreTests
//
//  SCRUM-216: Perfil › Restricciones muestra, en solo lectura, las restricciones del mismo
//  perfil que usa el plan: zona, lado, quién la declaró, si el plan la sigue cuidando y la
//  nota, en palabras simples; sin restricciones, un estado vacío. Integración con la
//  persistencia real: el perfil guardado y reabierto trae la restricción de codo que la
//  pantalla recibe, y es el mismo con el que se arma el plan.
//  SCRUM-36 cambió a propósito la forma del estado: las resueltas van aparte, en el historial
//  (`ordering` lo comprueba así).
//

import Foundation
import Testing
import PRCore
import PRDomain

private let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let spanish = RestrictionListPresenter(locale: Locale(identifier: "es_MX"), timeZone: zone)

/// Perfil hecho con el cuestionario real (paso "Restricciones" de SCRUM-209).
private func questionnaireProfile(zones: Set<BodyRegion>, note: String = "") throws -> OnboardingProfile {
    var draft = OnboardingDraft()
    let answers: [(OnboardingStep, OnboardingAnswer)] = [
        (.goal, .goal(.hypertrophy)),
        (.phase, .phase(.maintenance)),
        (.experience, .experience(.intermediate)),
        (.daysPerWeek, .trainingDays([.monday, .tuesday, .thursday, .friday])),
        (.sessionMinutes, .sessionMinutes(75)),
        (.variety, .variety(.balanced)),
        (.restrictions, .restrictions(RestrictionsAnswer(zones: zones, note: note))),
    ]
    for (step, answer) in answers { draft = draft.settingAnswer(answer, for: step) }
    return try OnboardingProfileBuilder(clock: { now }).build(from: draft)
}

/// Las que el plan cuida y, después, el historial.
private func items(_ state: RestrictionListState) -> [RestrictionListItem] {
    switch state {
    case .empty: return []
    case .loaded(let current, let history, _): return current + history
    }
}

@Suite("Perfil › Restricciones: lo que se ve (SCRUM-216 / SCRUM-36)")
struct RestrictionListPresenterTests {

    @Test("La restricción de codo del cuestionario se ve con su zona, quién la declaró, que el plan la cuida y la nota")
    func questionnaireElbow() throws {
        let profile = try questionnaireProfile(zones: [.elbow], note: "Me molesta al cargar la barra")
        let state = spanish.state(for: profile, now: now)
        guard case .loaded(let items, let history, let note) = state else {
            Issue.record("Debía haber una restricción: \(state)")
            return
        }
        #expect(note == "Me molesta al cargar la barra")
        #expect(history.isEmpty)
        let elbow = try #require(items.first)
        #expect(items.count == 1)
        #expect(elbow.region == "Codo")
        #expect(elbow.side == nil)
        #expect(elbow.source == "La declaraste tú")
        #expect(elbow.sourceKind == .userReported)
        #expect(elbow.status == "Tu plan la cuida.")
        #expect(elbow.statusKind == .active)
        #expect(elbow.accessibilityLabel == "Codo. La declaraste tú. Tu plan la cuida.")
    }

    @Test("Una indicación profesional con lado, nota y revisión vencida: sigue cuidándose (RN-004)")
    func professionalOverdue() throws {
        let shoulder = TrainingRestriction(
            bodyRegion: .shoulder, side: .right, startDate: now.addingTimeInterval(-60 * 86_400),
            reviewDate: now.addingTimeInterval(-86_400), status: .active, source: .professionalGuidance,
            forbiddenPatterns: [.verticalPress], notes: "  Sin press por encima de la cabeza  "
        )
        var profile = try questionnaireProfile(zones: [])
        profile.restrictions = [shoulder]
        let item = try #require(items(spanish.state(for: profile, now: now)).first)

        #expect(item.region == "Hombro")
        #expect(item.side == "Lado derecho")
        #expect(item.source == "Indicación de un profesional")
        #expect(item.statusKind == .reviewNeeded, "La fecha vencida no la resuelve")
        #expect(item.status == "Llegó su fecha de revisión; tu plan la sigue cuidando.")
        #expect(item.note == "Sin press por encima de la cabeza")
        #expect(item.review == "Revisión: 21 oct 2026")
        #expect(item.canAllowExercises, "Con origen profesional se ofrece permitir un ejercicio")
        // SCRUM-36: VoiceOver también lee la fecha de revisión.
        #expect(item.accessibilityLabel
                == "Hombro. Lado derecho. Indicación de un profesional. Llegó su fecha de revisión; tu plan la sigue cuidando. Revisión: 21 oct 2026. Nota: Sin press por encima de la cabeza.")
    }

    @Test("Orden: las que toca revisar, luego las activas de la cabeza a los pies; las resueltas, en el historial")
    func ordering() throws {
        var profile = try questionnaireProfile(zones: [.knee, .neck])
        profile.restrictions += [
            TrainingRestriction(bodyRegion: .wrist, startDate: now, status: .resolved),
            TrainingRestriction(bodyRegion: .ankle, startDate: now, status: .reviewNeeded),
        ]
        guard case .loaded(let current, let history, _) = spanish.state(for: profile, now: now) else {
            Issue.record("Debía haber restricciones")
            return
        }
        #expect(current.map(\.region) == ["Tobillo", "Cuello", "Rodilla"])
        #expect(history.map(\.region) == ["Muñeca"])
        #expect(history.first?.status == "Resuelta: ya no limita tu plan.")
        #expect(history.allSatisfy { !$0.isEditable })
    }

    @Test("Sin restricciones hay estado vacío; la nota del paso se conserva aunque no haya zonas")
    func emptyStates() throws {
        #expect(spanish.state(for: nil, now: now) == .empty(note: nil))
        #expect(spanish.state(for: try questionnaireProfile(zones: []), now: now) == .empty(note: nil))
        var noteOnly = try questionnaireProfile(zones: [])
        noteOnly.restrictionNote = "   "
        #expect(spanish.state(for: noteOnly, now: now) == .empty(note: nil), "Una nota en blanco no se muestra")
        noteOnly.restrictionNote = "A veces me truena la rodilla"
        #expect(spanish.state(for: noteOnly, now: now) == .empty(note: "A veces me truena la rodilla"))
    }

    @Test("En inglés también se lee en palabras simples")
    func english() throws {
        let profile = try questionnaireProfile(zones: [.elbow])
        let item = try #require(items(RestrictionListPresenter(locale: Locale(identifier: "en_US")).state(for: profile, now: now)).first)
        #expect(item.region == "Elbow")
        #expect(item.source == "You reported it")
        #expect(item.status == "Your plan works around it.")
    }

    @MainActor
    @Test("Integración: el perfil guardado con codo y reabierto llega a la pantalla, y es el que cuida el plan")
    func savedProfileReachesTheScreen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-restriction-list-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let profile = try questionnaireProfile(zones: [.elbow], note: "Me molesta al cargar la barra")

        let first = TodayPlanCoordinator(
            catalog: catalog, planStore: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).planStore(),
            clock: { now }, timeZone: { zone }
        )
        #expect(await first.activate(profile: profile, userID: "u1"))

        let reopened = TodayPlanCoordinator(
            catalog: catalog, planStore: try LocalPersistence(rootURL: root, log: PersistenceLog { _ in }).planStore(),
            clock: { now }, timeZone: { zone }
        )
        guard case .restored(let restored) = await reopened.restore(userID: "u1") else {
            Issue.record("El perfil debía restaurarse")
            return
        }
        let state = spanish.state(for: restored, now: now)
        #expect(items(state).map(\.region) == ["Codo"])
        #expect(state == spanish.state(for: profile, now: now), "La pantalla ve lo mismo que se guardó")

        // Una sola fuente: el plan restaurado evita lo que esa misma restricción prohíbe.
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let planned = await reopened.allKnownTemplates().flatMap { $0.plannedSets.compactMap { byID[$0.exerciseID] } }
        #expect(!planned.isEmpty)
        #expect(planned.allSatisfy { RestrictionPolicyEngine.verdict(for: $0, under: restored.restrictions) == .allowed })
    }
}
