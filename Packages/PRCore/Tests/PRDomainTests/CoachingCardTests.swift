//
//  CoachingCardTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de las tarjetas de educación contextual (PR-1501): educación ligada al
//  contexto real (calentamiento/descanso/molestia), id estable para descartabilidad,
//  y reducción de explicaciones en nivel advanced. Determinista y sin diagnóstico.
//

import Foundation
import Testing
import PRDomain

@Suite("Contextual coaching cards (PR-1501)")
struct CoachingCardTests {

    private let driver = CoachingCardDriver()

    // AC1: educación ligada al contexto — calentamiento.
    @Test("Guided: un set de calentamiento muestra una tarjeta de calentamiento")
    func guidedWarmupCard() {
        let card = driver.card(for: CoachingContext(level: .guided, isWarmup: true))
        #expect(card?.kind == .warmup)
        #expect(card?.id == CoachingCardDriver.warmupCardID)
    }

    // AC1: educación ligada al contexto — descanso.
    @Test("Guided: un descanso activo muestra una tarjeta de descanso")
    func guidedRestCard() {
        let card = driver.card(for: CoachingContext(level: .guided, restActive: true))
        #expect(card?.kind == .rest)
        #expect(card?.id == CoachingCardDriver.restCardID)
    }

    // AC1: sin contexto relevante → ninguna tarjeta (no inventar contenido).
    @Test("Guided: sin calentamiento ni descanso ni molestia no hay tarjeta")
    func guidedRoutineIsEmpty() {
        let card = driver.card(for: CoachingContext(level: .guided))
        #expect(card == nil)
    }

    // AC3: advanced reduce explicaciones — rutina sin tarjeta.
    @Test("Advanced: reduce explicaciones (no muestra calentamiento ni descanso)")
    func advancedReducesExplanations() {
        let warmup = driver.card(for: CoachingContext(level: .advanced, isWarmup: true))
        #expect(warmup == nil)
        let rest = driver.card(for: CoachingContext(level: .advanced, restActive: true))
        #expect(rest == nil)
    }

    // AC3 + seguridad: advanced SÍ muestra la tarjeta de molestia (riesgo, sin diagnóstico).
    @Test("Advanced: mantiene la tarjeta de seguridad ante molestia, sin diagnóstico")
    func advancedStillShowsPainSafety() {
        let card = driver.card(for: CoachingContext(
            level: .advanced,
            painRecommendation: .stopAndRest,
            exerciseName: "Press banca"
        ))
        #expect(card?.kind == .painSafety)
        #expect(card?.id == CoachingCardDriver.painSafetyCardID)
        // Debe ser no-diagnóstico: no debe contener la palabra "diagnóstico".
        #expect(card?.message.localizedCaseInsensitiveContains("diagnosticando") == true)
    }

    // AC1: derivado del motor de molestia (PR-1403), no inventado.
    @Test("La tarjeta de molestia manda sobre la de calentamiento (safety primero)")
    func painSafetyWinsOverWarmup() {
        let card = driver.card(for: CoachingContext(
            level: .guided,
            isWarmup: true,
            painRecommendation: .reduceIntensityAndMonitor
        ))
        #expect(card?.kind == .painSafety)
    }

    // AC2: id estable → descartabilidad durable.
    @Test("El id de la tarjeta es estable y codificable (descartable)")
    func stableDismissibleID() throws {
        #expect(CoachingCardDriver.painSafetyCardID.rawValue == "coaching.pain.safety")
        let encoded = try JSONEncoder().encode(CoachingCardDriver.warmupCardID)
        let decoded = try JSONDecoder().decode(CoachingCardID.self, from: encoded)
        #expect(decoded == CoachingCardDriver.warmupCardID)
    }

    // Determinismo: dos evaluaciones del mismo contexto producen el mismo card.
    @Test("Determinista: mismo contexto produce la misma tarjeta")
    func deterministic() {
        let a = driver.card(for: CoachingContext(level: .balanced, isWarmup: true, exerciseName: "Squat"))
        let b = driver.card(for: CoachingContext(level: .balanced, isWarmup: true, exerciseName: "Squat"))
        #expect(a == b)
    }
}