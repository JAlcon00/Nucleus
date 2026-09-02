import Testing
import Foundation
@testable import PRDomain

@Suite("Achievement framework (PR-1703)")
struct AchievementTests {

    private func unlocked(_ result: AchievementEngineResult, _ id: AchievementID) -> Bool {
        result.statuses.first { $0.definition.id == id }?.unlocked ?? false
    }

    private func newly(_ result: AchievementEngineResult) -> Set<AchievementID> {
        Set(result.newlyUnlocked.map { $0.id })
    }

    // MARK: - cada logro se desbloquea por su umbral

    @Test("first workout al completar 1 sesión")
    func firstWorkout() throws {
        let engine = AchievementEngine()
        let result = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkouts: 1))
        #expect(unlocked(result, .firstWorkout))
    }

    @Test("first PR cuando hay algún PR")
    func firstPR() throws {
        let engine = AchievementEngine()
        let result = try engine.evaluate(snapshot: AchievementSnapshot(hasAnyPR: true))
        #expect(unlocked(result, .firstPR))
    }

    @Test("consistency 4 y 8 semanas por racha máxima de consistency")
    func consistencyMilestones() throws {
        let engine = AchievementEngine()
        let at4 = try engine.evaluate(snapshot: AchievementSnapshot(longestConsistencyWeeks: 4))
        #expect(unlocked(at4, .consistency4Weeks))
        #expect(!unlocked(at4, .consistency8Weeks))

        let at8 = try engine.evaluate(snapshot: AchievementSnapshot(longestConsistencyWeeks: 8))
        #expect(unlocked(at8, .consistency4Weeks))
        #expect(unlocked(at8, .consistency8Weeks))
    }

    @Test("block complete y deload complete")
    func blockAndDeload() throws {
        let engine = AchievementEngine()
        let result = try engine.evaluate(snapshot: AchievementSnapshot(completedBlocks: 1, completedDeloads: 1))
        #expect(unlocked(result, .blockComplete))
        #expect(unlocked(result, .deloadComplete))
    }

    @Test("first smart substitution al usar una")
    func firstSmartSubstitution() throws {
        let engine = AchievementEngine()
        let result = try engine.evaluate(snapshot: AchievementSnapshot(smartSubstitutionsUsed: 1))
        #expect(unlocked(result, .firstSmartSubstitution))
    }

    @Test("working sets: umbrales 100/500/1000")
    func workingSetMilestones() throws {
        let engine = AchievementEngine()
        let below = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: 99))
        #expect(!unlocked(below, .workingSets100))

        let at100 = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: 100))
        #expect(unlocked(at100, .workingSets100))
        #expect(!unlocked(at100, .workingSets500))

        let at500 = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: 500))
        #expect(unlocked(at500, .workingSets100))
        #expect(unlocked(at500, .workingSets500))
        #expect(!unlocked(at500, .workingSets1000))

        let at1000 = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: 1000))
        #expect(unlocked(at1000, .workingSets100))
        #expect(unlocked(at1000, .workingSets500))
        #expect(unlocked(at1000, .workingSets1000))
    }

    // MARK: - idempotencia y nueva evaluación

    @Test("solo los logros recién alcanzados aparecen como newlyUnlocked")
    func onlyNewlyUnlockedReported() throws {
        let engine = AchievementEngine()
        let result = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkouts: 1, totalWorkingSets: 600))
        #expect(newly(result) == [.firstWorkout, .workingSets100, .workingSets500])
    }

    @Test("logro ya desbloqueado no se re-desbloquea pero se mantiene")
    func alreadyUnlockedStable() throws {
        let engine = AchievementEngine()
        let first = try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: 100))
        let unlockedFirst = first.statuses.first { $0.definition.id == .workingSets100 }!
        #expect(unlockedFirst.unlocked)
        #expect(unlockedFirst.unlockedAt != nil)

        // Segunda evaluación con el logro ya en el conjunto: no aparece como newly
        let second = try engine.evaluate(
            snapshot: AchievementSnapshot(totalWorkingSets: 100),
            alreadyUnlocked: [.workingSets100]
        )
        #expect(unlocked(second, .workingSets100))
        #expect(newly(second).isEmpty)
    }

    @Test("hay 10 logros definidos, incluidos los dos de consistency")
    func tenDefinitions() {
        let definitions = AchievementEngine.definitionsOrdered()
        #expect(definitions.count == 10)
        #expect(definitions.map { $0.id }.contains(.consistency4Weeks))
        #expect(definitions.map { $0.id }.contains(.consistency8Weeks))
    }

    // MARK: - validación

    @Test("snapshot con contador negativo lanza error")
    func invalidSnapshotThrows() {
        let engine = AchievementEngine()
        #expect(throws: DomainValidationError.invalidAchievementSnapshot) {
            try engine.evaluate(snapshot: AchievementSnapshot(totalWorkingSets: -1))
        }
    }
}