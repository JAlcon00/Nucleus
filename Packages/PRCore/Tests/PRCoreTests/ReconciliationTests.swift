//
//  ReconciliationTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Tests de reconciliación de workouts (PR-1105): overlap matcher, canonical energy
//  source (§15.2/§15.3) y la regla central de que el mismo workout NUNCA suma energía
//  dos veces (§15.1). Fixtures overlap / non-overlap del plan §13.
//

import Foundation
import Testing
import PRCore
import PRDomain

@Suite("Workout reconciliation (PR-1105)")
struct ReconciliationTests {

    private func candidate(
        start: Date,
        end: Date,
        kcal: Double? = 100,
        source: EnergySource = .ourHealthKitWorkout
    ) -> WorkoutEnergyCandidate {
        WorkoutEnergyCandidate(start: start, end: end, activeKilocalories: kcal, source: source)
    }

    private let t = Date(timeIntervalSince1970: 1_000_000)

    // 1. Exact duplicate: dos fuentes, mismo workout → 1 energía, sin doble conteo.
    @Test("Exact duplicate: mismo workout produce una única energía (no suma)")
    func exactDuplicateIsNotDoubleCounted() {
        let engine = WorkoutReconciliationEngine()
        let exact = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 180, source: .ourHealthKitWorkout)
        let duplicate = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 190, source: .externalAppleWorkout)

        let resolutions = engine.reconcile([exact, duplicate])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].deduplicated)
        // Se elige la fuente de mayor prioridad (§15.3), NO se suman 180+190.
        #expect(resolutions[0].energy?.activeKilocalories == 180)
        #expect(resolutions[0].energy?.source == .ourHealthKitWorkout)
    }

    // 2. 90% overlap → duplicado, energía única.
    @Test("90% overlap detecta duplicado con energía única")
    func ninetyPercentOverlapIsDuplicate() {
        let engine = WorkoutReconciliationEngine()
        let a = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 150, source: .ourHealthKitWorkout)
        let b = candidate(start: t.addingTimeInterval(180), end: t.addingTimeInterval(3600), kcal: 130, source: .externalHealthKitWorkout)
        // overlap = (3600-180)=3420; union = 3600 → 0.95
        #expect(engine.areDuplicateCandidates(a, b))

        let resolutions = engine.reconcile([a, b])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].energy?.activeKilocalories == 150)
    }

    // 3. Adjacent workouts (tocan pero no se solapan) → NO duplicado.
    @Test("Adjacent workouts (sin solape) no son duplicado")
    func adjacentWorkoutsAreDistinct() {
        let engine = WorkoutReconciliationEngine()
        let a = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 100, source: .ourHealthKitWorkout)
        let b = candidate(start: t.addingTimeInterval(3600), end: t.addingTimeInterval(7200), kcal: 100, source: .ourHealthKitWorkout)
        #expect(!engine.areDuplicateCandidates(a, b))
        #expect(engine.overlapRatio(a, b) == 0)

        let resolutions = engine.reconcile([a, b])
        #expect(resolutions.count == 2)
        // Energías independientes: 100 + 100 (cada una su propio workout).
        #expect(resolutions.map { $0.energy?.activeKilocalories }.compactMap { $0 }.reduce(0, +) == 200)
    }

    // 4. Dos workouts legítimos separados el mismo día → 2 resoluciones, sin fundir.
    @Test("Dos workouts legítimos separados el mismo día se mantienen distintos")
    func twoSeparateWorkoutsSameDayStayDistinct() {
        let engine = WorkoutReconciliationEngine()
        let morning = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 120, source: .ourHealthKitWorkout)
        let evening = candidate(start: t.addingTimeInterval(14 * 3600), end: t.addingTimeInterval(15 * 3600), kcal: 140, source: .ourHealthKitWorkout)

        let resolutions = engine.reconcile([morning, evening])
        #expect(resolutions.count == 2)
        #expect(resolutions.allSatisfy { !$0.deduplicated })
        #expect(resolutions.map { $0.energy?.activeKilocalories }.compactMap { $0 }.reduce(0, +) == 260)
    }

    // 5. Missing energy → no se inventa energía.
    @Test("Falta energía: no se inventa una resolución con energía")
    func missingEnergyIsNotInvented() {
        let engine = WorkoutReconciliationEngine()
        let noEnergy = candidate(start: t, end: t.addingTimeInterval(3600), kcal: nil, source: .ourHealthKitWorkout)
        let resolutions = engine.reconcile([noEnergy])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].energy == nil)
        #expect(!resolutions[0].deduplicated)
    }

    // 6. Prioridad canonical: nuestro HK vence a Apple externo en el mismo workout.
    @Test("Prioridad canonical: nuestro HealthKit vence a Apple externo")
    func canonicalPriorityOrder() {
        let engine = WorkoutReconciliationEngine()
        let ours = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 200, source: .ourHealthKitWorkout)
        let apple = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 175, source: .externalAppleWorkout)
        let other = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 160, source: .externalHealthKitWorkout)

        let resolutions = engine.reconcile([apple, other, ours])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].energy?.source == .ourHealthKitWorkout)
        #expect(resolutions[0].energy?.activeKilocalories == 200)
    }

    // 7. Un fallbackEstimate sólo se usa si no hay fuente superior con energía.
    @Test("Fallback estimate se usa sólo sin fuente superior")
    func fallbackOnlyWithoutSuperior() {
        let engine = WorkoutReconciliationEngine()
        let fallback = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 90, source: .fallbackEstimate)

        // Sólo fallback → se usa, pero etiquetado como estimación.
        let onlyFallback = engine.reconcile([fallback])
        #expect(onlyFallback[0].energy?.source == .fallbackEstimate)
        #expect(onlyFallback[0].energy?.confidence == 0.5)

        // Con fuente superior disponible, el fallback pierde.
        let ours = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 200, source: .ourHealthKitWorkout)
        let withSuperior = engine.reconcile([fallback, ours])
        #expect(withSuperior[0].energy?.source == .ourHealthKitWorkout)
    }

    // 8. Más de un cluster con energía distinta nunca se suma en una única.
    @Test("Los clusters independientes nunca se suman en una única energía")
    func independentClustersAreKeptSeparate() {
        let engine = WorkoutReconciliationEngine()
        let first = candidate(start: t, end: t.addingTimeInterval(3600), kcal: 120, source: .ourHealthKitWorkout)
        let firstDuplicate = candidate(start: t.addingTimeInterval(120), end: t.addingTimeInterval(3600), kcal: 110, source: .externalAppleWorkout)
        let second = candidate(start: t.addingTimeInterval(7200), end: t.addingTimeInterval(10800), kcal: 90, source: .ourHealthKitWorkout)

        let resolutions = engine.reconcile([first, firstDuplicate, second])
        #expect(resolutions.count == 2)
        let energies = resolutions.map { $0.energy?.activeKilocalories }.compactMap { $0 }
        // 120 (canónico del cluster 1) + 90 (cluster 2): nunca 120+110+90.
        #expect(energies.sorted() == [90, 120])
    }
}
// MARK: - SCRUM-245: la energía del mismo entrenamiento se cuenta una vez

@Suite("La energía del mismo entrenamiento se cuenta una vez (SCRUM-245)")
struct WorkoutEnergyCountedOnceTests {

    private let engine = WorkoutReconciliationEngine()
    private let sixPM = Date(timeIntervalSince1970: 1_000_000)

    /// Un candidato por minutos desde las 18:00.
    private func workout(
        _ startMinute: Double,
        _ endMinute: Double,
        type: HealthWorkoutActivityType = .strengthTraining,
        kcal: Double? = 100,
        source: EnergySource = .externalAppleWorkout,
        id: String = ""
    ) -> WorkoutEnergyCandidate {
        WorkoutEnergyCandidate(
            identifier: id,
            start: sixPM.addingTimeInterval(startMinute * 60),
            end: sixPM.addingTimeInterval(endMinute * 60),
            activityType: type,
            activeKilocalories: kcal,
            source: source
        )
    }

    // Criterio 1
    @Test("Uno dentro del otro es el mismo: el solapamiento se mide sobre el más corto")
    func containedWorkoutIsTheSame() {
        let long = workout(0, 60, kcal: 300, source: .externalAppleWorkout)
        let short = workout(10, 50, kcal: 280, source: .externalHealthKitWorkout)

        #expect(engine.overlapRatio(long, short) == 1)
        #expect(engine.areDuplicateCandidates(long, short))
        let resolutions = engine.reconcile([long, short])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].energy?.activeKilocalories == 300)
    }

    // Criterio 2
    @Test("A medias es otro entrenamiento")
    func halfOverlapIsDistinct() {
        let first = workout(0, 60)
        let second = workout(30, 90)

        #expect(engine.overlapRatio(first, second) == 0.5)
        #expect(!engine.areDuplicateCandidates(first, second))
        #expect(engine.reconcile([first, second]).count == 2)
    }

    // Criterio 3
    @Test("Seguidos, sin solape, son distintos aunque sean cortos")
    func backToBackIsDistinct() {
        #expect(!engine.areDuplicateCandidates(workout(0, 60), workout(60, 120)))
        // Con inicio y fin dentro de la tolerancia, pero sin un segundo en común.
        #expect(!engine.areDuplicateCandidates(workout(0, 3), workout(3, 6)))
    }

    // Criterio 4
    @Test("Fuera del umbral, con inicio y fin dentro de la tolerancia, es el mismo")
    func withinToleranceIsTheSame() {
        let first = workout(0, 30)
        let shifted = workout(10, 40)

        #expect(engine.overlapRatio(first, shifted) < engine.configuration.overlapThreshold)
        #expect(engine.areDuplicateCandidates(first, shifted))
        #expect(engine.reconcile([first, shifted]).count == 1)
    }

    @Test("Con el inicio o el fin fuera de la tolerancia, no")
    func outsideToleranceIsDistinct() {
        #expect(!engine.areDuplicateCandidates(workout(0, 30), workout(11, 41)))
    }

    @Test("Diez minutos de diferencia en una hora siguen siendo el mismo (gate, prueba 7)")
    func tenMinutesApartInAnHourIsTheSame() {
        #expect(engine.areDuplicateCandidates(workout(0, 60), workout(10, 70)))
    }

    // Criterio 5
    @Test("Fuerza tradicional y funcional pueden ser el mismo")
    func compatibleTypesCanMatch() {
        let traditional = workout(0, 60, type: .strengthTraining)
        let functional = workout(0, 60, type: .functionalStrengthTraining)

        #expect(engine.areDuplicateCandidates(traditional, functional))
    }

    @Test("Fuerza y carrera nunca, aunque coincidan al segundo")
    func incompatibleTypesNeverMatch() {
        let strength = workout(0, 60, type: .strengthTraining)
        let functional = workout(0, 60, type: .functionalStrengthTraining)
        let running = workout(0, 60, type: .running)

        #expect(!engine.areDuplicateCandidates(strength, running))
        #expect(!engine.areDuplicateCandidates(functional, running))
        #expect(engine.reconcile([strength, running]).count == 2)
    }

    // Criterio 6
    @Test("Gana la fuente de mayor prioridad que tenga energía real, sin sumar")
    func highestPriorityWithRealEnergyWins() {
        let ours = workout(0, 60, kcal: nil, source: .ourHealthKitWorkout)
        let apple = workout(0, 60, kcal: 250, source: .externalAppleWorkout)
        let other = workout(0, 60, kcal: 400, source: .externalHealthKitWorkout)

        let resolutions = engine.reconcile([other, ours, apple])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].candidateCount == 3)
        #expect(resolutions[0].energy?.source == .externalAppleWorkout)
        #expect(resolutions[0].energy?.activeKilocalories == 250)
    }

    @Test("Si ninguna fuente del grupo tiene energía, no hay energía")
    func noRealEnergyMeansNoEnergy() {
        let resolutions = engine.reconcile([
            workout(0, 60, kcal: nil, source: .ourHealthKitWorkout),
            workout(0, 60, kcal: nil, source: .externalAppleWorkout),
        ])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].energy == nil)
        #expect(resolutions[0].deduplicated)
    }

    @Test("Cero es energía real")
    func zeroIsRealEnergy() {
        let resolutions = engine.reconcile([workout(0, 60, kcal: 0)])
        #expect(resolutions[0].energy?.activeKilocalories == 0)
    }

    // Criterio 7
    @Test("A igual prioridad gana el de mayor duración")
    func longestWinsOnEqualPriority() {
        let long = workout(0, 60, kcal: 300, id: "b")
        let short = workout(5, 55, kcal: 200, id: "a")

        #expect(engine.reconcile([short, long])[0].energy?.activeKilocalories == 300)
        #expect(engine.reconcile([long, short])[0].energy?.activeKilocalories == 300)
    }

    @Test("A igual prioridad y duración gana el de menor identificador")
    func lowestIdentifierWinsOnTie() {
        let first = workout(0, 60, kcal: 300, id: "a")
        let second = workout(0, 60, kcal: 200, id: "b")

        #expect(engine.reconcile([second, first])[0].energy?.activeKilocalories == 300)
        #expect(engine.reconcile([first, second])[0].energy?.activeKilocalories == 300)
    }

    @Test("El mismo conjunto en cualquier orden da el mismo resultado")
    func orderDoesNotChangeTheResult() {
        let candidates = [
            workout(0, 60, kcal: 300, source: .externalAppleWorkout, id: "a"),
            workout(0, 60, kcal: 280, source: .externalAppleWorkout, id: "b"),
            workout(5, 55, kcal: 260, source: .externalAppleWorkout, id: "c"),
            workout(10, 70, kcal: nil, source: .ourHealthKitWorkout, id: "d"),
            workout(0, 60, type: .running, kcal: 500, source: .externalHealthKitWorkout, id: "e"),
            workout(120, 180, kcal: 150, source: .externalHealthKitWorkout, id: "f"),
            workout(130, 170, kcal: 170, source: .externalHealthKitWorkout, id: "g"),
            workout(300, 300, kcal: 999, id: "h"),
            workout(400, 390, kcal: 999, id: "i"),
        ]
        let expected = engine.reconcile(candidates)
        #expect(expected.count == 3)

        var generator = ShufflingGenerator(seed: 245)
        for _ in 0..<200 {
            #expect(engine.reconcile(candidates.shuffled(using: &generator)) == expected)
        }
    }

    // Criterio 8
    @Test("Umbral, tolerancia y confianza salen de la regla versionada")
    func policyComesFromTheVersionedRule() throws {
        let rule = try WorkoutReconciliationDefaults.makeRule()
        #expect(rule.id == WorkoutReconciliationDefaults.ruleID)
        #expect(rule.version == 1)

        let configuration = try WorkoutReconciliationConfiguration(rule: rule)
        #expect(configuration == .standard)
        #expect(engine.configuration == .standard)
    }

    @Test("Cambiar la regla cambia el resultado")
    func theRuleDrivesTheEngine() throws {
        var parameters = try WorkoutReconciliationDefaults.makeRule().parameters
        parameters[WorkoutReconciliationKeys.overlapThreshold] = 0.40
        parameters[WorkoutReconciliationKeys.endpointToleranceSeconds] = 0
        parameters[WorkoutReconciliationKeys.confidenceExternalAppleWorkout] = 0.70
        let rule = try EvidenceRule(
            id: WorkoutReconciliationDefaults.ruleID,
            name: "Prueba",
            category: .safety,
            confidence: .expertConsensus,
            version: 2,
            parameters: parameters
        )
        let custom = WorkoutReconciliationEngine(
            configuration: try WorkoutReconciliationConfiguration(rule: rule)
        )

        #expect(custom.areDuplicateCandidates(workout(0, 60), workout(30, 90)))
        #expect(!custom.areDuplicateCandidates(workout(0, 30), workout(20, 50)))
        #expect(custom.reconcile([workout(0, 60)])[0].energy?.confidence == 0.70)
    }

    @Test("Una regla incompleta o fuera de rango se rechaza")
    func invalidRulesAreRejected() throws {
        let valid = try WorkoutReconciliationDefaults.makeRule()

        var missing = valid
        missing.parameters[WorkoutReconciliationKeys.endpointToleranceSeconds] = nil
        #expect(throws: WorkoutReconciliationRuleError.missingConfig(
            keys: [WorkoutReconciliationKeys.endpointToleranceSeconds]
        )) {
            try WorkoutReconciliationConfiguration(rule: missing)
        }

        var outOfRange = valid
        outOfRange.parameters[WorkoutReconciliationKeys.overlapThreshold] = 1.5
        #expect(throws: WorkoutReconciliationRuleError.invalidValue(
            key: WorkoutReconciliationKeys.overlapThreshold
        )) {
            try WorkoutReconciliationConfiguration(rule: outOfRange)
        }

        var negative = valid
        negative.parameters[WorkoutReconciliationKeys.endpointToleranceSeconds] = -1
        #expect(throws: WorkoutReconciliationRuleError.invalidValue(
            key: WorkoutReconciliationKeys.endpointToleranceSeconds
        )) {
            try WorkoutReconciliationConfiguration(rule: negative)
        }

        var wrongCategory = valid
        wrongCategory.category = .volume
        #expect(throws: WorkoutReconciliationRuleError.wrongCategory) {
            try WorkoutReconciliationConfiguration(rule: wrongCategory)
        }
    }

    // Casos límite
    @Test("Conjunto vacío: ninguna resolución")
    func emptySet() {
        #expect(engine.reconcile([]).isEmpty)
    }

    @Test("Duración cero: no se une a nada ni aporta energía")
    func zeroDurationIsIgnored() {
        let instant = workout(30, 30, kcal: 999, source: .ourHealthKitWorkout)
        let real = workout(0, 60, kcal: 100, source: .externalAppleWorkout)

        #expect(engine.overlapRatio(instant, real) == 0)
        #expect(!engine.areDuplicateCandidates(instant, real))
        let resolutions = engine.reconcile([instant, real])
        #expect(resolutions.count == 1)
        #expect(resolutions[0].candidateCount == 1)
        #expect(resolutions[0].energy?.activeKilocalories == 100)
    }

    @Test("Fin antes que inicio: no se une a nada ni aporta energía")
    func invertedIntervalIsIgnored() {
        let inverted = workout(60, 0, kcal: 999, source: .ourHealthKitWorkout)
        let real = workout(0, 60, kcal: 100, source: .externalAppleWorkout)

        #expect(engine.overlapRatio(inverted, real) == 0)
        #expect(!engine.areDuplicateCandidates(inverted, real))
        #expect(engine.reconcile([inverted]).isEmpty)
        #expect(engine.reconcile([inverted, real])[0].energy?.activeKilocalories == 100)
    }

    @Test("Energía negativa, NaN o infinita no es energía real", arguments: [-1.0, .nan, .infinity])
    func invalidEnergyIsNotReal(kcal: Double) {
        let bad = workout(0, 60, kcal: kcal, source: .ourHealthKitWorkout)
        let good = workout(0, 60, kcal: 120, source: .externalHealthKitWorkout)

        #expect(engine.reconcile([bad])[0].energy == nil)
        #expect(engine.reconcile([bad, good])[0].energy?.activeKilocalories == 120)
    }

    @Test("A dentro de B y B dentro de C son un solo entrenamiento")
    func nestedWorkoutsAreOneGroup() {
        let a = workout(20, 30, kcal: 50, source: .externalHealthKitWorkout)
        let b = workout(10, 40, kcal: 70, source: .externalHealthKitWorkout)
        let c = workout(0, 100, kcal: 90, source: .externalAppleWorkout)

        for order in [[a, b, c], [c, b, a], [a, c, b], [c, a, b]] {
            let resolutions = engine.reconcile(order)
            #expect(resolutions.count == 1)
            #expect(resolutions[0].candidateCount == 3)
            #expect(resolutions[0].energy?.activeKilocalories == 90)
        }
    }

    @Test("Una cadena es un solo grupo aunque sus extremos no coincidan entre sí")
    func chainIsOneGroup() {
        let a = workout(0, 30, kcal: 50, source: .externalHealthKitWorkout)
        let b = workout(10, 40, kcal: 70, source: .externalHealthKitWorkout)
        let c = workout(20, 50, kcal: 90, source: .externalAppleWorkout)

        #expect(engine.areDuplicateCandidates(a, b))
        #expect(engine.areDuplicateCandidates(b, c))
        #expect(!engine.areDuplicateCandidates(a, c))
        for order in [[a, b, c], [c, b, a], [a, c, b], [c, a, b]] {
            let resolutions = engine.reconcile(order)
            #expect(resolutions.count == 1)
            #expect(resolutions[0].candidateCount == 3)
            #expect(resolutions[0].energy?.activeKilocalories == 90)
        }
    }

    @Test("Un entrenamiento externo aporta su referencia como identificador")
    func externalWorkoutCarriesItsIdentifier() {
        let reference = HealthWorkoutHandle.ID()
        let external = ExternalWorkout(
            referenceID: reference,
            start: sixPM,
            end: sixPM.addingTimeInterval(3600),
            activityType: .strengthTraining
        )

        #expect(external.asCandidate(source: .externalAppleWorkout).identifier == reference.rawValue.uuidString)
    }
}

/// Generador con semilla fija (SplitMix64): las barajas se repiten en cada corrida.
private struct ShufflingGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
