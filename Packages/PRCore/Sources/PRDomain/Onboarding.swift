//
//  Onboarding.swift
//  PRDomain
//
//  Created by PR.
//
//  Onboarding funcional (promptMaster §4, RF-003, PR-0402). Produce un primer perfil
//  útil sin cuestionario excesivo. INVARIANTES: determinista; días de entrenamiento
//  elegidos 2...7 (SCRUM-196: L, Mi, V…, el número sale de ellos);
//  `usualSessionMinutes` 30...240; el usuario puede volver atrás SIN perder las
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
    /// Días de la semana en que se puede entrenar (SCRUM-196).
    case trainingDays(Set<WeekDay>)
    case sessionMinutes(Int)
    case gym(GymID?)
    case variety(VarietyPreference)
    case restrictions([TrainingRestriction])

    /// ¿La respuesta permite avanzar? Días: al menos 2 y como mucho 7 (SCRUM-196);
    /// minutos: 30...240. El resto de respuestas tipadas siempre es válido.
    public var isValid: Bool {
        switch self {
        case .trainingDays(let days): return TrainingWeek.allowedTrainingDays.contains(days.count)
        case .sessionMinutes(let minutes): return TrainingWeek.allowedSessionMinutes.contains(minutes)
        case .goal, .phase, .experience, .gym, .variety, .restrictions: return true
        }
    }
}

/// Valores que el cuestionario muestra por defecto en los selectores numéricos. Lo que
/// se ve es lo que se registra: al llegar al paso se guarda como respuesta, para que
/// "Siguiente" funcione sin tener que mover el selector.
public enum OnboardingDefaults {
    public static let trainingDaysPerWeek = 4
    /// Reparto espaciado de `trainingDaysPerWeek` (L, M, J, V; igual a
    /// `TrainingWeek.spacedDays(count: 4)`, lo comprueba TrainingDaysTests).
    public static let trainingDays: Set<WeekDay> = [.monday, .tuesday, .thursday, .friday]
    public static let sessionMinutes = 60

    /// Respuesta por defecto de un paso con selector numérico; `nil` en el resto
    /// (objetivo, fase, experiencia y variedad exigen elegir: no se inventan).
    public static func answer(for step: OnboardingStep) -> OnboardingAnswer? {
        switch step {
        case .daysPerWeek: return .trainingDays(trainingDays)
        case .sessionMinutes: return .sessionMinutes(sessionMinutes)
        case .goal, .phase, .experience, .gym, .variety, .restrictions: return nil
        }
    }
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
    /// Días por semana. Con días elegidos, siempre es su número.
    public private(set) var trainingDaysPerWeek: Int
    /// Días elegidos (SCRUM-196). Un perfil de "N días" (anterior, o hecho con el
    /// constructor de N) son los primeros N desde el lunes. `nil` sólo si N está fuera de
    /// 2...7: el perfil sigue siendo inválido, nunca se recorta a otro número.
    public private(set) var trainingWeekdays: Set<WeekDay>?
    public var usualSessionMinutes: Int
    public var varietyPreference: VarietyPreference
    public var defaultGymID: GymID?
    public var restrictions: [TrainingRestriction]

    /// Perfil de "N días": los primeros N desde el lunes (el comportamiento anterior a
    /// SCRUM-196). Lo usan los perfiles guardados antes y los tests.
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
        self.trainingWeekdays = TrainingWeek.firstDays(trainingDaysPerWeek)
        self.usualSessionMinutes = usualSessionMinutes
        self.varietyPreference = varietyPreference
        self.defaultGymID = defaultGymID
        self.restrictions = restrictions
    }

    /// Perfil con los días elegidos (SCRUM-196). Falla con menos de 2 días.
    public init(
        goal: TrainingGoal,
        phase: BodyCompositionPhase,
        experience: ExperienceLevel,
        trainingDays: Set<WeekDay>,
        usualSessionMinutes: Int,
        varietyPreference: VarietyPreference,
        defaultGymID: GymID? = nil,
        restrictions: [TrainingRestriction] = []
    ) throws {
        let week = try TrainingWeek(trainingDays: trainingDays)
        self.goal = goal
        self.phase = phase
        self.experience = experience
        self.trainingDaysPerWeek = week.trainingDaysPerWeek
        self.trainingWeekdays = week.trainingDays
        self.usualSessionMinutes = usualSessionMinutes
        self.varietyPreference = varietyPreference
        self.defaultGymID = defaultGymID
        self.restrictions = restrictions
    }

    /// Semana del perfil: los días elegidos (o los primeros N de un perfil de "N días").
    public func trainingWeek() throws -> TrainingWeek {
        if let trainingWeekdays {
            return try TrainingWeek(trainingDays: trainingWeekdays)
        }
        return try TrainingWeek(trainingDaysPerWeek: trainingDaysPerWeek)
    }

    // MARK: Codable (SCRUM-196: migración de perfiles de "N días")

    private enum CodingKeys: String, CodingKey {
        case goal, phase, experience, trainingDaysPerWeek, trainingWeekdays
        case usualSessionMinutes, varietyPreference, defaultGymID, restrictions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decode(TrainingGoal.self, forKey: .goal)
        phase = try container.decode(BodyCompositionPhase.self, forKey: .phase)
        experience = try container.decode(ExperienceLevel.self, forKey: .experience)
        trainingDaysPerWeek = try container.decode(Int.self, forKey: .trainingDaysPerWeek)
        if let stored = try container.decodeIfPresent([WeekDay].self, forKey: .trainingWeekdays) {
            let days = Set(stored)
            // Días repetidos o que no cuadran con N: el registro está dañado; se trata como
            // ilegible (se ofrece rehacer el cuestionario) en vez de adivinar.
            guard days.count == stored.count, days.count == trainingDaysPerWeek else {
                throw DecodingError.dataCorruptedError(
                    forKey: .trainingWeekdays, in: container,
                    debugDescription: "Los días guardados no cuadran con trainingDaysPerWeek."
                )
            }
            trainingWeekdays = days
        } else {
            // Perfil anterior a SCRUM-196: los primeros N días desde el lunes (lo de antes).
            trainingWeekdays = TrainingWeek.firstDays(trainingDaysPerWeek)
        }
        usualSessionMinutes = try container.decode(Int.self, forKey: .usualSessionMinutes)
        varietyPreference = try container.decode(VarietyPreference.self, forKey: .varietyPreference)
        defaultGymID = try container.decodeIfPresent(GymID.self, forKey: .defaultGymID)
        restrictions = try container.decode([TrainingRestriction].self, forKey: .restrictions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(goal, forKey: .goal)
        try container.encode(phase, forKey: .phase)
        try container.encode(experience, forKey: .experience)
        try container.encode(trainingDaysPerWeek, forKey: .trainingDaysPerWeek)
        // De lunes a domingo: el archivo no cambia de orden entre guardados.
        let ordered = trainingWeekdays.map { days in WeekDay.allCases.filter { days.contains($0) } }
        try container.encodeIfPresent(ordered, forKey: .trainingWeekdays)
        try container.encode(usualSessionMinutes, forKey: .usualSessionMinutes)
        try container.encode(varietyPreference, forKey: .varietyPreference)
        try container.encodeIfPresent(defaultGymID, forKey: .defaultGymID)
        try container.encode(restrictions, forKey: .restrictions)
    }
}

// MARK: - Builder (finaliza el draft en OnboardingProfile)

/// Convierte un borrador completo en un `OnboardingProfile` válido (PR-0402).
///
/// Validaciones (§4.2): días elegidos 2...7 (SCRUM-196), `usualSessionMinutes` 30...240.
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

        let daysValue = days.daysValue
        let minutesValue = minutes.intValue

        guard (TrainingWeek.allowedTrainingDays).contains(daysValue.count) else { throw BuildError.invalidTrainingDays(daysValue.count) }
        guard (TrainingWeek.allowedSessionMinutes).contains(minutesValue) else { throw BuildError.invalidSessionMinutes(minutesValue) }

        let gymID: GymID? = if case .gym(let value) = draft.answer(for: .gym) { value } else { nil }
        let restrictions: [TrainingRestriction] =
            if case .restrictions(let value) = draft.answer(for: .restrictions) { value } else { [] }

        return try OnboardingProfile(
            goal: goal.goalValue,
            phase: phase.phaseValue,
            experience: experience.experienceValue,
            trainingDays: daysValue,
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

    /// ¿El paso actual está satisfactoriamente respondido (permite avanzar)? Una respuesta
    /// inválida (p. ej. un solo día elegido) no deja avanzar.
    public var canAdvance: Bool {
        if currentStep.allowsEmptyAnswer {
            return true
        }
        return draft.answer(for: currentStep)?.isValid ?? false
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
        case .sessionMinutes(let v): return v
        default: return 0
        }
    }
    var daysValue: Set<WeekDay> {
        guard case .trainingDays(let v) = self else { return [] }
        return v
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