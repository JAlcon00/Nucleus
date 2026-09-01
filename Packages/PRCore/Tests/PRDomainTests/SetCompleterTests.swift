import Testing
import Foundation
@testable import PRDomain

@Suite("One-tap set completion (PR-0603)")
struct SetCompleterTests {

    private func prescription(
        targetLoad: Double? = 100,
        repRange: ClosedRange<Int> = 8...12,
        unit: LoadUnit = .kilograms
    ) throws -> SetPrescription {
        try SetPrescription(
            targetRepRange: repRange,
            targetLoad: targetLoad,
            loadUnit: unit,
            restSeconds: 90...150
        )
    }

    private func plannedSet(_ prescription: SetPrescription) throws -> PlannedSet {
        PlannedSet(exerciseID: ExerciseID.test, prescription: prescription)
    }

    private func session(_ lifecycle: WorkoutLifecycleState = .active) -> WorkoutSessionRecord {
        WorkoutSessionRecord(lifecycle: lifecycle)
    }

    @Test("preload uses prescription targetLoad when present")
    func preloadUsesTargetLoad() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100))
        let draft = SetCompleter().preload(for: planned)

        #expect(draft.targetWeight == 100)
        #expect(draft.targetUnit == .kilograms)
        #expect(draft.targetReps == 8)
        #expect(!draft.weightFromHistory)
    }

    @Test("preload falls back to last performed weight when no targetLoad")
    func preloadFallsBackToHistory() throws {
        let planned = try plannedSet(try prescription(targetLoad: nil))
        let draft = SetCompleter().preload(for: planned, lastPerformedWeight: 75)

        #expect(draft.targetWeight == 75)
        #expect(draft.weightFromHistory)
    }

    @Test("preload uses zero placeholder when nothing available")
    func preloadZeroPlaceholder() throws {
        let planned = try plannedSet(try prescription(targetLoad: nil))
        let draft = SetCompleter().preload(for: planned)

        #expect(draft.targetWeight == 0)
        #expect(!draft.weightFromHistory)
    }

    @Test("one-tap records when input matches the target")
    func oneTapMatchesTarget() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100, repRange: 8...12))
        let completer = SetCompleter()
        let draft = completer.preload(for: planned)
        let input = SetCompletionInput(weight: 100, unit: .kilograms, reps: 8)

        let updated = try completer.oneTap(
            input: input,
            matches: draft,
            planned: planned,
            in: session()
        )

        let completed = try #require(updated)
        #expect(completed.sets.count == 1)
        #expect(completed.sets[0].weight == 100)
        #expect(completed.sets[0].reps == 8)
        #expect(completed.sets[0].lifecycle == .completed)
    }

    @Test("one-tap does not record when input differs from target")
    func oneTapDoesNotRecordOnMismatch() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100, repRange: 8...12))
        let completer = SetCompleter()
        let draft = completer.preload(for: planned)
        let input = SetCompletionInput(weight: 102.5, unit: .kilograms, reps: 10)

        let updated = try completer.oneTap(
            input: input,
            matches: draft,
            planned: planned,
            in: session()
        )
        #expect(updated == nil)
    }

    @Test("draft does not match a different unit or reps")
    func draftMatchingIsExact() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100, repRange: 8...12))
        let draft = SetCompleter().preload(for: planned)

        #expect(!draft.matches(SetCompletionInput(weight: 100, unit: .pounds, reps: 8)))
        #expect(!draft.matches(SetCompletionInput(weight: 100, unit: .kilograms, reps: 9)))
    }

    @Test("recordSet allows edited weight/reps and persists before UI transition")
    func recordSetEditable() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100, repRange: 8...12))
        let completer = SetCompleter()
        // Usuario edita: peso distinto, reps en rango alto.
        let input = SetCompletionInput(weight: 102.5, unit: .kilograms, reps: 12)

        let updated = try completer.recordSet(input: input, planned: planned, in: session())

        #expect(updated.sets.count == 1)
        #expect(updated.sets[0].weight == 102.5)
        #expect(updated.sets[0].reps == 12)
        #expect(updated.sets[0].lifecycle == .completed)
    }

    @Test("recordSet validates non-negative weight and positive reps")
    func recordSetValidation() throws {
        let planned = try plannedSet(try prescription())
        let completer = SetCompleter()

        #expect(throws: DomainValidationError.self) {
            _ = try completer.recordSet(
                input: SetCompletionInput(weight: -1, unit: .kilograms, reps: 8),
                planned: planned,
                in: session()
            )
        }
        #expect(throws: DomainValidationError.self) {
            _ = try completer.recordSet(
                input: SetCompletionInput(weight: 100, unit: .kilograms, reps: 0),
                planned: planned,
                in: session()
            )
        }
    }

    @Test("completion appends without mutating prior sets or plan")
    func appendOnly() throws {
        let planned = try plannedSet(try prescription(targetLoad: 100, repRange: 8...12))
        let completer = SetCompleter()
        let input = SetCompletionInput(weight: 100, unit: .kilograms, reps: 8)

        let once = try completer.recordSet(input: input, planned: planned, in: session())
        let twice = try completer.recordSet(input: input, planned: planned, in: once)

        let first = try #require(twice.sets.first)
        #expect(first.id == once.sets.first?.id)
        #expect(twice.sets.count == 2)
    }
}

extension ExerciseID {
    fileprivate static let test = ExerciseID(rawValue: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
}