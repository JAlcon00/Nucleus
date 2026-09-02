import Testing
import Foundation
@testable import PRDomain

@Suite("Bodybuilding phase domain (PR-1801)")
struct BodybuildingPhaseTests {

    @Test("existen las 4 fases offSeason/cut/contestPrep/recovery")
    func hasFourPhases() {
        #expect(BodybuildingPhase.allCases == [.offSeason, .cut, .contestPrep, .recovery])
    }

    @Test("el ciclo estándar es offSeason → cut → contestPrep → recovery → offSeason")
    func cyclicTransitions() {
        #expect(BodybuildingPhase.offSeason.next == .cut)
        #expect(BodybuildingPhase.cut.next == .contestPrep)
        #expect(BodybuildingPhase.contestPrep.next == .recovery)
        #expect(BodybuildingPhase.recovery.next == .offSeason)
    }

    @Test("contestPrep es la única fase de competición activa")
    func onlyContestPrepIsActiveCompetition() {
        #expect(BodybuildingPhase.contestPrep.isCompetitionActive == true)
        for phase in [BodybuildingPhase.offSeason, .cut, .recovery] {
            #expect(phase.isCompetitionActive == false)
        }
    }

    @Test("transición válida sólo si respeta el ciclo")
    func validTransitionsOnly() {
        let controller = BodybuildingPhaseController()
        #expect(controller.isValidTransition(from: .offSeason, to: .cut) == true)
        #expect(controller.isValidTransition(from: .cut, to: .contestPrep) == true)
        // Saltarse fases no es válido (p. ej. offSeason→contestPrep).
        #expect(controller.isValidTransition(from: .offSeason, to: .contestPrep) == false)
        #expect(controller.isValidTransition(from: .recovery, to: .cut) == false)
    }

    @Test("advance aplica el ciclo desde cualquier fase")
    func advanceMovesForward() {
        let controller = BodybuildingPhaseController()
        #expect(controller.advance(from: .cut) == .contestPrep)
        #expect(controller.advance(from: .recovery) == .offSeason)
    }

    @Test("TrainingGoal.bodybuilding es un valor del goal y queda SEPARADO de la fase")
    func goalSeparateFromPhase() {
        let controller = BodybuildingPhaseController()

        // El usuario puede cambiar de fase sin tocar el goal: el profile sólo guarda phase.
        var profile = BodybuildingPhaseProfile(phase: .offSeason)
        profile.phase = .contestPrep
        #expect(profile.phase == .contestPrep)

        // Un goal distinto de .bodybuilding (p. ej. strength) convive con cualquier fase:
        // la fase es una dimensión ortogonal y no altera el TrainingGoal.
        let strength = TrainingGoal.strength
        let bodybuildingGoal = TrainingGoal.bodybuilding
        #expect(bodybuildingGoal != strength)

        // El cambio de fase aplica SOLO a la fase (api sin TrainingGoal → goal quedaría intacto).
        let applied = controller.applyTransition(from: .cut, to: .contestPrep)
        #expect(applied?.phase == .contestPrep)
        #expect(controller.applyTransition(from: .cut, to: .recovery) == nil, "salto ilegal no aplica")

        // `bodybuilding` es un caso de TrainingGoal (PR-0104), no un valor de fase.
        // La fase de bodybuilding y el objetivo son tipos distintos e independientes:
        // `BodybuildingPhase` no expone ningún caso `.bodybuilding` y `TrainingGoal` sí.
        #expect(TrainingGoal.allCases.contains(.bodybuilding))
        #expect(BodybuildingPhase.allCases.filter { "\($0)" == "bodybuilding" }.isEmpty)
    }
}