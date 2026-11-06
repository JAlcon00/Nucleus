//
//  PlanPersonalizationEquivalenceTests.swift
//  PRCoreTests
//
//  SCRUM-240 (PR-E008): la IA usa la misma regla de equivalencia que el motor de sustitutos
//  (SCRUM-232, DE-3). Mismo músculo no es ejercicio equivalente: lo que hace otro movimiento
//  o no llega al mínimo ni se le ofrece ni se le acepta. Sin red.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let conversation = UUID(uuidString: "00000000-0000-0000-0000-000000000240") ?? UUID()

private func exercise(
    _ name: String,
    pattern: MovementPattern = .horizontalPull,
    primary: [MuscleGroup] = [.back],
    secondary: [MuscleGroup] = [],
    equipment: EquipmentType = .dumbbell,
    jointClass: JointClass = .multiJoint,
    roles: Set<ExerciseRole> = [.primaryCompound],
    stability: DemandLevel = .moderate
) throws -> Exercise {
    Exercise(
        canonicalName: name,
        movementPattern: pattern,
        primaryMuscles: try primary.map { try MuscleContribution(muscleGroupID: $0, activation: 1.0) },
        secondaryMuscles: try secondary.map { try MuscleContribution(muscleGroupID: $0, activation: 0.4) },
        equipment: equipment,
        jointClass: jointClass,
        stabilityDemand: stability,
        skillDemand: .moderate,
        systemicFatigueCost: try FatigueCost(normalized: 0.5),
        loadability: .discreteIncrements,
        defaultRoles: roles,
        substitutionFamilyID: ExerciseFamily(name: name, movementPatterns: [pattern]).id
    )
}

/// Espalda: un remo en el plan y candidatos que fallan cada parte de la regla.
private struct Back {
    let row: Exercise
    let dumbbellRow: Exercise
    let cableRow: Exercise
    /// Mismo músculo y clase articular, otro patrón.
    let pullUp: Exercise
    /// Mismo patrón y clase articular, otro músculo.
    let rearDeltRow: Exercise
    /// Mismo patrón y músculo, otra clase articular.
    let straightArmRow: Exercise
    /// Cumple patrón, músculo y clase articular, pero se parece poco: queda bajo el mínimo.
    let awkwardRow: Exercise
    let curl: Exercise

    init() throws {
        row = try exercise("Remo con barra", equipment: .barbell)
        dumbbellRow = try exercise("Remo con mancuerna")
        cableRow = try exercise("Remo en polea", equipment: .cable)
        pullUp = try exercise("Dominadas", pattern: .verticalPull, equipment: .bodyweight)
        rearDeltRow = try exercise("Remo al deltoide", primary: [.shoulders])
        straightArmRow = try exercise("Remo con brazos rectos", jointClass: .singleJoint)
        awkwardRow = try exercise(
            "Remo raro", primary: [.back, .biceps, .shoulders, .forearms], equipment: .other, roles: [.anchor]
        )
        curl = try exercise("Curl", pattern: .elbowFlexion, primary: [.biceps], jointClass: .singleJoint)
    }

    var catalog: [Exercise] {
        [row, dumbbellRow, cableRow, pullUp, rearDeltRow, straightArmRow, awkwardRow, curl]
    }
}

private func block(_ exercises: [Exercise], pairs: [(Exercise, Exercise)] = []) throws -> TrainingBlock {
    let work = try SetPrescription(targetRepRange: 8...12, loadUnit: .kilograms, restSeconds: 60...90)
    let session = SessionTemplate(
        title: "Espalda",
        plannedSets: exercises.flatMap { exercise in
            Array(repeating: PlannedSet(exerciseID: exercise.id, prescription: work), count: 3)
        },
        supersets: try pairs.map { pair in try #require(SupersetPair(first: pair.0.id, second: pair.1.id)) }
    )
    return try TrainingBlock(
        name: "Espalda",
        goal: .hypertrophy,
        phase: .maintenance,
        startDate: now,
        plannedWeeks: 6,
        sessions: [session],
        muscleTargets: [try MuscleVolumeTarget(muscleGroupID: .back, targetSetsPerWeek: 6)],
        priorities: [MusclePriority(muscleGroupID: .back, priority: .normal)],
        progressionPolicy: .doubleProgression,
        deloadPolicy: .afterSixWeeks,
        varietyPolicy: try VarietyPolicy(percentStable: 0.65)
    )
}

private func review(
    _ replace: Exercise, with candidate: Exercise, in block: TrainingBlock, catalog: [Exercise],
    equipment: EquipmentKnownness = .unknown, restrictions: [TrainingRestriction] = []
) throws -> PersonalizationReview {
    try PlanPersonalizationValidator.standard().reviewSubstitutions(
        [ProposedSubstitution(replace: replace.id, with: candidate.id)], block: block, catalog: catalog,
        activeRestrictions: restrictions, equipment: equipment, conversationID: conversation, now: now
    )
}

private func plan(days: Int, minutes: Int = 90) -> OnboardingProfile {
    OnboardingProfile(
        goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: days,
        usualSessionMinutes: minutes, varietyPreference: .balanced, defaultGymID: nil, restrictions: []
    )
}

@Suite("SCRUM-240 · La IA sólo propone sustitutos equivalentes de verdad")
struct PlanPersonalizationEquivalenceTests {

    @Test("Otro patrón: se rechaza, el plan conserva el remo y la bitácora guarda el motivo")
    func differentPatternIsRejected() throws {
        let back = try Back()
        let base = try block([back.row])
        let review = try review(back.row, with: back.pullUp, in: base, catalog: back.catalog)

        #expect(review.decisions.map(\.outcome) == [.rejected(.differentPattern)])
        #expect(review.acceptedSubstitutions.isEmpty)
        #expect(PlanPersonalizationApplier.substituting(review.acceptedSubstitutions, in: base) == base)
        let rejection = try #require(review.audit.last)
        #expect(rejection.notes == [PersonalizationRejection.differentPattern.rawValue])
    }

    @Test("Bajo el mínimo: se rechaza y la bitácora lleva la versión de la regla")
    func belowMinimumIsRejectedWithTheRule() throws {
        let back = try Back()
        let review = try review(back.row, with: back.awkwardRow, in: block([back.row]), catalog: back.catalog)

        #expect(review.decisions.map(\.outcome) == [.rejected(.belowMinimumScore)])
        let rejection = try #require(review.audit.last)
        #expect(rejection.notes == [PersonalizationRejection.belowMinimumScore.rawValue])
        #expect(rejection.ruleReference == (try EvidenceRuleReference(SubstitutionScoringDefaults.makeRule())))
    }

    @Test("Un sustituto equivalente se sigue aceptando")
    func equivalentSubstituteIsAccepted() throws {
        let back = try Back()
        let review = try review(back.row, with: back.dumbbellRow, in: block([back.row]), catalog: back.catalog)
        #expect(review.decisions.map(\.outcome) == [.accepted])
    }

    @Test("El motivo es el primero que falla, en el orden fijo de la regla")
    func rejectionOrder() throws {
        let back = try Back()
        let base = try block([back.row, back.curl], pairs: [(back.row, back.curl)])
        let noneOfThese = EquipmentKnownness.knownAvailable([.barbell])

        // Otro músculo y otro patrón.
        let curlLike = try exercise("Curl en polea", pattern: .elbowFlexion, primary: [.biceps], jointClass: .singleJoint)
        // Otro patrón y otra clase articular.
        let pullover = try exercise("Pullover", pattern: .verticalPull, jointClass: .singleJoint)
        // Otra clase articular y sin equipo.
        let straightArm = back.straightArmRow
        // Sin equipo y bajo el mínimo.
        let awkward = back.awkwardRow
        // Bajo el mínimo y rompe el superset (comparte bíceps con el curl).
        let awkwardWithBiceps = try exercise(
            "Remo raro con bíceps", primary: [.back, .biceps, .shoulders, .forearms], equipment: .barbell, roles: [.anchor]
        )
        let catalog = back.catalog + [curlLike, pullover, awkwardWithBiceps]

        func outcome(_ candidate: Exercise, equipment: EquipmentKnownness) throws -> [PersonalizationOutcome] {
            try review(back.row, with: candidate, in: base, catalog: catalog, equipment: equipment).decisions.map(\.outcome)
        }
        #expect(try outcome(curlLike, equipment: noneOfThese) == [.rejected(.differentMuscle)])
        #expect(try outcome(pullover, equipment: noneOfThese) == [.rejected(.differentPattern)])
        #expect(try outcome(straightArm, equipment: noneOfThese) == [.rejected(.differentJointClass)])
        #expect(try outcome(awkward, equipment: noneOfThese) == [.rejected(.equipmentUnavailable)])
        #expect(try outcome(awkwardWithBiceps, equipment: noneOfThese) == [.rejected(.belowMinimumScore)])
    }

    @Test("A la IA se le ofrecen las mejores por puntaje, no las primeras del catálogo")
    func alternativesAreRankedByScore() throws {
        let back = try Back()
        let weakest = try exercise("A remo flojo", roles: [.secondaryCompound], stability: .high)
        let weak = try exercise("B remo regular", stability: .high)
        let best = try exercise("Z remo igual")
        let tied = try exercise("Y remo igual")
        let catalog = [back.row, weakest, weak, best, tied, back.pullUp, back.awkwardRow]
        let validator = try PlanPersonalizationValidator.standard()
        let base = try block([back.row])

        let first = try validator.alternatives(block: base, catalog: catalog, activeRestrictions: [], equipment: .unknown, now: now)
        let again = try validator.alternatives(
            block: base, catalog: catalog.reversed(), activeRestrictions: [], equipment: .unknown, now: now
        )

        #expect(first[back.row.id] == [tied.id, best.id, weak.id], "Por puntaje; si empatan, por nombre; hasta el máximo")
        #expect(first == again, "No depende del orden del catálogo")
    }

    @Test("Un ejercicio sin equivalentes no aparece, y lo que proponga la IA se rechaza")
    func exerciseWithoutEquivalents() throws {
        let back = try Back()
        let catalog = [back.row, back.pullUp, back.rearDeltRow, back.straightArmRow]
        let base = try block([back.row])

        let alternatives = try PlanPersonalizationValidator.standard().alternatives(
            block: base, catalog: catalog, activeRestrictions: [], equipment: .unknown, now: now
        )
        #expect(alternatives[back.row.id] == nil)
        #expect(try review(back.row, with: back.pullUp, in: base, catalog: catalog).decisions.map(\.outcome)
            == [.rejected(.differentPattern)])
    }

    @Test("Un equivalente prohibido nunca se ofrece y se rechaza, también con la revisión vencida")
    func forbiddenEquivalent() throws {
        let back = try Back()
        let base = try block([back.row])
        let active = TrainingRestriction(bodyRegion: .shoulder, startDate: now, forbiddenExerciseIDs: [back.dumbbellRow.id])
        let overdue = TrainingRestriction(
            bodyRegion: .shoulder, startDate: now.addingTimeInterval(-86_400 * 30), reviewDate: now.addingTimeInterval(-86_400),
            forbiddenExerciseIDs: [back.dumbbellRow.id]
        )
        for restriction in [active, overdue] {
            let alternatives = try PlanPersonalizationValidator.standard().alternatives(
                block: base, catalog: back.catalog, activeRestrictions: [restriction], equipment: .unknown, now: now
            )
            #expect(alternatives[back.row.id] == [back.cableRow.id], "Sólo queda la polea")
            #expect(try review(back.row, with: back.dumbbellRow, in: base, catalog: back.catalog, restrictions: [restriction])
                .decisions.map(\.outcome) == [.rejected(.rejectedByPolicy)])
        }
    }

    @Test("La IA propone el mismo sustituto dos veces: la segunda es duplicado")
    func duplicateSubstitute() throws {
        let back = try Back()
        let secondRow = try exercise("Remo en máquina", equipment: .machine)
        let base = try block([back.row, secondRow])
        let review = try PlanPersonalizationValidator.standard().reviewSubstitutions(
            [
                ProposedSubstitution(replace: back.row.id, with: back.dumbbellRow.id),
                ProposedSubstitution(replace: secondRow.id, with: back.dumbbellRow.id),
            ],
            block: base, catalog: back.catalog + [secondRow], activeRestrictions: [], equipment: .unknown,
            conversationID: conversation, now: now
        )
        #expect(review.decisions.map(\.outcome) == [.accepted, .rejected(.duplicate)])
    }

    @Test("Catálogo real: lo que se le ofrece a la IA es lo que da el motor de sustitutos", arguments: [2, 4, 6])
    func parityWithTheSubstitutionEngine(days: Int) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let builder = TodayPlanBuilder()
        let generated = try builder.generate(profile: plan(days: days), catalog: catalog, planner: TodayPlanBuilder.defaultPlanner()).block
        var base = generated
        base.sessions = generated.sessions.map { session in
            var session = session
            session.supersets = nil
            return session
        }
        let inPlan = Set(base.sessions.flatMap(\.plannedSets).map(\.exerciseID))
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let validator = try PlanPersonalizationValidator.standard()
        let engine = SubstitutionScoringEngine(config: try SubstitutionScoringConfig(rule: SubstitutionScoringDefaults.makeRule()))
        let alternatives = try validator.alternatives(
            block: base, catalog: catalog.exercises, activeRestrictions: [], equipment: .unknown, now: now
        )

        for id in inPlan.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            let target = try #require(byID[id])
            let verdict = try engine.substitutes(for: SubstitutionRequest(
                target: target, candidates: catalog.exercises, sessionExerciseIDs: inPlan, asOf: now
            ))
            #expect(alternatives[id] ?? [] == verdict.ranked.map(\.exercise.id), "Ofrecidas para \(target.canonicalName)")
            for option in alternatives[id] ?? [] {
                #expect(byID[option]?.movementPattern == target.movementPattern, "Otro patrón para \(target.canonicalName)")
            }
            // Lo que se acepta: cada candidato del mismo patrón, contra el motor.
            for candidate in catalog.exercises where candidate.movementPattern == target.movementPattern && !inPlan.contains(candidate.id) {
                let equivalent = try !engine.substitutes(for: SubstitutionRequest(target: target, candidates: [candidate], asOf: now)).ranked.isEmpty
                let accepted = try validator.reviewSubstitutions(
                    [ProposedSubstitution(replace: id, with: candidate.id)], block: base, catalog: [target, candidate],
                    activeRestrictions: [], equipment: .unknown, conversationID: conversation, now: now
                ).decisions.allSatisfy(\.isAccepted)
                #expect(accepted == equivalent, "\(target.canonicalName) → \(candidate.canonicalName)")
            }
        }
    }
}
