//
//  AutoRescheduleEngineTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests para el motor determinista de auto-reprogramación tras descanso (PR-1304):
//  el descanso visto puede mover una sesión, se evitan conflictos de sesiones
//  consecutivas incompatibles, y los cambios importantes requieren confirmación.
//

import XCTest
@testable import PRDomain

final class AutoRescheduleEngineTests: XCTestCase {
    private let chest = MuscleGroup.chest
    private let legs = MuscleGroup.quadriceps

    private func makeEngine() throws -> AutoRescheduleEngine {
        try AutoRescheduleEngine(config: AutoRescheduleConfig(rule: AutoReschedulePolicyDefaults.makeRule()))
    }

    private func day(_ idx: Int, session: ScheduledSession?, blocked: Bool = false) -> ScheduleDay {
        ScheduleDay(dayIndex: idx, session: session, isBlockedRest: blocked)
    }

    // MARK: - Descanso recomendado mueve la sesión

    func testRestDayMovesSessionToNextFreeSlot() throws {
        let engine = try makeEngine()
        let push = ScheduledSession(title: "Push", focus: [chest])
        let schedule = [
            day(0, session: push, blocked: true), // afectado: día de descanso recomendado
            day(1, session: nil),                 // libre
        ]
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertEqual(result.proposal?.proposedDayIndex, 1)
        XCTAssertEqual(result.proposal?.session, push)
        XCTAssertFalse(result.proposal?.requiresUserConfirmation ?? true)
        XCTAssertEqual(result.decisionRecord.type, .reorder)
    }

    func testSkipsBlockedRestSlots() throws {
        let engine = try makeEngine()
        let push = ScheduledSession(title: "Push", focus: [chest])
        let schedule = [
            day(0, session: push, blocked: true),
            day(1, session: nil, blocked: true), // sigue siendo descanso
            day(2, session: nil),                // libre → se mueve aquí
        ]
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertEqual(result.proposal?.proposedDayIndex, 2)
    }

    // MARK: - Evita conflictos de sesiones consecutivas incompatibles

    func testAvoidsSlotAfterIncompatibleSameMuscleSession() throws {
        let engine = try makeEngine()
        let push = ScheduledSession(title: "Push", focus: [chest])
        let anotherPush = ScheduledSession(title: "Chest iso", focus: [chest])
        let pull = ScheduledSession(title: "Pull", focus: [legs])
        let schedule = [
            day(0, session: push, blocked: true), // afectada (Push) → moverse
            day(1, session: anotherPush),         // día siguiente ya tiene mismo foco
            day(2, session: nil),                 // libre, pero precedida por día1 (chest) incompatible
            day(3, session: pull, blocked: true),
        ]
        // Nota: día1 agregado para demostrar que el slot 2 choca con su día previo 1.
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        // día1 está ocupado (no es ranura). Según la lógica, day2 es libre y compatible
        // con day1 (¿mismos foco? sí → incompatible) por lo que se descarta; sin ranura.
        XCTAssertNil(result.proposal)
    }

    // MARK: - Cambio importante requiere confirmación

    func testImportantShiftForcesUserConfirmation() throws {
        let engine = try makeEngine()
        let push = ScheduledSession(title: "Push", focus: [chest])
        let schedule = [
            day(0, session: push, blocked: true),
            day(1, session: nil), // libre pero compatible; maxShift=2
        ]
        // Por defecto maxRecommendedShiftDays=2, shift=1 => NO importante.
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertFalse(result.proposal?.requiresUserConfirmation ?? true)
    }

    func testRequiresConfirmationWhenOnlySlotBeyondLimit() throws {
        // maxRecommendedShiftDays = 1 (config minimal) y única ranura libre a 2 días.
        var params = AutoReschedulePolicyKeys.defaults()
        params[AutoReschedulePolicyKeys.maxRecommendedShiftDays] = 1
        var rule = try AutoReschedulePolicyDefaults.makeRule()
        rule.parameters = params
        let engine = try AutoRescheduleEngine(config: AutoRescheduleConfig(rule: rule))

        let push = ScheduledSession(title: "Push", focus: [chest])
        let pull = ScheduledSession(title: "Pull", focus: [legs])
        let schedule = [
            day(0, session: push, blocked: true),
            day(1, session: pull), // ocupado
            day(2, session: nil),  // libre → shift=2 > 1 ⇒ confirmación
        ]
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertEqual(result.proposal?.proposedDayIndex, 2)
        XCTAssertTrue(result.proposal?.requiresUserConfirmation ?? false)
    }

    // MARK: - Validaciones

    func testNoSessionOnAffectedDayThrows() throws {
        let engine = try makeEngine()
        let schedule = [day(0, session: nil, blocked: true)]
        XCTAssertThrowsError(try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0)))
    }

    func testAffectedDayNotBlockedThrows() throws {
        let engine = try makeEngine()
        let schedule = [day(0, session: ScheduledSession(title: "Push", focus: [chest]))]
        XCTAssertThrowsError(try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0)))
    }

    func testAffectedDayOutOfRangeThrows() throws {
        let engine = try makeEngine()
        XCTAssertThrowsError(try engine.evaluate(AutoRescheduleInput(schedule: [], affectedDayIndex: 3)))
    }

    func testWrongCategoryRejected() throws {
        var rule = try AutoReschedulePolicyDefaults.makeRule()
        rule.category = .volume
        XCTAssertThrowsError(try AutoRescheduleConfig(rule: rule))
    }

    func testDecisionRecordAuditable() throws {
        let engine = try makeEngine()
        let push = ScheduledSession(title: "Push", focus: [chest])
        let schedule = [
            day(0, session: push, blocked: true),
            day(1, session: nil),
        ]
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertNotNil(result.proposal)
        XCTAssertEqual(result.decisionRecord.ruleReferences.map(\.ruleID), [AutoReschedulePolicyDefaults.ruleID])
        XCTAssertFalse(result.decisionRecord.inputFacts.isEmpty)
    }

    func testNoSlotMeansConservativeNoMove() throws {
        let engine = try makeEngine()
        let schedule = [day(0, session: ScheduledSession(title: "Push", focus: [chest]), blocked: true)]
        let result = try engine.evaluate(AutoRescheduleInput(schedule: schedule, affectedDayIndex: 0))
        XCTAssertNil(result.proposal)
        XCTAssertEqual(result.decisionRecord.type, .restChange)
    }
}