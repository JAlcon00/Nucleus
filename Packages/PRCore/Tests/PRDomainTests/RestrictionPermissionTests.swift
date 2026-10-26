//
//  RestrictionPermissionTests.swift
//  PRDomainTests
//
//  SCRUM-31 (PR-0109): mis restricciones nunca se saltan. Los tres lugares que revisan
//  restricciones (el plan con `ExerciseAssigner`, las sustituciones y la IA con
//  `RestrictionPolicyEngine`, el dropset con `IntensityAdvisor`) dan el mismo veredicto:
//  prohibir gana a permitir, el permiso de una restricción sólo refina esa restricción,
//  un ejercicio vale sólo si ninguna lo prohíbe (en cualquier orden), las resueltas no
//  cuentan y una fecha de revisión vencida no es curación.
//

import Foundation
import Testing
@testable import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

private func exercise(
    _ name: String,
    pattern: MovementPattern,
    muscle: MuscleGroup = .quadriceps,
    tags: Set<RestrictionTag> = []
) throws -> Exercise {
    try Exercise(
        canonicalName: name,
        movementPattern: pattern,
        primaryMuscles: [MuscleContribution(muscleGroupID: muscle, activation: 1.0)],
        equipment: .dumbbell,
        jointClass: .multiJoint,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: [],
        contraindicationTags: tags,
        substitutionFamilyID: ExerciseFamilyID()
    )
}

/// Lo que dice cada lugar que revisa restricciones sobre un ejercicio.
private struct Verdicts: Equatable, CustomStringConvertible {
    let plan: Bool
    let substitution: Bool
    let dropset: Bool

    static let allowed = Verdicts(plan: true, substitution: true, dropset: true)
    static let forbidden = Verdicts(plan: false, substitution: false, dropset: false)

    var description: String { "plan \(plan) · sustitución \(substitution) · dropset \(dropset)" }
}

private func verdicts(_ exercise: Exercise, _ restrictions: [TrainingRestriction]) throws -> Verdicts {
    // Plan: con un catálogo de sólo ese ejercicio, el assigner lo programa o no tiene qué programar.
    let muscle = try #require(exercise.primaryMuscles.first?.muscleGroupID)
    let planned = (try? ExerciseAssigner().assign(input: ExerciseAssignmentInput(
        muscleGroupID: muscle, catalog: [exercise], varietyPreference: .balanced,
        restrictions: restrictions, equipmentKnownness: .unknown
    ))) != nil
    let engine = try RestrictionPolicyEngine(config: RestrictionPolicyConfig(rule: RestrictionPolicyDefaults.makeRule()))
    let substitution = try engine.evaluate(
        RestrictionPolicyInput(exercise: exercise, activeRestrictions: restrictions, asOf: now)
    ).isAllowed
    let dropset = !IntensityAdvisor.isRestricted(exercise, by: restrictions)
    return Verdicts(plan: planned, substitution: substitution, dropset: dropset)
}

/// Todas las permutaciones: el veredicto no puede depender del orden.
private func permutations<T>(_ items: [T]) -> [[T]] {
    guard items.count > 1 else { return [items] }
    return items.indices.flatMap { index -> [[T]] in
        var rest = items
        let head = rest.remove(at: index)
        return permutations(rest).map { [head] + $0 }
    }
}

@Suite("Mis restricciones nunca se saltan (SCRUM-31)")
struct RestrictionPermissionTests {

    @Test("Permisos cruzados hombro + rodilla: el permiso de una no anula la prohibición de la otra")
    func crossAllowListNeverOverridesAnotherRestriction() throws {
        let lunge = try exercise("Zancada búlgara", pattern: .lunge)
        let landmine = try exercise("Press landmine", pattern: .verticalPress, muscle: .shoulders)
        let overhead = try exercise("Press militar", pattern: .verticalPress, muscle: .shoulders)
        // Hombro: evita el press vertical pero permite el landmine (refina lo suyo) y, por
        // error o por otra indicación, también la zancada que la rodilla prohíbe.
        let shoulder = TrainingRestriction(
            bodyRegion: .shoulder, startDate: now, forbiddenPatterns: BodyRegionRestrictionRule.forbiddenPatterns(for: .shoulder),
            allowedExerciseIDs: [landmine.id, lunge.id]
        )
        let knee = TrainingRestriction(
            bodyRegion: .knee, startDate: now, forbiddenPatterns: BodyRegionRestrictionRule.forbiddenPatterns(for: .knee)
        )
        for order in permutations([shoulder, knee]) {
            #expect(try verdicts(lunge, order) == .forbidden, "La zancada la prohíbe la rodilla; el permiso del hombro no la salva")
            #expect(try verdicts(landmine, order) == .allowed, "El permiso del hombro sí refina su propio patrón")
            #expect(try verdicts(overhead, order) == .forbidden)
        }
    }

    @Test("Prohibir por ID gana al permiso, incluso en la misma restricción")
    func explicitForbidBeatsOwnAllow() throws {
        let squat = try exercise("Sentadilla", pattern: .squat)
        let contradictory = TrainingRestriction(
            bodyRegion: .knee, startDate: now, forbiddenExerciseIDs: [squat.id], allowedExerciseIDs: [squat.id]
        )
        #expect(try verdicts(squat, [contradictory]) == .forbidden)
    }

    @Test("Varias restricciones: un ejercicio vale sólo si ninguna lo prohíbe, en cualquier orden")
    func everyRestrictionIsRespected() throws {
        let byPattern = try exercise("Extensión de pierna", pattern: .kneeExtension)
        let byID = try exercise("Sentadilla hack", pattern: .squat)
        let byTag = try exercise("Sentadilla con barra", pattern: .squat, tags: [.lowerBack])
        let free = try exercise("Prensa", pattern: .squat)
        let restrictions = [
            TrainingRestriction(bodyRegion: .knee, startDate: now, forbiddenPatterns: [.kneeExtension]),
            TrainingRestriction(bodyRegion: .hip, startDate: now, forbiddenExerciseIDs: [byID.id]),
            TrainingRestriction(bodyRegion: .lumbar, startDate: now, restrictionTags: [.lowerBack]),
        ]
        for order in permutations(restrictions) {
            for forbidden in [byPattern, byID, byTag] {
                #expect(try verdicts(forbidden, order) == .forbidden, "\(forbidden.canonicalName)")
            }
            #expect(try verdicts(free, order) == .allowed, "Ninguna prohíbe la prensa")
        }
    }

    @Test("Una restricción resuelta ya no limita")
    func resolvedNoLongerLimits() throws {
        let lunge = try exercise("Zancada", pattern: .lunge)
        let resolved = TrainingRestriction(
            bodyRegion: .knee, startDate: now, status: .resolved, forbiddenPatterns: [.lunge], forbiddenExerciseIDs: [lunge.id]
        )
        #expect(try verdicts(lunge, [resolved]) == .allowed)
    }

    @Test("Fecha de revisión vencida o pendiente de revisión: sigue aplicando hasta confirmar que se resolvió")
    func reviewDateIsNotRecovery() throws {
        let lunge = try exercise("Zancada", pattern: .lunge)
        let overdue = TrainingRestriction(
            bodyRegion: .knee, startDate: now.addingTimeInterval(-90 * 86_400), reviewDate: now.addingTimeInterval(-86_400),
            status: .active, forbiddenPatterns: [.lunge]
        )
        let pending = TrainingRestriction(bodyRegion: .knee, startDate: now, status: .reviewNeeded, forbiddenPatterns: [.lunge])
        #expect(overdue.refreshed(asOf: now).status == .reviewNeeded)
        for restriction in [overdue, pending] {
            #expect(try verdicts(lunge, [restriction]) == .forbidden)
        }
    }

    @Test("Las reglas por defecto de los tres lugares son las de la regla versionada")
    func defaultScopeIsTheVersionedRule() throws {
        let versioned = try RestrictionPolicyConfig(rule: RestrictionPolicyDefaults.makeRule()).scope
        #expect(versioned == RestrictionPolicyScope())
    }

    @Test("El veredicto combinado dice qué prohíbe: por ID antes que patrón y patrón antes que etiqueta")
    func combinedVerdictPrecedence() throws {
        let squat = try exercise("Sentadilla", pattern: .squat, tags: [.knee, .lowerBack])
        let byTag = TrainingRestriction(bodyRegion: .lumbar, startDate: now, restrictionTags: [.lowerBack, .knee])
        let byPattern = TrainingRestriction(bodyRegion: .knee, startDate: now, forbiddenPatterns: [.squat, .lunge])
        let byID = TrainingRestriction(bodyRegion: .hip, startDate: now, forbiddenExerciseIDs: [squat.id])

        #expect(RestrictionPolicyEngine.verdict(for: squat, under: [byTag]) == .forbiddenByTag([.knee, .lowerBack]))
        #expect(RestrictionPolicyEngine.verdict(for: squat, under: [byTag, byPattern]) == .forbiddenPattern([.squat]))
        #expect(RestrictionPolicyEngine.verdict(for: squat, under: [byTag, byPattern, byID]) == .forbiddenExplicit)
        #expect(RestrictionPolicyEngine.verdict(for: squat, under: []) == .allowed)
    }
}
