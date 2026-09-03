//
//  VolumeAllocatorTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del VolumeAllocator (PR-0502, plan §4B): distribución por tier de
//  prioridad, determinismo, ausencia de volumen negativo y reglas versionadas.
//

import Foundation
import Testing
@testable import PRDomain

private func makeConfig(version: Int = 1) throws -> VolumeConfig {
    try VolumeConfig(rule: VolumeDefaults.makeRule(version: version))
}

@Suite("VolumeAllocator distribution (PR-0502)")
struct VolumeAllocationTests {
    @Test("Respects maintain < normal < emphasize < specialize")
    func respectsTierOrdering() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let allocation = try allocator.allocate(priorities: [
            MusclePriority(muscleGroupID: .chest, priority: .specialize),
            MusclePriority(muscleGroupID: .back, priority: .emphasize),
            MusclePriority(muscleGroupID: .shoulders, priority: .normal),
            MusclePriority(muscleGroupID: .biceps, priority: .maintain),
        ])
        // Reales del valor representativo (mínimo del rango).
        #expect(allocation.target(for: .chest) == 16)     // specialize min
        #expect(allocation.target(for: .back) == 12)      // emphasize min
        #expect(allocation.target(for: .shoulders) == 8)  // normal min
        #expect(allocation.target(for: .biceps) == 4)     // maintain min
    }

    @Test("Tracks weekly budget ranges across all groups")
    func tracksBudget() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let allocation = try allocator.allocate(priorities: [
            MusclePriority(muscleGroupID: .chest, priority: .emphasize),
            MusclePriority(muscleGroupID: .quadriceps, priority: .normal),
        ])
        // emphasize 12...16 + normal 8...12 = 20...28
        #expect(allocation.minTotalWeeklySets == 20)
        #expect(allocation.maxTotalWeeklySets == 28)
        #expect(allocation.totalWeeklySets == 20)
    }

    @Test("Never produces negative volume")
    func noNegativeVolume() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let allocation = try allocator.allocate(priorities: [
            MusclePriority(muscleGroupID: .biceps, priority: .maintain),
        ])
        #expect(allocation.targets.allSatisfy { $0.weeklySets >= 0 })
    }

    @Test("Empty priorities produce empty allocation (no invented muscles)")
    func emptyPriorities() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let allocation = try allocator.allocate(priorities: [])
        #expect(allocation.targets.isEmpty)
        #expect(allocation.totalWeeklySets == 0)
    }

    @Test("Every target records its versioned rule reference")
    func recordsRuleReference() throws {
        let allocator = VolumeAllocator(config: try makeConfig(version: 3))
        let allocation = try allocator.allocate(priorities: [
            MusclePriority(muscleGroupID: .chest, priority: .emphasize),
        ])
        #expect(allocation.targets.first?.ruleReference.version == 3)
        #expect(allocation.targets.first?.ruleReference.ruleID == VolumeDefaults.ruleID)
    }

    @Test("Same inputs produce identical allocation")
    func deterministic() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let priorities = [
            MusclePriority(muscleGroupID: .chest, priority: .specialize),
            MusclePriority(muscleGroupID: .back, priority: .normal),
        ]
        let a = try allocator.allocate(priorities: priorities)
        let b = try allocator.allocate(priorities: priorities)
        #expect(a == b)
    }
}

@Suite("VolumeConfig validation (PR-0502)")
struct VolumeConfigTests {
    @Test("Rejects a rule missing required volume parameters")
    func rejectsMissingParameters() {
        let rule = try! EvidenceRule(
            id: VolumeDefaults.ruleID,
            name: "Broken",
            category: .volume,
            confidence: .emerging,
            version: 1,
            parameters: ["maintainMin": 4] // incompleto
        )
        #expect(throws: VolumeAllocationError.missingVolumeRule) {
            _ = try VolumeConfig(rule: rule)
        }
    }

    @Test("Ranges are ordered per tier via config keys")
    func configRangesOrdered() throws {
        let config = try makeConfig()
        #expect(config.range(for: .maintain) == 4...6)
        #expect(config.range(for: .normal) == 8...12)
        #expect(config.range(for: .emphasize) == 12...16)
        #expect(config.range(for: .specialize) == 16...20)
    }

    @Test("Invalid negative volume is rejected by the target type")
    func rejectsNegativeVolume() {
        // Solo llega negativo si la lógica del allocator se rompe; probamos el
        // guard de dominio del value type.
        #expect(throws: VolumeAllocationError.negativeVolume(muscle: "chest", sets: -1)) {
            _ = try MuscleVolumeAssignment(
                muscleGroupID: .chest,
                weeklySets: -1,
                priority: .normal,
                ruleReference: try EvidenceRuleReference(ruleID: VolumeDefaults.ruleID, version: 1)
            )
        }
    }
}

@Suite("VolumeAllocator time budget (PR-0502)")
struct VolumeAllocatorTimeBudgetTests {
    private func priority(_ muscle: MuscleGroup.ID, _ tier: PriorityTier) -> MusclePriority {
        MusclePriority(muscleGroupID: muscle, priority: tier)
    }

    @Test("Without a time budget no check is attached")
    func noBudgetProducesNoTimeCheck() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let allocation = try allocator.allocate(priorities: [
            priority(.chest, .emphasize),
            priority(.back, .normal),
        ])
        #expect(allocation.timeCheck == nil)
    }

    @Test("Generous budget reports fitsBudget true")
    func generousBudgetFits() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        // emphasize 12 + normal 8 = 20 sets; 20 × 3 = 60 min.
        let allocation = try allocator.allocate(
            priorities: [priority(.chest, .emphasize), priority(.back, .normal)],
            weeklyTimeBudgetMinutes: 60,
            minutesPerWorkingSet: 3.0
        )
        #expect(allocation.timeCheck?.estimatedMinutes == 60)
        #expect(allocation.timeCheck?.budgetMinutes == 60)
        #expect(allocation.timeCheck?.fitsBudget == true)
    }

    @Test("Tight budget reports fitsBudget false instead of breaking the evidence floor")
    func tightBudgetDoesNotFit() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        // emphasize 12 + normal 8 = 20 sets; 20 × 2 = 40 min > 30 min budget.
        let allocation = try allocator.allocate(
            priorities: [priority(.chest, .emphasize), priority(.back, .normal)],
            weeklyTimeBudgetMinutes: 30,
            minutesPerWorkingSet: 2.0
        )
        #expect(allocation.timeCheck?.estimatedMinutes == 40)
        #expect(allocation.timeCheck?.fitsBudget == false)
        // El suelo de evidencia no se rompe: los sets siguen en los mínimos versionados.
        #expect(allocation.target(for: .chest) == 12)
        #expect(allocation.target(for: .back) == 8)
    }

    @Test("Same inputs produce the same time check")
    func timeCheckDeterministic() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        let priorities = [priority(.chest, .specialize), priority(.biceps, .normal)]
        let a = try allocator.allocate(priorities: priorities, weeklyTimeBudgetMinutes: 90, minutesPerWorkingSet: 3.0)
        let b = try allocator.allocate(priorities: priorities, weeklyTimeBudgetMinutes: 90, minutesPerWorkingSet: 3.0)
        #expect(a.timeCheck == b.timeCheck)
        #expect(a.timeCheck?.fitsBudget == true)
    }

    @Test("Minutes per set rounding rounds the estimate up")
    func estimateRoundsUp() throws {
        let allocator = VolumeAllocator(config: try makeConfig())
        // 20 sets × 3.1 = 62 min (en vez de 62.0 exacto) → 62.
        let allocation = try allocator.allocate(
            priorities: [priority(.chest, .emphasize), priority(.back, .normal)],
            weeklyTimeBudgetMinutes: 100,
            minutesPerWorkingSet: 3.1
        )
        #expect(allocation.timeCheck?.estimatedMinutes == 62)
    }
}