//
//  LoadHistory.swift
//  PRDomain
//
//  Created by PR.
//
//  Per-machine load history (plan §9, RF-013, PR-0906). Mantiene un estimado EWMA de
//  carga por clave `exercise + machineInstance` (§6.5) a partir de sets completados
//  que reportan su instancia de máquina. Al sustituir, recupera el historial del
//  SUSTITUTO en su propia máquina — nunca transfiere la carga del ejercicio original.
//  Determinista y auditable.
//

import Foundation

/// Perfil EWMA de carga por máquina (espejo de `ExerciseDurationProfile`, PR-0801).
public struct MachineLoadProfile: Codable, Hashable, Sendable {
    /// Media exponencial ponderada (kg/lb) de la carga en esa máquina.
    public var averageLoad: Double
    /// Unidad de la carga.
    public var unit: LoadUnit
    /// Nº de muestras observadas.
    public var sampleCount: Int
    /// Confianza (0...1): crece con las muestras (misma curva logística que duración).
    public var confidence: Double

    public init(averageLoad: Double, unit: LoadUnit, sampleCount: Int, confidence: Double? = nil) {
        self.averageLoad = averageLoad
        self.unit = unit
        self.sampleCount = sampleCount
        self.confidence = confidence ?? Self.confidence(forSampleCount: sampleCount)
    }

    /// Confianza logística simple: ~0 con pocas muestras, →1 al acumular.
    public static func confidence(forSampleCount n: Int, k: Double = 10) -> Double {
        guard n >= 0 else { return 0 }
        return Double(n) / (Double(n) + k)
    }
}

/// Errores del historial por máquina.
public enum MachineLoadHistoryError: Error, Equatable, Sendable {
    /// Un set sin instancia de máquina no puede generar una clave de historial por máquina.
    case setLacksMachineProfile
    case invalidLoad(Double)
}

/// Historial de carga por máquina (plan §9, RF-013, PR-0906).
///
/// Reglas deterministas:
/// - `record` actualiza el perfil EWMA de la clave `(exercise + machineInstance)`
///   correspondiente al set completado. Requiere `SetRecord.machineProfileID`.
/// - `weight(forMachine:exercise:)` devuelve el estimado del SUSTITUTO en su propia
///   máquina; si no hay historial, devuelve `nil`. NUNCA cae a la carga del ejercicio
///   original (la clave usa el `exerciseID` del sustituto).
/// - La clave `MachineLoadHistoryKey` es `exercise + machineInstanceID` (§6.5): la
///   carga de dos máquinas del mismo tipo NO es intercambiable.
public struct MachineLoadHistoryService: Sendable {
    /// Suavizado EWMA para una observación nueva (α más pequeño con más muestras).
    public var smoothingBase: Double
    /// Estado persistible: perfiles por clave de historial.
    public var profiles: [MachineLoadHistoryKey: MachineLoadProfile]

    public init(
        smoothingBase: Double = 2.0,
        profiles: [MachineLoadHistoryKey: MachineLoadProfile] = [:]
    ) throws {
        for (key, profile) in profiles {
            guard profile.averageLoad.isFinite, profile.averageLoad >= 0 else {
                throw MachineLoadHistoryError.invalidLoad(profile.averageLoad)
            }
            _ = key
        }
        self.smoothingBase = smoothingBase
        self.profiles = profiles
    }

    /// Carga desde el historial de una máquina concreta (`nil` si aún no hay muestras).
    public func weight(forExercise exerciseID: ExerciseID, onMachine machineID: MachineProfileID) -> Double? {
        let key = MachineLoadHistoryKey(exerciseID: exerciseID, machineInstanceID: machineID)
        return profiles[key]?.averageLoad
    }

    /// Carga del historial del SUSTITUTO en su propia máquina. Usa el `exerciseID`
    /// del sustituto en la clave, por lo que es imposible transferir la carga del
    /// original. Devuelve `nil` si no hay historial propio del sustituto.
    public func weightForSubstitute(
        _ substituteExercise: Exercise,
        onMachine machine: MachineProfile
    ) -> MachineLoadProfile? {
        let key = MachineLoadHistoryKey(
            exerciseID: substituteExercise.id,
            machineInstanceID: machine.id
        )
        return profiles[key]
    }

    /// Registra un set completado en el historial de su instancia de máquina (EWMA).
    /// Devuelve el nuevo estado de perfiles para persistir.
    public func record(_ set: SetRecord) throws -> [MachineLoadHistoryKey: MachineLoadProfile] {
        guard let machineID = set.machineProfileID else {
            throw MachineLoadHistoryError.setLacksMachineProfile
        }
        guard set.weight.isFinite, set.weight >= 0 else {
            throw MachineLoadHistoryError.invalidLoad(set.weight)
        }
        let key = MachineLoadHistoryKey(
            exerciseID: set.exerciseID,
            machineInstanceID: MachineProfileID(rawValue: machineID)
        )
        let current = profiles[key]
        let updated = Self.ewma(
            observation: set.weight,
            unit: set.unit,
            current: current,
            smoothingBase: smoothingBase
        )
        var next = profiles
        next[key] = updated
        return next
    }

    /// Reconstruye el servicio con un estado de perfiles persistido.
    public func replacing(profiles: [MachineLoadHistoryKey: MachineLoadProfile]) throws -> MachineLoadHistoryService {
        try MachineLoadHistoryService(smoothingBase: smoothingBase, profiles: profiles)
    }

    // MARK: - EWMA

    private static func ewma(
        observation: Double,
        unit: LoadUnit,
        current: MachineLoadProfile?,
        smoothingBase: Double
    ) -> MachineLoadProfile {
        let priorCount = current?.sampleCount ?? 0
        let alpha = 1.0 / (smoothingBase + Double(priorCount))
        let priorAverage = current?.averageLoad ?? observation
        let newAverage = alpha * observation + (1 - alpha) * priorAverage
        let newCount = priorCount + 1
        return MachineLoadProfile(
            averageLoad: newAverage,
            unit: unit,
            sampleCount: newCount,
            confidence: MachineLoadProfile.confidence(forSampleCount: newCount)
        )
    }
}