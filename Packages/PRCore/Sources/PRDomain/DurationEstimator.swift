//
//  DurationEstimator.swift
//  PRDomain
//
//  Created by PR.
//
//  Duration estimator (plan §8, RF-006, PR-0801). Estima la duración de una sesión
//  desde defaults por set/rest/transición/categoría, y actualiza un perfil personal
//  (EWMA) con workouts completados: la confianza crece con las muestras y el motor
//  favorece los tiempos personales sobre los defaults cuando la confianza es
//  suficiente. Determinista; no depende de una API.
//

import Foundation

/// Perfil EWMA de duración por ejercicio del usuario (promptMaster §11).
public struct ExerciseDurationProfile: Codable, Hashable, Sendable {
    /// Media exponencial ponderada (segundos) del tiempo por set del ejercicio.
    public var averageSeconds: Double
    /// Nº de muestras observadas.
    public var sampleCount: Int
    /// Confianza (0...1): crece con las muestras.
    public var confidence: Double

    public init(averageSeconds: Double, sampleCount: Int, confidence: Double? = nil) {
        self.averageSeconds = averageSeconds
        self.sampleCount = sampleCount
        self.confidence = confidence ?? Self.confidence(forSampleCount: sampleCount)
    }

    /// Confianza logística simple: ~0 con pocas muestras, →1 al acumular.
    public static func confidence(forSampleCount n: Int, k: Double = 10) -> Double {
        guard n >= 0 else { return 0 }
        return Double(n) / (Double(n) + k)
    }
}

/// Defaults de duración (ciencia-base, referenciados; PR-0801).
public struct DurationDefaults: Sendable {
    /// Segundos por set de trabajo por defecto (categoría genérica).
    public var defaultSetSeconds: Double
    /// Segundos de transición/descanso entre sets.
    public var defaultTransitionSeconds: Double
    /// Multiplicador aplicado a sets de calentamiento (más rápido).
    public var warmupMultiplier: Double
    /// Segundos por set por defecto por ejercicio (override).
    public var perExerciseSeconds: [ExerciseID: Double]
    /// Umbral de confianza (0...1) a partir del cual se prefiere el tiempo personal.
    public var personalThreshold: Double

    public init(
        defaultSetSeconds: Double = 60,
        defaultTransitionSeconds: Double = 30,
        warmupMultiplier: Double = 0.6,
        perExerciseSeconds: [ExerciseID: Double] = [:],
        personalThreshold: Double = 0.5
    ) {
        self.defaultSetSeconds = defaultSetSeconds
        self.defaultTransitionSeconds = defaultTransitionSeconds
        self.warmupMultiplier = warmupMultiplier
        self.perExerciseSeconds = perExerciseSeconds
        self.personalThreshold = personalThreshold
    }
}

/// Estima y aprende la duración (PR-0801).
public struct DurationEstimator: Sendable {
    public var defaults: DurationDefaults
    /// Suavizado EWMA para una observación nueva (α más pequeño con más muestras).
    public var smoothingBase: Double

    public init(defaults: DurationDefaults = DurationDefaults(), smoothingBase: Double = 2.0) {
        self.defaults = defaults
        self.smoothingBase = smoothingBase
    }

    /// ¿Preferir el tiempo personal sobre el default para este perfil?
    public func shouldPreferPersonal(_ profile: ExerciseDurationProfile?) -> Bool {
        guard let profile else { return false }
        return profile.confidence >= defaults.personalThreshold
    }

    /// Duración (segundos) por set para un ejercicio, usando perfil personal si la
    /// confianza es suficiente, si no el default (per-exercise o genérico).
    public func setDuration(for exercise: ExerciseID, profile: ExerciseDurationProfile?) -> Double {
        if shouldPreferPersonal(profile), let profile {
            return profile.averageSeconds
        }
        return defaults.perExerciseSeconds[exercise] ?? defaults.defaultSetSeconds
    }

    /// Estima la duración de una sesión a partir de sus sets planeados.
    /// Devuelve segundos (enteros, mín. 0).
    public func estimate(
        plannedSets: [PlannedSet],
        profiles: [ExerciseID: ExerciseDurationProfile] = [:]
    ) -> Int {
        var total = 0.0
        for (index, planned) in plannedSets.enumerated() {
            let prescription = planned.prescription
            let profile = profiles[planned.exerciseID]
            let perSet = setDuration(for: planned.exerciseID, profile: profile)
            let warmupFactor = prescription.isWarmup ? defaults.warmupMultiplier : 1.0
            total += perSet * warmupFactor
            // Descanso tras cada set salvo que sea el último (separado por transición).
            let rest = Double(prescription.restSeconds.lowerBound)
            total += rest
            if index < plannedSets.count - 1 {
                total += defaults.defaultTransitionSeconds
            }
        }
        return Int(total.rounded())
    }

    /// Aprende EWMA a partir de una observación real (segundos por set de un
    /// workout completado). La confianza crece con el nº de muestras.
    public func record(
        observationSecondsPerSet: Double,
        current: ExerciseDurationProfile?
    ) -> ExerciseDurationProfile {
        let priorCount = current?.sampleCount ?? 0
        let alpha = 1.0 / (smoothingBase + Double(priorCount))
        let priorAverage = current?.averageSeconds ?? observationSecondsPerSet
        let newAverage = alpha * observationSecondsPerSet + (1 - alpha) * priorAverage
        let newCount = priorCount + 1
        return ExerciseDurationProfile(
            averageSeconds: newAverage,
            sampleCount: newCount,
            confidence: ExerciseDurationProfile.confidence(forSampleCount: newCount)
        )
    }
}