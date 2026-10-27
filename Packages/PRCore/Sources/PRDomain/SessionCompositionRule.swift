//
//  SessionCompositionRule.swift
//  PRDomain
//
//  SCRUM-218 (PR-B004): cuántos ejercicios lleva una sesión según los minutos del usuario
//  y cuántas series de trabajo tiene como mínimo cada uno. Constantes versionadas: cambiar
//  un número es cambiar la regla (sube `version`).
//
//  Decisiones de Jesús (2026-10-26):
//  - el tope del rango se cumple siempre; el mínimo, sólo si el volumen semanal alcanza con
//    2 series por ejercicio (el volumen no sube con el tiempo hasta la decisión D1);
//  - al recortar, nunca se quitan las anclas compuestas ni los músculos prioritarios;
//  - si eso protegido ya pasa del tope, se queda y la explicación lo dice.
//

import Foundation

public struct SessionCompositionRule: Sendable, Equatable {

    /// Hasta `maxMinutes` minutos por sesión, entre `exercises` ejercicios.
    public struct Bracket: Sendable, Equatable {
        public let maxMinutes: Int
        public let exercises: ClosedRange<Int>
    }

    /// Va en la explicación del bloque (`sessionComposition`).
    public let version: String
    /// En orden de minutos; por encima del último tramo se usa el último.
    public let brackets: [Bracket]
    /// Ninguna serie suelta: cada ejercicio tiene al menos estas series de trabajo.
    public let minimumWorkSets: Int
    /// Con objetivo fuerza, un ancla compuesta no baja de estas series al recortar.
    public let strengthAnchorMinimumSets: Int

    public static let standard = SessionCompositionRule(
        version: "pr-b004-v1",
        brackets: [
            Bracket(maxMinutes: 30, exercises: 3...4),
            Bracket(maxMinutes: 45, exercises: 4...5),
            Bracket(maxMinutes: 60, exercises: 5...7),
            Bracket(maxMinutes: 90, exercises: 7...9),
        ],
        minimumWorkSets: 2,
        strengthAnchorMinimumSets: 3
    )

    /// Rango de ejercicios por sesión para `minutes`.
    public func exerciseRange(forMinutes minutes: Int) -> ClosedRange<Int> {
        guard let last = brackets.last else { return 1...Int.max }
        return brackets.first { minutes <= $0.maxMinutes }?.exercises ?? last.exercises
    }
}
