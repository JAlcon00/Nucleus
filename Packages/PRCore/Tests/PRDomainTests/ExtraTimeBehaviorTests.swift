import Testing
import Foundation
@testable import PRDomain

@Suite("Extra time behavior (PR-0804)")
struct ExtraTimeBehaviorTests {

    @Test("never multiplies working volume with 180 min available")
    func doesNotMultiplyVolume() {
        let behavior = ExtraTimeBehavior(
            mobilitySeconds: 300,
            cardioSeconds: 600,
            posingSeconds: 480
        )
        // Mucho tiempo extra (10800s) no dispara volumen de trabajo automático.
        let plan = behavior.plan(
            extraSeconds: 10800,
            goal: .strength,
            phase: .maintenance,
            hasOptionals: true
        )
        #expect(plan.notes.contains { $0.contains("No se multiplica el volumen") })
        // Sin cardio/posing para strength/maintenance, sólo mobility opcional.
        #expect(plan.activities == [.mobility])
    }

    @Test("optionals are kept separate from the core")
    func optionalsSeparate() {
        let behavior = ExtraTimeBehavior()
        let plan = behavior.plan(extraSeconds: 600, goal: .strength, phase: .maintenance, hasOptionals: true)
        #expect(plan.optionalsAreSeparate)
    }

    @Test("mobility is always appropriate")
    func mobilityAlwaysApplies() {
        let behavior = ExtraTimeBehavior(mobilitySeconds: 300, cardioSeconds: 600, posingSeconds: 480)
        let plan = behavior.plan(extraSeconds: 300, goal: .bodybuilding, phase: .surplus, hasOptionals: false)
        #expect(plan.activities == [.mobility])
        #expect(plan.usedSeconds == 300)
    }

    @Test("cardio corresponds for generalHealth/recomposition/powerbuilding")
    func cardioApplies() {
        let behavior = ExtraTimeBehavior()
        #expect(behavior.cardioApplies(goal: .generalHealth, phase: .maintenance))
        #expect(behavior.cardioApplies(goal: .recomposition, phase: .surplus))
        #expect(behavior.cardioApplies(goal: .powerbuilding, phase: .maintenance))
        // hypertrophy en surplus → no cardio.
        #expect(!behavior.cardioApplies(goal: .hypertrophy, phase: .surplus))
        // pero en deficit sí.
        #expect(behavior.cardioApplies(goal: .hypertrophy, phase: .deficit))
    }

    @Test("cardio and posing only added when they correspond")
    func cardioPosingGated() {
        let behavior = ExtraTimeBehavior(mobilitySeconds: 300, cardioSeconds: 600, posingSeconds: 480)
        // bodybuilding → mobility + posing; cardio no (surplus).
        let plan = behavior.plan(extraSeconds: 6000, goal: .bodybuilding, phase: .surplus, hasOptionals: true)
        #expect(plan.activities.contains(.mobility))
        #expect(plan.activities.contains(.posing))
        #expect(!plan.activities.contains(.cardio))
        #expect(plan.notes.contains { $0.contains("Cardio no corresponde") })
    }

    @Test("never exceeds available extra time")
    func neverExceeds() {
        let behavior = ExtraTimeBehavior(mobilitySeconds: 300, cardioSeconds: 600, posingSeconds: 480)
        // Solo 400s: mobility (300) cabe; cardio (600) no; posing (480) no.
        let plan = behavior.plan(extraSeconds: 400, goal: .bodybuilding, phase: .deficit, hasOptionals: false)
        #expect(plan.usedSeconds <= 400)
        #expect(plan.activities == [.mobility])
    }

    @Test("explains leftover unused time when no activity corresponds")
    func explainsLeftover() {
        let behavior = ExtraTimeBehavior(mobilitySeconds: 300, cardioSeconds: 600, posingSeconds: 480)
        // 100s: ni mobility (300) cabe → no se usa tiempo; se explica el sobrante.
        let plan = behavior.plan(extraSeconds: 100, goal: .strength, phase: .surplus, hasOptionals: false)
        #expect(plan.usedSeconds == 0)
        #expect(plan.notes.contains { $0.contains("no se rellena") })
    }
}