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
    // Costo sistémico de fatiga según clase articular; el patrón y el equipo lo ajustan
    // (`systemicFatigue`, SCRUM-219).
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
    /// fallback por grupo muscular primario. El orden importa (SCRUM-37): lo aislado y
    /// específico va antes que lo genérico, para que "close-grip … curl" sea curl y no
    /// press, "split squat" sea zancada y no sentadilla, y "row" sólo cuente como palabra
    /// ("narrow" no es remo). "Rope" no vuelve cardio a un ejercicio con cuerda de polea.
    static func pattern(name: String, primaryMuscles: [String]) -> MovementPattern {
        let n = name.lowercased()
        let words = Set(n.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let primary = primaryMuscles.first

        // Pantorrilla.
        if containsAny(n, "calf raise", "calf press", "standing calf", "seated calf", "donkey calf") {
            return .calfPlantarFlexion
        }
        // Antebrazo y muñeca: trabajo de codo (la restricción de codo los quita).
        if containsAny(n, "wrist curl", "wrist rotation", "forearm", "reverse curl") {
            return .elbowFlexion
        }
        if containsAny(n, "wrist extension") {
            return .elbowExtension
        }
        // Rodilla aislada.
        if containsAny(n, "leg extension", "knee extension") {
            return .kneeExtension
        }
        if containsAny(n, "leg curl", "knee flexion", "hamstring curl", "nordic") {
            return .kneeFlexion
        }
        // Cadera aislada: abducción, aducción y patadas de glúteo.
        if containsAny(n, "hip abduction", "hip adduction", "cable hip", "hip abductor", "thigh adductor", "thigh abductor", "monster walk") {
            return .hipExtension
        }
        if n.contains("kickback"), primary == "glutes" || primary == "hamstrings" {
            return .hipExtension
        }
        // Hombro: rotadores y deltoide posterior (antes que la rotación de tronco y los remos).
        if containsAny(n, "external rotation", "internal rotation") {
            return .shoulderExtension
        }
        if containsAny(n, "reverse fly", "reverse flye", "back fly", "back flye", "rear delt", "rear-delt", "rear deltoid", "face pull", "low-pulley side", "y raise")
            || (containsAny(n, "fly", "flye") && primary == "shoulders") {
            return .shoulderExtension
        }
        // Elevaciones y remo al mentón o al cuello: abducción (lo quita la restricción de hombro).
        if containsAny(n, "lateral raise", "side raise", "side lateral", "scaption", "front raise", "shoulder raise", "deltoid raise", "upright", "row to neck", "shrug")
            || (!words.isDisjoint(with: ["raise", "raises"]) && primary == "shoulders") {
            return .shoulderAbduction
        }
        if containsAny(n, "russian twist", "wood chop", "woodchop", "side bend", "torso twist", "trunk twist", "rotation", "rotational", "judo flip") {
            return .trunkRotation
        }
        // Brazos aislados antes que press, remos y jalones.
        if containsAny(n, "curl", "preacher", "concentration", "21s") {
            return .elbowFlexion
        }
        if words.contains("dip") || words.contains("dips") {
            return n.contains("jerk") ? .verticalPress : .horizontalPress
        }
        if containsAny(n, "triceps", "tricep", "skullcrusher", "skull crusher", "pushdown", "push-down", "kickback", "overhead extension") {
            return .elbowExtension
        }
        // Por encima de la cabeza: vertical de manos, jerk, push press y press tras nuca.
        // ("Neck press" a secas es press de banca hasta el cuello: va con los de pecho.)
        if containsAny(n, "handstand", "jerk", "push press") || (containsAny(n, "behind the neck", "behind-the-neck", "behind neck") && words.contains("press")) {
            return .verticalPress
        }
        // Jalones y dominadas.
        if containsAny(n, "pull-up", "pullup", "chin-up", "chinup", "lat pulldown", "pulldown", "pull down", "muscle up", "high pull") {
            return .verticalPull
        }
        // Press inclinado o declinado: siempre de pecho, aunque diga "dumbbell press".
        if words.contains("press"), !words.isDisjoint(with: ["incline", "decline"]) {
            return .horizontalPress
        }
        if containsAny(n, "bench press", "floor press", "push-up", "pushup", "push up", "chest press", "machine press", "neck press", "fly", "flye", "crossover", "cable cross", "butterfly", "body-up", "close-grip", "pec deck") {
            return .horizontalPress
        }
        if containsAny(n, "overhead press", "shoulder press", "military press", "arnold press", "standing press", "strict press", "dumbbell press") {
            return .verticalPress
        }
        if !words.isDisjoint(with: ["row", "rows"]) || containsAny(n, "bent-over", "pendlay", "pullover", "t-bar") {
            return .horizontalPull
        }
        // Zancadas antes que sentadilla: la sentadilla dividida es zancada.
        if containsAny(n, "lunge", "step-up", "step up", "stepup", "bulgarian", "split squat") {
            return .lunge
        }
        if containsAny(n, "squat", "leg press", "zercher") {
            return .squat
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
        if containsAny(n, "farmer", "yoke", "suitcase", "waiter", "carry") || words.contains("walk") {
            return .carry
        }
        if containsAny(n, "windmill", "stretch", "yoga", "balance", "mobility", "band pull apart") || !words.isDisjoint(with: ["rom", "neck"]) {
            return .mobility
        }
        if containsAny(n, "air bike", "bike", "battling", "rope climb", "rope jump", "jump rope", "sprint", "burpee", "slam", "medicine ball")
            || !words.isDisjoint(with: ["jump", "jumps", "run"]) {
            return .conditioning
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

    /// Ángulo del movimiento inferido por el nombre (sólo press). El press vertical siempre
    /// es por encima de la cabeza (SCRUM-37: antes quedaba "flat", como el de banca).
    static func angle(name: String, pattern: MovementPattern) -> MovementAngle? {
        let n = name.lowercased()
        switch pattern {
        case .horizontalPress:
            if containsAny(n, "incline") { return .incline }
            if containsAny(n, "decline") { return .decline }
            return .flat
        case .verticalPress:
            return .overhead
        default:
            return nil
        }
    }

    /// Aperturas (pecho o deltoide posterior): siempre de una articulación, aunque el
    /// dataset diga "compound" (SCRUM-37).
    static func isFly(_ name: String) -> Bool {
        containsAny(name.lowercased(), "fly", "flye", "crossover", "cable cross", "butterfly", "pec deck")
    }

    // MARK: Contribuciones musculares

    /// Un grupo muscular cuenta una sola vez (SCRUM-37): "traps" y "middle back" son los dos
    /// espalda. `excluding` quita de los secundarios lo que ya es principal.
    static func makeContributions(
        _ muscles: [String],
        activation: Double,
        excluding: Set<MuscleGroup.ID> = []
    ) throws -> [MuscleContribution] {
        var seen = excluding
        return try muscles.compactMap { name in
            guard let group = muscleGroupMap[name], seen.insert(group).inserted else { return nil }
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

    /// El dataset marca la Smith como "machine" (o "barbell"); el nombre la distingue
    /// (SCRUM-219: guía la barra como una máquina, pero el gesto es el de la barra).
    static func equipment(for raw: String?, name: String = "") -> EquipmentType {
        if name.lowercased().contains("smith") { return .smithMachine }
        return equipmentMap[raw ?? ""] ?? .other
    }

    /// Costo sistémico de fatiga (SCRUM-219). Lo axial con barra libre cuesta más que lo guiado:
    /// - compuesto: 0.5, más la bisagra (+0.2), la sentadilla (+0.15) y la zancada o la cargada
    ///   (+0.1);
    /// - aislamiento: 0.25;
    /// - equipo: barra +0.15, mancuerna o kettlebell +0.05, polea, Smith o bandas −0.1, máquina
    ///   −0.15. En un aislamiento cuenta un tercio.
    static func systemicFatigue(pattern: MovementPattern, jointClass: JointClass, equipment: EquipmentType) -> Double {
        let equipmentShift: Double
        switch equipment {
        case .barbell: equipmentShift = 0.15
        case .dumbbell, .kettlebell: equipmentShift = 0.05
        case .bodyweight, .other: equipmentShift = 0
        case .cable, .smithMachine, .bands: equipmentShift = -0.1
        case .machine, .plateLoaded, .sled: equipmentShift = -0.15
        }
        switch jointClass {
        case .singleJoint:
            return singleJointFatigue + equipmentShift / 3
        case .multiJoint:
            let patternShift: Double
            switch pattern {
            case .hinge: patternShift = 0.2
            case .squat: patternShift = 0.15
            case .lunge, .carry: patternShift = 0.1
            case .horizontalPress, .verticalPress, .horizontalPull, .verticalPull, .kneeExtension,
                 .kneeFlexion, .hipExtension, .shoulderAbduction, .shoulderExtension, .elbowFlexion,
                 .elbowExtension, .calfPlantarFlexion, .trunkFlexion, .trunkExtension, .trunkRotation,
                 .conditioning, .mobility, .posing:
                patternShift = 0
            }
            return min(1, max(0.05, multiJointFatigue + patternShift + equipmentShift))
        }
    }

    static func parseLevel(_ raw: String?) -> DemandLevel {
        switch raw?.lowercased() {
        case "beginner": return .low
        case "intermediate": return .moderate
        case "expert": return .high
        default: return .moderate
        }
    }

    static func jointClass(for mechanic: String?, primaryCount: Int, name: String = "") -> JointClass {
        if isFly(name) { return .singleJoint }
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
            // Una sola articulación es aislamiento, también en patrones de compuesto
            // (aperturas, jalón con brazos rectos; SCRUM-37).
            return isCompound ? [.primaryCompound] : [.accessoryIsolation]
        }
    }

    // MARK: Contraindicaciones (SCRUM-37)

    /// Zonas que un ejercicio carga aunque su patrón no lo diga. Es la red de seguridad de
    /// las restricciones (`RestrictionPolicyEngine` cruza estas etiquetas con las de la
    /// restricción): si un nombre se clasifica mal, el músculo principal o el gesto por
    /// encima de la cabeza lo siguen quitando.
    /// - Codo: músculo principal tríceps, bíceps o antebrazo (fondos, press cerrado, curls
    ///   y extensiones).
    /// - Hombro y cuello: la carga termina sobre o detrás de la cabeza (vertical de manos,
    ///   arrancada, envión, push press, cargada y press, sentadilla con barra arriba).
    /// - Hombro: el remo sube al mentón o al cuello.
    /// - Cuello: todo lo que nombra el cuello (tras nuca, resistencia de cuello).
    static func contraindicationTags(name: String, primaryMuscles: [MuscleGroup]) -> Set<RestrictionTag> {
        let n = name.lowercased()
        var tags: Set<RestrictionTag> = []
        if primaryMuscles.contains(where: { $0 == .triceps || $0 == .biceps || $0 == .forearms }) {
            tags.insert(.elbow)
        }
        // Carga sobre la cabeza: hombro y cuello (la tabla del cuello quita el press vertical).
        if containsAny(n, "handstand", "snatch", "jerk", "push press", "clean and press", "behind the neck", "behind-the-neck", "behind neck")
            || (n.contains("overhead") && containsAny(n, "squat", "walk")) {
            tags.formUnion([.shoulder, .neck])
        }
        if containsAny(n, "upright", "row to neck") {
            tags.insert(.shoulder)
        }
        if n.split(whereSeparator: { !$0.isLetter }).contains("neck") {
            tags.insert(.neck)
        }
        return tags
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
        // Nombres en español (id del dataset → nombre). Si falta el recurso o un id, el
        // ejercicio conserva su nombre original en inglés: nunca se inventa un nombre.
        var spanishNames: [String: String] = [:]
        if let namesURL = Bundle.module.url(forResource: "exercise-names-es", withExtension: "json") {
            spanishNames = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: namesURL))
        }
        // Lista curada de ejercicios de referencia por músculo (id del dataset, en orden de
        // preferencia). Sin el recurso el catálogo funciona igual, con la asignación genérica.
        var staples: [String: [String]] = [:]
        if let staplesURL = Bundle.module.url(forResource: "exercise-staples", withExtension: "json") {
            staples = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: staplesURL))
        }
        return try load(from: data, spanishNames: spanishNames, staples: staples)
    }

    /// Mapea datos crudos JSON del dataset a `ExerciseCatalog`. `spanishNames` es opcional:
    /// el nombre en español pasa a `canonicalName` y el original en inglés queda como alias
    /// (la búsqueda sigue encontrando "bench press"). Los IDs no dependen del nombre.
    public static func load(
        from data: Data,
        spanishNames: [String: String] = [:],
        staples: [String: [String]] = [:]
    ) throws -> ExerciseCatalog {
        // id del dataset → su lugar en la lista curada (un ejercicio es de referencia de UN músculo).
        var stapleByID: [String: StapleSelection] = [:]
        for (muscleName, ids) in staples {
            guard let muscle = MuscleGroup(rawValue: muscleName) else { continue }
            for (rank, id) in ids.enumerated() where stapleByID[id] == nil {
                stapleByID[id] = StapleSelection(muscle: muscle, rank: rank)
            }
        }
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

            let equipment = ExerciseInflector.equipment(for: entry.equipment, name: entry.name)
            let jointClass = ExerciseInflector.jointClass(
                for: entry.mechanic,
                primaryCount: entry.primaryMuscles.count,
                name: entry.name
            )
            let isMultiJoint = jointClass == .multiJoint

            let primary = try ExerciseInflector.makeContributions(
                entry.primaryMuscles,
                activation: ExerciseInflector.primaryActivation
            )
            let secondary = try ExerciseInflector.makeContributions(
                entry.secondaryMuscles,
                activation: ExerciseInflector.secondaryActivation,
                excluding: Set(primary.map(\.muscleGroupID))
            )

            let exercise = Exercise(
                id: ExerciseID(rawValue: SeedID.uuid(namespace: "exercise", slug: entry.id)),
                canonicalName: spanishNames[entry.id] ?? entry.name,
                aliases: spanishNames[entry.id] == nil ? [] : [entry.name],
                movementPattern: pattern,
                movementAngle: ExerciseInflector.angle(name: entry.name, pattern: pattern),
                primaryMuscles: primary,
                secondaryMuscles: secondary,
                equipment: equipment,
                laterality: .bilateral,
                jointClass: jointClass,
                stabilityDemand: ExerciseInflector.parseLevel(entry.level),
                skillDemand: ExerciseInflector.parseLevel(entry.level),
                systemicFatigueCost: try FatigueCost(normalized: ExerciseInflector.systemicFatigue(
                    pattern: pattern, jointClass: jointClass, equipment: equipment
                )),
                localFatigue: try ExerciseInflector.makeLocalFatigue(
                    contributions: primary + secondary,
                    ratio: ExerciseInflector.localFatigueRatio
                ),
                loadability: ExerciseInflector.loadability(for: equipment),
                defaultRoles: ExerciseInflector.defaultRoles(
                    for: pattern,
                    isCompound: isMultiJoint
                ),
                contraindicationTags: ExerciseInflector.contraindicationTags(
                    name: entry.name,
                    primaryMuscles: primary.map(\.muscleGroupID)
                ),
                substitutionFamilyID: family.id,
                staple: stapleByID[entry.id]
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