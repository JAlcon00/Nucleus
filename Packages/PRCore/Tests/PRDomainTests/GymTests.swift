//
//  GymTests.swift
//  PRDomainTests
//
//  Created by PR.
//

import Foundation
import Testing
@testable import PRDomain

@Suite("Availability states (PR-0105)")
struct AvailabilityTests {

    @Test("Four availability states are distinct")
    func statesDistinct() {
        let states = Set(EquipmentAvailabilityState.allCases)
        #expect(states.count == 4)
        #expect(states.contains(.doesNotExist))
        #expect(states.contains(.occupied))
        #expect(states.contains(.unknown))
        #expect(states.contains(.available))
    }

    @Test("GymProfile exposes availability for equipment")
    func gymAvailability() {
        let gym = GymProfile(
            name: "Main Gym",
            equipmentAvailability: [
                EquipmentAvailability(equipmentType: .barbell, state: .available),
                EquipmentAvailability(equipmentType: .smithMachine, state: .doesNotExist),
            ]
        )
        #expect(gym.state(of: .barbell) == .available)
        #expect(gym.state(of: .smithMachine) == .doesNotExist)
        #expect(gym.state(of: .machine) == .unknown)
    }
}

@Suite("MachineProfile per-instance history (PR-0105)")
struct MachineProfileTests {

    @Test("Two machines of same type are distinct instances with distinct keys")
    func distinctInstances() {
        let exerciseID = ExerciseID()
        let gymID = GymID()

        let machineA = MachineProfile(gymID: gymID, exerciseID: exerciseID, model: "Model A")
        let machineB = MachineProfile(gymID: gymID, exerciseID: exerciseID, model: "Model B")

        #expect(machineA.id != machineB.id)
        #expect(machineA.loadHistoryKey.machineInstanceID != machineB.loadHistoryKey.machineInstanceID)
        #expect(machineA.loadHistoryKey.exerciseID == machineB.loadHistoryKey.exerciseID)
        // El historial se puede clavear por exercise + instancia.
        #expect(Set([machineA.loadHistoryKey, machineB.loadHistoryKey]).count == 2)
    }

    @Test("MachineProfile round-trips through Codable")
    func roundTrips() throws {
        let gymID = GymID()
        let machine = MachineProfile(
            gymID: gymID,
            exerciseID: ExerciseID(),
            manufacturer: "Technogym",
            model: "Pure Strength",
            userLabel: "Chest press"
        )
        let data = try JSONEncoder().encode(machine)
        let decoded = try JSONDecoder().decode(MachineProfile.self, from: data)
        #expect(decoded == machine)
        #expect(decoded.gymID == gymID)
        #expect(decoded.userLabel == "Chest press")
    }
}

@Suite("Occupied is session-scoped (PR-0105)")
struct SessionScopedTests {

    @Test("Occupied state clears when session ends")
    func occupiedClearsOnSessionEnd() {
        var gym = GymProfile(
            name: "Main Gym",
            equipmentAvailability: [
                EquipmentAvailability(equipmentType: .dumbbell, state: .available),
            ]
        )
        gym = gym.markingOccupied(.dumbbell)
        #expect(gym.state(of: .dumbbell) == .occupied)

        // Un equipo no registrado que fue marcado ocupado no persiste como ocupado.
        gym = gym.markingOccupied(.cable)
        #expect(gym.state(of: .cable) == .occupied)

        let after = gym.endingSession()
        // `available` registrado vuelve a available; no registrado vuelve a unknown.
        #expect(after.state(of: .dumbbell) == .available)
        #expect(after.state(of: .cable) == .unknown)
        #expect(after.equipmentAvailability.allSatisfy { $0.state != .occupied })
    }

    @Test("GymProfile round-trips through Codable")
    func gymRoundTrips() throws {
        let gym = GymProfile(
            name: "Main Gym",
            equipmentAvailability: [
                EquipmentAvailability(equipmentType: .barbell, state: .available)
            ],
            machineInstances: [
                MachineProfile(gymID: GymID(), exerciseID: ExerciseID())
            ]
        )
        let data = try JSONEncoder().encode(gym)
        let decoded = try JSONDecoder().decode(GymProfile.self, from: data)
        #expect(decoded == gym)
        #expect(decoded.name == "Main Gym")
        #expect(decoded.machineInstances.count == 1)
    }
}
