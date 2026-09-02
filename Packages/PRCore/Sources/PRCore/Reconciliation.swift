//
//  Reconciliation.swift
//  PRCore
//
//  Created by PR.
//
//  Workout reconciliation (plan §13 Fase 10, promptMaster §15, PR-1105).
//  Regla central (§15.1): NUNCA sumar energía de dos fuentes que describen el mismo
//  workout. Este motor agrupa candidatos que describen el mismo evento (overlap >= 80%,
//  tipo compatible) y produce UNA energía canónica por workout según prioridad §15.3,
//  sin doble contabilización y sin fabricar números (sólo se emite si hay energía real).
//  Determinista; PRCore no importa HealthKit.
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

/// Candidato a energía: una representación (posiblemente duplicada) de un workout.
/// Sólo transporta metadata; nunca fabrica sets (PR-1104).
public struct WorkoutEnergyCandidate: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var activityType: HealthWorkoutActivityType
    public var activeKilocalories: Double?
    public var source: EnergySource
    public var sourceName: String?

    public init(
        start: Date,
        end: Date,
        activityType: HealthWorkoutActivityType = .strengthTraining,
        activeKilocalories: Double? = nil,
        source: EnergySource,
        sourceName: String? = nil
    ) {
        self.start = start
        self.end = end
        self.activityType = activityType
        self.activeKilocalories = activeKilocalories
        self.source = source
        self.sourceName = sourceName
    }
}

/// Resolución de un workout: energía canónica (si existe) + si se deduplicaron candidatos.
public struct WorkoutEnergyResolution: Codable, Sendable, Hashable {
    public var energy: CanonicalWorkoutEnergy?
    /// Cuántos candidatos describían el mismo workout (>= 2 = hubo duplicados).
    public var candidateCount: Int
    /// Verdadero si > 1 candidato se agrupó en una única energía (no suma).
    public var deduplicated: Bool

    public init(energy: CanonicalWorkoutEnergy?, candidateCount: Int, deduplicated: Bool) {
        self.energy = energy
        self.candidateCount = candidateCount
        self.deduplicated = deduplicated
    }
}

/// Motor de reconciliación (plan §13, promptMaster §15).
///
/// Reglas deterministas:
/// - dos candidatos son DUPLICADO si `overlap / union >= overlapThreshold` (default 0.80)
///   Y tipo de actividad compatible;
/// - se agrupan los candidatos que describen el mismo evento;
/// - por grupo se elige UN su único energía de la fuente de mayor prioridad con energía real;
/// - grupos sin energía real no producen energía (no se inventa);
/// - dos workouts legítimos separados (no solapados) se mantienen como resoluciones distintas.
public struct WorkoutReconciliationEngine: Sendable {
    public var overlapThreshold: Double

    public init(overlapThreshold: Double = 0.80) {
        self.overlapThreshold = min(max(overlapThreshold, 0), 1)
    }

    /// ¿Los dos candidatos describen el mismo workout? (overlap matcher §15.4)
    public func areDuplicateCandidates(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Bool {
        guard a.activityType == b.activityType else { return false }
        return overlapRatio(a, b) >= overlapThreshold
    }

    /// Proporción de solapamiento temporal (intersección / unión), en 0...1.
    public func overlapRatio(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Double {
        let intersection = max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
        let union = max(a.end, b.end).timeIntervalSince(min(a.start, b.start))
        guard union > 0 else { return 0 }
        return intersection / union
    }

    /// Reconoce los candidatos y devuelve una resolución por workout único. No suma energía.
    public func reconcile(_ candidates: [WorkoutEnergyCandidate]) -> [WorkoutEnergyResolution] {
        // Agrupar los candidatos que describen el mismo workout (grafo de duplicados).
        let sorted = candidates.sorted { $0.start < $1.start }
        var clusters: [[WorkoutEnergyCandidate]] = []
        for candidate in sorted {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { areDuplicateCandidates($0, candidate) }
            }) {
                clusters[index].append(candidate)
            } else {
                clusters.append([candidate])
            }
        }
        return clusters.map { cluster in
            WorkoutEnergyResolution(
                energy: canonicalEnergy(for: cluster),
                candidateCount: cluster.count,
                deduplicated: cluster.count > 1
            )
        }
    }

    /// Elige la energía canónica de un cluster según prioridad §15.3, sin sumar.
    /// Devuelve nil si ningún candidato del cluster tiene energía real (no se inventa).
    private func canonicalEnergy(for cluster: [WorkoutEnergyCandidate]) -> CanonicalWorkoutEnergy? {
        let best = cluster
            .filter { $0.activeKilocalories != nil && $0.activeKilocalories! >= 0 }
            .min { $0.source.priority < $1.source.priority }
        guard let best, let kcal = best.activeKilocalories else { return nil }
        let source = best.source
        return CanonicalWorkoutEnergy(
            activeKilocalories: kcal,
            source: source,
            confidence: confidence(for: source)
        )
    }

    /// Confianza coherente con la fuente (no un score inventado): mejora con confiabilidad.
    private func confidence(for source: EnergySource) -> Double {
        switch source {
        case .ourHealthKitWorkout: return 1.0
        case .externalAppleWorkout: return 0.92
        case .externalHealthKitWorkout: return 0.85
        case .fallbackEstimate: return 0.5
        }
    }
}

/// Adapta `ExternalWorkout` (PR-1104) a un candidato de reconciliación.
extension ExternalWorkout {
    public func asCandidate(source: EnergySource) -> WorkoutEnergyCandidate {
        WorkoutEnergyCandidate(
            start: start,
            end: end,
            activityType: activityType,
            activeKilocalories: activeKilocalories,
            source: source,
            sourceName: sourceName ?? deviceName
        )
    }
}