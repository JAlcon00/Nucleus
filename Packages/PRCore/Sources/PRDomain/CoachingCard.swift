//
//  CoachingCard.swift
//  PRDomain
//
//  Created by PR.
//
//  Tarjeta de educación contextual durante el entrenamiento (PR-1501). Modelo puro,
//  determinista y SIN diagnóstico: una tarjeta tiene un id ESTABLE (para ser
//  descartable por la UI) y un cuerpo derivado de hechos de contexto reales del
//  dominio (calentamiento, descanso, recomendación de molestia). El nivel de detalle
//  (guided/balanced/advanced) lo determina `CoachingCardDriver`.
//

import Foundation

/// Id ESTABLE de una tarjeta de coaching (la UI puede descartarla de forma durable).
public struct CoachingCardID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Categoría de la tarjeta (para que la UI la distinga visualmente, sin reglas).
public enum CoachingCardKind: String, Codable, Sendable, Hashable {
    /// Educación de calentamiento.
    case warmup
    /// Racional del descanso entre series.
    case rest
    /// Respuesta conservadora y segura ante molestia reportada (sin diagnóstico).
    case painSafety
}

/// Una tarjeta de educación contextual lista para presentar.
public struct CoachingCard: Equatable, Sendable {
    public let id: CoachingCardID
    public let kind: CoachingCardKind
    public let title: String
    public let message: String

    public init(id: CoachingCardID, kind: CoachingCardKind, title: String, message: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }
}