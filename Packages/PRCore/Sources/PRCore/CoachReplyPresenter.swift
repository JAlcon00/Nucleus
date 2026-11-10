//
//  CoachReplyPresenter.swift
//  PRCore
//
//  SCRUM-272 (PR-I003): lo que dice el entrenador, en palabras simples. No decide nada: el
//  coordinador ya validó con la política y el motor. Nunca nombra una lesión, no promete
//  recuperación y no inventa números (los minutos y los nombres salen del contexto). Textos
//  en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

/// Texto y botones de una respuesta.
public struct CoachReply: Equatable, Sendable {
    public let text: String
    public let reasons: [String]
    public let actions: [CoachAction]

    public init(text: String, reasons: [String] = [], actions: [CoachAction] = []) {
        self.text = text
        self.reasons = reasons
        self.actions = actions
    }
}

public struct CoachReplyPresenter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: Frases sugeridas

    /// Las frases que se ofrecen según dónde está la persona y qué se puede explicar. Todas
    /// las entiende el intérprete local.
    public func suggestions(for snapshot: CoachSnapshot?) -> [String] {
        guard let snapshot else { return [] }
        switch snapshot.surface {
        case .workout:
            var phrases = [
                resource("Está ocupada", "Entrenador: frase sugerida, la máquina del ejercicio actual está ocupada"),
                resource("Cámbiame este ejercicio", "Entrenador: frase sugerida, pedir un sustituto"),
            ]
            if snapshot.hasCompletedSet {
                phrases.append(resource("Me duele", "Entrenador: frase sugerida, reportar dolor"))
            }
            if snapshot.decisions.contains(where: { $0.topic == .suggestedLoad }) {
                phrases.append(resource("¿Por qué este peso?", "Entrenador: frase sugerida, explicar el peso precargado"))
            }
            return phrases
        case .today:
            var phrases = [resource("Tengo 30 minutos", "Entrenador: frase sugerida, ajustar la sesión al tiempo")]
            let topics = Set(snapshot.decisions.map(\.topic))
            for topic in [ExplainableTopic.sessionOrder, .timeFit, .readiness, .gymChange] where topics.contains(topic) {
                if let phrase = whyPhrase(topic) { phrases.append(phrase) }
            }
            return phrases
        }
    }

    private func whyPhrase(_ topic: ExplainableTopic) -> String? {
        switch topic {
        case .sessionOrder: return resource("¿Por qué este orden?", "Entrenador: frase sugerida, explicar el orden")
        case .timeFit: return resource("¿Por qué tan corta?", "Entrenador: frase sugerida, explicar el ajuste al tiempo")
        case .readiness: return resource("¿Por qué más ligero?", "Entrenador: frase sugerida, explicar el día aligerado")
        case .gymChange: return resource("¿Por qué cambió?", "Entrenador: frase sugerida, explicar el cambio por el gimnasio")
        case .suggestedLoad: return resource("¿Por qué este peso?", "Entrenador: frase sugerida, explicar el peso precargado")
        case .pain: return resource("¿Por qué esta recomendación?", "Entrenador: frase sugerida, explicar la recomendación por dolor")
        }
    }

    // MARK: Aclarar

    public func clarification(_ clarification: AgentClarification, snapshot: CoachSnapshot) -> CoachReply {
        switch clarification {
        case .general:
            return CoachReply(
                text: resource("No te entendí. Prueba con una frase corta, como estas:", "Entrenador: no entendió el mensaje"),
                actions: suggestions(for: snapshot).map(CoachAction.say)
            )
        case .minutes:
            return CoachReply(
                text: resource("¿Cuántos minutos tienes hoy?", "Entrenador: pide los minutos disponibles"),
                actions: SessionTimeChoice.quickMinutes.map { .say(resource("Tengo \($0) minutos", "Entrenador: frase sugerida con minutos")) }
            )
        case .equipment:
            return CoachReply(text: resource(
                "¿Cuál máquina? Dímelo durante el entrenamiento y adelanto otro ejercicio.",
                "Entrenador: máquina ocupada sin decir cuál, fuera del entrenamiento"
            ))
        case .painLevel:
            return CoachReply(
                text: resource("¿Cuánto te duele: un poco, bastante o mucho?", "Entrenador: pide el nivel de dolor"),
                actions: [
                    .say(resource("Me duele un poco", "Entrenador: frase sugerida, dolor leve")),
                    .say(resource("Me duele bastante", "Entrenador: frase sugerida, dolor moderado")),
                    .say(resource("Me duele mucho", "Entrenador: frase sugerida, dolor alto")),
                ]
            )
        case .whichDecision(let options):
            let explainable = options.compactMap { option in snapshot.decisions.first { $0.id == option.id } }
            guard !explainable.isEmpty else { return nothingToExplain() }
            return CoachReply(
                text: resource("¿Cuál quieres que te explique?", "Entrenador: pide cuál decisión explicar"),
                actions: explainable.map { .explain($0.id, label: decisionLabel($0)) }
            )
        case .nothingToExplain:
            return nothingToExplain()
        case .exerciseSwapNeedsWorkout:
            return CoachReply(text: substitutionNeedsWorkout())
        case .whichGym(let gyms):
            guard !gyms.isEmpty else {
                return CoachReply(text: resource(
                    "Primero agrega el gimnasio en Perfil › Mi gimnasio.",
                    "Entrenador: no hay gimnasios con nombre para elegir"
                ))
            }
            return CoachReply(
                text: resource("¿A cuál gimnasio?", "Entrenador: pide a cuál gimnasio cambiar"),
                actions: gyms.map { .say(resource("Estoy en \($0.name)", "Entrenador: frase sugerida para cambiar de gimnasio")) }
            )
        case .oneThingAtATime:
            return CoachReply(text: resource(
                "Una cosa a la vez: dime primero lo más urgente.",
                "Entrenador: el mensaje pide dos cosas"
            ))
        }
    }

    private func nothingToExplain() -> CoachReply {
        CoachReply(text: resource(
            "Ahora no hay una decisión de ese tema que explicar.",
            "Entrenador: no hay registro que explicar"
        ))
    }

    /// Etiqueta del botón que explica una decisión. Con el ejercicio cuando hay varios del
    /// mismo tema (p. ej. dos cambios del gimnasio).
    public func decisionLabel(_ decision: ExplainableDecision) -> String {
        if decision.topic == .gymChange, let original = decision.value(ExplainableFactKey.gymOriginal), !original.isEmpty {
            return resource("Por qué cambió \(original)", "Entrenador: botón para explicar el cambio de un ejercicio por el gimnasio")
        }
        return DecisionExplanationPresenter(locale: locale).explanation(for: decision).title
    }

    // MARK: Política

    public func confirmation(for command: AgentWriteCommand, preview: AgentActionPreview) -> String {
        let choices = OnboardingChoicePresenter(locale: locale)
        switch command {
        case .changeGoal(let goal):
            return resource(
                "¿Cambiar tu objetivo a \(choices.goalLabel(goal))? Abro el cuestionario para que lo revises; tu historial no se borra.",
                "Entrenador: confirmar cambio de objetivo"
            )
        case .changePhase(let phase):
            return resource(
                "¿Cambiar tu fase a \(choices.phaseLabel(phase))? Abro el cuestionario para que lo revises; tu historial no se borra.",
                "Entrenador: confirmar cambio de fase"
            )
        case .saveRestriction:
            return resource("¿Agregar una restricción? Abro Restricciones para que la revises.", "Entrenador: confirmar una restricción")
        case .adjustPlan:
            return resource("¿Cambiar tu plan? Abro \"Cambiar objetivo o fase\" para que lo revises.", "Entrenador: confirmar un cambio del plan")
        case .recomputeSession, .markEquipmentUnavailable, .requestSubstitution, .recordFatigue, .recordPain,
             .changeGym, .recommendRest, .rescheduleWorkout, .presentExplanation:
            return resource("¿Confirmas este cambio?", "Entrenador: confirmar un cambio")
        }
    }

    public func rejection(_ verdict: ActionPolicyVerdict) -> String {
        let painGate = verdict.decisionRecord.inputFacts.contains { $0.key == "painGate" && $0.value == "activo" }
        if painGate {
            return resource(
                "Con dolor moderado o alto en esta sesión no subo carga ni volumen, ni cambio lo que podría subirlos.",
                "Entrenador: la política rechazó por dolor"
            )
        }
        if verdict.action == .replaceExercise {
            return resource("Ese cambio saltaría una restricción activa, así que no lo hago.", "Entrenador: la política rechazó por restricción")
        }
        return resource("Las reglas de seguridad no permiten ese cambio.", "Entrenador: la política rechazó el cambio")
    }

    public func policyUnavailable() -> String {
        resource(
            "No pude revisar ese cambio con las reglas de seguridad, así que no hice nada.",
            "Entrenador: la política no se pudo leer"
        )
    }

    public func cancelled() -> String {
        resource("Listo, no cambié nada.", "Entrenador: la persona canceló")
    }

    public func clipped(_ maximum: Int) -> String {
        resource("Tu mensaje era muy largo: leí los primeros \(maximum) caracteres.", "Entrenador: el mensaje se cortó")
    }

    // MARK: Tiempo

    public func time(_ outcome: CoachTimeOutcome, minutes: Int?) -> CoachReply {
        switch outcome {
        case .adjusted(let explanation):
            guard let minutes else {
                return CoachReply(text: resource("Quité el ajuste de tiempo de hoy.", "Entrenador: se quitó el ajuste de tiempo"))
            }
            return CoachReply(
                text: resource("Ajusté tu sesión de hoy a \(minutes) min.", "Entrenador: sesión ajustada al tiempo"),
                reasons: explanation?.reasons ?? []
            )
        case .workoutInProgress:
            return CoachReply(text: timeDuringWorkout())
        case .outOfRange:
            let range = TrainingWeek.allowedSessionMinutes
            return CoachReply(text: resource(
                "Puedo ajustar la sesión entre \(range.lowerBound) y \(range.upperBound) minutos.",
                "Entrenador: minutos fuera de rango"
            ))
        case .saveFailed:
            return CoachReply(text: resource("No se pudo guardar el ajuste; tu sesión sigue igual.", "Entrenador: no se guardó el ajuste de tiempo"))
        }
    }

    public func timeDuringWorkout() -> String {
        resource(
            "Tu entrenamiento ya empezó y esa sesión no cambia. El tiempo se elige en Hoy antes de empezar.",
            "Entrenador: no se ajusta el tiempo con el entrenamiento en curso"
        )
    }

    // MARK: Equipo y sustitutos

    public func equipmentOutsideWorkout(_ reason: UnavailabilityReason) -> String {
        switch reason {
        case .occupied:
            return resource(
                "Cuando estés entrenando, dime que está ocupada y adelanto otro ejercicio.",
                "Entrenador: máquina ocupada fuera del entrenamiento"
            )
        case .doesNotExist:
            return resource(
                "Márcalo durante el entrenamiento con \"No hay esta máquina aquí\" y lo recuerdo en este gimnasio.",
                "Entrenador: máquina que no hay, fuera del entrenamiento"
            )
        }
    }

    public func equipmentMismatch(_ exercise: String?) -> String {
        guard let exercise else {
            return resource("Sólo puedo marcar la máquina del ejercicio actual. ¿Es esa?", "Entrenador: la máquina no es la del ejercicio actual")
        }
        return resource(
            "Sólo puedo marcar la máquina del ejercicio actual, \(exercise). ¿Es esa?",
            "Entrenador: la máquina no es la del ejercicio actual (con nombre)"
        )
    }

    public func occupiedPhrase() -> String {
        resource("Está ocupada", "Entrenador: frase sugerida, la máquina del ejercicio actual está ocupada")
    }

    public func occupied(_ outcome: OccupiedOutcome) -> String {
        switch outcome {
        case .advanced(let next, let after):
            return resource("Listo: haces \(next) ahora y \(after) va justo después.", "Entrenador: máquina ocupada, se adelantó otro ejercicio")
        case .needsChoice:
            return resource(
                "No hay otro ejercicio que adelantar sin cansarte de más: elige qué hacer.",
                "Entrenador: máquina ocupada, hay que elegir"
            )
        case .movedToEnd(let exercise):
            return resource("\(exercise) va al final.", "Entrenador: el ejercicio ocupado va al final")
        }
    }

    public func openingMissingMachine() -> String {
        resource("Abro las opciones: ahí está \"No hay esta máquina aquí\".", "Entrenador: abre la hoja con la máquina que no hay")
    }

    public func openingSubstitutes() -> String {
        resource(
            "Abro los sustitutos equivalentes; lo que prohíben tus restricciones no aparece.",
            "Entrenador: abre la hoja de sustitutos"
        )
    }

    public func substitutionNeedsWorkout() -> String {
        resource("Cambiar un ejercicio se hace durante el entrenamiento.", "Entrenador: sustituir fuera del entrenamiento")
    }

    // MARK: Dolor y fatiga

    public func openingPainReport() -> String {
        resource("Abro \"¿Te dolió?\" para que registres cuánto.", "Entrenador: abre el reporte de dolor")
    }

    public func painNeedsASet() -> String {
        resource(
            "El dolor se registra sobre la última serie hecha y todavía no hay ninguna.",
            "Entrenador: dolor antes de la primera serie"
        )
    }

    public func painOutsideWorkout() -> String {
        resource("Si algo te duele, agrégalo como restricción y el plan lo evita.", "Entrenador: dolor fuera del entrenamiento")
    }

    public func declinedDiagnosis() -> String {
        resource(
            "No puedo decirte qué tienes: eso lo valora un profesional de la salud. Sí puedo registrar el dolor o evitar ese movimiento.",
            "Entrenador: no responde preguntas de diagnóstico"
        )
    }

    public func fatigueNotHandled(surface: CoachSurface) -> String {
        switch surface {
        case .today:
            return resource(
                "Desde aquí no cambio la sesión por cansancio. Si dormiste mal, contesta \"¿Cómo dormiste?\" en Hoy y aligero el día.",
                "Entrenador: fatiga en Hoy"
            )
        case .workout:
            return resource(
                "Desde aquí no cambio la sesión por cansancio. Si algo te duele, dímelo y lo registramos.",
                "Entrenador: fatiga en el entrenamiento"
            )
        }
    }

    // MARK: Objetivo, restricciones y gimnasio

    public func openingGoalChange() -> String {
        resource("Abro \"Cambiar objetivo o fase\" para que lo revises.", "Entrenador: abre el cambio de objetivo o fase")
    }

    public func openingRestrictions() -> String {
        resource("Abro Restricciones para que la revises.", "Entrenador: abre Restricciones")
    }

    public func alreadyInGym(_ name: String) -> String {
        resource("Ya estás en \(name).", "Entrenador: ya está en ese gimnasio")
    }

    public func gymSelected(_ name: String) -> String {
        resource("Listo, ahora entrenas en \(name).", "Entrenador: cambió de gimnasio")
    }

    public func gymNotSaved() -> String {
        resource("No se pudo cambiar de gimnasio; sigues en el mismo.", "Entrenador: no se guardó el cambio de gimnasio")
    }

    public func notHandledHere() -> String {
        resource("Eso todavía no lo hago desde aquí.", "Entrenador: acción que el chat no hace")
    }

    // MARK: ¿Por qué?

    public func explanation(for decision: ExplainableDecision) -> DecisionExplanation {
        DecisionExplanationPresenter(locale: locale).explanation(for: decision)
    }

    // MARK: Fuente

    /// La nota bajo una respuesta del intérprete local cuando la IA no estaba (DI-1 A).
    public func sourceNote(_ source: CoachReplySource?) -> String? {
        switch source {
        case .offline(.noBackend)?:
            return resource("Sin conexión a la IA: entiendo frases cortas.", "Entrenador: respondió el intérprete local, sin IA")
        case .offline(.timeout)?, .offline(.backendFailure)?:
            return resource("La IA no respondió: contesté con el intérprete local.", "Entrenador: la IA no respondió a tiempo")
        case .engine?, .ai?, nil:
            return nil
        }
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
