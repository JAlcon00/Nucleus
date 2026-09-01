import Testing
import Foundation
@testable import PRDomain

@Suite("Mark occupied (PR-0902)")
struct OccupancyControllerTests {

    @Test("marks equipment occupied during the session")
    func marksOccupied() throws {
        let controller = OccupancyController()
        let profile = try GymProfileManager().create(name: "A")
        let change = controller.markOccupied(
            .barbell,
            in: profile,
            orderedUses: [OrderedEquipmentUse(itemID: UUID(), equipmentTypes: [.dumbbell])]
        )
        #expect(change.profile.state(of: .barbell) == .occupied)
        #expect(change.occupiedType == .barbell)
        // No dispara reorder (ningún ítem usa barbell).
        #expect(!change.shouldReorder)
    }

    @Test("triggers reorder when a planned item uses the occupied equipment")
    func triggersReorderOnRelevantEquipment() throws {
        let controller = OccupancyController()
        let profile = try GymProfileManager().create(name: "A")
        let uses = [
            OrderedEquipmentUse(itemID: UUID(), equipmentTypes: [.cable]),
            OrderedEquipmentUse(itemID: UUID(), equipmentTypes: [.barbell, .plateLoaded]),
        ]
        let change = controller.markOccupied(.barbell, in: profile, orderedUses: uses)
        #expect(change.shouldReorder)
    }

    @Test("no reorder when occupied equipment is not in the plan")
    func noReorderWhenIrrelevant() throws {
        let controller = OccupancyController()
        let profile = try GymProfileManager().create(name: "A")
        let uses = [OrderedEquipmentUse(itemID: UUID(), equipmentTypes: [.machine])]
        let change = controller.markOccupied(.bands, in: profile, orderedUses: uses)
        #expect(!change.shouldReorder)
    }

    @Test("occupancy is session-scoped and cleared at end of session")
    func sessionScopedAndCleared() throws {
        let controller = OccupancyController()
        let profile = try GymProfileManager().create(name: "A")
        let change = controller.markOccupied(
            .smithMachine,
            in: profile,
            orderedUses: [OrderedEquipmentUse(itemID: UUID(), equipmentTypes: [.smithMachine])]
        )
        #expect(change.profile.state(of: .smithMachine) == .occupied)

        // No persiste como hecho del gym: al finalizar la sesión vuelve a unknown.
        let ended = controller.endingSession(change.profile)
        #expect(ended.state(of: .smithMachine) == .unknown)
    }

    @Test("multiple occupancies accumulate within the session")
    func accumulates() throws {
        let controller = OccupancyController()
        let profile = try GymProfileManager().create(name: "A")
        let first = controller.markOccupied(.dumbbell, in: profile, orderedUses: [])
        let second = controller.markOccupied(.sled, in: first.profile, orderedUses: [])
        #expect(second.profile.state(of: .dumbbell) == .occupied)
        #expect(second.profile.state(of: .sled) == .occupied)
    }
}