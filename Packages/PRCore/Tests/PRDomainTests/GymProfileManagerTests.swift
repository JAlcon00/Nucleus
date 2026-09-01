import Testing
import Foundation
@testable import PRDomain

@Suite("Gym profile manager (PR-0901)")
struct GymProfileManagerTests {

    @Test("create builds an empty gym without forcing equipment")
    func createEmptyGym() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "Main Gym")
        #expect(profile.name == "Main Gym")
        #expect(profile.equipmentAvailability.isEmpty)
        // Equipamiento sin confirmar queda .unknown (progressive disclosure).
        #expect(manager.state(of: .barbell, in: profile) == .unknown)
        #expect(manager.knownEquipmentTypes(profile).isEmpty)
    }

    @Test("create rejects empty name")
    func createRejectsEmptyName() {
        let manager = GymProfileManager()
        #expect(throws: GymProfileManagerError.emptyName) {
            _ = try manager.create(name: "   ")
        }
    }

    @Test("rename updates the name")
    func rename() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        let renamed = try manager.rename(profile, to: "B")
        #expect(renamed.name == "B")
        #expect(renamed.id == profile.id)
    }

    @Test("select sets the active gym")
    func selectActiveGym() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        let selected = manager.select(profile)
        #expect(selected.activeGymID == profile.id)
    }

    @Test("set availability persists available and doesNotExist")
    func setAvailability() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        let withBar = try manager.setAvailability(.barbell, to: .available, on: profile)
        let withBands = try manager.setAvailability(.bands, to: .doesNotExist, on: withBar)

        #expect(manager.state(of: .barbell, in: withBands) == .available)
        #expect(manager.state(of: .bands, in: withBands) == .doesNotExist)
        #expect(manager.knownEquipmentTypes(withBands).contains(.barbell))
        #expect(manager.knownEquipmentTypes(withBands).contains(.bands))
        // Los no mencionados siguen unknown.
        #expect(manager.state(of: .machine, in: withBands) == .unknown)
    }

    @Test("occupied is session-scoped and rejected by the manager")
    func occupiedRejected() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        #expect(throws: GymProfileManagerError.occupancyIsSessionScoped) {
            _ = try manager.setAvailability(.barbell, to: .occupied, on: profile)
        }
        // La ocupación de sesión se marca vía GymProfile.markingOccupied (no persistido).
        let marked = profile.markingOccupied(.barbell)
        #expect(manager.state(of: .barbell, in: marked) == .occupied)
        #expect(manager.knownEquipmentTypes(marked).isEmpty)
    }

    @Test("equipment can go unknown -> available -> doesNotExist and back")
    func availabilityTransitions() throws {
        let manager = GymProfileManager()
        let profile = try manager.create(name: "A")
        let a = try manager.setAvailability(.cable, to: .available, on: profile)
        let d = try manager.setAvailability(.cable, to: .doesNotExist, on: a)
        let u = try manager.setAvailability(.cable, to: .unknown, on: d)
        #expect(manager.state(of: .cable, in: u) == .unknown)
    }
}