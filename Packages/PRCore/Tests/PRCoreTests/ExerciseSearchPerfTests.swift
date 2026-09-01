//
//  ExerciseSearchPerfTests.swift
//  PRCoreTests
//
//  Created by PR.
//
//  Test de rendimiento de la búsqueda offline sobre el catálogo MVP real
//  (PR-0302): respuesta < 100 ms con los 678 ejercicios bundleados.
//

import Foundation
import Testing
@testable import PRCore
import PRDomain

@Suite("ExerciseSearch perf on bundled catalog (PR-0302)")
struct ExerciseSearchPerfTests {
    @Test("Text search stays under 100 ms on the 678-exercise catalog")
    func textSearchUnder100ms() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let engine = ExerciseSearchEngine(exercises: catalog.exercises)
        #expect(engine.count == 678)

        let queries = [
            ExerciseSearchQuery(text: "bench press"),
            ExerciseSearchQuery(text: "squat"),
            ExerciseSearchQuery(equipment: [.barbell], movementPatterns: [.hinge]),
            ExerciseSearchQuery(text: "dumbbell", muscleGroups: [.shoulders]),
        ]

        // Precalenta (index ya construido); sólo medimos las búsquedas.
        let start = ContinuousClock.now
        var totalHits = 0
        for query in queries {
            totalHits += engine.search(matching: query).count
        }
        let elapsed = start.duration(to: .now)

        #expect(totalHits > 0)
        #expect(elapsed <= .milliseconds(100), "search took \(elapsed)")
    }

    @Test("Filter query is deterministic on the real catalog")
    func deterministicOnRealCatalog() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let engine = ExerciseSearchEngine(exercises: catalog.exercises)
        let query = ExerciseSearchQuery(text: "press", equipment: [.barbell])
        let first = engine.search(matching: query).map(\.exercise.id)
        let second = engine.search(matching: query).map(\.exercise.id)
        #expect(first == second)
        #expect(!first.isEmpty)
    }
}