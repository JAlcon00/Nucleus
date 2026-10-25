//
//  IntensityAdvisor.swift
//  PRDomain
//
//  SCRUM-200: a qué RIR llegar en cada ejercicio y si conviene un dropset. El motor
//  decide con reglas fijas y deterministas (sin LLM); la vista sólo muestra el resultado.
//
//  Regla aprobada (2026-10-22):
//  - RIR objetivo por tipo: compuesto pesado con barra libre → 2; otro compuesto → 1–2;
//    aislado → 0–1. Los rangos viven en `IntensityPolicyConfig`.
//  - Dropset sólo en aislados o en ejercicios de carga fija (máquina, polea, Smith), y
//    sólo en la última serie de trabajo. Nunca con barra libre pesada, en compuestos de
//    peso libre, con peso corporal, para novato o principiante, en descarga o con una
//    restricción activa que afecte al ejercicio.
//

import Foundation

/// Parámetros de la política de intensidad (los números no viven en el código que decide).
public struct IntensityPolicyConfig: Sendable, Equatable {
    /// Compuesto con barra libre (sentadilla, peso muerto, press): más técnica y fatiga.
    public var heavyBarbellCompoundRIR: ClosedRange<Int>
    /// Otros compuestos (máquina, Smith, mancuernas).
    public var compoundRIR: ClosedRange<Int>
    /// Aislados: se pueden llevar más cerca del fallo con poco riesgo.
    public var isolationRIR: ClosedRange<Int>
    /// Experiencia mínima para recomendar un dropset.
    public var dropsetMinimumExperience: ExperienceLevel

    public init(
        heavyBarbellCompoundRIR: ClosedRange<Int> = 2...2,
        compoundRIR: ClosedRange<Int> = 1...2,
        isolationRIR: ClosedRange<Int> = 0...1,
        dropsetMinimumExperience: ExperienceLevel = .intermediate
    ) {
        self.heavyBarbellCompoundRIR = heavyBarbellCompoundRIR
        self.compoundRIR = compoundRIR
        self.isolationRIR = isolationRIR
        self.dropsetMinimumExperience = dropsetMinimumExperience
    }

    public static let standard = IntensityPolicyConfig()
}

/// Tipo de ejercicio para la intensidad.
public enum ExerciseIntensityClass: String, Sendable, CaseIterable, Hashable {
    case heavyBarbellCompound
    case compound
    case isolation
}

/// Por qué NO conviene un dropset. Se evalúan en este orden: la primera que aplica gana.
public enum DropsetBlocker: String, Sendable, CaseIterable, Hashable, Codable {
    /// Hay una restricción activa que afecta al ejercicio (seguridad primero).
    case restriction
    /// Semana de descarga: se baja la intensidad, no se sube.
    case deload
    /// Novato o principiante: primero técnica y progresión simple.
    case experience
    /// Barra libre pesada: bajar el peso a mitad de serie es lento e inseguro.
    case heavyFreeBarbell
    /// Peso corporal: no hay carga que bajar.
    case bodyweight
    /// Compuesto con peso libre (mancuernas, kettlebell): demasiada técnica bajo fatiga.
    case freeWeightCompound
}

/// Si conviene un dropset en el ejercicio.
public enum DropsetAdvice: Sendable, Hashable, Codable {
    /// Conviene, sólo en la última serie de trabajo.
    case recommendedOnLastSet
    case notRecommended(DropsetBlocker)
}

/// Lo que el motor recomienda para un ejercicio.
public struct IntensityAdvice: Sendable, Hashable {
    public let intensityClass: ExerciseIntensityClass
    public let targetRIR: ClosedRange<Int>
    public let dropset: DropsetAdvice
}

/// Decide RIR y dropset por ejercicio. Puro y determinista.
public struct IntensityAdvisor: Sendable {
    public let config: IntensityPolicyConfig

    public init(config: IntensityPolicyConfig = .standard) {
        self.config = config
    }

    /// Compuesto con barra libre, otro compuesto o aislado.
    public func intensityClass(of exercise: Exercise) -> ExerciseIntensityClass {
        switch exercise.jointClass {
        case .singleJoint:
            return .isolation
        case .multiJoint:
            return exercise.equipment == .barbell ? .heavyBarbellCompound : .compound
        }
    }

    /// RIR objetivo según el tipo.
    public func targetRIR(for exercise: Exercise) -> ClosedRange<Int> {
        switch intensityClass(of: exercise) {
        case .heavyBarbellCompound: return config.heavyBarbellCompoundRIR
        case .compound: return config.compoundRIR
        case .isolation: return config.isolationRIR
        }
    }

    /// RIR y dropset para un ejercicio, una persona y su contexto.
    public func advice(
        for exercise: Exercise,
        experience: ExperienceLevel,
        isDeload: Bool = false,
        isRestricted: Bool = false
    ) -> IntensityAdvice {
        let intensityClass = intensityClass(of: exercise)
        return IntensityAdvice(
            intensityClass: intensityClass,
            targetRIR: targetRIR(for: exercise),
            dropset: dropset(
                for: exercise, intensityClass: intensityClass,
                experience: experience, isDeload: isDeload, isRestricted: isRestricted
            )
        )
    }

    /// ¿Alguna restricción en vigor prohíbe el ejercicio (por ID, patrón o etiqueta)? La
    /// misma evaluación que el plan y las sustituciones (SCRUM-31).
    public static func isRestricted(_ exercise: Exercise, by restrictions: [TrainingRestriction]) -> Bool {
        RestrictionPolicyEngine.verdict(for: exercise, under: restrictions) != .allowed
    }

    /// Consejo de dropset de cada ejercicio para esta persona (experiencia y restricciones
    /// del perfil). Lo usa el entrenamiento para avisar en la última serie de trabajo.
    public func dropsetAdvice(for exercises: [Exercise], profile: OnboardingProfile) -> [ExerciseID: DropsetAdvice] {
        Dictionary(
            exercises.map { exercise in
                (exercise.id, advice(
                    for: exercise,
                    experience: profile.experience,
                    isRestricted: Self.isRestricted(exercise, by: profile.restrictions)
                ).dropset)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Privado

    private func dropset(
        for exercise: Exercise,
        intensityClass: ExerciseIntensityClass,
        experience: ExperienceLevel,
        isDeload: Bool,
        isRestricted: Bool
    ) -> DropsetAdvice {
        if isRestricted { return .notRecommended(.restriction) }
        if isDeload { return .notRecommended(.deload) }
        if Self.rank(experience) < Self.rank(config.dropsetMinimumExperience) {
            return .notRecommended(.experience)
        }
        switch intensityClass {
        case .heavyBarbellCompound:
            return .notRecommended(.heavyFreeBarbell)
        case .compound, .isolation:
            break
        }
        if exercise.loadability == .bodyweight { return .notRecommended(.bodyweight) }
        switch intensityClass {
        case .isolation:
            return .recommendedOnLastSet
        case .compound, .heavyBarbellCompound:
            return exercise.loadability == .fixedStack ? .recommendedOnLastSet : .notRecommended(.freeWeightCompound)
        }
    }

    /// Orden de experiencia (novato < principiante < intermedio < avanzado < competitivo).
    private static func rank(_ level: ExperienceLevel) -> Int {
        switch level {
        case .novice: return 0
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        case .competitive: return 4
        }
    }
}
