import Testing
import Foundation
@testable import PRDomain

@Suite("Specialization blocks (PR-1802)")
struct SpecializationTests {

    private func config() throws -> VolumeConfig {
        try VolumeConfig(rule: VolumeDefaults.makeRule())
    }

    @Test("músculos seleccionados (emphasize/specialize) reciben el mayor volumen")
    func selectedMusclesSpecialize() throws {
        let engine = SpecializationBlockEngine(allocator: VolumeAllocator(config: try config()))
        let result = try engine.build(input: SpecializationInput(
            priorities: [
                MusclePriority(muscleGroupID: .chest, priority: .specialize),
                MusclePriority(muscleGroupID: .back, priority: .emphasize),
                MusclePriority(muscleGroupID: .quadriceps, priority: .normal),
            ],
            weeklyTimeBudgetMinutes: 1000
        ))

        // specialize → 16 sets, emphasize → 12
        #expect(result.specializedMuscles == [.chest, .back])
        #expect(result.allocation.target(for: .chest) == 16)
        #expect(result.allocation.target(for: .back) == 12)
    }

    @Test("no prioritarios se mantienen en su tier (normal no sube por capricho)")
    func nonPrioritiesMaintained() throws {
        let engine = SpecializationBlockEngine(allocator: VolumeAllocator(config: try config()))
        let result = try engine.build(input: SpecializationInput(
            priorities: [
                MusclePriority(muscleGroupID: .chest, priority: .specialize),
                MusclePriority(muscleGroupID: .quadriceps, priority: .normal),
                MusclePriority(muscleGroupID: .calves, priority: .maintain),
            ],
            weeklyTimeBudgetMinutes: 1000
        ))

        // normal → 8, maintain → 4: mantenidos en su rango
        #expect(result.maintainedMuscles == [.quadriceps, .calves])
        #expect(result.allocation.target(for: .quadriceps) == 8)
        #expect(result.allocation.target(for: .calves) == 4)
    }

    @Test("presupuesto de tiempo respetado: reporta si cabe o no")
    func timeBudgetRespected() throws {
        let engine = SpecializationBlockEngine(allocator: VolumeAllocator(config: try config()))
        // chest(16) + quad(8) = 24 sets → 24 × 3min = 72 min
        let input = SpecializationInput(
            priorities: [
                MusclePriority(muscleGroupID: .chest, priority: .specialize),
                MusclePriority(muscleGroupID: .quadriceps, priority: .normal),
            ],
            weeklyTimeBudgetMinutes: 60
        )
        let tight = try engine.build(input: input)
        #expect(tight.timeCheck.estimatedMinutes == 72)
        #expect(tight.timeCheck.fitsBudget == false)

        let roomy = try engine.build(input: SpecializationInput(
            priorities: input.priorities,
            weeklyTimeBudgetMinutes: 90
        ))
        #expect(roomy.timeCheck.fitsBudget == true)
    }

    @Test("sin ningún músculo emphasise/specialize no hay bloque de especialización")
    func noSpecializationSelection() throws {
        let engine = SpecializationBlockEngine(allocator: VolumeAllocator(config: try config()))
        let selection = SpecializationBlockEngine.selection(from: [
            MusclePriority(muscleGroupID: .chest, priority: .normal),
            MusclePriority(muscleGroupID: .back, priority: .maintain),
        ])
        #expect(selection.isSpecialization == false)
        #expect(selection.specializeTargets.isEmpty)
        #expect(selection.emphasizeTargets.isEmpty)
    }

    @Test("selección determinista y enumera los targets de cada tier")
    func selectionIsDeterministic() {
        let selection = SpecializationBlockEngine.selection(from: [
            MusclePriority(muscleGroupID: .biceps, priority: .emphasize),
            MusclePriority(muscleGroupID: .forearms, priority: .specialize),
            MusclePriority(muscleGroupID: .triceps, priority: .emphasize),
        ])
        #expect(selection.specializeTargets == [.forearms])
        #expect(selection.emphasizeTargets == [.biceps, .triceps])
        #expect(selection.isSpecialization == true)
    }

    @Test("entrada inválida (sin prioridades o presupuesto negativo) lanza error")
    func invalidInputThrows() {
        let engine = SpecializationBlockEngine(allocator: VolumeAllocator(config: try! config()))
        #expect(throws: DomainValidationError.invalidSpecializationInput) {
            _ = try engine.build(input: SpecializationInput(priorities: [], weeklyTimeBudgetMinutes: 100))
        }
        #expect(throws: DomainValidationError.invalidSpecializationInput) {
            _ = try engine.build(input: SpecializationInput(
                priorities: [MusclePriority(muscleGroupID: .chest, priority: .specialize)],
                weeklyTimeBudgetMinutes: -5
            ))
        }
    }
}