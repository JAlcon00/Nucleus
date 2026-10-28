//
//  CatalogClassificationTests.swift
//  PRCoreTests
//
//  SCRUM-37 (P0) con el catálogo real: una restricción nunca deja pasar un ejercicio que
//  carga su zona (con un criterio que no usa la clasificación que se prueba: el nombre del
//  dataset y el músculo principal); los 63 ejercicios de referencia tienen el patrón
//  esperado; todo el catálogo es válido y lo que no cuadra está en una lista con su razón;
//  la búsqueda sin conexión responde en menos de 100 ms.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

/// Nombre original del dataset (en inglés). El canónico es el español; el original queda
/// como alias.
private func english(_ exercise: Exercise) -> String {
    exercise.aliases.first ?? exercise.canonicalName
}

/// ¿El ejercicio carga la zona? Sigue la tabla zona → patrones de SCRUM-209
/// (`BodyRegionRestrictionRule`), pero mirando el nombre del dataset y el músculo principal,
/// no el patrón inferido:
/// - codo: curls, extensiones y fondos, o tríceps, bíceps o antebrazo como principal;
/// - hombro: press por encima de la cabeza y elevaciones;
/// - cuello: press por encima de la cabeza, cargadas y lo que nombra el cuello;
/// - muñeca: cargadas;
/// - lumbar: bisagra, extensión y rotación de tronco;
/// - cadera, rodilla y tobillo: zancadas (más extensión de rodilla y pantorrilla).
private func loads(_ exercise: Exercise, _ region: BodyRegion) -> Bool {
    let name = english(exercise).lowercased()
    let words = Set(name.split { !$0.isLetter }.map(String.init))
    func has(_ fragments: [String]) -> Bool { fragments.contains { name.contains($0) } }
    let primary = Set(exercise.primaryMuscles.map(\.muscleGroupID))
    let overhead = ["overhead press", "shoulder press", "military", "arnold", "push press", "jerk", "snatch", "handstand", "behind the neck", "behind neck", "behind-the-neck"]
    let carries = ["farmer", "yoke", "suitcase", "carry"]
    let lunges = ["lunge", "split squat", "step-up", "step up", "bulgarian"]
    switch region {
    case .elbow:
        let armWork = (name.contains("curl") && !has(["leg curl", "hamstring curl"]))
            || has(["triceps", "tricep", "skull", "pushdown"])
            || !words.isDisjoint(with: ["dip", "dips"])
            || (name.contains("kickback") && !primary.contains(.glutes))
        return armWork || !primary.isDisjoint(with: [.triceps, .biceps, .forearms])
    case .shoulder:
        return has(overhead + ["lateral raise", "front raise", "side lateral", "upright"])
            || (name.contains("raise") && primary.contains(.shoulders))
    case .neck:
        return has(overhead + carries) || words.contains("neck")
    case .wrist, .hand:
        return has(carries)
    case .lumbar:
        return has(["deadlift", "romanian", "good morning", "hyperextension", "back extension", "russian twist", "wood chop", "woodchop", "swing"])
    case .hip, .groin:
        return has(lunges)
    case .knee:
        return has(lunges + ["leg extension"])
    case .ankle, .foot:
        return has(lunges + ["calf raise", "calf press"])
    case .thoracic, .core:
        return false
    }
}

private func restrictions(_ region: BodyRegion) -> [TrainingRestriction] {
    BodyRegionRestrictionRule.restrictions(for: RestrictionsAnswer(zones: [region]), now: now)
}

@Suite("SCRUM-37 · Las restricciones se respetan con el catálogo real")
struct CatalogRestrictionTests {

    @Test("Ningún músculo recibe un ejercicio que carga la zona restringida, con cualquier variedad",
          arguments: BodyRegionRestrictionRule.selectableRegions)
    func assignerNeverLoadsTheZone(region: BodyRegion) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for muscle in MuscleGroup.allCases {
            for variety in VarietyPreference.allCases {
                // Sin ningún ejercicio permitido el músculo se queda fuera (y el plan lo explica).
                guard let result = try? ExerciseAssigner().assign(input: ExerciseAssignmentInput(
                    muscleGroupID: muscle, catalog: catalog.exercises, varietyPreference: variety,
                    restrictions: restrictions(region), equipmentKnownness: .unknown
                )) else { continue }
                for assigned in result.assignments {
                    let exercise = try #require(byID[assigned.exercise])
                    #expect(!loads(exercise, region), "\(region): \(muscle) recibe \(english(exercise))")
                }
            }
        }
    }

    @Test("El plan completo no programa nada que cargue la zona", arguments: BodyRegionRestrictionRule.selectableRegions)
    func planNeverLoadsTheZone(region: BodyRegion) throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for days in [3, 5] {
            var profile = OnboardingProfile(
                goal: .hypertrophy, phase: .maintenance, experience: .intermediate, trainingDaysPerWeek: days,
                usualSessionMinutes: 90, varietyPreference: .varied
            )
            profile.restrictions = restrictions(region)
            let result = try TodayPlanBuilder().generate(
                profile: profile, catalog: catalog, planner: TodayPlanBuilder.defaultPlanner(), blockID: TrainingBlockID()
            )
            for id in Set(result.block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) }) {
                let exercise = try #require(byID[id])
                #expect(!loads(exercise, region), "\(region), \(days) días: \(english(exercise))")
            }
        }
    }

    @Test("El caso que se encontró: con codo restringido, nada de tríceps ni bíceps con cuerda, fondos ni curls")
    func elbowRestrictionCase() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for muscle in [MuscleGroup.triceps, .biceps] {
            let result = try? ExerciseAssigner().assign(input: ExerciseAssignmentInput(
                muscleGroupID: muscle, catalog: catalog.exercises, varietyPreference: .balanced,
                restrictions: restrictions(.elbow), equipmentKnownness: .unknown
            ))
            let names = (result?.assignments ?? []).compactMap { byID[$0.exercise] }.map(english)
            for banned in ["Cable Rope Overhead Triceps Extension", "Triceps Pushdown - Rope Attachment", "Dips - Triceps Version", "Cable Hammer Curls - Rope Attachment"] {
                #expect(!names.contains(banned), "\(muscle): \(names)")
            }
        }
    }
}

/// Patrón esperado de cada ejercicio de referencia (`exercise-staples.json`), revisado uno
/// por uno el 2026-10-28.
private let staplePatterns: [String: MovementPattern] = [
    // Pecho
    "Barbell Bench Press - Medium Grip": .horizontalPress, "Incline Dumbbell Press": .horizontalPress,
    "Dumbbell Bench Press": .horizontalPress, "Cable Crossover": .horizontalPress,
    "Machine Bench Press": .horizontalPress, "Dumbbell Flyes": .horizontalPress, "Pushups": .horizontalPress,
    // Espalda
    "Bent Over Barbell Row": .horizontalPull, "Wide-Grip Lat Pulldown": .verticalPull,
    "Seated Cable Rows": .horizontalPull, "One-Arm Dumbbell Row": .horizontalPull,
    "Close-Grip Front Lat Pulldown": .verticalPull, "T-Bar Row with Handle": .horizontalPull,
    "Pullups": .verticalPull, "Straight-Arm Pulldown": .verticalPull,
    // Hombro
    "Dumbbell Shoulder Press": .verticalPress, "Side Lateral Raise": .shoulderAbduction,
    "Seated Barbell Military Press": .verticalPress, "Cable Seated Lateral Raise": .shoulderAbduction,
    "Face Pull": .shoulderExtension, "Cable Rear Delt Fly": .shoulderExtension,
    "Machine Shoulder (Military) Press": .verticalPress, "Arnold Dumbbell Press": .verticalPress,
    // Bíceps
    "Barbell Curl": .elbowFlexion, "Incline Dumbbell Curl": .elbowFlexion, "Hammer Curls": .elbowFlexion,
    "Preacher Curl": .elbowFlexion, "Standing Biceps Cable Curl": .elbowFlexion, "Concentration Curls": .elbowFlexion,
    // Tríceps
    "Triceps Pushdown": .elbowExtension, "EZ-Bar Skullcrusher": .elbowExtension,
    "Cable Rope Overhead Triceps Extension": .elbowExtension, "Dips - Triceps Version": .horizontalPress,
    "Standing Dumbbell Triceps Extension": .elbowExtension, "Triceps Pushdown - Rope Attachment": .elbowExtension,
    "Bench Dips": .horizontalPress,
    // Cuádriceps
    "Barbell Squat": .squat, "Leg Press": .squat, "Leg Extensions": .kneeExtension, "Dumbbell Lunges": .lunge,
    "Hack Squat": .squat, "Front Barbell Squat": .squat, "Split Squat with Dumbbells": .lunge,
    // Femoral
    "Romanian Deadlift": .hinge, "Seated Leg Curl": .kneeFlexion, "Lying Leg Curls": .kneeFlexion,
    "Stiff-Legged Dumbbell Deadlift": .hinge, "Good Morning": .hinge, "Standing Leg Curl": .kneeFlexion,
    // Glúteo
    "Barbell Hip Thrust": .hinge, "Barbell Glute Bridge": .hinge, "One-Legged Cable Kickback": .hipExtension,
    "Single Leg Glute Bridge": .hinge, "Glute Kickback": .hipExtension,
    // Pantorrilla
    "Standing Calf Raises": .calfPlantarFlexion, "Seated Calf Raise": .calfPlantarFlexion,
    "Standing Dumbbell Calf Raise": .calfPlantarFlexion, "Calf Press": .calfPlantarFlexion,
    // Core
    "Cable Crunch": .trunkFlexion, "Hanging Leg Raise": .trunkFlexion, "Plank": .trunkFlexion,
    "Crunches": .trunkFlexion, "Barbell Ab Rollout - On Knees": .trunkFlexion,
]

@Suite("SCRUM-37 · Los 63 ejercicios de referencia")
struct StapleClassificationTests {

    @Test("Cada staple tiene el patrón esperado y su músculo como principal")
    func staplesAreClassified() throws {
        let staples = try ExerciseCatalogLoader.loadBundled().exercises.filter { $0.staple != nil }
        #expect(staples.count == 63)
        #expect(Set(staples.map(english)) == Set(staplePatterns.keys))
        for exercise in staples {
            let name = english(exercise)
            #expect(exercise.movementPattern == staplePatterns[name], "\(name): \(exercise.movementPattern)")
            let muscle = try #require(exercise.staple?.muscle)
            #expect(exercise.primaryMuscles.first?.muscleGroupID == muscle, "\(name) no tiene \(muscle) como principal")
        }
    }
}

/// Ejercicios cuyo patrón no es el típico de su músculo principal, con la razón. Si aparece
/// uno nuevo, se revisa y se agrega aquí o se corrige la regla.
private let patternExceptions: [String: String] = Dictionary(uniqueKeysWithValues: [
    // Levantamiento olímpico y de fuerza: el dataset marca cuádriceps u hombro, pero el gesto
    // es bisagra (cargadas, arrancadas, peso muerto) o envión (press vertical).
    ("Cable Deadlifts", "peso muerto"), ("Car Deadlift", "peso muerto"), ("Leverage Deadlift", "peso muerto"),
    ("One-Arm Side Deadlift", "peso muerto"), ("Rickshaw Deadlift", "peso muerto"), ("Trap Bar Deadlift", "peso muerto"),
    ("Clean from Blocks", "cargada"), ("Clean Pull", "cargada"), ("Hang Clean", "cargada"),
    ("Hang Clean - Below the Knees", "cargada"), ("Split Clean", "cargada"), ("Two-Arm Kettlebell Clean", "cargada"),
    ("Bottoms-Up Clean From The Hang Position", "cargada"), ("Clean and Press", "cargada y press"),
    ("Snatch", "arrancada"), ("Snatch Balance", "arrancada"), ("Snatch from Blocks", "arrancada"),
    ("Heaving Snatch Balance", "arrancada"), ("Power Snatch from Blocks", "arrancada"),
    ("Double Kettlebell Snatch", "arrancada"), ("One-Arm Kettlebell Snatch", "arrancada"),
    ("One-Arm Kettlebell Split Snatch", "arrancada"),
    ("Jerk Dip Squat", "envión"), ("Power Jerk", "envión"), ("Split Jerk", "envión"), ("Squat Jerk", "envión"),
    ("Yoke Walk", "cargada caminando"), ("Sled Overhead Backward Walk", "cargada caminando"),
    // Aductores: el dataset los cuenta como cuádriceps; el gesto es de cadera.
    ("Band Hip Adductions", "aducción de cadera"), ("Cable Hip Adduction", "aducción de cadera"),
    ("Thigh Adductor", "aducción de cadera"),
    // Pullover: extensión de hombro con el pecho como principal en el dataset.
    ("Bent-Arm Dumbbell Pullover", "pullover"), ("Straight-Arm Dumbbell Pullover", "pullover"),
    ("Wide-Grip Decline Barbell Pullover", "pullover"), ("Front Raise And Pullover", "elevación y pullover"),
    // Movimientos combinados o de cuerpo completo.
    ("Kettlebell Turkish Get-Up (Lunge style)", "levantada turca"), ("Kettlebell Turkish Get-Up (Squat style)", "levantada turca"),
    ("Kettlebell Halo with Overhead Extension", "halo con extensión"), ("Lunge Pass Through", "zancada con pase"),
    ("Reverse Hyperextension", "extensión de tronco"), ("Flutter Kicks", "abdomen"),
    ("Cable Incline Pushdown", "jalón de dorsal con brazos rectos: el codo lo quita, más seguro"),
    ("Battling Ropes", "cardio"), ("Rope Climb", "cardio"),
])

/// Ejercicios de fuerza que se quedan como cardio o movilidad, con la razón.
private let nonStrengthExceptions: [String: String] = [
    "Balance Board": "equilibrio", "Downward Facing Balance": "yoga", "Band Pull Apart": "calentamiento con banda",
    "Battling Ropes": "cardio", "Rope Climb": "cardio",
]

@Suite("SCRUM-37 · Catálogo completo")
struct CatalogValidityTests {

    /// Patrones típicos de cada músculo principal.
    private static let typicalPatterns: [MuscleGroup: Set<MovementPattern>] = [
        .triceps: [.elbowExtension, .horizontalPress, .verticalPress],
        .biceps: [.elbowFlexion, .horizontalPull, .verticalPull],
        .forearms: [.elbowFlexion, .elbowExtension, .carry],
        .quadriceps: [.squat, .lunge, .kneeExtension, .conditioning, .mobility],
        .hamstrings: [.hinge, .kneeFlexion, .mobility, .conditioning],
        .glutes: [.hinge, .hipExtension, .squat, .lunge, .mobility],
        .calves: [.calfPlantarFlexion, .mobility, .conditioning],
        .chest: [.horizontalPress, .mobility],
        .back: [.horizontalPull, .verticalPull, .shoulderAbduction, .shoulderExtension, .mobility, .hinge],
        .shoulders: [.verticalPress, .shoulderAbduction, .shoulderExtension, .horizontalPress, .mobility],
        .core: [.trunkFlexion, .trunkRotation, .trunkExtension, .mobility, .conditioning],
        .spinalErectors: [.trunkExtension, .hinge, .mobility],
    ]

    @Test("Todo ejercicio tiene patrón, músculo principal, rol y familia válidos, sin músculos repetidos")
    func everyExerciseIsValid() throws {
        let catalog = try ExerciseCatalogLoader.loadBundled()
        let families = Dictionary(catalog.families.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for exercise in catalog.exercises {
            let name = english(exercise)
            #expect(!exercise.primaryMuscles.isEmpty, "\(name) sin músculo principal")
            #expect(!exercise.defaultRoles.isEmpty, "\(name) sin rol")
            #expect(families[exercise.substitutionFamilyID]?.movementPatterns.contains(exercise.movementPattern) == true, "\(name) sin familia de su patrón")
            let muscles = (exercise.primaryMuscles + exercise.secondaryMuscles).map(\.muscleGroupID)
            #expect(Set(muscles).count == muscles.count, "\(name) repite músculos: \(muscles)")
            switch exercise.movementPattern {
            case .horizontalPress:
                #expect([.flat, .incline, .decline].contains(exercise.movementAngle), "\(name)")
            case .verticalPress:
                #expect(exercise.movementAngle == .overhead, "\(name)")
            default:
                #expect(exercise.movementAngle == nil, "\(name)")
            }
        }
    }

    @Test("Las aperturas son de una articulación y aislamiento")
    func fliesAreIsolation() throws {
        let flies = try ExerciseCatalogLoader.loadBundled().exercises.filter { exercise in
            let name = english(exercise).lowercased()
            return ["fly", "flye", "crossover", "butterfly"].contains { name.contains($0) }
        }
        #expect(flies.count >= 10)
        for exercise in flies {
            #expect(exercise.jointClass == .singleJoint, "\(english(exercise))")
            #expect(exercise.defaultRoles == [.accessoryIsolation], "\(english(exercise)): \(exercise.defaultRoles)")
        }
    }

    @Test("Lo que no cuadra con su músculo principal está en la lista con su razón")
    func mismatchesAreExplained() throws {
        let mismatched = try ExerciseCatalogLoader.loadBundled().exercises.filter { exercise in
            guard let primary = exercise.primaryMuscles.first?.muscleGroupID else { return false }
            return Self.typicalPatterns[primary]?.contains(exercise.movementPattern) == false
        }
        #expect(Set(mismatched.map(english)) == Set(patternExceptions.keys))
    }

    @Test("Ningún ejercicio de fuerza queda como cardio o movilidad, salvo los de la lista")
    func strengthIsNotCardio() throws {
        let strength: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps, .quadriceps, .hamstrings, .glutes, .calves]
        let nonStrength = try ExerciseCatalogLoader.loadBundled().exercises.filter { exercise in
            [.conditioning, .mobility].contains(exercise.movementPattern)
                && exercise.primaryMuscles.first.map { strength.contains($0.muscleGroupID) } == true
        }
        #expect(Set(nonStrength.map(english)) == Set(nonStrengthExceptions.keys))
    }

    @Test("La búsqueda sin conexión por nombre, equipo, patrón y músculo responde en menos de 100 ms")
    func searchIsFast() throws {
        let engine = ExerciseSearchEngine(exercises: try ExerciseCatalogLoader.loadBundled().exercises)
        let queries = [
            ExerciseSearchQuery(text: "press banca"),
            ExerciseSearchQuery(text: "curl", equipment: [.dumbbell]),
            ExerciseSearchQuery(movementPatterns: [.hinge]),
            ExerciseSearchQuery(text: "remo", muscleGroups: [.back]),
        ]
        let clock = ContinuousClock()
        for query in queries {
            var hits: [ExerciseSearchHit] = []
            let elapsed = clock.measure { hits = engine.search(matching: query) }
            #expect(!hits.isEmpty, "\(query)")
            #expect(elapsed < .milliseconds(100), "\(query): \(elapsed)")
        }
    }
}
