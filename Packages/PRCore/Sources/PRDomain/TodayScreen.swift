//
//  TodayScreen.swift
//  PRDomain
//
//  Created by PR.
//
//  Today screen domain (plan §8, RF-005, PR-0601). Deriva, de forma determinista y
//  pura (sin Views, sin red), el modelo que la pantalla "Hoy" presenta: la sesión de
//  hoy (título + nº de sets), su duración estimada, y un estado claro entre
//  `restDay` (día de descanso), `readyToStart` (sesión planeada, CTA empezar) y
//  `activeWorkout` (sesión en curso / pausada). Funciona offline porque sólo depende
//  de inputs pasados. Decide el estado; la UI sólo lo presenta.
//

import Foundation

/// Estado claro que la pantalla "Hoy" presenta (PR-0601). Uno y sólo uno es activo.
public enum TodayScreenState: Equatable, Sendable {
    /// Día de descanso o sin sesión hoy: no hay CTA empezar.
    case restDay
    /// Sesión planeada y no iniciada: mostrar título, sets y duración; CTA empezar.
    case readyToStart(SessionPresentation)
    /// Sesión en curso (activa o pausada): mostrar indicación de en curso; CTA continuar.
    case activeWorkout(SessionPresentation, isPaused: Bool)
}

/// Presentación de la sesión para la pantalla "Hoy" (PR-0601). Sólo datos presentables;
/// el título y los sets provienen de la plantilla; la duración estimada se inyecta.
public struct SessionPresentation: Equatable, Sendable {
    public var templateID: SessionTemplate.ID
    public var title: String
    /// Nº de sets de trabajo (excluye calentamiento) más calentamientos.
    public var workSetCount: Int
    public var warmupSetCount: Int
    public var estimatedMinutes: Int?

    public init(
        templateID: SessionTemplate.ID,
        title: String,
        workSetCount: Int,
        warmupSetCount: Int,
        estimatedMinutes: Int? = nil
    ) {
        self.templateID = templateID
        self.title = title
        self.workSetCount = workSetCount
        self.warmupSetCount = warmupSetCount
        self.estimatedMinutes = estimatedMinutes
    }
}

/// Problemas de la derivación de la pantalla "Hoy" (PR-0601).
public enum TodayScreenError: Error, Equatable, Sendable {
    /// Se pidió una sesión pero no hay plantilla candidata.
    case noTemplate
    /// Entrada incoherente (p. ej. duración negativa).
    case invalidInput
}

/// Coordinador determinista de la pantalla "Hoy" (PR-0601).
///
/// Entradas: plantilla candidata del día (nil = día de descanso), sesión activa
/// (nil = ninguna), duración estimada (nil = no disponible). Salida: `TodayScreenState`.
/// La elección de "cuál es la plantilla de hoy" la hace la capa de aplicación; aquí se
/// preservan las invariantes de producto: día de descanso sin CTA, sesión en curso no
/// se sobrescribe, y la duración nunca se inventa (nil si no se calculó).
public struct TodayScreenDriver: Sendable {
    public init() {}

    /// Deriva el estado de la pantalla "Hoy".
    public func derive(
        todayTemplate: SessionTemplate?,
        activeSession: WorkoutSessionRecord?,
        estimatedMinutes: Int? = nil
    ) -> TodayScreenState {
        if let activeSession, isLive(activeSession.lifecycle) {
            let presentation = presentation(for: todayTemplate, estimatedMinutes: estimatedMinutes)
            return .activeWorkout(presentation, isPaused: activeSession.lifecycle == .paused)
        }
        guard let template = todayTemplate, !template.plannedSets.isEmpty else {
            // Sin sesión activa y sin plantilla para hoy: día de descanso / sin sesión.
            return .restDay
        }
        return .readyToStart(
            presentation(for: template, estimatedMinutes: estimatedMinutes)
        )
    }

    /// Nº de sets de trabajo y de calentamiento de una plantilla (sin magia).
    public func setCounts(of template: SessionTemplate) -> (work: Int, warmup: Int) {
        var work = 0
        var warmup = 0
        for planned in template.plannedSets {
            if planned.prescription.isWarmup {
                warmup += 1
            } else {
                work += 1
            }
        }
        return (work, warmup)
    }

    // MARK: - Helpers

    private func presentation(
        for template: SessionTemplate?,
        estimatedMinutes: Int?
    ) -> SessionPresentation {
        guard let template else {
            return SessionPresentation(templateID: SessionTemplate.ID(), title: "", workSetCount: 0, warmupSetCount: 0)
        }
        let counts = setCounts(of: template)
        return SessionPresentation(
            templateID: template.id,
            title: template.title,
            workSetCount: counts.work,
            warmupSetCount: counts.warmup,
            estimatedMinutes: estimatedMinutes
        )
    }

    private func isLive(_ lifecycle: WorkoutLifecycleState) -> Bool {
        switch lifecycle {
        case .active, .paused, .preparing, .finishing: return true
        case .planned, .completed, .abandoned: return false
        }
    }
}