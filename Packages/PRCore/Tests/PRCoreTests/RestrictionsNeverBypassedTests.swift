//
//  RestrictionsNeverBypassedTests.swift
//  PRCoreTests
//
//  SCRUM-31 (PR-0109) con el catálogo real: restricciones de hombro y rodilla con permisos
//  cruzados nunca dejan pasar un ejercicio prohibido al plan guardado (persistencia real en
//  un directorio temporal), a las sustituciones ni a lo que se le ofrece a la IA; un músculo
//  sin ejercicio seguro se omite y se explica; y 100 planes con restricciones al azar
//  (semilla fija) traen 0 ejercicios prohibidos.
//
//  El oráculo `isForbidden` está escrito aparte a partir de la historia, sin reutilizar el
//  código que decide.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
private let now = Date(timeIntervalSince1970: 1_792_670_400)

/// La historia, tal cual: prohibido si alguna restricción en vigor lo prohíbe por ID, o por
/// patrón o etiqueta sin que ESA MISMA restricción lo permita. Las resueltas no cuentan.
private func isForbidden(_ exercise: Exercise, by restrictions: [TrainingRestriction]) -> Bool {
    restrictions.contains { restriction in
        guard restriction.status != .resolved else { return false }
        if restriction.forbiddenExerciseIDs.contains(exercise.id) { return true }
        let hit = restriction.forbiddenPatterns.contains(exercise.movementPattern)
            || !restriction.restrictionTags.isDisjoint(with: exercise.contraindicationTags)
        return hit && !restriction.allowedExerciseIDs.contains(exercise.id)
    }
}

private func planned(_ templates: [SessionTemplate], _ catalog: ExerciseCatalog) -> [Exercise] {
    let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return templates.flatMap { $0.plannedSets.compactMap { byID[$0.exerciseID] } }
}

private func ids(_ catalog: ExerciseCatalog, patterns: Set<MovementPattern>) -> Set<ExerciseID> {
    Set(catalog.exercises.filter { patterns.contains($0.movementPattern) }.map(\.id))
}

/// Hombro y rodilla del formulario; cada una "permite" todo lo que la otra prohíbe.
private func crossedShoulderAndKnee(_ catalog: ExerciseCatalog) -> [TrainingRestriction] {
    let shoulderPatterns = BodyRegionRestrictionRule.forbiddenPatterns(for: .shoulder)
    let kneePatterns = BodyRegionRestrictionRule.forbiddenPatterns(for: .knee)
    let shoulder = TrainingRestriction(
        bodyRegion: .shoulder, startDate: now, forbiddenPatterns: shoulderPatterns,
        allowedExerciseIDs: ids(catalog, patterns: kneePatterns)
    )
    let knee = TrainingRestriction(
        bodyRegion: .knee, startDate: now, forbiddenPatterns: kneePatterns,
        allowedExerciseIDs: ids(catalog, patterns: shoulderPatterns)
    )
    return [shoulder, knee]
}

private func profile(_ restrictions: [TrainingRestriction]) throws -> OnboardingProfile {
    var profile = try OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
        trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 75, varietyPreference: .varied
    )
    profile.restrictions = restrictions
    return profile
}

private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pr-restrictions-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// SplitMix64: generador con semilla para que los 100 planes sean siempre los mismos.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Mis restricciones nunca se saltan con el catálogo real (SCRUM-31)")
struct RestrictionsNeverBypassedTests {

    @MainActor
    @Test("Hombro + rodilla con permisos cruzados: el plan guardado no trae nada prohibido, ni tras reabrir")
    func crossedPermissionsPlanAndPersistence() async throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let restrictions = crossedShoulderAndKnee(catalog)
        let root = try makeRoot()
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let first = TodayPlanCoordinator(catalog: catalog, planStore: try persistence.planStore(), clock: { now }, timeZone: { zone })
        #expect(await first.activate(profile: try profile(restrictions), userID: "u1"))

        let reopened = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        let second = TodayPlanCoordinator(catalog: catalog, planStore: try reopened.planStore(), clock: { now }, timeZone: { zone })
        #expect(await second.restore(userID: "u1") == .restored(try profile(restrictions)))
        let exercises = planned(await second.allKnownTemplates(), catalog)
        #expect(!exercises.isEmpty)
        let forbidden = exercises.filter { isForbidden($0, by: restrictions) }
        #expect(forbidden.isEmpty, "Prohibidos en el plan: \(Set(forbidden.map(\.canonicalName)).sorted())")
    }

    @Test("Hombro + rodilla con permisos cruzados: sustituciones, IA y dropset tampoco dejan pasar nada")
    func crossedPermissionsSubstitutionsAgentAndDropset() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let restrictions = crossedShoulderAndKnee(catalog)
        let builder = TodayPlanBuilder()
        let result = try builder.generate(profile: try profile(restrictions), catalog: catalog, planner: TodayPlanBuilder.defaultPlanner())
        let inPlan = planned(result.block.sessions, catalog)

        // Sustituciones: con todo el catálogo como candidatos.
        let engine = SubstitutionScoringEngine(config: try SubstitutionScoringConfig(rule: SubstitutionScoringDefaults.makeRule()))
        for target in Dictionary(inPlan.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values {
            let verdict = try engine.substitutes(for: SubstitutionRequest(
                target: target, candidates: catalog.exercises, activeRestrictions: restrictions, asOf: now
            ))
            let forbidden = verdict.ranked.map(\.exercise).filter { isForbidden($0, by: restrictions) }
            #expect(forbidden.isEmpty, "Sustitutos prohibidos de \(target.canonicalName): \(forbidden.map(\.canonicalName))")
        }

        // IA: lo que se le ofrece y lo que se acepta si lo propone.
        let validator = try PlanPersonalizationValidator.standard()
        let equipment = builder.defaultEquipmentKnownness()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let offered = try validator.alternatives(
            block: result.block, catalog: catalog.exercises, activeRestrictions: restrictions, equipment: equipment, now: now
        )
        let offeredForbidden = offered.values.flatMap { $0 }.compactMap { byID[$0] }.filter { isForbidden($0, by: restrictions) }
        #expect(offeredForbidden.isEmpty, "Alternativas prohibidas ofrecidas a la IA: \(offeredForbidden.map(\.canonicalName))")

        // Una propuesta con forma válida pero prohibida (sólo "permitida" por la otra zona) se rechaza.
        let unrestricted = try validator.alternatives(
            block: result.block, catalog: catalog.exercises, activeRestrictions: [], equipment: equipment, now: now
        )
        let proposal = unrestricted.sorted { $0.key.rawValue.uuidString < $1.key.rawValue.uuidString }.lazy.compactMap { replace, options in
            options.first { byID[$0].map { isForbidden($0, by: restrictions) } ?? false }.map { ProposedSubstitution(replace: replace, with: $0) }
        }.first
        let forbiddenProposal = try #require(proposal, "El catálogo real tiene alguna alternativa que sólo la otra zona permite")
        let review = try validator.reviewSubstitutions(
            [forbiddenProposal], block: result.block, catalog: catalog.exercises, activeRestrictions: restrictions,
            equipment: equipment, conversationID: UUID(), now: now
        )
        #expect(review.decisions.map(\.outcome) == [.rejected(.rejectedByPolicy)])

        // Dropset: todo lo prohibido cuenta como restringido; lo del plan no.
        for exercise in catalog.exercises {
            #expect(IntensityAdvisor.isRestricted(exercise, by: restrictions) == isForbidden(exercise, by: restrictions), "\(exercise.canonicalName)")
        }
    }

    @Test("Un músculo sin ejercicio seguro se omite y se explica, aunque otra restricción \"permita\" sus ejercicios")
    func emptiedMuscleWithCrossedPermission() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let biceps = catalog.exercises.filter {
            $0.primaryMuscles.contains { $0.muscleGroupID == .biceps } || $0.secondaryMuscles.contains { $0.muscleGroupID == .biceps }
        }
        let elbow = TrainingRestriction(bodyRegion: .elbow, startDate: now, forbiddenPatterns: Set(biceps.map(\.movementPattern)))
        let shoulder = TrainingRestriction(
            bodyRegion: .shoulder, startDate: now, forbiddenPatterns: [.verticalPress], allowedExerciseIDs: Set(biceps.map(\.id))
        )
        // El hombro primero: el orden en el que antes su permiso le ganaba al codo.
        let restrictions = [shoulder, elbow]
        let result = try TodayPlanBuilder().generate(
            profile: try profile(restrictions), catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()
        )

        let forbidden = planned(result.block.sessions, catalog).filter { isForbidden($0, by: restrictions) }
        #expect(forbidden.isEmpty, "Nunca se fuerza uno: \(Set(forbidden.map(\.canonicalName)).sorted())")
        #expect(!result.block.muscleTargets.contains { $0.muscleGroupID == .biceps })
        let skipped = try #require(result.explanation.facts.first { $0.key == "restrictedMuscles" })
        #expect(skipped.value.contains("biceps"), "La explicación lo dice")
    }

    @Test("100 planes con restricciones al azar (semilla fija): 0 ejercicios prohibidos")
    func hundredSeededPlans() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let builder = TodayPlanBuilder()
        let planner = TodayPlanBuilder.defaultPlanner()
        var rng = SeededGenerator(seed: 31)
        var violations: [String] = []
        var failures: [String] = []
        var crossedPermissions = 0

        for index in 0..<100 {
            let zones = Set(BodyRegionRestrictionRule.selectableRegions.filter { _ in Bool.random(using: &rng) })
            var restrictions = BodyRegionRestrictionRule.restrictions(for: RestrictionsAnswer(zones: zones), now: now)
            let anyForbidden = ids(catalog, patterns: Set(restrictions.flatMap(\.forbiddenPatterns))).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            let everything = catalog.exercises.map(\.id)
            restrictions = restrictions.map { restriction in
                var restriction = restriction
                // Permisos que suelen caer en lo que prohíbe otra zona, IDs prohibidos y estados al azar.
                restriction.allowedExerciseIDs = Set((0..<Int.random(in: 0...12, using: &rng)).compactMap { _ in anyForbidden.randomElement(using: &rng) })
                restriction.forbiddenExerciseIDs = Set((0..<Int.random(in: 0...3, using: &rng)).compactMap { _ in everything.randomElement(using: &rng) })
                restriction.status = [RestrictionStatus.active, .active, .reviewNeeded, .resolved].randomElement(using: &rng) ?? .active
                return restriction
            }
            crossedPermissions += restrictions.filter { restriction in
                restrictions.contains { other in
                    other.id != restriction.id && other.status != .resolved
                        && !restriction.allowedExerciseIDs.isDisjoint(with: ids(catalog, patterns: other.forbiddenPatterns))
                }
            }.count

            let days = Int.random(in: 2...6, using: &rng)
            var profile = OnboardingProfile(
                goal: TrainingGoal.allCases.randomElement(using: &rng) ?? .hypertrophy,
                phase: BodyCompositionPhase.allCases.randomElement(using: &rng) ?? .maintenance,
                experience: ExperienceLevel.allCases.randomElement(using: &rng) ?? .intermediate,
                trainingDaysPerWeek: days,
                usualSessionMinutes: [45, 60, 75, 90].randomElement(using: &rng) ?? 60,
                varietyPreference: VarietyPreference.allCases.randomElement(using: &rng) ?? .balanced
            )
            profile.restrictions = restrictions
            do {
                let result = try builder.generate(profile: profile, catalog: catalog, planner: planner)
                let forbidden = planned(result.block.sessions, catalog).filter { isForbidden($0, by: restrictions) }
                if !forbidden.isEmpty {
                    violations.append("plan \(index): \(Set(forbidden.map(\.canonicalName)).sorted())")
                }
            } catch {
                failures.append("plan \(index): \(error)")
            }
        }

        #expect(crossedPermissions > 0, "La semilla sí genera permisos cruzados (si no, la prueba no prueba nada)")
        #expect(failures.isEmpty, "Planes que no se pudieron armar: \(failures)")
        #expect(violations.isEmpty, "Planes con ejercicios prohibidos: \(violations)")
    }
}
