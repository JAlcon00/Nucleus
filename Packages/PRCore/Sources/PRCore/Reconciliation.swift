//
//  Reconciliation.swift
//  PRCore
//
//  Created by PR.
//
//  Workout reconciliation (plan §13 Fase 10, promptMaster §15, PR-1105).
//  Regla central (§15.1): NUNCA sumar energía de dos fuentes que describen el mismo
//  workout. Este motor agrupa candidatos que describen el mismo evento (solapamiento sobre
//  el más corto, o inicio y fin dentro de la tolerancia, con tipo compatible; SCRUM-245) y
//  produce UNA energía canónica por workout según prioridad §15.3, sin doble contabilización
//  y sin fabricar números (sólo se emite si hay energía real). Umbral, tolerancia y
//  confianza salen de la regla versionada (`ReconciliationRule.swift`).
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
    /// Identificador estable de la fuente: desempata a igual prioridad y duración (SCRUM-245).
    public var identifier: String
    public var start: Date
    public var end: Date
    public var activityType: HealthWorkoutActivityType
    public var activeKilocalories: Double?
    public var source: EnergySource
    public var sourceName: String?

    public init(
        identifier: String = "",
        start: Date,
        end: Date,
        activityType: HealthWorkoutActivityType = .strengthTraining,
        activeKilocalories: Double? = nil,
        source: EnergySource,
        sourceName: String? = nil
    ) {
        self.identifier = identifier
        self.start = start
        self.end = end
        self.activityType = activityType
        self.activeKilocalories = activeKilocalories
        self.source = source
        self.sourceName = sourceName
    }

    /// Un candidato sin duración, o con el fin antes del inicio, no describe un entrenamiento.
    var hasValidInterval: Bool { end > start }

    var durationSeconds: TimeInterval { end.timeIntervalSince(start) }

    /// La energía sólo si es real: ni negativa, ni `NaN`, ni infinita. Cero sí es real.
    var realKilocalories: Double? {
        guard let activeKilocalories, activeKilocalories.isFinite, activeKilocalories >= 0 else {
            return nil
        }
        return activeKilocalories
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
/// - dos candidatos son DUPLICADO si tienen tipo compatible, comparten tiempo y además el
///   solapamiento sobre el más corto llega al umbral, o su inicio y su fin están dentro de
///   la tolerancia (§15.4). Sobre el más corto, un entrenamiento dentro de otro es el mismo:
///   es la opción que no duplica energía;
/// - se agrupan por componentes conexas: si A coincide con B y B con C, los tres son uno;
/// - por grupo gana la fuente de mayor prioridad con energía real; a igual prioridad, el de
///   mayor duración, y si empatan, el de menor identificador. Nunca se suma;
/// - grupos sin energía real no producen energía (no se inventa);
/// - un candidato sin duración o con el fin antes del inicio se ignora: no se une a nada ni
///   aporta energía;
/// - el resultado no depende del orden de entrada.
public struct WorkoutReconciliationEngine: Sendable {
    public let configuration: WorkoutReconciliationConfiguration

    public init(configuration: WorkoutReconciliationConfiguration = .standard) {
        self.configuration = configuration
    }

    /// ¿Los dos candidatos describen el mismo workout? (overlap matcher §15.4)
    public func areDuplicateCandidates(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Bool {
        guard areCompatible(a.activityType, b.activityType) else { return false }
        let ratio = overlapRatio(a, b)
        guard ratio > 0 else { return false }
        return ratio >= configuration.overlapThreshold || endpointsAreWithinTolerance(a, b)
    }

    /// Proporción de solapamiento temporal sobre el más corto, en 0...1.
    public func overlapRatio(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Double {
        guard a.hasValidInterval, b.hasValidInterval else { return 0 }
        let intersection = max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
        return intersection / min(a.durationSeconds, b.durationSeconds)
    }

    /// Reconoce los candidatos y devuelve una resolución por workout único. No suma energía.
    public func reconcile(_ candidates: [WorkoutEnergyCandidate]) -> [WorkoutEnergyResolution] {
        let valid = candidates.filter(\.hasValidInterval).sorted(by: isOrderedBefore)
        return clusters(of: valid).map { cluster in
            WorkoutEnergyResolution(
                energy: canonicalEnergy(for: cluster),
                candidateCount: cluster.count,
                deduplicated: cluster.count > 1
            )
        }
    }

    private func endpointsAreWithinTolerance(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Bool {
        let tolerance = configuration.endpointToleranceSeconds
        return abs(a.start.timeIntervalSince(b.start)) <= tolerance
            && abs(a.end.timeIntervalSince(b.end)) <= tolerance
    }

    /// Tipos que pueden describir el mismo entrenamiento (§15.4).
    private func areCompatible(_ a: HealthWorkoutActivityType, _ b: HealthWorkoutActivityType) -> Bool {
        family(of: a) == family(of: b)
    }

    private enum ActivityFamily {
        case strength
        case running
        case other
    }

    private func family(of type: HealthWorkoutActivityType) -> ActivityFamily {
        switch type {
        case .strengthTraining, .functionalStrengthTraining: return .strength
        case .running: return .running
        case .other: return .other
        }
    }

    /// Orden total de entrada: lo que hace que la salida no dependa del orden recibido.
    private func isOrderedBefore(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Bool {
        (a.start, a.end, a.source.priority, a.identifier, a.realKilocalories ?? -1, a.activityType.rawValue)
            < (b.start, b.end, b.source.priority, b.identifier, b.realKilocalories ?? -1, b.activityType.rawValue)
    }

    /// Componentes conexas del grafo de duplicados, en el orden de `sorted`.
    private func clusters(of sorted: [WorkoutEnergyCandidate]) -> [[WorkoutEnergyCandidate]] {
        var visited = Set<Int>()
        var clusters: [[WorkoutEnergyCandidate]] = []
        for seed in sorted.indices where !visited.contains(seed) {
            visited.insert(seed)
            var pending = [seed]
            var cluster: [WorkoutEnergyCandidate] = []
            while let current = pending.popLast() {
                cluster.append(sorted[current])
                for other in sorted.indices where !visited.contains(other) {
                    if areDuplicateCandidates(sorted[current], sorted[other]) {
                        visited.insert(other)
                        pending.append(other)
                    }
                }
            }
            clusters.append(cluster)
        }
        return clusters
    }

    /// Elige la energía canónica de un cluster según prioridad §15.3, sin sumar.
    /// Devuelve nil si ningún candidato del cluster tiene energía real (no se inventa).
    private func canonicalEnergy(for cluster: [WorkoutEnergyCandidate]) -> CanonicalWorkoutEnergy? {
        let best = cluster
            .filter { $0.realKilocalories != nil }
            .min(by: winsOver)
        guard let best, let kcal = best.realKilocalories else { return nil }
        return CanonicalWorkoutEnergy(
            activeKilocalories: kcal,
            source: best.source,
            confidence: configuration.confidence(for: best.source)
        )
    }

    /// Prioridad, después mayor duración, después menor identificador. La energía sólo
    /// desempata candidatos sin identificador, para que el orden siga siendo total.
    private func winsOver(_ a: WorkoutEnergyCandidate, _ b: WorkoutEnergyCandidate) -> Bool {
        (a.source.priority, -a.durationSeconds, a.identifier, a.realKilocalories ?? 0)
            < (b.source.priority, -b.durationSeconds, b.identifier, b.realKilocalories ?? 0)
    }
}

/// Adapta `ExternalWorkout` (PR-1104) a un candidato de reconciliación.
extension ExternalWorkout {
    public func asCandidate(source: EnergySource) -> WorkoutEnergyCandidate {
        WorkoutEnergyCandidate(
            identifier: referenceID.rawValue.uuidString,
            start: start,
            end: end,
            activityType: activityType,
            activeKilocalories: activeKilocalories,
            source: source,
            sourceName: sourceName ?? deviceName
        )
    }
}