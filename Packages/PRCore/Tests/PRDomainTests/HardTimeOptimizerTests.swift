import Testing
import Foundation
@testable import PRDomain

@Suite("Hard time optimizer (PR-0802)")
struct HardTimeOptimizerTests {

    private func makeItem(
        name: String,
        role: AssignmentRole,
        muscles: Set<MuscleGroup>,
        priority: Bool = false,
        sets: Int = 4,
        perSet: Double = 60,
        rest: Double = 90
    ) -> SessionItem {
        SessionItem(
            exerciseID: ExerciseID(),
            name: name,
            role: role,
            muscleGroups: muscles,
            isPriorityMuscle: priority,
            setCount: sets,
            secondsPerSet: perSet,
            restSeconds: rest
        )
    }

    @Test("fits when within limit without changes")
    func fitsInLimit() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Bench", role: .anchor, muscles: [.chest, .triceps]),
        ]
        // 1 item: 4*60 + 90*3 = 240+270 = 510, no transitions
        let result = optimizer.optimize(items: items, limitSeconds: 600, toleranceSeconds: 60)
        #expect(result.withinLimit)
        #expect(result.kept.count == 1)
        #expect(result.estimatedSeconds == 510)
    }

    @Test("anchor and priority muscles are preserved even over limit")
    func preservesAnchorsAndPriorities() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Squat", role: .anchor, muscles: [.quadriceps]),
            makeItem(name: "Accessory Curl", role: .rotatable, muscles: [.biceps], sets: 4, perSet: 60, rest: 90),
        ]
        // Squat 510 + Curl 510 + transition 30 = 1050
        let result = optimizer.optimize(items: items, limitSeconds: 600, toleranceSeconds: 0)
        // Debe conservar Squat; recortar/descartar el accessory.
        #expect(result.kept.contains { $0.name == "Squat" })
        #expect(result.notes.contains { $0.contains("Accessory") || $0.contains("accesorio") })
    }

    @Test("optionals are eliminated first")
    func eliminatesOptionalsFirst() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Anchor DL", role: .anchor, muscles: [.back, .hamstrings]),
            makeItem(name: "Optional Fly", role: .optional, muscles: [.chest]),
        ]
        // Anchor 510 + Optional 510 + 30 = 1050 > 600
        let result = optimizer.optimize(items: items, limitSeconds: 600, toleranceSeconds: 0)
        #expect(!result.kept.contains { $0.name == "Optional Fly" })
        #expect(result.kept.count == 1)
    }

    @Test("reduces accessory set count before dropping it")
    func reducesAccessoryBeforeDropping() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Anchor Press", role: .anchor, muscles: [.chest]),
            makeItem(name: "Curl", role: .rotatable, muscles: [.biceps], sets: 6, perSet: 30, rest: 60),
        ]
        // Anchor 4*60+90*3=510; Curl 6*30+60*5=480; total 990+30=1020
        // Limit 800: reduce Curl 6→3: 3*30+60*2=210 → 510+210+30=750 <= 800
        let result = optimizer.optimize(items: items, limitSeconds: 800, toleranceSeconds: 0)
        #expect(result.withinLimit)
        let curl = result.kept.first { $0.name == "Curl" }
        #expect(curl.map { $0.setCount } == 3)
    }

    @Test("never adds incompatible supersets")
    func neverAddsIncompatibleSupersets() {
        let optimizer = HardTimeOptimizer()
        let first = makeItem(name: "Bench", role: .rotatable, muscles: [.chest, .triceps])
        let second = makeItem(name: "Pushdown", role: .rotatable, muscles: [.triceps])
        // Solapan triceps → incompatible → CompatibleSuperset debe ser nil.
        #expect(CompatibleSuperset(first: first, second: second) == nil)
    }

    @Test("adds only compatible supersets")
    func addsCompatibleSupersets() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Anchor Squat", role: .anchor, muscles: [.quadriceps, .glutes]),
            makeItem(name: "Curl", role: .rotatable, muscles: [.biceps]),
            makeItem(name: "Fly", role: .rotatable, muscles: [.chest]),
        ]
        let result = optimizer.optimize(items: items, limitSeconds: 10_000, toleranceSeconds: 0)
        // Curl (biceps) y Fly (chest) son disjuntos → superset compatible.
        #expect(result.supersets.contains { $0.first.name == "Curl" && $0.second.name == "Fly" })
    }

    @Test("reports best-effort and withinLimit false when impossible")
    func reportsBestEffortWhenImpossible() {
        let optimizer = HardTimeOptimizer()
        let items = [makeItem(name: "Heavy", role: .anchor, muscles: [.chest], sets: 10, perSet: 120, rest: 120)]
        // 10*120 + 120*9 = 1200+1080 = 2280 > 2000
        let result = optimizer.optimize(items: items, limitSeconds: 2000, toleranceSeconds: 0)
        #expect(!result.withinLimit)
        #expect(result.kept.contains { $0.name == "Heavy" })
        #expect(result.notes.contains { $0.contains("Límite no alcanzado") })
    }

    @Test("tolerance is documented in result")
    func documentsTolerance() {
        let optimizer = HardTimeOptimizer()
        let items = [makeItem(name: "Anchor", role: .anchor, muscles: [.chest], sets: 4, perSet: 60, rest: 90)] // 510
        let result = optimizer.optimize(items: items, limitSeconds: 480, toleranceSeconds: 30)
        #expect(result.limitSeconds == 480)
        #expect(result.toleranceSeconds == 30)
        #expect(result.withinLimit) // 510 <= 480+30
    }
}