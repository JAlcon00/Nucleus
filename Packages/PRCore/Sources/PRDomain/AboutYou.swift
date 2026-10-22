//
//  AboutYou.swift
//  PRDomain
//
//  "Sobre ti" (SCRUM-198, U5): nombre, edad, sexo, estatura y peso de la persona.
//  Minimización de datos (docs/ux/auditoria-ui-2026-10-22.md §4.5): sólo lo necesario y
//  para qué se usa. Se guarda SOLO en el dispositivo, dentro del perfil; no va a logs,
//  analytics ni al LLM y nunca se usa para calcular calorías. La edad se guarda como año
//  de nacimiento.
//  Política v1 (decisión de producto del 2026-10-21): edad mínima 18 años, porque el
//  motor de progresión no está validado para menores; con menos de 18 no se genera el plan.
//

import Foundation

/// Sexo declarado. Sólo para cargas iniciales de referencia; nunca cambia las reglas de
/// seguridad. "Prefiero no decir" es una respuesta completa.
public enum DeclaredSex: String, Codable, Sendable, CaseIterable, Hashable {
    case male
    case female
    case undisclosed
}

public enum AboutYouError: Error, Equatable, Sendable {
    case nameTooLong(Int)
    case invalidBirthYear(Int)
    case invalidAge(Int)
    case underMinimumAge(Int)
    case invalidHeight(Int)
    case invalidWeight(Double)
    case missingAnswer
}

/// Datos de la persona, ya validados.
public struct AboutYou: Codable, Sendable, Hashable {
    /// Edad mínima para generar un plan (política v1).
    public static let minimumAge = 18
    /// Edades que ofrece el selector (se muestran desde 16 para poder explicar el mínimo).
    public static let selectableAges: ClosedRange<Int> = 16...90
    /// Estatura aceptada en centímetros.
    public static let heightCentimetersRange: ClosedRange<Int> = 120...230
    /// Largo máximo del nombre (sólo se usa para saludar).
    public static let maxNameLength = 40

    /// Peso corporal aceptado según la unidad.
    public static func weightRange(for unit: LoadUnit) -> ClosedRange<Double> {
        switch unit {
        case .kilograms: return 30...300
        case .pounds: return 66...660
        }
    }

    /// Nombre para el saludo; `nil` si no se dio.
    public let name: String?
    public let birthYear: Int
    public let sex: DeclaredSex
    public let heightCentimeters: Int?
    /// Peso con un decimal, en `weightUnit`.
    public let weight: Double
    public let weightUnit: LoadUnit

    public init(
        name: String?,
        birthYear: Int,
        sex: DeclaredSex,
        heightCentimeters: Int?,
        weight: Double,
        weightUnit: LoadUnit
    ) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count <= Self.maxNameLength else { throw AboutYouError.nameTooLong(trimmed.count) }
        guard birthYear > 0 else { throw AboutYouError.invalidBirthYear(birthYear) }
        if let heightCentimeters, !Self.heightCentimetersRange.contains(heightCentimeters) {
            throw AboutYouError.invalidHeight(heightCentimeters)
        }
        let rounded = (weight * 10).rounded() / 10
        guard rounded.isFinite, Self.weightRange(for: weightUnit).contains(rounded) else {
            throw AboutYouError.invalidWeight(weight)
        }
        self.name = trimmed.isEmpty ? nil : trimmed
        self.birthYear = birthYear
        self.sex = sex
        self.heightCentimeters = heightCentimeters
        self.weight = rounded
        self.weightUnit = weightUnit
    }

    /// Edad en `date` (sólo se guarda el año: es la del cumpleaños de ese año).
    public func age(on date: Date, timeZone: TimeZone) -> Int {
        Self.year(of: date, timeZone: timeZone) - birthYear
    }

    /// Año de nacimiento para una edad elegida en `date`.
    public static func birthYear(forAge age: Int, on date: Date, timeZone: TimeZone) -> Int {
        year(of: date, timeZone: timeZone) - age
    }

    private static func year(of date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.year, from: date)
    }

    // MARK: Codable (valida al leer: un registro dañado no entra)

    private enum CodingKeys: String, CodingKey {
        case name, birthYear, sex, heightCentimeters, weight, weightUnit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name),
            birthYear: try container.decode(Int.self, forKey: .birthYear),
            sex: try container.decode(DeclaredSex.self, forKey: .sex),
            heightCentimeters: try container.decodeIfPresent(Int.self, forKey: .heightCentimeters),
            weight: try container.decode(Double.self, forKey: .weight),
            weightUnit: try container.decode(LoadUnit.self, forKey: .weightUnit)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(birthYear, forKey: .birthYear)
        try container.encode(sex, forKey: .sex)
        try container.encodeIfPresent(heightCentimeters, forKey: .heightCentimeters)
        try container.encode(weight, forKey: .weight)
        try container.encode(weightUnit, forKey: .weightUnit)
    }
}

/// "Sobre ti" mientras se llena: lo obligatorio puede faltar todavía. Nunca se rellena
/// con valores inventados (sin edad, sexo o peso no se puede continuar).
public struct AboutYouAnswer: Equatable, Sendable {
    public var name: String
    public var age: Int?
    public var sex: DeclaredSex?
    public var heightCentimeters: Int?
    public var weight: Double?
    public var weightUnit: LoadUnit

    public init(
        name: String = "",
        age: Int? = nil,
        sex: DeclaredSex? = nil,
        heightCentimeters: Int? = nil,
        weight: Double? = nil,
        weightUnit: LoadUnit = .kilograms
    ) {
        self.name = name
        self.age = age
        self.sex = sex
        self.heightCentimeters = heightCentimeters
        self.weight = weight
        self.weightUnit = weightUnit
    }

    /// Respuesta a partir de datos guardados (para editarlos).
    public init(_ aboutYou: AboutYou, on date: Date, timeZone: TimeZone) {
        self.init(
            name: aboutYou.name ?? "",
            age: aboutYou.age(on: date, timeZone: timeZone),
            sex: aboutYou.sex,
            heightCentimeters: aboutYou.heightCentimeters,
            weight: aboutYou.weight,
            weightUnit: aboutYou.weightUnit
        )
    }

    /// La edad elegida está por debajo del mínimo: se explica y no se genera el plan.
    public var isUnderMinimumAge: Bool {
        age.map { $0 < AboutYou.minimumAge } ?? false
    }

    /// ¿Se puede continuar? Edad (≥ mínimo), sexo y peso válidos; nombre y estatura opcionales.
    public var isComplete: Bool {
        guard let age, AboutYou.selectableAges.contains(age), !isUnderMinimumAge,
              sex != nil, let weight else { return false }
        if let heightCentimeters, !AboutYou.heightCentimetersRange.contains(heightCentimeters) { return false }
        let rounded = (weight * 10).rounded() / 10
        return AboutYou.weightRange(for: weightUnit).contains(rounded)
            && name.trimmingCharacters(in: .whitespacesAndNewlines).count <= AboutYou.maxNameLength
    }

    /// Valida y convierte (la edad pasa a año de nacimiento con la fecha inyectada).
    public func aboutYou(on date: Date, timeZone: TimeZone) throws -> AboutYou {
        guard let age, let sex, let weight else { throw AboutYouError.missingAnswer }
        guard AboutYou.selectableAges.contains(age) else { throw AboutYouError.invalidAge(age) }
        guard age >= AboutYou.minimumAge else { throw AboutYouError.underMinimumAge(age) }
        return try AboutYou(
            name: name,
            birthYear: AboutYou.birthYear(forAge: age, on: date, timeZone: timeZone),
            sex: sex,
            heightCentimeters: heightCentimeters,
            weight: weight,
            weightUnit: weightUnit
        )
    }
}
