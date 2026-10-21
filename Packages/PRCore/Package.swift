// swift-tools-version: 6.0
//
// PRCore — local Swift Package con el dominio y el motor de entrenamiento de PR.
//
// Reglas del contrato (promptMaster.md):
// - El Domain NO depende de SwiftUI, HealthKit, SwiftData ni networking.
// - Strict Concurrency: todos los modelos adecuados son Sendable.
// - El determinismo del TrainingEngine es una invariante.
//

import PackageDescription

let package = Package(
    name: "PRCore",
    // Español es el idioma inicial (RNF-013); los strings de PRCore viven en
    // `Resources/Localizable.xcstrings`.
    defaultLocalization: "es",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PRCore", targets: ["PRCore"]),
        .library(name: "PRDomain", targets: ["PRDomain"]),
    ],
    targets: [
        // Módulo de dominio puro. Sin dependencias de Apple frameworks.
        .target(
            name: "PRDomain"
        ),
        // Agregador de alto nivel que la app importa.
        .target(
            name: "PRCore",
            dependencies: ["PRDomain"],
            resources: [
                // Ejercicios curados del catálogo inicial (PR-0301). Dataset
                // "free-exercise-db" (Unlicense); ver ADR-0002.
                .copy("Resources/exercises.json"),
                .copy("Resources/exercise-names-es.json"),
                // Strings de presentación localizables (PR-1004).
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        .testTarget(
            name: "PRDomainTests",
            dependencies: ["PRDomain"]
        ),
        // Tests de contratos de persistencia con fakes in-memory (PR-0201).
        .testTarget(
            name: "PRCoreTests",
            dependencies: ["PRCore"]
        ),
    ]
)
