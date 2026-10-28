//
//  ExerciseSelectionRule.swift
//  PRDomain
//
//  SCRUM-219 (PR-B005): qué ejercicios recibe cada músculo. Cada músculo tiene "slots"
//  funcionales (pecho: press plano, press inclinado y apertura) y el plan los cubre antes de
//  repetir uno. Dentro de un slot:
//  - el ancla se elige por objetivo y experiencia: el novato recibe lo guiado (máquina, Smith,
//    prensa) y el avanzado con objetivo de fuerza, la barra libre;
//  - los rotables se eligen por experiencia y fase (en déficit, menos fatiga sistémica) y giran
//    de un bloque al siguiente sin azar.
//  Constantes versionadas: cambiar un número es cambiar la regla (sube `version`).
//

import Foundation

/// Función de un ejercicio dentro de su músculo. Se reconoce por patrón, ángulo y
/// articulaciones, nunca por el nombre.
public enum ExerciseSlot: String, Codable, Sendable, CaseIterable, Hashable {
    case flatPress
    case inclinePress
    case chestFly
    case row
    case verticalPull
    case straightArmPull
    case overheadPress
    case lateralRaise
    case rearDelt
    case curl
    case tricepsExtension
    case tricepsPress
    case squat
    case lunge
    case kneeExtension
    case hinge
    case legCurl
    case hipThrust
    case hipExtension
    case calfRaise
    case trunk
}

/// Lo del perfil que cambia qué ejercicios salen.
public struct ExerciseSelectionProfile: Sendable, Hashable {
    public let goal: TrainingGoal
    public let experience: ExperienceLevel
    public let phase: BodyCompositionPhase

    public init(goal: TrainingGoal, experience: ExperienceLevel, phase: BodyCompositionPhase) {
        self.goal = goal
        self.experience = experience
        self.phase = phase
    }

    /// Sin persona (pruebas del assigner, usos sin perfil): hipertrofia, intermedio, mantenimiento.
    public static let neutral = ExerciseSelectionProfile(goal: .hypertrophy, experience: .intermediate, phase: .maintenance)
}

public struct ExerciseSelectionRule: Sendable, Equatable {

    /// Va en la explicación del bloque (`exerciseSelection`).
    public let version: String
    /// De un bloque al siguiente, cada slot gira entre sus mejores `rotationPool` rotables.
    public let rotationPool: Int

    public static let standard = ExerciseSelectionRule(version: "pr-b005-v1", rotationPool: 3)

    /// Slots de cada músculo, en orden: el ancla sale del primero que tenga ejercicios.
    public func slots(for muscle: MuscleGroup) -> [ExerciseSlot] {
        switch muscle {
        case .chest: return [.flatPress, .inclinePress, .chestFly]
        case .back: return [.row, .verticalPull, .straightArmPull]
        case .shoulders: return [.overheadPress, .lateralRaise, .rearDelt]
        case .biceps: return [.curl]
        case .triceps: return [.tricepsExtension, .tricepsPress]
        case .quadriceps: return [.squat, .lunge, .kneeExtension]
        case .hamstrings: return [.hinge, .legCurl]
        case .glutes: return [.hipThrust, .hipExtension]
        case .calves: return [.calfRaise]
        case .core: return [.trunk]
        case .forearms, .spinalErectors: return []
        }
    }

    /// El slot que ocupa `exercise` para `muscle`; `nil` si no cumple ninguna función del músculo.
    public func slot(of exercise: Exercise, for muscle: MuscleGroup) -> ExerciseSlot? {
        let pattern = exercise.movementPattern
        let isCompound = exercise.jointClass == .multiJoint
        switch muscle {
        case .chest:
            guard pattern == .horizontalPress else { return nil }
            if !isCompound { return .chestFly }
            return exercise.movementAngle == .incline ? .inclinePress : .flatPress
        case .back:
            if pattern == .horizontalPull { return .row }
            if pattern == .verticalPull { return isCompound ? .verticalPull : .straightArmPull }
            return nil
        case .shoulders:
            if pattern == .verticalPress { return .overheadPress }
            if pattern == .shoulderAbduction { return .lateralRaise }
            return pattern == .shoulderExtension ? .rearDelt : nil
        case .biceps:
            return pattern == .elbowFlexion ? .curl : nil
        case .triceps:
            if pattern == .elbowExtension { return .tricepsExtension }
            return pattern == .horizontalPress ? .tricepsPress : nil
        case .quadriceps:
            if pattern == .squat { return .squat }
            if pattern == .lunge { return .lunge }
            return pattern == .kneeExtension ? .kneeExtension : nil
        case .hamstrings:
            if pattern == .hinge { return .hinge }
            return pattern == .kneeFlexion ? .legCurl : nil
        case .glutes:
            if pattern == .hinge { return .hipThrust }
            return pattern == .hipExtension ? .hipExtension : nil
        case .calves:
            return pattern == .calfPlantarFlexion ? .calfRaise : nil
        case .core:
            return [.trunkFlexion, .trunkExtension, .trunkRotation].contains(pattern) ? .trunk : nil
        case .forearms, .spinalErectors:
            return nil
        }
    }

    /// Puntaje del ancla: experiencia y objetivo. La fase no la cambia: lo principal se mantiene
    /// también en déficit (especificidad).
    public func anchorScore(_ exercise: Exercise, profile: ExerciseSelectionProfile) -> Double {
        experienceAffinity(exercise.equipment, profile.experience)
            + goalAffinity(exercise, profile.goal)
            + curatedBonus(exercise)
            - skillPenalty(exercise, profile.experience)
    }

    /// Puntaje de un rotable: experiencia y fase. En déficit pesa la fatiga sistémica, así los
    /// accesorios pasan a lo guiado; el objetivo ya lo marca el ancla.
    public func rotationScore(_ exercise: Exercise, profile: ExerciseSelectionProfile) -> Double {
        experienceAffinity(exercise.equipment, profile.experience)
            + curatedBonus(exercise)
            - skillPenalty(exercise, profile.experience)
            - fatigueWeight(profile.phase) * exercise.systemicFatigueCost.normalized
    }

    // MARK: - Tablas

    /// Estabilidad externa: el novato prefiere lo guiado (máquina, Smith, polea); desde
    /// intermedio todo el equipo de gimnasio vale igual y decide el objetivo.
    private func experienceAffinity(_ equipment: EquipmentType, _ experience: ExperienceLevel) -> Double {
        switch experience {
        case .novice:
            switch equipment {
            case .machine, .smithMachine, .plateLoaded, .sled: return 4
            case .cable: return 3
            case .dumbbell, .kettlebell: return 1
            case .barbell, .bodyweight, .bands, .other: return 0
            }
        case .beginner:
            switch equipment {
            case .machine, .smithMachine, .plateLoaded, .sled, .cable: return 3
            case .dumbbell, .kettlebell: return 2
            case .barbell, .bodyweight: return 1
            case .bands, .other: return 0
            }
        case .intermediate, .advanced, .competitive:
            switch equipment {
            case .barbell, .dumbbell, .kettlebell, .machine, .smithMachine, .plateLoaded, .sled, .cable: return 2
            case .bodyweight: return 1
            case .bands, .other: return 0
            }
        }
    }

    /// Lo que pide el objetivo al ejercicio principal: la fuerza, la barra en los básicos (la
    /// Smith la acerca para quien empieza; en aislamientos, core o pantorrilla la barra no da
    /// especificidad); la hipertrofia, tensión estable (mancuerna, máquina); la salud y la
    /// recomposición, lo guiado.
    private func goalAffinity(_ exercise: Exercise, _ goal: TrainingGoal) -> Double {
        let equipment = exercise.equipment
        switch goal {
        case .strength:
            guard isBasicLift(exercise) else { return 0 }
            switch equipment {
            case .barbell: return 3
            case .smithMachine: return 2
            case .dumbbell, .kettlebell: return 1
            case .machine, .plateLoaded, .sled, .cable, .bodyweight, .bands, .other: return 0
            }
        case .powerbuilding:
            guard isBasicLift(exercise) else { return 0 }
            switch equipment {
            case .barbell: return 3
            case .smithMachine: return 2
            case .dumbbell, .kettlebell, .machine, .plateLoaded: return 1
            case .sled, .cable, .bodyweight, .bands, .other: return 0
            }
        case .hypertrophy, .bodybuilding:
            switch equipment {
            case .dumbbell, .machine, .plateLoaded: return 2
            case .barbell, .smithMachine, .cable, .kettlebell: return 1
            case .sled, .bodyweight, .bands, .other: return 0
            }
        case .recomposition, .generalHealth:
            switch equipment {
            case .machine, .plateLoaded: return 2
            case .dumbbell, .smithMachine, .cable, .kettlebell: return 1
            case .barbell, .sled, .bodyweight, .bands, .other: return 0
            }
        }
    }

    /// Los básicos compuestos: press, remo, jalón, sentadilla, bisagra y zancada.
    private func isBasicLift(_ exercise: Exercise) -> Bool {
        guard exercise.jointClass == .multiJoint else { return false }
        switch exercise.movementPattern {
        case .horizontalPress, .verticalPress, .horizontalPull, .verticalPull, .squat, .hinge, .lunge:
            return true
        case .kneeExtension, .kneeFlexion, .hipExtension, .shoulderAbduction, .shoulderExtension, .elbowFlexion,
             .elbowExtension, .calfPlantarFlexion, .trunkFlexion, .trunkExtension, .trunkRotation, .carry,
             .conditioning, .mobility, .posing:
            return false
        }
    }

    /// El orden de la lista curada desempata: los tres primeros suman un poco (0.75, 0.5, 0.25).
    private func curatedBonus(_ exercise: Exercise) -> Double {
        guard let rank = exercise.staple?.rank else { return 0 }
        return Double(max(0, 3 - rank)) * 0.25
    }

    /// La técnica difícil (nivel "experto" del dataset) no es para quien empieza.
    private func skillPenalty(_ exercise: Exercise, _ experience: ExperienceLevel) -> Double {
        guard exercise.skillDemand == .high else { return 0 }
        switch experience {
        case .novice: return 3
        case .beginner: return 1
        case .intermediate, .advanced, .competitive: return 0
        }
    }

    /// Cuánto resta la fatiga sistémica (0…1) a un rotable según la fase.
    private func fatigueWeight(_ phase: BodyCompositionPhase) -> Double {
        switch phase {
        case .deficit: return 8
        case .maintenance, .unspecified: return 2
        case .surplus: return 0
        }
    }
}
