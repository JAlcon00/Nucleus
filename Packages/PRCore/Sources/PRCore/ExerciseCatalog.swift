//
//  ExerciseCatalog.swift
//  PRCore
//
//  Created by PR.
//
//  Catálogo inicial de ejercicios (PR-0301). Importa el dataset público
//  "free-exercise-db" (Unlicense) y lo mapea a la ontología `Exercise` de
//  PRDomain. Las reglas de mapeo son heurísticas deterministas centralizadas
//  aquí (no dispersas), versionadas y documentadas en ADR-0002.
//
//  Invariantes:
//  - IDs deterministas (slug → UUID estable): re-importar es idempotente.
//  - Mismas entradas → mismo catálogo (reglas sin azar ni estado).
//  - El mapeo no depende de nombres en runtime; sólo ocurre en el seed.
//

import CryptoKit
import Foundation
import PRDomain

// MARK: - Seed ID (determinista)

/// Deriva un UUID estable a partir de un slug, con namespace por tipo.
/// Permite que el import sea idempotente: el mismo slug siempre produce el
/// mismo `ExerciseID`/`ExerciseFamilyID`, sin estado de import previo.
enum SeedID {
    /// Devuelve un UUID determinista: SHA-256(namespace + slug) → 16 bytes.
    static func uuid(namespace: String, slug: String) -> UUID {
        var preimage = Data("PR::\(namespace)::".utf8)
        preimage.append(Data(slug.utf8))
        let digest = SHA256.hash(data: preimage)
        var bytes = [UInt8](digest.prefix(16))
        // Fijar bits de versión 5 y variante RFC-4122 para ser un UUID válido.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

// MARK: - DTO del dataset

/// Entrada cruda del JSON `free-exercise-db` (sólo los campos usados).
/// `equipment`, `mechanic` y `force` pueden venir `null` en el dataset.
struct FreeExerciseDBEntry: Decodable, Sendable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let category: String?
}

// MARK: - Origen/versión del dataset

/// Metadata del dataset importado (se incluye en el catálogo versionado).
public struct ExerciseCatalogSource: Sendable, Equatable {
    public let name: String
    public let version: String
    public let url: String
    public let license: String

    public init(name: String, version: String, url: String, license: String) {
        self.name = name
        self.version = version
        self.url = url
        self.license = license
    }
}

// MARK: - Catálogo

/// Catálogo de ejercicios versionado, listo para consumir por el engine.
public struct ExerciseCatalog: Sendable {
    public let source: ExerciseCatalogSource
    public let families: [ExerciseFamily]
    public let exercises: [Exercise]

    public init(source: ExerciseCatalogSource, families: [ExerciseFamily], exercises: [Exercise]) {
        self.source = source
        self.families = families
        self.exercises = exercises
    }

    /// Ejercicios del catálogo que corresponden a un patrón de movimiento.
    public func exercises(in pattern: MovementPattern) -> [Exercise] {
        exercises.filter { $0.movementPattern == pattern }
    }
}

// MARK: - Errores

public enum ExerciseCatalogError: Error, Sendable, Equatable {
    case bundledResourceMissing
    case undecodableDataset(underlying: String)
}

// MARK: - Seeder idempotente

/// Resultado de un import de catálogo a un repositorio.
public struct ExerciseSeedResult: Sendable, Equatable {
    /// Cantidad de ejercicios ya presentes (salteados).
    public let skipped: Int
    /// Cantidad de ejercicios nuevos persistidos en este import.
    public let inserted: Int

    public init(skipped: Int, inserted: Int) {
        self.skipped = skipped
        self.inserted = inserted
    }
}

/// Importa el catálogo a un `ExerciseRepository` de forma idempotente.
/// Re-ejecutar el seed en el mismo repositorio no duplica entradas: los IDs
/// son deterministas y los ejercicios ya presentes se saltean.
public final class ExerciseCatalogSeeder: Sendable {
    public init() {}

    /// Importa la versión bundleada del catálogo, respetando el criterio de
    /// aceptación PR-0301 "import/seed idempotente".
    public func seed(
        catalogLoader: (() throws -> ExerciseCatalog)? = nil,
        into repository: any ExerciseRepository
    ) async throws -> ExerciseSeedResult {
        let catalog = try (catalogLoader ?? { try ExerciseCatalogLoader.loadBundled() })()
        var skipped = 0
        var inserted = 0
        for exercise in catalog.exercises {
            if try await repository.exercise(id: exercise.id) != nil {
                skipped += 1
            } else {
                try await repository.save(exercise)
                inserted += 1
            }
        }
        return ExerciseSeedResult(skipped: skipped, inserted: inserted)
    }
}

// MARK: - Inflector de campos derivados

/// Reglas deterministas que infieren campos `Exercise` ausentes en el dataset.
/// Cada constante/regla está centralizada y documentada en ADR-0002.
enum ExerciseInflector {
    // Activación normalizada por rol muscular (0...1).
    static let primaryActivation = 1.0
    static let secondaryActivation = 0.4
    // Fracción de la contribución que se traduce a fatiga local por grupo.
    static let localFatigueRatio = 0.5
    // Costo sistémico de fatiga según clase articular.
    static let multiJointFatigue = 0.5
    static let singleJointFatigue = 0.25
    // Umbral de grupos primarios para considerar multiarticular.
    static let multiJointMuscleThreshold = 2

    private static let muscleGroupMap: [String: MuscleGroup] = [
        "abdominals": .core,
        "abductors": .glutes,
        "adductors": .quadriceps,
        "biceps": .biceps,
        "calves": .calves,
        "chest": .chest,
        "forearms": .forearms,
        "glutes": .glutes,
        "hamstrings": .hamstrings,
        "lats": .back,
        "lower back": .spinalErectors,
        "middle back": .back,
        "neck": .spinalErectors,
        "quadriceps": .quadriceps,
        "shoulders": .shoulders,
        "traps": .back,
        "triceps": .triceps,
    ]

    private static let equipmentMap: [String: EquipmentType] = [
        "barbell": .barbell,
        "dumbbell": .dumbbell,
        "cable": .cable,
        "machine": .machine,
        "body only": .bodyweight,
        "bands": .bands,
        "kettlebells": .kettlebell,
        "e-z curl bar": .barbell,
        "other": .other,
        "medicine ball": .other,
        "exercise ball": .other,
    ]

    // MARK: Patrón de movimiento

    /// Inferencia del `MovementPattern` a partir del nombre y músculos.
    /// Reglas en orden de prioridad (primera que haga match gana), con
    /// fallback por grupo muscular primario.
    static func pattern(name: String, primaryMuscles: [String]) -> MovementPattern {
        let n = name.lowercased()

        if containsAny(n, "calf raise", "calf press", "standing calf", "seated calf", "donkey calf") {
            return .calfPlantarFlexion
        }
        if containsAny(n, "wrist curl", "forearm") {
            return .elbowFlexion
        }
        if containsAny(n, "wrist extension", "reverse curl") {
            return .elbowExtension
        }
        if containsAny(n, "leg extension", "knee extension") {
            return .kneeExtension
        }
        if containsAny(n, "leg curl", "knee flexion", "hamstring curl", "nordic") {
            return .kneeFlexion
        }
        if containsAny(n, "hip abduction", "hip adduction", "cable hip", "hip abductor") {
            return .hipExtension
        }
        if containsAny(n, "russian twist", "wood chop", "woodchop", "side bend", "torso twist", "trunk twist", "rotation", "rotational", "judo flip") {
            return .trunkRotation
        }
        if containsAny(n, "external rotation", "internal rotation") {
            return .shoulderExtension
        }
        if containsAny(n, "reverse fly", "rear delt", "rear deltoid", "face pull", "low-pulley side", "y raise") {
            return .shoulderExtension
        }
        if containsAny(n, "lateral raise", "side raise", "scaption", "front raise", "shoulder raise", "deltoid raise", "upright row", "shrug") {
            return .shoulderAbduction
        }
        if containsAny(n, "bench press", "floor press", "push-up", "pushup", "chest press", "machine press", "fly", "flyes", "dip", "dips", "crossover", "cable cross", "butterfly", "body-up", "close-grip") {
            return .horizontalPress
        }
        if containsAny(n, "overhead press", "shoulder press", "military press", "arnold press", "standing press", "strict press", "push press", "jerk", "handstand", "dumbbell press") {
            return .verticalPress
        }
        if containsAny(n, "pull-up", "pullup", "chin-up", "chinups", "lat pulldown", "pulldown", "pull down", "snatch", "high pull") {
            return .verticalPull
        }
        if containsAny(n, "row", "bent-over", "pendlay", "seated row", "cable row", "inverted row", "pullover", "t-bar") {
            return .horizontalPull
        }
        if containsAny(n, "squat", "leg press", "hack squat", "sissy squat", "goblet squat", "front squat", "zercher", "split squat") {
            return .squat
        }
        if containsAny(n, "lunge", "step-up", "step up", "stepup", "bulgarian") {
            return .lunge
        }
        if containsAny(n, "deadlift", "dead lift", "romanian", "rdl", "good morning", "hip thrust", "glute bridge", "pull-through", "swing", "swings", "clean", "snatch", "jefferson", "pull to") {
            return .hinge
        }
        if containsAny(n, "crunch", "sit-up", "sit up", "ab rollout", "ab roll", "v-up", "jackknife", "hanging leg", "knee raise", "flutter", "scissor", "cocoon", "toes to", "elbow to knee", "heel toucher", "bicycle", "plank", "hollow", "bird dog", "dead bug", "side plank", "wall sit") {
            return .trunkFlexion
        }
        if containsAny(n, "back extension", "hyperextension", "superman", "rev hyperextension") {
            return .trunkExtension
        }
        if containsAny(n, "farmer", "walk", "yoke", "suitcase", "waiter") {
            return .carry
        }
        if containsAny(n, "windmill", "stretch", "yoga", "balance", "mobility", "rom", "neck", "band pull apart") {
            return .mobility
        }
        if containsAny(n, "air bike", "bike", "battling", "rope", "jump", "sprint", "run", "burpee", "slam", "medicine ball") {
            return .conditioning
        }
        if containsAny(n, "curl", "preacher", "concentration", "21s", "ez-bar curl", "hammer") {
            return .elbowFlexion
        }
        if containsAny(n, "triceps", "skullcrusher", "skull crusher", "pushdown", "kickback", "overhead extension", "chair dip", "bench dip", "cable pushdown") {
            return .elbowExtension
        }

        // Fallback por músculo primario.
        switch primaryMuscles.first {
        case "chest": return .horizontalPress
        case "shoulders": return .verticalPress
        case "lats": return .verticalPull
        case "middle back": return .horizontalPull
        case "biceps": return .elbowFlexion
        case "triceps": return .elbowExtension
        case "abdominals": return .trunkFlexion
        case "quadriceps": return .squat
        case "hamstrings", "glutes": return .hinge
        case "calves": return .calfPlantarFlexion
        case "forearms": return .elbowFlexion
        case "abductors", "adductors": return .hipExtension
        case "traps": return .shoulderAbduction
        case "lower back": return .trunkExtension
        case "neck": return .mobility
        default: return .conditioning
        }
    }

    /// Ángulo del movimiento inferido por el nombre (sólo press/remo).
    static func angle(name: String, pattern: MovementPattern) -> MovementAngle? {
        let n = name.lowercased()
        switch pattern {
        case .horizontalPress, .verticalPress:
            if containsAny(n, "incline") { return .incline }
            if containsAny(n, "decline") { return .decline }
            if containsAny(n, "overhead") { return .overhead }
            if containsAny(n, "upright") { return .upright }
            return .flat
        default:
            return nil
        }
    }

    // MARK: Contribuciones musculares

    static func makeContributions(_ muscles: [String], activation: Double) throws -> [MuscleContribution] {
        try muscles.compactMap { name in
            guard let group = muscleGroupMap[name] else { return nil }
            return try MuscleContribution(muscleGroupID: group, activation: activation)
        }
    }

    static func makeLocalFatigue(
        contributions: [MuscleContribution],
        ratio: Double
    ) throws -> [MuscleGroup.ID: FatigueCost] {
        var result: [MuscleGroup.ID: FatigueCost] = [:]
        for contribution in contributions {
            let value = max(0, min(1, contribution.activation * ratio))
            result[contribution.muscleGroupID] = try FatigueCost(normalized: value)
        }
        return result
    }

    // MARK: Otros campos

    static func equipment(for raw: String?) -> EquipmentType {
        equipmentMap[raw ?? ""] ?? .other
    }

    static func parseLevel(_ raw: String?) -> DemandLevel {
        switch raw?.lowercased() {
        case "beginner": return .low
        case "intermediate": return .moderate
        case "expert": return .high
        default: return .moderate
        }
    }

    static func jointClass(for mechanic: String?, primaryCount: Int) -> JointClass {
        switch mechanic?.lowercased() {
        case "compound": return .multiJoint
        case "isolation": return .singleJoint
        default:
            return primaryCount >= multiJointMuscleThreshold ? .multiJoint : .singleJoint
        }
    }

    static func loadability(for equipment: EquipmentType) -> Loadability {
        switch equipment {
        case .machine, .cable, .plateLoaded, .smithMachine: return .fixedStack
        case .barbell, .dumbbell, .kettlebell, .sled: return .discreteIncrements
        case .bodyweight: return .bodyweight
        case .bands: return .resisted
        case .other: return .discreteIncrements
        }
    }

    static func defaultRoles(for pattern: MovementPattern, isCompound: Bool) -> Set<ExerciseRole> {
        switch pattern {
        case .mobility: return [.mobility]
        case .conditioning, .carry: return [.conditioning]
        case .posing: return [.posing]
        case .shoulderAbduction, .shoulderExtension, .elbowFlexion, .elbowExtension,
             .kneeExtension, .kneeFlexion, .hipExtension, .calfPlantarFlexion,
             .trunkRotation, .trunkFlexion, .trunkExtension:
            return isCompound ? [.secondaryCompound] : [.accessoryIsolation]
        default:
            return isCompound ? [.primaryCompound] : [.secondaryCompound]
        }
    }

    private static func containsAny(_ string: String, _ fragments: String...) -> Bool {
        fragments.contains { string.contains($0) }
    }
}

// MARK: - Cargador

/// Carga y mapea el catálogo desde el bundle o desde datos crudos.
public enum ExerciseCatalogLoader {
    /// Nombre del dataset versionado incrustado en el bundle.
    public static let bundledFileName = "exercises.json"

    /// Metadata de origen del dataset incrustado (Unlicense / public domain).
    public static let bundledSource = ExerciseCatalogSource(
        name: "free-exercise-db",
        version: "0.0.1+20260801",
        url: "https://github.com/yuhonas/free-exercise-db",
        license: "Unlicense (public domain)"
    )

    /// Carga el catálogo desde el bundle de PRCore.
    public static func loadBundled() throws -> ExerciseCatalog {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw ExerciseCatalogError.bundledResourceMissing
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Mapea datos crudos JSON del dataset a `ExerciseCatalog`.
    public static func load(from data: Data) throws -> ExerciseCatalog {
        let entries: [FreeExerciseDBEntry]
        do {
            entries = try JSONDecoder().decode([FreeExerciseDBEntry].self, from: data)
        } catch {
            throw ExerciseCatalogError.undecodableDataset(underlying: "\(error)")
        }

        // Familia única por patrón, con ID determinista derivado del patrón.
        let patternNames: [MovementPattern: String] = [
            .horizontalPress: "Horizontal Press",
            .verticalPress: "Vertical Press",
            .horizontalPull: "Horizontal Pull",
            .verticalPull: "Vertical Pull",
            .squat: "Squat",
            .hinge: "Hinge",
            .lunge: "Lunge",
            .kneeExtension: "Knee Extension",
            .kneeFlexion: "Knee Flexion",
            .hipExtension: "Hip Extension",
            .shoulderAbduction: "Shoulder Abduction",
            .shoulderExtension: "Shoulder Extension",
            .elbowFlexion: "Elbow Flexion",
            .elbowExtension: "Elbow Extension",
            .calfPlantarFlexion: "Calf Plantar Flexion",
            .trunkFlexion: "Trunk Flexion",
            .trunkExtension: "Trunk Extension",
            .trunkRotation: "Trunk Rotation",
            .carry: "Carry",
            .conditioning: "Conditioning",
            .mobility: "Mobility",
            .posing: "Posing",
        ]

        var familyByName: [String: ExerciseFamily] = [:]
        var exercises: [Exercise] = []

        for entry in entries {
            let pattern = ExerciseInflector.pattern(
                name: entry.name,
                primaryMuscles: entry.primaryMuscles
            )
            let familyID = ExerciseFamilyID(
                rawValue: SeedID.uuid(namespace: "family", slug: pattern.rawValue)
            )
            let familyName = patternNames[pattern] ?? pattern.rawValue
            let family: ExerciseFamily
            if let existing = familyByName[familyName] {
                family = existing
            } else {
                family = ExerciseFamily(
                    id: familyID,
                    name: familyName,
                    movementPatterns: [pattern]
                )
                familyByName[familyName] = family
            }

            let equipment = ExerciseInflector.equipment(for: entry.equipment)
            let isMultiJoint = ExerciseInflector.jointClass(
                for: entry.mechanic,
                primaryCount: entry.primaryMuscles.count
            ) == .multiJoint

            let primary = try ExerciseInflector.makeContributions(
                entry.primaryMuscles,
                activation: ExerciseInflector.primaryActivation
            )
            let secondary = try ExerciseInflector.makeContributions(
                entry.secondaryMuscles,
                activation: ExerciseInflector.secondaryActivation
            )

            let exercise = Exercise(
                id: ExerciseID(rawValue: SeedID.uuid(namespace: "exercise", slug: entry.id)),
                canonicalName: entry.name,
                aliases: [],
                movementPattern: pattern,
                movementAngle: ExerciseInflector.angle(name: entry.name, pattern: pattern),
                primaryMuscles: primary,
                secondaryMuscles: secondary,
                equipment: equipment,
                laterality: .bilateral,
                jointClass: ExerciseInflector.jointClass(
                    for: entry.mechanic,
                    primaryCount: entry.primaryMuscles.count
                ),
                stabilityDemand: ExerciseInflector.parseLevel(entry.level),
                skillDemand: ExerciseInflector.parseLevel(entry.level),
                systemicFatigueCost: try FatigueCost(normalized: isMultiJoint
                    ? ExerciseInflector.multiJointFatigue
                    : ExerciseInflector.singleJointFatigue),
                localFatigue: try ExerciseInflector.makeLocalFatigue(
                    contributions: primary + secondary,
                    ratio: ExerciseInflector.localFatigueRatio
                ),
                loadability: ExerciseInflector.loadability(for: equipment),
                defaultRoles: ExerciseInflector.defaultRoles(
                    for: pattern,
                    isCompound: isMultiJoint
                ),
                contraindicationTags: [],
                substitutionFamilyID: family.id
            )
            exercises.append(exercise)
        }

        return ExerciseCatalog(
            source: bundledSource,
            families: Array(familyByName.values),
            exercises: exercises
        )
    }
}