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