import Testing
import Foundation
@testable import PRDomain

@Suite("Consistency streak (PR-1702)")
struct ConsistencyStreakTests {

    private func week(_ offset: Int, fulfillment: Double, painBlocked: Bool = false) -> StreakWeek {
        let weekStart = Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(Double(offset) * 7 * 24 * 3600)
        return StreakWeek(weekStart: weekStart, fulfillmentRatio: fulfillment, isPainBlocked: painBlocked)
    }

    // MARK: - streak por semanas de cumplimiento

    @Test("racha actual y máxima por semanas cumplidas consecutivas")
    func countsWeeklyFulfilled() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0),
            week(2, fulfillment: 1.0),
        ])
        #expect(result.currentStreakWeeks == 3)
        #expect(result.longestStreakWeeks == 3)
        #expect(result.isFulfilledThisWeek == true)
        #expect(result.weeks.count == 3)
    }

    // MARK: - descanso programado no rompe consistency

    @Test("semana de descanso programado (fulfillment 1.0) mantiene la racha, no la reinicia")
    func plannedRestKeepsStreak() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0), // descanso programado: está cumplida (1.0)
            week(2, fulfillment: 1.0),
        ])
        #expect(result.currentStreakWeeks == 3)
        #expect(result.longestStreakWeeks == 3)
    }

    @Test("racha tras un trailer de descanso se mantiene, no se reinicia")
    func trailingRestKeepsStreak() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0),
            week(2, fulfillment: 1.0), // descanso al final: no rompe
        ])
        #expect(result.currentStreakWeeks == 3)
    }

    // MARK: - pain blocks progression (pausa, no rompe)

    @Test("semana bloqueada por dolor pausa la racha: no la reinicia ni la extiende")
    func painWeekPauses() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0),
            week(2, fulfillment: 0.0, painBlocked: true), // pausa
            week(3, fulfillment: 1.0),
        ])
        // 2 cumplidas + pausa + 1 cumplida = racha corriente de 3; no se reinició
        #expect(result.currentStreakWeeks == 3)
        #expect(result.longestStreakWeeks == 3)
        #expect(result.weeks[2] == .paused)
    }

    // MARK: - no streak de entrenar todos los días como métrica principal

    @Test("una semana no cumplida reinicia la racha (NO streak diario de entrenamiento)")
    func missedWeekResets() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0),
            week(2, fulfillment: 1.0),
            week(3, fulfillment: 0.5), // no cumplida
            week(4, fulfillment: 1.0),
        ])
        #expect(result.currentStreakWeeks == 1)
        #expect(result.longestStreakWeeks == 3)
        #expect(result.isFulfilledThisWeek == true)
    }

    // MARK: - borde

    @Test("histórico vacío → racha 0")
    func emptyNoStreak() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [])
        #expect(result.currentStreakWeeks == 0)
        #expect(result.longestStreakWeeks == 0)
        #expect(result.isFulfilledThisWeek == false)
        #expect(result.weeks.isEmpty)
    }

    @Test("semana en curso sin cumplir (aún) → la racha no se reinicia si no es fin de semana")
    func inProgressWeekDoesNotReset() throws {
        let engine = ConsistencyStreakEngine()
        let result = try engine.streak(weeks: [
            week(0, fulfillment: 1.0),
            week(1, fulfillment: 1.0),
            week(2, fulfillment: 0.3), // semana en progreso / sin cumplir
        ])
        #expect(result.currentStreakWeeks == 0)
        #expect(result.isFulfilledThisWeek == false)
    }

    @Test("fulfillment fuera de rango lanza error")
    func invalidRatioThrows() {
        let engine = ConsistencyStreakEngine()
        #expect(throws: DomainValidationError.invalidStreakWeek) {
            _ = try engine.streak(weeks: [week(0, fulfillment: 1.2)])
        }
    }
}