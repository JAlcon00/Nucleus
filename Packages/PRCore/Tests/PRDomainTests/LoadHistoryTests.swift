//
//  LoadHistoryTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del per-machine load history (PR-0906): historial EWMA por clave
//  `exercise + machineInstance`, independencia entre instancias, y sustitución que
//  recupera el historial del sustituto sin transferir la carga del original.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Per-machine load history (PR-0906)")
struct LoadHistoryTests {

    private func set(
        exerciseID: ExerciseID,
        machineID: MachineProfileID?,
        weight: Double,
        unit: LoadUnit = .kilograms,
        reps: Int = 8
    ) -> SetRecord {
        try! SetRecord(
            exerciseID: exerciseID,
            machineProfileID: machineID?.rawValue,
            weight: weight,
            unit: unit,
            reps: reps,
            lifecycle: .completed
        )
    }

    @Test("Acumula historial EWMA de load por exercise+machineInstance")
    func accumulatesPerMachineHistory() throws {
        let exercise = ExerciseID()
        let machine = MachineProfileID()
        var service = try MachineLoadHistoryService()

        let wants1 = try service.record(set(exerciseID: exercise, machineID: machine, weight: 100))
        service = try service.replacing(profiles: wants1)
        let wants2 = try service.record(set(exerciseID: exercise, machineID: machine, weight: 120))
        service = try service.replacing(profiles: wants2)

        let profile = service.profiles[MachineLoadHistoryKey(exerciseID: exercise, machineInstanceID: machine)]
        #expect(profile != nil)
        #expect(profile!.sampleCount == 2)
        // EWMA: con un solo smoothing base, primera → 100, segunda → 100 + (120-100)*1/3.
        #expect(profile!.confidence > 0)
        // La carga acumulada está entre las dos observaciones y cerca de la última.
        #expect(profile!.averageLoad > 100 && profile!.averageLoad <= 120)
    }

    @Test("Instancias de máquina distintas tienen historial independiente")
    func distinctMachinesIndependend() throws {
        let exercise = ExerciseID()
        let machineA = MachineProfileID()
        let machineB = MachineProfileID()
        var service = try MachineLoadHistoryService()

        let wants = try service.record(set(exerciseID: exercise, machineID: machineA, weight: 100))
        service = try service.replacing(profiles: wants)

        // La máquina B no tiene historial aunque la A sí.
        #expect(service.weight(forExercise: exercise, onMachine: machineB) == nil)
        #expect(service.weight(forExercise: exercise, onMachine: machineA) == 100)
    }

    @Test("Sustitución recupera el historial del sustituto, no transfiere el del original")
    func substitutionUsesSubstituteHistory() throws {
        let original = ExerciseID()
        let substitute = ExerciseID()
        let machine = MachineProfileID()
        var service = try MachineLoadHistoryService()

        // Historico del ORIGINAL en la máquina.
        let wants = try service.record(set(exerciseID: original, machineID: machine, weight: 200))
        service = try service.replacing(profiles: wants)

        let substituteExercise = makeExercise(id: substitute, name: "Substitute")

        // El SUSTITUTO no tiene historial propio → nil, y NUNCA cae al peso del original.
        #expect(service.weightForSubstitute(substituteExercise, onMachine: MachineProfile(id: machine, gymID: GymID(), exerciseID: substituteExercise.id)) == nil)
    }

    @Test("Sustitución usa su propio historial cuando existe")
    func substitutionUsesOwnHistoryWhenPresent() throws {
        let substitute = ExerciseID()
        let mixed = ExerciseID()
        let machine = MachineProfileID()
        var service = try MachineLoadHistoryService()

        // El sustituto sí tiene historial propio en esa máquina.
        let wants = try service.record(set(exerciseID: substitute, machineID: machine, weight: 80))
        service = try service.replacing(profiles: wants)
        // El original (otro ejercicio) también, con otra carga.
        let wants2 = try service.record(set(exerciseID: mixed, machineID: machine, weight: 200))
        service = try service.replacing(profiles: wants2)

        let substituteMachine = MachineProfile(id: machine, gymID: GymID(), exerciseID: substitute)
        let profile = service.weightForSubstitute(makeExercise(id: substitute, name: "S"), onMachine: substituteMachine)
        #expect(profile?.averageLoad == 80)
    }

    @Test("Un set sin instancia de máquina no puede mantener historial por máquina")
    func setWithoutMachineProfileThrows() throws {
        let service = try MachineLoadHistoryService()
        #expect(throws: MachineLoadHistoryError.setLacksMachineProfile) {
            try service.record(set(exerciseID: ExerciseID(), machineID: nil, weight: 80))
        }
    }

    // MARK: - Fixtures

    private func makeExercise(id: ExerciseID, name: String) -> Exercise {
        Exercise(
            id: id,
            canonicalName: name,
            movementPattern: .horizontalPress,
            primaryMuscles: [try! MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
            equipment: .machine,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [.primaryCompound],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }
}