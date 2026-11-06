//
//  SubstitutionScoringTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del motor de scoring de sustitución (PR-0904): gate de seguridad, ranking
//  reproducible por pesos del §10.3, dimensiones de matching y "no safe substitute".
//

import Foundation
import Testing
@testable import PRDomain

private enum SubstitutionFixture {
    // target: DB flat bench press
    static let dbBench = make(
        name: "Dumbbell Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [.triceps, .shoulders],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .moderate,
        fatigue: 0.5
    )

    // ideal muscle + pattern + role + angle, different equipment
    static let smithBench = make(
        name: "Smith Machine Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .smithMachine,
        primary: [.chest],
        secondary: [.triceps, .shoulders],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .low,
        fatigue: 0.5
    )

    // same muscle, same pattern, but incline angle + higher stability
    static let inclineDB = make(
        name: "Incline Dumbbell Press",
        pattern: .horizontalPress,
        angle: .incline,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [.shoulders, .triceps],
        roles: [.secondaryCompound],
        stability: .high,
        fatigue: 0.45
    )

    // different pattern (vertical press) and different primary (shoulders)
    static let shoulderPress = make(
        name: "Shoulder Press",
        pattern: .verticalPress,
        angle: .overhead,
        equipment: .barbell,
        primary: [.shoulders],
        secondary: [.triceps],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .high,
        fatigue: 0.35
    )

    // SCRUM-232: el mismo press con otro equipo.
    static let barbellBench = make(
        name: "Barbell Bench Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .barbell,
        primary: [.chest],
        secondary: [.triceps, .shoulders],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .moderate,
        fatigue: 0.55
    )

    static let machinePress = make(
        name: "Machine Chest Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .machine,
        primary: [.chest],
        secondary: [.triceps],
        roles: [.secondaryCompound],
        stability: .low,
        fatigue: 0.4
    )

    // mismo músculo y clase articular, otro patrón
    static let chestDip = make(
        name: "Chest Dip",
        pattern: .verticalPress,
        angle: nil,
        equipment: .bodyweight,
        primary: [.chest],
        secondary: [.triceps],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .moderate,
        fatigue: 0.5
    )

    // mismo patrón y clase articular, ningún músculo principal en común
    static let landminePress = make(
        name: "Landmine Press",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .barbell,
        primary: [.shoulders],
        secondary: [.chest, .triceps],
        roles: [.primaryCompound, .secondaryCompound],
        stability: .moderate,
        fatigue: 0.5
    )

    // mismo patrón y músculo, otra clase articular
    static let dumbbellFly = make(
        name: "Dumbbell Fly",
        pattern: .horizontalPress,
        angle: .flat,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [],
        roles: [.accessoryIsolation],
        stability: .moderate,
        fatigue: 0.3,
        jointClass: .singleJoint
    )

    // cumple patrón, músculo y clase articular, pero se parece poco: queda bajo el mínimo
    static let awkwardPress = make(
        name: "Awkward Press",
        pattern: .horizontalPress,
        angle: .incline,
        equipment: .other,
        primary: [.chest, .triceps, .shoulders, .back],
        secondary: [],
        roles: [.anchor],
        stability: .high,
        fatigue: 0.5
    )

    static let config: SubstitutionScoringConfig = {
        try! SubstitutionScoringConfig(rule: try SubstitutionScoringDefaults.makeRule())
    }()

    fileprivate static func make(
        name: String,
        pattern: MovementPattern,
        angle: MovementAngle?,
        equipment: EquipmentType,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        roles: Set<ExerciseRole>,
        stability: DemandLevel,
        fatigue: Double,
        jointClass: JointClass = .multiJoint
    ) -> Exercise {
        try! Exercise(
            canonicalName: name,
            movementPattern: pattern,
            movementAngle: angle,
            primaryMuscles: primary.map { try! MuscleContribution(muscleGroupID: $0, activation: 1.0) },
            secondaryMuscles: secondary.map { try! MuscleContribution(muscleGroupID: $0, activation: 0.4) },
            equipment: equipment,
            jointClass: jointClass,
            stabilityDemand: stability,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: fatigue),
            loadability: .discreteIncrements,
            defaultRoles: roles,
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}

@Suite("Substitution scoring engine (PR-0904)")
struct SubstitutionScoringTests {

    private var engine: SubstitutionScoringEngine {
        SubstitutionScoringEngine(config: SubstitutionFixture.config)
    }

    private func request(
        target: Exercise,
        candidates: [Exercise],
        role: ExerciseRole? = .primaryCompound,
        restrictions: [TrainingRestriction] = [],
        signal: SubstitutionUserSignal = SubstitutionUserSignal()
    ) -> SubstitutionRequest {
        SubstitutionRequest(
            target: target,
            targetRole: role,
            candidates: candidates,
            userSignal: signal,
            activeRestrictions: restrictions
        )
    }

    @Test("la config exige pesos versionados que suman 1.00")
    func configWeightsSumToOne() throws {
        let rule = try SubstitutionScoringDefaults.makeRule()
        let config = try SubstitutionScoringConfig(rule: rule)
        #expect(config.muscleMatch == 0.30)
        #expect(config.movementPatternMatch == 0.20)
        #expect(config.trainingRoleMatch == 0.15)
        #expect(config.angleMatch == 0.10)
        #expect(config.fatigueProfileMatch == 0.08)
        #expect(config.stabilityMatch == 0.05)
        #expect(config.userHistoryConfidence == 0.05)
        #expect(config.preferenceMatch == 0.04)
        #expect(config.equipmentConfidence == 0.03)
    }

    @Test("rechaza pesos que no suman 1.00")
    func rejectsNonUnityWeights() throws {
        var params = SubstitutionScoringKeys.defaults()
        params[SubstitutionScoringKeys.muscleMatch] = 0.5 // desvía la suma
        let rule = try EvidenceRule(
            id: SubstitutionScoringDefaults.ruleID,
            name: "bad",
            category: .safety,
            confidence: .expertConsensus,
            version: 1,
            parameters: params
        )
        do {
            _ = try SubstitutionScoringConfig(rule: rule)
            Issue.record("Debería haber rechazado pesos que no suman 1.00")
        } catch {
            guard case SubstitutionScoringError.weightsDoNotSumToOne = error else {
                Issue.record("Error inesperado: \(error)")
                return
            }
        }
    }

    @Test("el candidato más equivalente (músculo+patrón+rol+ángulo) lidera el ranking")
    func bestEquivalentRanksFirst() throws {
        let target = SubstitutionFixture.dbBench
        // smith: mismo patrón/músculo/ángulo, equipo distinto → mejor que incline. El press de
        // hombro (otro patrón y otro músculo) ya no entra: DE-3, SCRUM-232.
        let verdict = try engine.substitutes(for: request(
            target: target,
            candidates: [SubstitutionFixture.shoulderPress, SubstitutionFixture.smithBench, SubstitutionFixture.inclineDB]
        ))
        let ranked = verdict.ranked
        #expect(ranked.map(\.exercise.id) == [SubstitutionFixture.smithBench.id, SubstitutionFixture.inclineDB.id])
        #expect(ranked[0].totalScore > ranked[1].totalScore)
    }

    @Test("el ranking es reproducible: mismos inputs → mismo orden")
    func reproducibleRanking() throws {
        let r = SubstitutionRequest(
            target: SubstitutionFixture.dbBench,
            candidates: [SubstitutionFixture.shoulderPress, SubstitutionFixture.smithBench, SubstitutionFixture.inclineDB]
        )
        let first = try engine.substitutes(for: r).ranked.map(\.exercise.id)
        let second = try engine.substitutes(for: r).ranked.map(\.exercise.id)
        #expect(first == second)
    }

    @Test("historial y preferencia del usuario elevan el score del sustituto")
    func userSignalLiftsScore() throws {
        let target = SubstitutionFixture.dbBench
        let incline = SubstitutionFixture.inclineDB

        let baseline = try engine.substitutes(for: request(
            target: target,
            candidates: [incline]
        )).ranked[0].totalScore

        let boosted = try engine.substitutes(for: request(
            target: target,
            candidates: [incline],
            signal: SubstitutionUserSignal(
                historyConfidence: [incline.id: 1.0],
                preferredExerciseIDs: [incline.id]
            )
        )).ranked[0].totalScore

        // 1.0 de historial (0.05) + 1.0 de preferencia (0.04) elevan el total.
        #expect(boosted > baseline)
    }

    @Test("un sustituto prohibido por la política nunca se adopta (gate de seguridad)")
    func forbiddenCandidateNotAdopted() throws {
        let shoulderPress = SubstitutionFixture.shoulderPress
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            status: .active,
            forbiddenPatterns: [.verticalPress]
        )
        // shoulder press lleva patrón verticalPress prohibido → excluido.
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: [SubstitutionFixture.smithBench, shoulderPress],
            restrictions: [restriction]
        ))
        let ranked = verdict.ranked
        #expect(ranked.count == 1)
        #expect(ranked[0].exercise.id == SubstitutionFixture.smithBench.id)
    }

    @Test("no safe substitute cuando todas las candidatas están prohibidas")
    func noSafeSubstituteWhenAllForbidden() throws {
        let press = SubstitutionFixture.smithBench
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder,
            status: .active,
            forbiddenPatterns: [.horizontalPress, .verticalPress]
        )
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: [press],
            restrictions: [restriction]
        ))
        #expect(verdict.ranked.isEmpty)
    }

    @Test("sin candidatas devuelve no safe substitute")
    func noCandidatesReturnsNoSafe() throws {
        let verdict = try engine.substitutes(for: request(
            target: SubstitutionFixture.dbBench,
            candidates: []
        ))
        if case .safe = verdict {
            Issue.record("no candidates should not yield a safe substitute")
        }
        #expect(verdict.ranked.isEmpty)
    }

    @Test("la máquina ocupada/inexistente reduce el score del candidato")
    func occupiedOrMissingEquipmentDowngradesScore() throws {
        let target = SubstitutionFixture.dbBench
        let smith = SubstitutionFixture.smithBench

        let score = { (gym: GymProfile?) throws -> Double in
            try engine.substitutes(for: SubstitutionRequest(
                target: target,
                candidates: [smith],
                gymProfile: gym
            )).ranked[0].totalScore
        }

        let unknownGym = GymProfile(name: "A")
        let occupiedGym = unknownGym.markingOccupied(.smithMachine)

        let withOccupied = try score(occupiedGym)
        let withUnknown = try score(unknownGym)

        // occupied (confianza 0) puntúa peor que unknown (confianza 0.5).
        #expect(withOccupied < withUnknown)
    }
}

private let reviewDay = Date(timeIntervalSince1970: 1_792_670_400)

/// SCRUM-232 (PR-E001, DE-3): mismo músculo no es ejercicio equivalente. Sólo sale lo que hace
/// el mismo movimiento, es seguro, está disponible, no está ya en la sesión y llega al mínimo.
@Suite("SCRUM-232 · Sustituto equivalente: mismo movimiento, seguro y disponible")
struct EquivalentSubstituteTests {
    private let target = SubstitutionFixture.dbBench

    private var engine: SubstitutionScoringEngine {
        SubstitutionScoringEngine(config: SubstitutionFixture.config)
    }

    private func engine(minimumScore: Double) throws -> SubstitutionScoringEngine {
        var parameters = SubstitutionScoringKeys.defaults()
        parameters[SubstitutionScoringKeys.minimumScore] = minimumScore
        return SubstitutionScoringEngine(config: try SubstitutionScoringConfig(rule: try rule(parameters)))
    }

    private func rule(_ parameters: [String: Double], version: Int = 2) throws -> EvidenceRule {
        try EvidenceRule(
            id: SubstitutionScoringDefaults.ruleID, name: "Prueba", category: .safety,
            confidence: .expertConsensus, version: version, parameters: parameters
        )
    }

    private func forbidding(_ exercises: Exercise...) -> TrainingRestriction {
        TrainingRestriction(
            bodyRegion: .shoulder, startDate: reviewDay, status: .active, forbiddenExerciseIDs: Set(exercises.map(\.id))
        )
    }

    @Test("Sólo sale la candidata que cumple toda la regla")
    func onlyFullyEquivalentCandidatePasses() throws {
        let forbidden = SubstitutionFixture.barbellBench
        let unavailable = SubstitutionFixture.machinePress
        let inSession = SubstitutionFixture.inclineDB
        let verdict = try engine.substitutes(for: SubstitutionRequest(
            target: target,
            candidates: [
                target, SubstitutionFixture.chestDip, SubstitutionFixture.landminePress, SubstitutionFixture.dumbbellFly,
                forbidden, unavailable, inSession, SubstitutionFixture.awkwardPress, SubstitutionFixture.smithBench,
            ],
            unavailableExerciseIDs: [unavailable.id],
            sessionExerciseIDs: [inSession.id],
            activeRestrictions: [forbidding(forbidden)],
            asOf: reviewDay
        ))
        #expect(verdict.ranked.map(\.exercise.canonicalName) == [SubstitutionFixture.smithBench.canonicalName])
    }

    @Test("Press de banca: el press con mancuernas sí, lo que sólo comparte músculo no")
    func benchPressKeepsThePressNotTheMuscle() throws {
        let verdict = try engine.substitutes(for: SubstitutionRequest(
            target: SubstitutionFixture.barbellBench,
            candidates: [SubstitutionFixture.chestDip, SubstitutionFixture.dumbbellFly, SubstitutionFixture.dbBench]
        ))
        #expect(verdict.ranked.map(\.exercise.id) == [SubstitutionFixture.dbBench.id])
    }

    @Test("Una candidata prohibida nunca sale, aunque tenga el mejor puntaje")
    func forbiddenNeverAppearsEvenWithTheBestScore() throws {
        let best = SubstitutionFixture.smithBench
        let candidates = [best, SubstitutionFixture.inclineDB]
        let free = try engine.substitutes(for: SubstitutionRequest(target: target, candidates: candidates))
        #expect(free.ranked.first?.exercise.id == best.id, "Sin la restricción es la mejor")

        let verdict = try engine.substitutes(for: SubstitutionRequest(
            target: target, candidates: candidates, activeRestrictions: [forbidding(best)], asOf: reviewDay
        ))
        #expect(verdict.ranked.map(\.exercise.id) == [SubstitutionFixture.inclineDB.id])
    }

    @Test("Una restricción con la revisión vencida y sin resolver sigue prohibiendo")
    func overdueRestrictionStillForbids() throws {
        let smith = SubstitutionFixture.smithBench
        let overdue = TrainingRestriction(
            bodyRegion: .shoulder, startDate: reviewDay.addingTimeInterval(-86_400 * 30),
            reviewDate: reviewDay.addingTimeInterval(-86_400), status: .active, forbiddenExerciseIDs: [smith.id]
        )
        let verdict = try engine.substitutes(for: SubstitutionRequest(
            target: target, candidates: [smith], activeRestrictions: [overdue], asOf: reviewDay
        ))
        #expect(verdict == .noEquivalent(.allForbidden))
    }

    @Test("Sin candidatas equivalentes: catálogo vacío, sólo el objetivo u otro movimiento")
    func noCandidatesReasons() throws {
        let otherMovements = [SubstitutionFixture.chestDip, SubstitutionFixture.landminePress, SubstitutionFixture.dumbbellFly]
        for candidates in [[], [target], otherMovements] {
            #expect(try engine.substitutes(for: SubstitutionRequest(target: target, candidates: candidates))
                == .noEquivalent(.noCandidates))
        }
        let smith = SubstitutionFixture.smithBench
        #expect(try engine.substitutes(for: SubstitutionRequest(target: target, candidates: [smith], sessionExerciseIDs: [smith.id]))
            == .noEquivalent(.noCandidates), "Ya está en la sesión")
    }

    @Test("Un objetivo sin músculos principales no tiene equivalentes")
    func targetWithoutPrimaryMuscles() throws {
        let unknown = SubstitutionFixture.make(
            name: "Sin músculos", pattern: .horizontalPress, angle: nil, equipment: .other, primary: [], secondary: [],
            roles: [.primaryCompound], stability: .moderate, fatigue: 0.5
        )
        #expect(try engine.substitutes(for: SubstitutionRequest(target: unknown, candidates: [SubstitutionFixture.smithBench]))
            == .noEquivalent(.noCandidates))
    }

    @Test("Todo el patrón prohibido: el motivo es la restricción")
    func wholePatternForbidden() throws {
        let restriction = TrainingRestriction(
            bodyRegion: .shoulder, startDate: reviewDay, status: .active, forbiddenPatterns: [.horizontalPress]
        )
        #expect(try engine.substitutes(for: SubstitutionRequest(
            target: target, candidates: [SubstitutionFixture.smithBench, SubstitutionFixture.machinePress],
            activeRestrictions: [restriction], asOf: reviewDay
        )) == .noEquivalent(.allForbidden))
    }

    @Test("Las permitidas no están en el gimnasio: el motivo es la disponibilidad")
    func allUnavailable() throws {
        let smith = SubstitutionFixture.smithBench
        let machine = SubstitutionFixture.machinePress
        #expect(try engine.substitutes(for: SubstitutionRequest(
            target: target, candidates: [smith, machine], unavailableExerciseIDs: [machine.id],
            activeRestrictions: [forbidding(smith)], asOf: reviewDay
        )) == .noEquivalent(.allUnavailable))
    }

    @Test("La disponibilidad es por ejercicio: otro con el mismo equipo sigue disponible (DE-1)")
    func availabilityIsPerExercise() throws {
        let machine = SubstitutionFixture.machinePress
        let otherMachine = SubstitutionFixture.make(
            name: "Hammer Chest Press", pattern: .horizontalPress, angle: .flat, equipment: .machine, primary: [.chest],
            secondary: [.triceps], roles: [.secondaryCompound], stability: .low, fatigue: 0.4
        )
        let verdict = try engine.substitutes(for: SubstitutionRequest(
            target: target, candidates: [machine, otherMachine], unavailableExerciseIDs: [machine.id]
        ))
        #expect(verdict.ranked.map(\.exercise.id) == [otherMachine.id])
    }

    @Test("Todas bajo el mínimo: el motivo es el puntaje")
    func allBelowMinimum() throws {
        #expect(try engine.substitutes(for: SubstitutionRequest(target: target, candidates: [SubstitutionFixture.awkwardPress]))
            == .noEquivalent(.allBelowMinimum))
    }

    @Test("El mínimo incluye al puntaje exacto")
    func minimumIsInclusive() throws {
        let smith = SubstitutionFixture.smithBench
        let request = SubstitutionRequest(target: target, candidates: [smith])
        let score = try #require(try engine(minimumScore: 0).substitutes(for: request).ranked.first?.totalScore)

        #expect(try engine(minimumScore: score).substitutes(for: request).ranked.map(\.exercise.id) == [smith.id])
        #expect(try engine(minimumScore: min(1, score + 0.01)).substitutes(for: request) == .noEquivalent(.allBelowMinimum))
    }

    @Test("Los mismos datos dan el mismo orden; si empatan, por nombre y sin depender de la entrada")
    func deterministicOrder() throws {
        func twin(_ name: String) -> Exercise {
            SubstitutionFixture.make(
                name: name, pattern: .horizontalPress, angle: .flat, equipment: .machine, primary: [.chest],
                secondary: [.triceps], roles: [.secondaryCompound], stability: .low, fatigue: 0.4
            )
        }
        let alpha = twin("Alpha Press")
        let beta = twin("Beta Press")
        let sameNameA = twin("Gamma Press")
        let sameNameB = twin("Gamma Press")
        let order = { (candidates: [Exercise]) throws -> [ExerciseID] in
            try engine(minimumScore: 0.60).substitutes(for: SubstitutionRequest(target: target, candidates: candidates)).ranked.map(\.exercise.id)
        }

        #expect(try order([beta, alpha]).first == alpha.id)
        #expect(try order([alpha, beta]) == order([beta, alpha]))
        #expect(try order([sameNameA, sameNameB]) == order([sameNameB, sameNameA]), "Mismo nombre: orden estable")
    }

    @Test("Trae como máximo maxOptions, las mejores, cada una con sus componentes y la regla con versión")
    func atMostMaxOptionsWithFacts() throws {
        let candidates = [
            SubstitutionFixture.inclineDB, SubstitutionFixture.machinePress, SubstitutionFixture.barbellBench, SubstitutionFixture.smithBench,
        ]
        let ranked = try engine.substitutes(for: SubstitutionRequest(target: target, candidates: candidates)).ranked
        #expect(ranked.count == SubstitutionFixture.config.maxOptions)
        #expect(!ranked.map(\.exercise.id).contains(SubstitutionFixture.inclineDB.id), "La de menor puntaje queda fuera")

        let reference = try EvidenceRuleReference(ruleID: SubstitutionScoringDefaults.ruleID, version: 2)
        for option in ranked {
            #expect(option.ruleReference == reference)
            #expect(Set(option.components.map(\.key)) == SubstitutionScoringKeys.weights)
            let sum = option.components.reduce(0) { $0 + $1.contribution }
            #expect(abs(sum - option.totalScore) < 0.000_001)
        }
    }

    @Test("La regla sube a v2 con el mínimo y el máximo de opciones versionados")
    func ruleV2CarriesTheLimits() throws {
        let rule = try SubstitutionScoringDefaults.makeRule()
        #expect(rule.version == 2)
        let config = try SubstitutionScoringConfig(rule: rule)
        #expect(config.minimumScore == 0.60)
        #expect(config.maxOptions == 3)
    }

    @Test("Una regla sin los límites no sirve: v1 ya no alcanza")
    func ruleWithoutLimitsIsRejected() throws {
        var parameters = SubstitutionScoringKeys.defaults()
        parameters[SubstitutionScoringKeys.minimumScore] = nil
        parameters[SubstitutionScoringKeys.maxOptions] = nil
        let oldRule = try rule(parameters, version: 1)
        #expect(throws: SubstitutionScoringError.missingConfig(keys: [SubstitutionScoringKeys.maxOptions, SubstitutionScoringKeys.minimumScore])) {
            try SubstitutionScoringConfig(rule: oldRule)
        }
    }

    @Test("Límites fuera de rango se rechazan", arguments: [
        (SubstitutionScoringKeys.minimumScore, 1.5),
        (SubstitutionScoringKeys.minimumScore, -0.1),
        (SubstitutionScoringKeys.maxOptions, 0.0),
        (SubstitutionScoringKeys.maxOptions, 2.5),
    ])
    func invalidLimitsAreRejected(key: String, value: Double) throws {
        var parameters = SubstitutionScoringKeys.defaults()
        parameters[key] = value
        let badRule = try rule(parameters)
        #expect(throws: SubstitutionScoringError.invalidLimit(key: key)) {
            try SubstitutionScoringConfig(rule: badRule)
        }
    }
}