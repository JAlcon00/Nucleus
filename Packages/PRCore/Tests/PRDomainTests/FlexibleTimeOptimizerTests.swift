import Testing
import Foundation
@testable import PRDomain

@Suite("Flexible time optimizer (PR-0803)")
struct FlexibleTimeOptimizerTests {

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

    @Test("reports inWindow when already within target tolerance")
    func alreadyInWindow() {
        let optimizer = FlexibleTimeOptimizer()
        let items = [makeItem(name: "Bench", role: .anchor, muscles: [.chest])] // 510
        let result = optimizer.optimize(items: items, targetSeconds: 500, toleranceSeconds: 60)
        #expect(result.status == .inWindow)
        #expect(result.inWindow)
        #expect(result.kept.count == 1)
    }

    @Test("trims just enough to enter the window from above")
    func trimsIntoWindow() {
        let optimizer = FlexibleTimeOptimizer()
        let items = [
            makeItem(name: "Squat", role: .anchor, muscles: [.quadriceps]),         // 510
            makeItem(name: "Curl", role: .rotatable, muscles: [.biceps], sets: 4),  // 510
        ] // total 510+510+30 = 1050
        // Window target 700 ± 200 → lower 500, upper 900 → 1050 > 900, trim.
        let result = optimizer.optimize(items: items, targetSeconds: 700, toleranceSeconds: 200)
        #expect(result.status == .inWindow)
        #expect(result.estimatedSeconds >= result.lowerBound)
        #expect(result.estimatedSeconds <= result.upperBound)
    }

    @Test("reports under without adding volume")
    func reportsUnder() {
        let optimizer = FlexibleTimeOptimizer()
        let items = [makeItem(name: "Squat", role: .anchor, muscles: [.quadriceps])] // 510
        // Window target 900 ± 100 → lower 800 → 510 < 800 → under.
        let result = optimizer.optimize(items: items, targetSeconds: 900, toleranceSeconds: 100)
        #expect(result.status == .under)
        #expect(result.kept.count == 1)
        #expect(result.notes.contains { $0.contains("extra-time") })
    }

    @Test("explains when not feasible above the window")
    func explainsNotFeasibleOver() {
        let optimizer = FlexibleTimeOptimizer()
        let items = [makeItem(name: "Heavy", role: .anchor, muscles: [.chest], sets: 10, perSet: 120, rest: 120)] // 2280
        let result = optimizer.optimize(items: items, targetSeconds: 1500, toleranceSeconds: 0)
        #expect(result.status == .notFeasible)
        #expect(result.notes.contains { $0.contains("No es factible") })
    }

    @Test("explains not feasible when window is too narrow")
    func explainsNarrowWindow() {
        let optimizer = FlexibleTimeOptimizer()
        // Anchor 510 + accessory Curl 510 = 1050.
        let items = [
            makeItem(name: "Squat", role: .anchor, muscles: [.quadriceps]),
            makeItem(name: "Curl", role: .rotatable, muscles: [.biceps], sets: 4, perSet: 60, rest: 90),
        ]
        // target 800 ± 0: 1050 > 800; trim quita/reduce accessorio → salta a 510 (<800) o resta halves.
        // Ningún ajuste cae en [800,800] → notFeasible explicado.
        let result = optimizer.optimize(items: items, targetSeconds: 800, toleranceSeconds: 0)
        #expect(result.status == .notFeasible)
        #expect(!result.notes.isEmpty)
    }

    @Test("preserves anchors even when trimming")
    func preservesAnchorsWhenTrimming() {
        let optimizer = FlexibleTimeOptimizer()
        let items = [
            makeItem(name: "Squat", role: .anchor, muscles: [.quadriceps]),
            makeItem(name: "Optional", role: .optional, muscles: [.biceps]),
        ] // 510+510+30 = 1050
        let result = optimizer.optimize(items: items, targetSeconds: 600, toleranceSeconds: 60)
        // Anchors/priority deben sobrevivir; el optional se elimina.
        #expect(result.kept.contains { $0.name == "Squat" })
        #expect(!result.kept.contains { $0.name == "Optional" })
    }
}