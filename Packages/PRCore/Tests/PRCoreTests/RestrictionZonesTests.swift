//
//  RestrictionZonesTests.swift
//  PRCoreTests
//
//  SCRUM-209 (FB-2): las zonas del paso "Restricciones" hacen que el motor evite sus
//  patrones de riesgo con el catálogo real; la nota no cambia el plan; sin restricción el
//  plan es el mismo; un músculo que se queda sin ejercicios se omite y se explica (nunca
//  se evade la restricción ni falla el plan); los perfiles anteriores se siguen leyendo.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let fixedID = RestrictionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000209") ?? UUID())

private func profile(zones: Set<BodyRegion> = [], note: String = "") throws -> OnboardingProfile {
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
    return try OnboardingProfileBuilder(clock: { now }, newRestrictionID: { fixedID }).build(from: draft)
}

private func plan(_ profile: OnboardingProfile) throws -> (BlockPlanningResult, ExerciseCatalog) {
    let catalog = try ExerciseCatalogLoader.loadBundled()
    let result = try TodayPlanBuilder().generate(
        profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner(), blockID: TrainingBlockID()
    )
    return (result, catalog)
}

private func patterns(_ result: BlockPlanningResult, _ catalog: ExerciseCatalog) -> Set<MovementPattern> {
    let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return Set(result.block.sessions.flatMap { $0.plannedSets.compactMap { byID[$0.exerciseID]?.movementPattern } })
}

private func exercises(_ result: BlockPlanningResult) -> [[ExerciseID]] {
    result.block.sessions.map { $0.plannedSets.map(\.exerciseID) }
}

@Suite("Restricciones por zona (SCRUM-209)")
struct RestrictionZonesTests {

    @Test("Cada zona del formulario evita sus patrones y el plan se arma igual", arguments: BodyRegionRestrictionRule.selectableRegions)
    func eachZoneAvoidsItsPatterns(region: BodyRegion) throws {
        let (result, catalog) = try plan(try profile(zones: [region]))
        let forbidden = BodyRegionRestrictionRule.forbiddenPatterns(for: region)
        #expect(!forbidden.isEmpty)
        #expect(patterns(result, catalog).isDisjoint(with: forbidden), "\(region): ningún patrón prohibido en el plan")
        #expect(!result.block.sessions.isEmpty, "\(region): el plan no falla")
        #expect(result.explanation.facts.contains(DecisionFact(key: "restrictedRegions", value: region.rawValue)))
    }

    @Test("Sin restricción el plan es idéntico al de antes")
    func noRestrictionSamePlan() throws {
        let (withEmpty, _) = try plan(try profile())
        let legacy = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 75, varietyPreference: .balanced
        )
        let (before, _) = try plan(legacy)
        #expect(exercises(withEmpty) == exercises(before))
        #expect(!withEmpty.explanation.facts.contains { $0.key == "restrictedRegions" })
    }

    @Test("La nota no cambia el plan ni define el bloque")
    func noteDoesNotChangePlan() throws {
        let plain = try profile(zones: [.knee])
        let noted = try profile(zones: [.knee], note: "Me duele al bajar escaleras")
        #expect(noted.restrictionNote == "Me duele al bajar escaleras")
        #expect(exercises(try plan(plain).0) == exercises(try plan(noted).0))
        #expect(plain.trainingFields == noted.trainingFields, "Cambiar sólo la nota no regenera el bloque")
    }

    @Test("Si una restricción deja a un músculo sin ejercicios se omite y se explica; nunca se evade")
    func emptiedMuscleIsSkippedAndExplained() throws {
        // Restricción amplia (hecha en Perfil): prohíbe todo patrón de flexión de codo.
        var base = try profile()
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let bicepsPatterns = Set(catalog.exercises
            .filter { $0.primaryMuscles.contains { $0.muscleGroupID == .biceps } || $0.secondaryMuscles.contains { $0.muscleGroupID == .biceps } }
            .map(\.movementPattern))
        base.restrictions = [TrainingRestriction(bodyRegion: .elbow, startDate: now, forbiddenPatterns: bicepsPatterns)]
        let (result, _) = try plan(base)

        #expect(patterns(result, catalog).isDisjoint(with: bicepsPatterns), "Nunca se evade la restricción")
        #expect(!result.block.muscleTargets.contains { $0.muscleGroupID == .biceps })
        let skipped = try #require(result.explanation.facts.first { $0.key == "restrictedMuscles" })
        #expect(skipped.value.contains("biceps"))
        let lines = PlanRationalePresenter(locale: Locale(identifier: "es_MX"))
            .lines(facts: result.explanation.facts, emphasis: [], substitutions: [])
        #expect(lines.contains { $0.contains("Bíceps") }, "La explicación lo dice")
    }

    @Test("Rehacer el cuestionario conserva la restricción de la misma zona y las profesionales")
    func redoKeepsRestrictions() throws {
        let professional = TrainingRestriction(bodyRegion: .knee, startDate: now, source: .professionalGuidance, forbiddenPatterns: [.squat])
        let hidden = TrainingRestriction(bodyRegion: .thoracic, startDate: now, forbiddenPatterns: [.trunkRotation])
        let shoulder = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenPatterns: [.verticalPress])
        let previous = [shoulder, professional, hidden]

        // Deja hombro, desmarca rodilla (profesional) y no puede ver espalda alta.
        let result = BodyRegionRestrictionRule.restrictions(
            for: RestrictionsAnswer(zones: [.shoulder, .ankle], previous: previous), now: now
        )
        #expect(result.contains(shoulder), "Misma zona: misma restricción (mismo ID)")
        #expect(result.contains(professional), "Una restricción profesional no se quita desde el formulario")
        #expect(result.contains(hidden), "Una zona que el formulario no muestra se conserva")
        #expect(result.contains { $0.bodyRegion == .ankle && $0.source == .userReported })
    }

    @Test("Un perfil guardado antes de SCRUM-209 (con gimnasio y sin nota) se sigue leyendo")
    func legacyProfileDecodes() throws {
        // Así se guardaba: con gimnasio y sin la clave de la nota.
        let old = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 60, varietyPreference: .balanced,
            defaultGymID: GymID()
        )
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "restrictionNote")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(OnboardingProfile.self, from: legacy)
        #expect(decoded == old)
        #expect(decoded.restrictionNote == nil)
        #expect(decoded.defaultGymID != nil)
        #expect(decoded.trainingWeekdays == [.monday, .wednesday, .friday])
        let again = try JSONDecoder().decode(OnboardingProfile.self, from: try JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }
}
