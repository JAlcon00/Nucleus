//
//  HealthPrefillCoordinator.swift
//  PRCore
//
//  SCRUM-206 (IA-5): botón opcional "Usar datos de Salud" en "Sobre ti". Lee Salud a
//  través de un lector inyectado (HealthKit en la app, simulado en tests), convierte con
//  `HealthPrefillMapper` y deja un estado claro para cada caso. Nunca bloquea el
//  formulario: sin permiso, sin datos o sin Salud, se sigue a mano.
//

import Foundation
import Observation
import PRDomain

/// Resultado de leer Salud.
public enum HealthReadResult: Sendable, Equatable {
    case sample(HealthProfileSample)
    /// La persona negó el permiso (cuando Salud lo informa; por privacidad, a veces sólo
    /// llega sin datos).
    case denied
    /// Salud no está disponible en este dispositivo o falló la lectura.
    case unavailable
}

/// Quien lee Salud. Sólo lectura: nunca escribe.
public protocol HealthProfileReading: Sendable {
    func readProfile() async -> HealthReadResult
}

/// Estado del botón "Usar datos de Salud".
public enum HealthPrefillState: Sendable, Equatable {
    case idle
    case loading
    /// Se llenaron `filled` campos; `ignored` venían fuera de rango.
    case filled(filled: Int, ignored: Int)
    /// Salud no trajo nada utilizable (o el permiso se negó sin avisar).
    case noData
    case denied
    case unavailable
}

@MainActor
@Observable
public final class HealthPrefillCoordinator {
    public private(set) var state: HealthPrefillState = .idle

    private let reader: (any HealthProfileReading)?
    private let mapper = HealthPrefillMapper()
    private let clock: () -> Date
    private let timeZone: () -> TimeZone

    public init(
        reader: (any HealthProfileReading)?,
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.reader = reader
        self.clock = clock
        self.timeZone = timeZone
    }

    /// ¿Se ofrece el botón? (sin lector, p. ej. en pruebas de UI, no se muestra).
    public var isOffered: Bool { reader != nil }

    /// Lee Salud y devuelve el borrador con lo que se pudo llenar (o el mismo si nada).
    /// Un segundo toque mientras carga no lanza otra lectura.
    public func prefill(_ answer: AboutYouAnswer) async -> AboutYouAnswer {
        guard let reader, state != .loading else { return answer }
        state = .loading
        switch await reader.readProfile() {
        case .denied:
            state = .denied
            return answer
        case .unavailable:
            state = .unavailable
            return answer
        case .sample(let sample):
            let result = mapper.prefill(answer, with: sample, on: clock(), timeZone: timeZone())
            state = result.filled.isEmpty ? .noData : .filled(filled: result.filled.count, ignored: result.ignored.count)
            return result.answer
        }
    }

    /// Olvida el aviso (p. ej. al cerrar la pantalla).
    public func reset() {
        state = .idle
    }
}
