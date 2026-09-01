import Testing
import Foundation
@testable import PRDomain

@Suite("Mark missing (PR-0903)")
struct MissingEquipmentGuardTests {

    private func profile(withMissing types: [EquipmentType]) throws -> GymProfile {
        let manager = GymProfileManager()
        var profile = try manager.create(name: "A")
        for type in types {
            profile = try manager.setAvailability(type, to: .doesNotExist, on: profile)
        }
        return profile
    }

    private func item(_ id: String, equipment: Set<EquipmentType>) -> EquipmentRequiringItem {
        EquipmentRequiringItem(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            name: id,
            requiredEquipment: equipment
        )
    }

    @Test("persists missing in the gym profile")
    func persistsMissing() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        let updated = try manager.setAvailability(.barbell, to: .doesNotExist, on: profile)
        #expect(updated.state(of: .barbell) == .doesNotExist)
    }

    @Test("future items requiring missing equipment are blocked")
    func blocksMissingEquipment() throws {
        let guardD = MissingEquipmentGuard()
        let profile = try profile(withMissing: [.smithMachine])
        let items = [
            item("Squat on smith", equipment: [.smithMachine]),
            item("Barbell bench", equipment: [.barbell]),
        ]
        let result = guardD.filter(items, in: profile)
        #expect(result.allowed.map(\.name) == ["Barbell bench"])
        #expect(result.blocked.map(\.name) == ["Squat on smith"])
        #expect(result.missingTypes == [.smithMachine])
    }

    @Test("missing only blocks its own equipment, not others")
    func onlyBlocksItsOwn() throws {
        let guardD = MissingEquipmentGuard()
        let profile = try profile(withMissing: [.cable])
        let result = guardD.filter(
            [item("Machine press", equipment: [.machine])],
            in: profile
        )
        #expect(result.allowed.count == 1)
        #expect(result.blocked.isEmpty)
    }

    @Test("revert allows future sessions to program again")
    func revertAllowsProgrammingAgain() throws {
        let guardD = MissingEquipmentGuard()
        let profile = try profile(withMissing: [.bands])
        #expect(guardD.isMissing(.bands, in: profile))

        let reverted = try guardD.revert(.bands, in: profile)
        #expect(reverted.state(of: .bands) == .unknown)
        #expect(!guardD.isMissing(.bands, in: reverted))
        #expect(guardD.filter([item("Band pull", equipment: [.bands])], in: reverted).blocked.isEmpty)
    }

    @Test("available and unknown equipment do not block")
    func availableAndUnknownDoNotBlock() throws {
        let manager = GymProfileManager()
        var profile = try manager.create(name: "A")
        profile = try manager.setAvailability(.dumbbell, to: .available, on: profile)
        let guardD = MissingEquipmentGuard()
        #expect(!guardD.isMissing(.dumbbell, in: profile)) // available
        #expect(!guardD.isMissing(.barbell, in: profile))  // unknown
    }
}