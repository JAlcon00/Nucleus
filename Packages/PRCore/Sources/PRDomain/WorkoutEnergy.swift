//
//  WorkoutEnergy.swift
//  PRDomain
//
//  Energía de un entrenamiento (promptMaster §15). Vive en el dominio para que la sesión la
//  pueda guardar (SCRUM-250); las claves de `Codable` no cambian al mudarla de PRCore.
//

import Foundation

/// Fuente de la energía canónica (promptMaster §15.2). Orden de prioridad inversa al
/// `priority` (1 = más confiable). Véase §15.3.
public enum EnergySource: String, Codable, Sendable, CaseIterable, Hashable {
    /// Workout iniciado por PR con HealthKit/Apple Watch.
    case ourHealthKitWorkout
    /// Workout nativo Apple Watch.
    case externalAppleWorkout
    /// Otro HKWorkout confiable.
    case externalHealthKitWorkout
    /// Estimación fallback (etiquetada siempre como estimación).
    case fallbackEstimate

    /// Prioridad §15.3: menor número = más confiable.
    public var priority: Int {
        switch self {
        case .ourHealthKitWorkout: return 1
        case .externalAppleWorkout: return 2
        case .externalHealthKitWorkout: return 3
        case .fallbackEstimate: return 4
        }
    }
}

/// Energía canónica de un workout (promptMaster §15.2). Nunca se suma entre fuentes.
public struct CanonicalWorkoutEnergy: Codable, Sendable, Hashable {
    public var activeKilocalories: Double
    public var source: EnergySource
    /// Confianza 0...1 coherente con la fuente; no es un score inventado.
    public var confidence: Double

    public init(activeKilocalories: Double, source: EnergySource, confidence: Double) {
        self.activeKilocalories = activeKilocalories
        self.source = source
        self.confidence = confidence
    }
}

/// Algo que Salud registró y no es una sesión de Nucleus (DF-5): sólo contexto. No cuenta en
/// la racha, ni en el plan, ni en la recuperación, y nunca trae series.
public struct HealthActivity: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    /// Tipo de actividad, como lo clasificó la app.
    public let activity: String
    public let sourceName: String?
    public let energy: CanonicalWorkoutEnergy?

    public init(
        id: UUID,
        start: Date,
        end: Date,
        activity: String,
        sourceName: String?,
        energy: CanonicalWorkoutEnergy?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.activity = activity
        self.sourceName = sourceName
        self.energy = energy
    }

    public var durationSeconds: Int { Int(max(0, end.timeIntervalSince(start))) }
}
