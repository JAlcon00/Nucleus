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
/// SCRUM-227 (PR-B003, ADR-0004): la experiencia elige el punto dentro del rango de cada
/// nivel de prioridad; nunca sale del rango.
@Suite("SCRUM-227 · Volumen por experiencia dentro del rango")
struct VolumeByExperienceTests {
    private let tiers: [PriorityTier] = [.maintain, .normal, .emphasize, .specialize]

    private func sets(_ tier: PriorityTier, _ experience: ExperienceLevel?, config: VolumeConfig? = nil) throws -> Int? {
        let allocator = VolumeAllocator(config: try config ?? makeConfig(version: 2))
        return try allocator.allocate(priorities: [MusclePriority(muscleGroupID: .chest, priority: tier)], experience: experience)
            .target(for: .chest)
    }

    @Test("Novato el mínimo, principiante un cuarto, intermedio la mitad, avanzado y competitivo el máximo")
    func positionByExperience() throws {
        let expected: [PriorityTier: [ExperienceLevel: Int]] = [
            .maintain: [.novice: 4, .beginner: 4, .intermediate: 5, .advanced: 6, .competitive: 6],
            .normal: [.novice: 8, .beginner: 9, .intermediate: 10, .advanced: 12, .competitive: 12],
            .emphasize: [.novice: 12, .beginner: 13, .intermediate: 14, .advanced: 16, .competitive: 16],
            .specialize: [.novice: 16, .beginner: 17, .intermediate: 18, .advanced: 20, .competitive: 20],
        ]
        for tier in tiers {
            for experience in ExperienceLevel.allCases {
                #expect(try sets(tier, experience) == expected[tier]?[experience], "\(tier), \(experience)")
            }
        }
    }

    @Test("Sin experiencia, el mínimo (como antes); con cualquiera, nunca fuera del rango")
    func alwaysWithinRange() throws {
        let config = try makeConfig(version: 2)
        for tier in tiers {
            let range = config.range(for: tier)
            #expect(try sets(tier, nil) == range.lowerBound)
            for experience in ExperienceLevel.allCases {
                let value = try #require(try sets(tier, experience))
                #expect(range.contains(value), "\(tier), \(experience): \(value) fuera de \(range)")
            }
        }
    }

    @Test("El énfasis sigue recibiendo más que lo normal en cada nivel de experiencia (SCRUM-215)")
    func emphasisStaysAbove() throws {
        for experience in ExperienceLevel.allCases {
            #expect(try #require(try sets(.emphasize, experience)) > (try #require(try sets(.normal, experience))), "\(experience)")
        }
    }

    @Test("Una posición fuera de [0, 1] en la regla se acota al rango")
    func positionIsClamped() throws {
        var parameters = try VolumeDefaults.makeRule().parameters
        parameters[VolumeConfigKeys.positionAdvanced] = 3
        parameters[VolumeConfigKeys.positionNovice] = -1
        let config = try VolumeConfig(rule: EvidenceRule(
            id: VolumeDefaults.ruleID, name: "Fuera de rango", category: .volume, confidence: .emerging,
            version: 99, parameters: parameters
        ))
        #expect(try sets(.normal, .advanced, config: config) == 12)
        #expect(try sets(.normal, .novice, config: config) == 8)
    }

    @Test("El tiempo pone el techo: si no cabe, baja hacia el mínimo del rango y nunca por debajo")
    func timeCeilingLowersTowardMinimum() throws {
        let allocator = VolumeAllocator(config: try makeConfig(version: 2))
        let priorities = [MusclePriority(muscleGroupID: .chest, priority: .normal), MusclePriority(muscleGroupID: .back, priority: .normal)]
        let free = try allocator.allocate(priorities: priorities, experience: .advanced)
        #expect(free.totalWeeklySets == 24, "Sin techo: el máximo de los dos (12 + 12)")
        let fitted = try allocator.allocate(priorities: priorities, experience: .advanced, maxWeeklySets: 20)
        #expect(fitted.target(for: .chest) == 10)
        #expect(fitted.target(for: .back) == 10, "Baja parejo, una serie a la vez")
        let tight = try allocator.allocate(priorities: priorities, experience: .advanced, maxWeeklySets: 10)
        #expect(tight.target(for: .chest) == 8)
        #expect(tight.target(for: .back) == 8, "Nunca por debajo del mínimo: lo que no quepa lo recorta la sesión")
        let novice = try allocator.allocate(priorities: priorities, experience: .novice, maxWeeklySets: 10)
        #expect(novice.totalWeeklySets == 16, "El novato ya está en el mínimo")
        #expect(try allocator.allocate(priorities: priorities, experience: .advanced, maxWeeklySets: 20) == fitted)
    }

    @Test("La regla por defecto es la v2 y trae la posición de cada experiencia")
    func defaultRuleIsV2() throws {
        let rule = try VolumeDefaults.makeRule()
        #expect(rule.version == 2)
        for experience in ExperienceLevel.allCases {
            #expect(rule.parameters[VolumeConfigKeys.positionKey(for: experience)] != nil, "\(experience)")
        }
    }
}
