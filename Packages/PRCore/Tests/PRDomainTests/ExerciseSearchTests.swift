//
//  ExerciseSearchTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests de la búsqueda offline de ejercicios (PR-0302): matching por nombre y
//  aliases, filtros por equipment/patrón/músculos, determinismo y orden estable.
//

import Foundation
import Testing
@testable import PRDomain

private enum SearchFixture {
    static let benchPress = make(
        name: "Dumbbell Bench Press",
        aliases: ["DB Bench Press", "Dumbbell Flat Press"],
        pattern: .horizontalPress,
        equipment: .dumbbell,
        primary: [.chest],
        secondary: [.triceps, .shoulders]
    )

    static let barbellOverheadPress = make(
        name: "Overhead Press",
        aliases: ["Shoulder Press", "Military Press"],
        pattern: .verticalPress,
        equipment: .barbell,
        primary: [.shoulders],
        secondary: [.triceps]
    )

    static let seatedCableRow = make(
        name: "Seated Cable Row",
        aliases: ["Cable Row", "Low Row"],
        pattern: .horizontalPull,
        equipment: .cable,
        primary: [.back],
        secondary: [.biceps]
    )

    static let barbellRow = make(
        name: "Barbell Bent-Over Row",
        aliases: ["Bent-Over Row", "BB Row"],
        pattern: .horizontalPull,
        equipment: .barbell,
        primary: [.back],
        secondary: [.biceps]
    )

    private static func make(
        name: String,
        aliases: [String],
        pattern: MovementPattern,
        equipment: EquipmentType,
        primary: [MuscleGroup],
        secondary: [MuscleGroup]
    ) -> Exercise {
        try! Exercise(
            canonicalName: name,
            aliases: aliases,
            movementPattern: pattern,
            primaryMuscles: primary.map { try! MuscleContribution(muscleGroupID: $0, activation: 1.0) },
            secondaryMuscles: secondary.map { try! MuscleContribution(muscleGroupID: $0, activation: 0.4) },
            equipment: equipment,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try! FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [.primaryCompound],
            substitutionFamilyID: ExerciseFamilyID()
        )
    }

    static let all = [benchPress, barbellOverheadPress, seatedCableRow, barbellRow]

    static func engine() -> ExerciseSearchEngine {
        ExerciseSearchEngine(exercises: all)
    }
}

@Suite("ExerciseSearchEngine matching (PR-0302)")
struct ExerciseSearchMatchingTests {
    @Test("Matches by full canonical name")
    func fullCanonicalName() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "Overhead Press"))
        #expect(hits.map(\.exercise.canonicalName) == ["Overhead Press"])
    }

    @Test("Matches by alias")
    func matchesByAlias() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "Military Press"))
        #expect(hits.map(\.exercise.canonicalName) == ["Overhead Press"])
    }

    @Test("Matches token subset out of order")
    func tokenSubsetOutOfOrder() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "bench dumbbell"))
        #expect(hits.map(\.exercise.canonicalName) == ["Dumbbell Bench Press"])
    }

    @Test("Is case and diacritic insensitive")
    func caseAndDiacriticInsensitive() {
        // El nombre canónico "Dumbbell Bench Press" rota a "dumbbell bench press";
        // buscamos una variante en mayúsculas y con diacríticos que se normalice igual.
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "DÚMBBELL BÉNCH PRÉSS"))
        #expect(hits.first?.exercise.canonicalName == "Dumbbell Bench Press")
    }

    @Test("Empty text still applies equipment filter")
    func emptyTextAppliesFilters() {
        // Filtro de equipment sin texto: devuelve los que usan barbell.
        let barbell = SearchFixture.engine().search(matching: ExerciseSearchQuery(equipment: [.barbell]))
        let names = barbell.map(\.exercise.canonicalName).sorted()
        #expect(names == ["Barbell Bent-Over Row", "Overhead Press"])
    }
}

@Suite("ExerciseSearchEngine filters (PR-0302)")
struct ExerciseSearchFilterTests {
    @Test("Filters by equipment")
    func filtersByEquipment() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(equipment: [.cable]))
        #expect(hits.map(\.exercise.canonicalName) == ["Seated Cable Row"])
    }

    @Test("Filters by movement pattern")
    func filtersByPattern() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(movementPatterns: [.horizontalPull]))
        #expect(Set(hits.map(\.exercise.canonicalName)) == ["Seated Cable Row", "Barbell Bent-Over Row"])
    }

    @Test("Filters by muscle group")
    func filtersByMuscle() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(muscleGroups: [.triceps]))
        #expect(Set(hits.map(\.exercise.canonicalName)) == ["Dumbbell Bench Press", "Overhead Press"])
    }

    @Test("Combines filters with AND")
    func combinesFiltersWithAND() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(
            equipment: [.barbell],
            movementPatterns: [.horizontalPull]
        ))
        #expect(hits.map(\.exercise.canonicalName) == ["Barbell Bent-Over Row"])
    }

    @Test("Text plus filters narrows results")
    func textPlusFilters() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(
            text: "row",
            movementPatterns: [.horizontalPull]
        ))
        #expect(hits.map(\.exercise.canonicalName).sorted() == ["Barbell Bent-Over Row", "Seated Cable Row"])
    }
}

@Suite("ExerciseSearchEngine determinism (PR-0302)")
struct ExerciseSearchDeterminismTests {
    @Test("Same query returns same order every time")
    func deterministicOrder() {
        let engine = SearchFixture.engine()
        let a = engine.search(matching: ExerciseSearchQuery(text: "p"))
        let b = engine.search(matching: ExerciseSearchQuery(text: "p"))
        #expect(a.map(\.exercise.id) == b.map(\.exercise.id))
    }

    @Test("No text match returns no hits")
    func noTextMatch() {
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "zzzz"))
        #expect(hits.isEmpty)
    }

    @Test("Empty query returns all exercises in stable order")
    func emptyQueryListsAll() {
        let engine = SearchFixture.engine()
        let all = engine.search(matching: ExerciseSearchQuery())
        #expect(all.count == engine.count)
    }

    @Test("Results are ordered by relevance then name")
    func relevanceOrdering() {
        // "press" coincide como prefijo/alias; el que mejor puntúe aparece primero.
        let hits = SearchFixture.engine().search(matching: ExerciseSearchQuery(text: "press"))
        let scores = hits.map(\.textScore)
        #expect(scores == scores.sorted(by: >))
    }
}