//
//  HealthPrefill.swift
//  PRDomain
//
//  SCRUM-206 (IA-5): prellenar "Sobre ti" con datos de Apple Salud, si el usuario lo pide.
//
//  Contrato:
//  - Sólo se LEEN fecha de nacimiento, sexo, estatura y peso; nada se escribe en Salud.
//  - Cada valor pasa por los mismos rangos de `AboutYou`; uno fuera de rango se ignora
//    (el campo queda como estaba) y se informa como ignorado.
//  - Sólo se llenan los campos que Salud trae válidos; el nombre nunca se toca.
//  - Sexo "otro" o sin indicar en Salud no se adivina: lo elige la persona.
//  - Sin datos utilizables es "sin datos": el formulario manual sigue igual.
//

import Foundation

/// Sexo biológico tal como lo reporta Salud (independiente de HealthKit).
public enum HealthBiologicalSex: String, Sendable, Hashable, CaseIterable {
    case female
    case male
    case other
    case notSet
}

/// Lo que se leyó de Salud. Cualquier campo puede faltar.
public struct HealthProfileSample: Sendable, Equatable {
    public var birthDate: DateComponents?
    public var biologicalSex: HealthBiologicalSex?
    public var heightMeters: Double?
    public var weightKilograms: Double?

    public init(
        birthDate: DateComponents? = nil,
        biologicalSex: HealthBiologicalSex? = nil,
        heightMeters: Double? = nil,
        weightKilograms: Double? = nil
    ) {
        self.birthDate = birthDate
        self.biologicalSex = biologicalSex
        self.heightMeters = heightMeters
        self.weightKilograms = weightKilograms
    }

    public static let empty = HealthProfileSample()
}

/// Campos de "Sobre ti" que Salud puede llenar.
public enum AboutYouHealthField: String, Sendable, Hashable, CaseIterable {
    case age
    case sex
    case height
    case weight
}

/// Resultado de aplicar una lectura de Salud al borrador.
public struct HealthPrefillResult: Sendable, Equatable {
    public let answer: AboutYouAnswer
    /// Campos que se llenaron.
    public let filled: Set<AboutYouHealthField>
    /// Campos que Salud trajo pero fuera de rango (se dejaron como estaban).
    public let ignored: Set<AboutYouHealthField>

    public init(answer: AboutYouAnswer, filled: Set<AboutYouHealthField>, ignored: Set<AboutYouHealthField>) {
        self.answer = answer
        self.filled = filled
        self.ignored = ignored
    }
}

/// Convierte una lectura de Salud en el borrador de "Sobre ti". Pura y determinista.
public struct HealthPrefillMapper: Sendable {
    public init() {}

    public func prefill(
        _ answer: AboutYouAnswer,
        with sample: HealthProfileSample,
        on date: Date,
        timeZone: TimeZone
    ) -> HealthPrefillResult {
        var result = answer
        var filled: Set<AboutYouHealthField> = []
        var ignored: Set<AboutYouHealthField> = []

        if let birthYear = sample.birthDate?.year {
            // Misma regla que `AboutYou` (guarda sólo el año): así el año de nacimiento
            // guardado es exactamente el de Salud.
            let age = AboutYou.birthYear(forAge: 0, on: date, timeZone: timeZone) - birthYear
            if AboutYou.selectableAges.contains(age) {
                result.age = age
                filled.insert(.age)
            } else {
                ignored.insert(.age)
            }
        }

        switch sample.biologicalSex {
        case .female:
            result.sex = .female
            filled.insert(.sex)
        case .male:
            result.sex = .male
            filled.insert(.sex)
        case .other, .notSet, nil:
            break
        }

        if let meters = sample.heightMeters {
            let centimeters = meters.isFinite ? Int((meters * 100).rounded()) : -1
            if AboutYou.heightCentimetersRange.contains(centimeters) {
                result.heightCentimeters = centimeters
                filled.insert(.height)
            } else {
                ignored.insert(.height)
            }
        }

        if let kilograms = sample.weightKilograms {
            let value: Double
            switch answer.weightUnit {
            case .kilograms: value = kilograms
            case .pounds: value = kilograms * AboutYou.poundsPerKilogram
            }
            let rounded = (value * 10).rounded() / 10
            if rounded.isFinite, AboutYou.weightRange(for: answer.weightUnit).contains(rounded) {
                result.weight = rounded
                filled.insert(.weight)
            } else {
                ignored.insert(.weight)
            }
        }

        return HealthPrefillResult(answer: result, filled: filled, ignored: ignored)
    }
}

extension AboutYou {
    /// Libras por kilogramo (definición exacta: 1 lb = 0.45359237 kg).
    public static let poundsPerKilogram = 1 / 0.45359237
}
