//
//  RoutineCharacterizationTests.swift
//  PRCoreTests
//
//  SCRUM-214 (PR-B001): test de caracterización del motor de rutinas con el catálogo real.
//  Mide cuántas rutinas distintas salen de una muestra determinista de 200 perfiles de la
//  matriz {días 2–7} × {variedad} × {objetivo} × {experiencia} × {fase} × {30, 45, 60, 90,
//  120 min}, y deja escrita la línea base (`[PR-B001]` en el log de `make ci`).
//  Las comprobaciones del gate de la Fase B que fallaban iban en `withKnownIssue`; cada
//  historia que las arregló quitó la suya. Desde SCRUM-219 (2026-10-28) no queda ninguna.
//  No cambia el motor ni exige más series con más minutos (eso es PR-B003, decisión D1).
//

import Foundation
import Testing
import PRCore
import PRDomain

/// Un perfil de la matriz.
private struct ProfileCase: Hashable, CustomStringConvertible {
    let days: Int
    let variety: VarietyPreference
    let goal: TrainingGoal
    let experience: ExperienceLevel
    let phase: BodyCompositionPhase
    let minutes: Int

    static let dayOptions = Array(2...7)
    static let minuteOptions = [30, 45, 60, 90, 120]
    static let total = dayOptions.count * VarietyPreference.allCases.count * TrainingGoal.allCases.count
        * ExperienceLevel.allCases.count * BodyCompositionPhase.allCases.count * minuteOptions.count

    /// El caso `index` de la matriz completa (base mixta, sin huecos ni repetidos).
    init(index: Int) {
        var rest = index
        func next<T>(_ options: [T]) -> T {
            defer { rest /= options.count }
            return options[rest % options.count]
        }
        days = next(Self.dayOptions)
        variety = next(VarietyPreference.allCases)
        goal = next(TrainingGoal.allCases)
        experience = next(ExperienceLevel.allCases)
        phase = next(BodyCompositionPhase.allCases)
        minutes = next(Self.minuteOptions)
    }

    init(days: Int, variety: VarietyPreference, goal: TrainingGoal, experience: ExperienceLevel, phase: BodyCompositionPhase, minutes: Int) {
        self.days = days
        self.variety = variety
        self.goal = goal
        self.experience = experience
        self.phase = phase
        self.minutes = minutes
    }

    func with(goal: TrainingGoal) -> ProfileCase {
        ProfileCase(days: days, variety: variety, goal: goal, experience: experience, phase: phase, minutes: minutes)
    }

    func with(experience: ExperienceLevel) -> ProfileCase {
        ProfileCase(days: days, variety: variety, goal: goal, experience: experience, phase: phase, minutes: minutes)
    }

    var profile: OnboardingProfile {
        OnboardingProfile(
            goal: goal, phase: phase, experience: experience, trainingDaysPerWeek: days,
            usualSessionMinutes: minutes, varietyPreference: variety
        )
    }

    var description: String {
        "\(days)d·\(variety.rawValue)·\(goal.rawValue)·\(experience.rawValue)·\(phase.rawValue)·\(minutes)min"
    }
}

/// SplitMix64: la muestra es siempre la misma.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Lo que importa de un bloque generado, sin IDs aleatorios.
private struct GeneratedRoutine {
    let exercises: Set<ExerciseID>
    /// Por sesión: título y, por ejercicio en orden, sus series de trabajo.
    let shape: [String]
    /// Series de trabajo de cada ejercicio en cada sesión.
    let workSetsPerExercise: [Int]
    let primaryMuscles: Set<MuscleGroup.ID>
    /// Título de cada sesión y cuántos ejercicios trae (SCRUM-218).
    let exercisesPerSession: [(title: String, count: Int)]
    /// Sesiones que la explicación marca sobre el tope de ejercicios.
    let sessionsOverRange: Set<String>
    /// Pantorrilla o core que la explicación dice que no cupieron en el tiempo (SCRUM-215).
    let maintenanceLeftOut: Set<MuscleGroup.ID>
}

private let blockID = TrainingBlockID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000214") ?? UUID())

private struct Engine {
    let catalog: ExerciseCatalog
    let builder = TodayPlanBuilder()
    let planner = TodayPlanBuilder.defaultPlanner()
    let byID: [ExerciseID: Exercise]

    init() throws {
        catalog = try ExerciseCatalogLoader.loadBundled()
        byID = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func routine(_ profileCase: ProfileCase) throws -> GeneratedRoutine {
        let result = try builder.generate(profile: profileCase.profile, catalog: catalog, planner: planner, blockID: blockID)
        let block = result.block
        let overRange = result.explanation.facts.first { $0.key == "sessionsOverRange" }?.value ?? ""
        let leftOut = result.explanation.facts.first { $0.key == "maintenanceLeftOut" }?.value ?? ""
        var shape: [String] = []
        var workSets: [Int] = []
        var perSession: [(title: String, count: Int)] = []
        for session in block.sessions {
            perSession.append((session.title, Set(session.plannedSets.map(\.exerciseID)).count))
            var order: [ExerciseID] = []
            var counts: [ExerciseID: Int] = [:]
            for set in session.plannedSets {
                if counts[set.exerciseID] == nil { order.append(set.exerciseID) }
                counts[set.exerciseID, default: 0] += set.prescription.isWarmup ? 0 : 1
            }
            shape.append(session.title + ":" + order.map { "\($0.rawValue)x\(counts[$0] ?? 0)" }.joined(separator: ","))
            workSets += order.map { counts[$0] ?? 0 }
        }
        let exercises = Set(block.sessions.flatMap { $0.plannedSets.map(\.exerciseID) })
        let primary = Set(exercises.compactMap { byID[$0] }.flatMap { $0.primaryMuscles.map(\.muscleGroupID) })
        return GeneratedRoutine(
            exercises: exercises, shape: shape, workSetsPerExercise: workSets, primaryMuscles: primary,
            exercisesPerSession: perSession,
            sessionsOverRange: Set(overRange.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }),
            maintenanceLeftOut: Set(leftOut.split(separator: ",").compactMap { MuscleGroup(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
        )
    }
}

/// 200 casos de la matriz, siempre los mismos.
private func sample(_ count: Int, seed: UInt64) -> [ProfileCase] {
    var rng = SeededGenerator(seed: seed)
    return Array(0..<ProfileCase.total).shuffled(using: &rng).prefix(count).map(ProfileCase.init(index:))
}

private func percent(_ part: Int, _ whole: Int) -> Int {
    whole == 0 ? 0 : (part * 100) / whole
}

@Suite("Caracterización del motor de rutinas (SCRUM-214 · PR-B001)")
struct RoutineCharacterizationTests {

    @Test("Composición de sesión por duración y días (línea base de PR-B004)")
    func sessionCompositionBaseline() throws {
        let engine = try Engine()
        let estimator = DurationEstimator()
        for goal in [TrainingGoal.hypertrophy, .strength] {
            for minutes in ProfileCase.minuteOptions {
                for days in ProfileCase.dayOptions {
                    let profileCase = ProfileCase(days: days, variety: .balanced, goal: goal, experience: .intermediate, phase: .maintenance, minutes: minutes)
                    let block = try engine.builder.generate(profile: profileCase.profile, catalog: engine.catalog, planner: engine.planner, blockID: blockID).block
                    var rows: [String] = []
                    for session in block.sessions {
                        var counts: [ExerciseID: Int] = [:]
                        for set in session.plannedSets where !set.prescription.isWarmup { counts[set.exerciseID, default: 0] += 1 }
                        let minSets = counts.values.min() ?? 0
                        let estimated = estimator.estimate(plannedSets: session.plannedSets) / 60
                        rows.append("\(counts.count)ej·min\(minSets)s·\(estimated)′")
                    }
                    print("[PR-B004] \(goal.rawValue) \(minutes)min \(days)d: \(rows.joined(separator: " | "))")
                }
            }
        }
    }

    @Test("Mismo perfil y mismo bloque ⇒ la misma rutina (variación intencional, nunca aleatoria)")
    func deterministic() throws {
        let engine = try Engine()
        for profileCase in sample(10, seed: 214) {
            #expect(try engine.routine(profileCase).shape == engine.routine(profileCase).shape, "\(profileCase)")
        }
    }

    @Test("Línea base y gate de la Fase B sobre 200 perfiles de la matriz")
    func baselineAndPhaseBGate() throws {
        let engine = try Engine()
        let cases = sample(200, seed: 214)
        var routines: [ProfileCase: GeneratedRoutine] = [:]
        for profileCase in cases { routines[profileCase] = try engine.routine(profileCase) }

        // Línea base: cuántas rutinas distintas salen, en total y por número de días.
        let all = cases.compactMap { routines[$0] }
        let exerciseSets = Set(all.map(\.exercises))
        let shapes = Set(all.map(\.shape))
        let byDays = Dictionary(grouping: cases, by: \.days).mapValues { group in
            (profiles: group.count, sets: Set(group.compactMap { routines[$0]?.exercises }).count)
        }
        print("[PR-B001] \(cases.count) perfiles ⇒ \(exerciseSets.count) conjuntos de ejercicios distintos, \(shapes.count) rutinas distintas (ejercicios, orden y series)")
        for days in ProfileCase.dayOptions {
            let row = byDays[days]
            print("[PR-B001]   \(days) días: \(row?.profiles ?? 0) perfiles ⇒ \(row?.sets ?? 0) conjuntos")
        }
        for variety in VarietyPreference.allCases {
            let group = cases.filter { $0.variety == variety }
            let sets = Set(group.compactMap { routines[$0]?.exercises }).count
            print("[PR-B001]   variedad \(variety.rawValue): \(group.count) perfiles ⇒ \(sets) conjuntos")
        }
        #expect(exerciseSets.count >= 1)

        // Gate 1: el objetivo y la experiencia cambian qué ejercicios salen.
        let bases = sample(40, seed: 2140)
        var goalDiffers = 0, experienceDiffers = 0
        for base in bases {
            let strength = try engine.routine(base.with(goal: .strength)).exercises
            let hypertrophy = try engine.routine(base.with(goal: .hypertrophy)).exercises
            if strength != hypertrophy { goalDiffers += 1 }
            let novice = try engine.routine(base.with(experience: .novice)).exercises
            let advanced = try engine.routine(base.with(experience: .advanced)).exercises
            if novice != advanced { experienceDiffers += 1 }
        }
        print("[PR-B001] pares fuerza/hipertrofia con ejercicios distintos: \(goalDiffers)/\(bases.count) (\(percent(goalDiffers, bases.count)) %)")
        print("[PR-B001] pares novato/avanzado con ejercicios distintos: \(experienceDiffers)/\(bases.count) (\(percent(experienceDiffers, bases.count)) %)")
        // SCRUM-219 (PR-B005): las anclas salen por objetivo y experiencia.
        #expect(percent(goalDiffers, bases.count) >= 80, "Fuerza vs hipertrofia")
        #expect(percent(experienceDiffers, bases.count) >= 80, "Novato vs avanzado")

        // Gate 2: ningún ejercicio con menos de 2 series de trabajo (SCRUM-218).
        let occurrences = all.flatMap(\.workSetsPerExercise)
        let single = occurrences.filter { $0 < 2 }.count
        print("[PR-B001] ejercicios con menos de 2 series de trabajo: \(single) de \(occurrences.count) (\(percent(single, occurrences.count)) %)")
        #expect(single == 0)

        // Gate 4: rango de ejercicios por duración (SCRUM-218). El tope se cumple salvo en
        // las sesiones que la explicación marca (lo protegido no se quita, decisión 3); el
        // mínimo sólo si el volumen alcanza, así que aquí sólo se informa.
        let rule = SessionCompositionRule.standard
        var sessions = 0, overCap = 0, flagged = 0, underFloor = 0
        for profileCase in cases {
            guard let routine = routines[profileCase] else { continue }
            let range = rule.exerciseRange(forMinutes: profileCase.minutes)
            for (title, count) in routine.exercisesPerSession {
                sessions += 1
                if count > range.upperBound {
                    if routine.sessionsOverRange.contains(title) { flagged += 1 } else { overCap += 1 }
                }
                if count < range.lowerBound { underFloor += 1 }
            }
        }
        print("[PR-B004] \(sessions) sesiones: \(flagged) sobre el tope con aviso (lo protegido no se quita), \(underFloor) bajo el mínimo porque el volumen no alcanza")
        #expect(overCap == 0, "Sesiones sobre el tope sin aviso")

        // Gate 3: pantorrilla y core en el plan (SCRUM-215). Decisión de Jesús (2026-10-27):
        // gana el tiempo. Entran en mantenimiento y, si no caben en la semana con los minutos
        // del perfil, la explicación lo dice. Ningún plan los deja fuera sin decirlo.
        let withCalves = all.filter { $0.primaryMuscles.contains(.calves) }.count
        let withCore = all.filter { $0.primaryMuscles.contains(.core) }.count
        print("[PR-B001] planes con pantorrilla: \(withCalves)/\(all.count); con core: \(withCore)/\(all.count)")
        let unexplained = all.filter { routine in
            [MuscleGroup.calves, .core].contains { !routine.primaryMuscles.contains($0) && !routine.maintenanceLeftOut.contains($0) }
        }.count
        #expect(unexplained == 0, "Planes sin pantorrilla o core que no lo dicen")
    }
}
