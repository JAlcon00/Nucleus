//
//  Onboarding.swift
//  PRDomain
//
//  Created by PR.
//
//  Onboarding funcional (promptMaster §4, RF-003, PR-0402). Produce un primer perfil
//  útil sin cuestionario excesivo. INVARIANTES: determinista; `trainingDaysPerWeek`
//  2...7; `usualSessionMinutes` 20...240; el usuario puede volver atrás SIN perder las
//  respuestas ya dadas; el onboarding se completa sin HealthKit (el gym/perfil de
//  restricciones es opcional y el login no requiere HealthKit, RF-003/PR-0401).
//

import Foundation

// MARK: - Steps

/// Orden exhaustivo y tipado de los pasos del onboarding (§4.1).
public enum OnboardingStep: String, Codable, Sendable, CaseIterable, Hashable {
    case goal
    case phase
    case experience
    case daysPerWeek
    case sessionMinutes
    case gym
    case variety
    case restrictions

    /// Todos los pasos en el orden del flujo.
    public static var ordered: [OnboardingStep] {
        OnboardingStep.allCases
    }

    /// ¿Este paso admite respuesta vacía (no bloqueante)? gym y restrictions son opcionales.
    public var allowsEmptyAnswer: Bool {
        switch self {
        case .goal, .phase, .experience, .daysPerWeek, .sessionMinutes, .variety:
            return false
        case .gym, .restrictions:
            return true
        }
    }
}

// MARK: - Draft (answers acumuladas)

/// Respuestas tipadas por paso. Ata cada paso a su tipo de respuesta concreto; ningún
/// String/bool ambiguo (SKILL §3 Modeling).
public enum OnboardingAnswer: Equatable, Sendable {
    case goal(TrainingGoal)
    case phase(BodyCompositionPhase)
    case experience(ExperienceLevel)
    case daysPerWeek(Int)
    case sessionMinutes(Int)
    case gym(GymID?)
    case variety(VarietyPreference)
    case restrictions([TrainingRestriction])
}

/// Borrador del onboarding: acumula respuestas y conserva las dadas al navegar atrás.
public struct OnboardingDraft: Equatable, Sendable {
    /// Respuestas por paso. Los pasos aún no respondidos NO están presentes.
    public private(set) var answers: [OnboardingStep: OnboardingAnswer]

    public init(answers: [OnboardingStep: OnboardingAnswer] = [:]) {
        self.answers = answers
    }

    /// Respuesta actual de un paso, si existe.
    public func answer(for step: OnboardingStep) -> OnboardingAnswer? {
        answers[step]
    }

    /// Guarda la respuesta de un paso (immutable; devuelve un nuevo draft).
    public func settingAnswer(_ answer: OnboardingAnswer, for step: OnboardingStep) -> OnboardingDraft {
        var copy = self
        copy.answers[step] = answer
        return copy
    }

    /// ¿El borrador tiene respuesta para el paso dado?
    public func hasAnswer(for step: OnboardingStep) -> Bool {
        answers[step] != nil
    }

    /// ¿Todos los pasos obligatorios están respondidos?
    public var isCompleted: Bool {
        OnboardingStep.ordered.allSatisfy { step in
            hasAnswer(for: step)
        }
    }
}

// MARK: - OnboardingProfile (datos mínimos §4.2)

/// Perfil mínimo producido al completar el onboarding (promptMaster §4.2 / RF-003).
///
/// El `phase` es `BodyCompositionPhase` (surplus/deficit/maintenance), independiente del
/// `BodybuildingPhase` de competición (PR-1801). No inventa objetivos: si el usuario omite
/// uno, el builder no finaliza en lugar de asumir un valor.
public struct OnboardingProfile: Codable, Sendable, Hashable {
    public var goal: TrainingGoal
    public var phase: BodyCompositionPhase
    public var experience: ExperienceLevel
    public var trainingDaysPerWeek: Int
    public var usualSessionMinutes: Int
    public var varietyPreference: VarietyPreference
    public var defaultGymID: GymID?
    public var restrictions: [TrainingRestriction]

    public init(
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        experience: ExperienceLevel,
        trainingDaysPerWeek: Int,
        usualSessionMinutes: Int,
        varietyPreference: VarietyPreference,
        defaultGymID: GymID? = nil,
        restrictions: [TrainingRestriction] = []
    ) {
        self.goal = goal
        self.phase = phase
        self.experience = experience
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.usualSessionMinutes = usualSessionMinutes
        self.varietyPreference = varietyPreference
        self.defaultGymID = defaultGymID
        self.restrictions = restrictions
    }
}

// MARK: - Builder (finaliza el draft en OnboardingProfile)

/// Convierte un borrador completo en un `OnboardingProfile` válido (PR-0402).
///
/// Validaciones (§4.2): `trainingDaysPerWeek` 2...7, `usualSessionMinutes` 20...240.
/// gym y restrictions son opcionales (nil / vacío). No inventa respuestas: si un paso
/// obligatorio falta, no finaliza.
public struct OnboardingProfileBuilder: Sendable {

    public init() {}

    /// Error de finalización (nunca inventa valores; falla ante input incompleto/inválido).
    public enum BuildError: Error, Equatable, Sendable {
        case missingAnswer(OnboardingStep)
        case invalidTrainingDays(Int)
        case invalidSessionMinutes(Int)
    }

    /// Construye el perfil sólo si el borrador está completo y las respuestas son válidas.
    public func build(from draft: OnboardingDraft) throws -> OnboardingProfile {
        guard let goal = draft.answer(for: .goal) else { throw BuildError.missingAnswer(.goal) }
        guard let phase = draft.answer(for: .phase) else { throw BuildError.missingAnswer(.phase) }
        guard let experience = draft.answer(for: .experience) else { throw BuildError.missingAnswer(.experience) }
        guard let days = draft.answer(for: .daysPerWeek) else { throw BuildError.missingAnswer(.daysPerWeek) }
        guard let minutes = draft.answer(for: .sessionMinutes) else { throw BuildError.missingAnswer(.sessionMinutes) }
        guard let variety = draft.answer(for: .variety) else { throw BuildError.missingAnswer(.variety) }

        let daysValue = days.intValue
        let minutesValue = minutes.intValue

        guard (2...7).contains(daysValue) else { throw BuildError.invalidTrainingDays(daysValue) }
        guard (20...240).contains(minutesValue) else { throw BuildError.invalidSessionMinutes(minutesValue) }

        let gymID: GymID? = if case .gym(let value) = draft.answer(for: .gym) { value } else { nil }
        let restrictions: [TrainingRestriction] =
            if case .restrictions(let value) = draft.answer(for: .restrictions) { value } else { [] }

        return OnboardingProfile(
            goal: goal.goalValue,
            phase: phase.phaseValue,
            experience: experience.experienceValue,
            trainingDaysPerWeek: daysValue,
            usualSessionMinutes: minutesValue,
            varietyPreference: variety.varietyValue,
            defaultGymID: gymID,
            restrictions: restrictions
        )
    }
}

// MARK: - Flow controller (navegación sin pérdida de respuestas)

/// Controla la navegación del flujo: adelante/atrás preservando TODAS las respuestas.
///
/// Reglas:
/// - `advance` sólo avanza si el paso actual tiene respuesta válida (o es opcional/empty).
/// - `goBack` retrocede un paso sin borrar nada de lo ya respondido.
/// - `currentStep` es el paso en el que se está (nunca se sale del rango).
public struct OnboardingFlowController: Sendable {
    private let steps: [OnboardingStep]
    /// Índice del paso actual (0...count-1).
    public private(set) var currentIndex: Int
    /// Borrador con todas las respuestas acumuladas.
    public private(set) var draft: OnboardingDraft

    public init(
        steps: [OnboardingStep] = OnboardingStep.ordered,
        startingIndex: Int = 0,
        draft: OnboardingDraft = OnboardingDraft()
    ) {
        self.steps = steps.isEmpty ? OnboardingStep.ordered : steps
        self.currentIndex = min(max(0, startingIndex), self.steps.count - 1)
        self.draft = draft
    }

    public var stepsOrder: [OnboardingStep] { steps }

    /// Paso actual.
    public var currentStep: OnboardingStep { steps[currentIndex] }

    /// ¿Está en el primer paso?
    public var isAtStart: Bool { currentIndex == 0 }

    /// ¿Está en el último paso?
    public var isAtEnd: Bool { currentIndex == steps.count - 1 }

    /// Registra la respuesta del paso actual (nunca borra respuestas previas).
    public func answering(_ answer: OnboardingAnswer) -> OnboardingFlowController {
        var copy = self
        copy.draft = draft.settingAnswer(answer, for: currentStep)
        return copy
    }

    /// ¿El paso actual está satisfactoriamente respondido (permite avanzar)?
    public var canAdvance: Bool {
        if currentStep.allowsEmptyAnswer {
            return true
        }
        return draft.hasAnswer(for: currentStep)
    }

    /// Avanza si el paso actual es válido; si ya está en el último, no hace nada.
    public func advance() -> OnboardingFlowController {
        guard canAdvance, !isAtEnd else { return self }
        var copy = self
        copy.currentIndex += 1
        return copy
    }

    /// Retrocede un paso (conserva todas las respuestas). En el primero, no hace nada.
    public func goBack() -> OnboardingFlowController {
        guard !isAtStart else { return self }
        var copy = self
        copy.currentIndex -= 1
        return copy
    }

    /// ¿El flujo puede finalizarse (todos los pasos obligatorios respondidos)?
    public var isFlowComplete: Bool {
        isAtEnd && canAdvance
    }
}

// MARK: - Int extraction helpers (respuestas tipadas → primitivas para validación)

private extension OnboardingAnswer {
    var intValue: Int {
        switch self {
        case .daysPerWeek(let v), .sessionMinutes(let v): return v
        default: return 0
        }
    }
    var goalValue: TrainingGoal {
        guard case .goal(let v) = self else { return .generalHealth }
        return v
    }
    var phaseValue: BodyCompositionPhase {
        guard case .phase(let v) = self else { return .maintenance }
        return v
    }
    var experienceValue: ExperienceLevel {
        guard case .experience(let v) = self else { return .intermediate }
        return v
    }
    var varietyValue: VarietyPreference {
        guard case .variety(let v) = self else { return .balanced }
        return v
    }
}