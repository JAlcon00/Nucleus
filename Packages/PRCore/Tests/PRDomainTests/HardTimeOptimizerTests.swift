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

    @Test("SCRUM-30: lo que queda conserva el orden de la sesión y se reduce el último accesorio")
    func keepsSessionOrderAndReducesTheLastAccessory() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Primer accesorio", role: .rotatable, muscles: [.biceps]),
            makeItem(name: "Ancla", role: .anchor, muscles: [.chest]),
            makeItem(name: "Último accesorio", role: .rotatable, muscles: [.triceps]),
        ]
        // 3 × 510 + 60 = 1 590; con 1 400 basta reducir el último 4→2 (1 290).
        let result = optimizer.optimize(items: items, limitSeconds: 1_400)
        #expect(result.kept.map(\.name) == ["Primer accesorio", "Ancla", "Último accesorio"])
        #expect(result.kept.map(\.setCount) == [4, 4, 2])
        #expect(result.withinLimit)
    }

    @Test("SCRUM-30: si hay que quitar un accesorio se quita el último")
    func dropsTheLastAccessory() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Ancla", role: .anchor, muscles: [.chest]),
            makeItem(name: "Accesorio 1", role: .rotatable, muscles: [.biceps], sets: 1),
            makeItem(name: "Accesorio 2", role: .rotatable, muscles: [.triceps], sets: 1),
        ]
        // 510 + 60 + 60 + 2 × 30 = 690; con 620 se quita "Accesorio 2" (600).
        let result = optimizer.optimize(items: items, limitSeconds: 620)
        #expect(result.kept.map(\.name) == ["Ancla", "Accesorio 1"])
        #expect(result.withinLimit)
    }

    @Test("SCRUM-225: un accesorio de 2 series se quita en lugar de quedar en 1")
    func twoSetAccessoryIsDroppedNotHalved() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Ancla", role: .anchor, muscles: [.chest]),
            makeItem(name: "Accesorio", role: .rotatable, muscles: [.biceps], sets: 2, perSet: 30, rest: 60),
        ]
        // 510 + (2×30 + 60) + 30 = 660; con 600 ya no se puede partir: se quita.
        let result = optimizer.optimize(items: items, limitSeconds: 600)
        #expect(result.kept.map(\.name) == ["Ancla"])
        #expect(result.withinLimit)
    }

    @Test("SCRUM-225: un accesorio de 6 baja a 3 y luego a 2, nunca a 1")
    func accessoryNeverGoesBelowTwo() {
        let optimizer = HardTimeOptimizer()
        let items = [
            makeItem(name: "Ancla", role: .anchor, muscles: [.chest]),
            makeItem(name: "Accesorio", role: .rotatable, muscles: [.biceps], sets: 6, perSet: 30, rest: 60),
        ]
        // Ancla 510; accesorio con 2 series = 120; total 660. Con 680 cabe con 2 (no con 1).
        let result = optimizer.optimize(items: items, limitSeconds: 680)
        #expect(result.kept.first { $0.name == "Accesorio" }?.setCount == 2)
        #expect(result.withinLimit)
    }

    @Test("SCRUM-225: con calentamiento, el mínimo es de 2 series de trabajo")
    func minimumCountsWorkSetsNotWarmups() {
        let optimizer = HardTimeOptimizer()
        let accessory = SessionItem(
            exerciseID: ExerciseID(), name: "Accesorio", role: .rotatable, muscleGroups: [.biceps],
            setCount: 4, secondsPerSet: 30, restSeconds: 60, warmupSets: 1
        )
        let items = [makeItem(name: "Ancla", role: .anchor, muscles: [.chest]), accessory]
        // 510 + (4×30 + 3×60) + 30 = 840. Partir a la mitad dejaría 2 = 1 cal. + 1 de trabajo;
        // el mínimo es 1 cal. + 2 de trabajo = 3: 510 + 210 + 30 = 750 ≤ 760.
        let result = optimizer.optimize(items: items, limitSeconds: 760)
        #expect(result.kept.first { $0.name == "Accesorio" }?.setCount == 3)
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