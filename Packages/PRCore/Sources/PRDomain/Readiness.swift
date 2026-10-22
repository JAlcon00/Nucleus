//
//  Readiness.swift
//  PRDomain
//
//  SCRUM-203 (IA-2): check-in diario de sueño y ajuste del entrenamiento del día.
//
//  Regla (determinista, sin LLM; números en `ReadinessPolicyConfig`):
//  - Sin check-in, o con sueño suficiente y bueno: el día no cambia.
//  - Sueño corto (< 6 h) o malo: el día se aligera. RIR +1 en todas las series de
//    trabajo y una serie menos en cada aislado que tenga más de una. Los compuestos
//    conservan sus series: son los que sostienen la progresión.
//  - Nunca sube la carga ni cambia las repeticiones: un check-in sólo puede aligerar.
//  - El bloque guardado no se toca: el ajuste es sólo de la sesión de hoy y conserva su
//    ID (si la app se cierra a mitad del entrenamiento se retoma la misma sesión).
//

import Foundation

/// Cómo durmió la persona, en sus palabras.
public enum SleepQuality: String, Codable, Sendable, CaseIterable, Hashable {
    case good
    case poor
}

public enum SleepCheckInError: Error, Equatable, Sendable {
    case invalidHours(Double)
}

/// Check-in de un día: horas dormidas y si durmió bien.
public struct SleepCheckIn: Codable, Sendable, Hashable {
    /// Horas posibles (con media hora de precisión en la UI).
    public static let hoursRange: ClosedRange<Double> = 0...16

    /// Día local del check-in ("2026-10-22"): uno por día.
    public let day: String
    public let hours: Double
    public let quality: SleepQuality

    public init(day: String, hours: Double, quality: SleepQuality) throws {
        guard hours.isFinite, Self.hoursRange.contains(hours) else { throw SleepCheckInError.invalidHours(hours) }
        self.day = day
        self.hours = hours
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey { case day, hours, quality }

    /// Un check-in leído del disco pasa por la misma validación que uno nuevo.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            day: try container.decode(String.self, forKey: .day),
            hours: try container.decode(Double.self, forKey: .hours),
            quality: try container.decode(SleepQuality.self, forKey: .quality)
        )
    }

    /// Día local de una fecha, en el formato de `day`.
    public static func day(of date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// Parámetros de la regla de disposición.
public struct ReadinessPolicyConfig: Sendable, Equatable {
    /// Menos horas que esto cuenta como sueño corto.
    public var shortSleepHours: Double
    /// Cuánto sube el RIR en un día ligero.
    public var rirIncrease: Int
    /// Cuántas series de trabajo se quitan a cada aislado (siempre queda al menos una).
    public var isolationSetReduction: Int

    public init(shortSleepHours: Double = 6, rirIncrease: Int = 1, isolationSetReduction: Int = 1) {
        self.shortSleepHours = shortSleepHours
        self.rirIncrease = rirIncrease
        self.isolationSetReduction = isolationSetReduction
    }

    public static let standard = ReadinessPolicyConfig()
}

/// Por qué se aligera el día.
public enum ReadinessReason: String, Codable, Sendable, CaseIterable, Hashable {
    case shortSleep
    case poorSleep
    case shortAndPoorSleep
}

/// Ajuste del día decidido por el motor.
public enum ReadinessAdjustment: Sendable, Hashable {
    case none
    case lighter(reason: ReadinessReason, rirIncrease: Int, isolationSetReduction: Int)
}

/// Decide y aplica el ajuste del día. Puro y determinista.
public struct ReadinessEngine: Sendable {
    public let config: ReadinessPolicyConfig

    public init(config: ReadinessPolicyConfig = .standard) {
        self.config = config
    }

    public func adjustment(for checkIn: SleepCheckIn?) -> ReadinessAdjustment {
        guard let checkIn else { return .none }
        let short = checkIn.hours < config.shortSleepHours
        let poor: Bool
        switch checkIn.quality {
        case .good: poor = false
        case .poor: poor = true
        }
        let reason: ReadinessReason
        switch (short, poor) {
        case (false, false): return .none
        case (true, false): reason = .shortSleep
        case (false, true): reason = .poorSleep
        case (true, true): reason = .shortAndPoorSleep
        }
        return .lighter(reason: reason, rirIncrease: config.rirIncrease, isolationSetReduction: config.isolationSetReduction)
    }

    /// Sesión de hoy con el ajuste aplicado. Mismo ID y título; carga y repeticiones
    /// intactas. `jointClass` dice qué ejercicios son aislados (del catálogo).
    public func apply(
        _ adjustment: ReadinessAdjustment,
        to template: SessionTemplate,
        jointClass: (ExerciseID) -> JointClass?
    ) -> SessionTemplate {
        switch adjustment {
        case .none:
            return template
        case .lighter(_, let rirIncrease, let isolationSetReduction):
            var toRemove: [ExerciseID: Int] = [:]
            var workSets: [ExerciseID: Int] = [:]
            for planned in template.plannedSets where !planned.prescription.isWarmup {
                workSets[planned.exerciseID, default: 0] += 1
            }
            for (exerciseID, count) in workSets where jointClass(exerciseID) == .singleJoint {
                toRemove[exerciseID] = min(isolationSetReduction, count - 1)
            }
            var kept: [PlannedSet] = []
            // Se quitan las últimas series de trabajo de cada aislado (se recorre al revés).
            for planned in template.plannedSets.reversed() {
                if !planned.prescription.isWarmup, let remaining = toRemove[planned.exerciseID], remaining > 0 {
                    toRemove[planned.exerciseID] = remaining - 1
                    continue
                }
                var adjusted = planned
                if !planned.prescription.isWarmup, let rir = planned.prescription.targetRIR {
                    adjusted.prescription.targetRIR = (rir.lowerBound + rirIncrease)...(rir.upperBound + rirIncrease)
                }
                kept.append(adjusted)
            }
            var result = template
            result.plannedSets = kept.reversed()
            return result
        }
    }
}
