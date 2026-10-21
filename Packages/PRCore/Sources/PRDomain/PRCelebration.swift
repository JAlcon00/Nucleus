//
//  PRCelebration.swift
//  PRDomain
//
//  Created by PR.
//
//  Celebración de récords personales (PR-1004, promptMaster §19). Decide de forma
//  determinista QUÉ se celebra a partir de los `PersonalRecord` ya detectados (nunca
//  inventa uno):
//  - una entrada por ejercicio (la mejor: mayor peso, luego más reps);
//  - unidad real del set (kg/lb), nunca asumida ni convertida;
//  - qué explicación corresponde según el nivel de coaching (§17.2).
//  No produce texto: el dominio devuelve hechos y `PRCelebrationPresenter` (PRCore) los
//  convierte en strings localizables (RNF-013).
//

import Foundation

/// Explicación educativa que acompaña la celebración según el nivel de coaching.
public enum PRCelebrationDetail: String, Codable, Sendable, Hashable {
    /// `guided`: qué es la sobrecarga progresiva y que el plan decide la próxima subida.
    case progressiveOverloadExplained
    /// `balanced`: una línea factual (superaste tu mejor carga registrada).
    case bestLoadSurpassed
}

/// Un récord a celebrar (hechos, sin texto).
public struct PRCelebrationItem: Equatable, Sendable, Identifiable {
    public var id: ExerciseID { exerciseID }
    public let exerciseID: ExerciseID
    /// Nombre canónico del catálogo; `nil` si el catálogo no lo tiene (no se inventa).
    public let exerciseName: String?
    public let weight: Double
    public let unit: LoadUnit
    public let reps: Int
}

/// Celebración decidida por el dominio (o ninguna si no hay récords).
public struct PRCelebration: Equatable, Sendable {
    /// Al menos un elemento: una celebración vacía no se construye.
    public let items: [PRCelebrationItem]
    /// `nil` en `advanced` (reduce explicaciones).
    public let detail: PRCelebrationDetail?
}

/// Construye la celebración de récords (PR-1004). Puro y determinista.
public struct PRCelebrationBuilder: Sendable {

    public init() {}

    public func celebration(
        for records: [PersonalRecord],
        exerciseNames: [ExerciseID: String] = [:],
        level: CoachingDetailLevel
    ) -> PRCelebration? {
        let best = bestPerExercise(records)
        guard !best.isEmpty else { return nil }
        let items = best.map { record in
            PRCelebrationItem(
                exerciseID: record.exerciseID,
                exerciseName: exerciseNames[record.exerciseID],
                weight: record.weight,
                unit: record.unit,
                reps: record.reps
            )
        }
        return PRCelebration(items: items, detail: detail(for: level))
    }

    // MARK: - Reglas

    /// Una entrada por ejercicio: mayor peso; empate → más reps; empate → más reciente.
    /// Orden de salida: por momento del récord y, en empate, por id (estable).
    /// Récords con peso no finito/negativo o reps < 1 se descartan (RC-003).
    private func bestPerExercise(_ records: [PersonalRecord]) -> [PersonalRecord] {
        var best: [ExerciseID: PersonalRecord] = [:]
        for record in records where record.weight.isFinite && record.weight >= 0 && record.reps >= 1 {
            guard let current = best[record.exerciseID] else {
                best[record.exerciseID] = record
                continue
            }
            if (record.weight, record.reps, record.achievedAt) > (current.weight, current.reps, current.achievedAt) {
                best[record.exerciseID] = record
            }
        }
        return best.values.sorted {
            if $0.achievedAt != $1.achievedAt { return $0.achievedAt < $1.achievedAt }
            return $0.exerciseID.rawValue.uuidString < $1.exerciseID.rawValue.uuidString
        }
    }

    /// Educación contextual (§17.2): explicar el concepto cuando sucede, menos en avanzado.
    private func detail(for level: CoachingDetailLevel) -> PRCelebrationDetail? {
        switch level {
        case .guided: return .progressiveOverloadExplained
        case .balanced: return .bestLoadSurpassed
        case .advanced: return nil
        }
    }
}
