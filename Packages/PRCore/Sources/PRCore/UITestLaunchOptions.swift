//
//  UITestLaunchOptions.swift
//  PRCore
//
//  Created by PR.
//
//  Opciones de arranque para pruebas automáticas de UI (XCUIAutomation). Sólo existen
//  en builds Debug; en Release se ignoran siempre, aunque vengan los argumentos:
//  - `-PRUITestReset`: la persistencia vive en un directorio temporal NUEVO, aparte de
//    los datos reales (cada prueba empieza de cero y nunca toca datos del usuario).
//  - `-PRFixedDate yyyy-MM-dd`: fija "hoy" (mediodía local) para probar lunes/domingo
//    sin cambiar la fecha del simulador.
//  - `-PRUITestStoreID <id>`: junto con el reset, el directorio temporal lleva ese id y se
//    REUTILIZA al relanzar la app (para probar que cierra y reabre recordando el plan).
//  La decisión es pura y testeable; la app sólo pasa sus argumentos y si es Debug.
//

import Foundation

public struct UITestLaunchOptions: Equatable, Sendable {
    public static let resetArgument = "-PRUITestReset"
    public static let fixedDateArgument = "-PRFixedDate"
    public static let storeIDArgument = "-PRUITestStoreID"

    /// Usar persistencia aislada en un directorio temporal nuevo.
    public let isolatedPersistence: Bool
    /// Fecha local (año, mes, día) que reemplaza a "hoy"; `nil` = reloj real.
    public let fixedDay: DateComponents?

    /// Identificador del directorio aislado; `nil` = uno nuevo en cada arranque.
    public let storeID: String?

    public init(isolatedPersistence: Bool = false, fixedDay: DateComponents? = nil, storeID: String? = nil) {
        self.isolatedPersistence = isolatedPersistence
        self.fixedDay = fixedDay
        self.storeID = storeID
    }

    /// Nombre del directorio temporal aislado: estable con `storeID`, nuevo si no hay.
    public var isolatedDirectoryName: String {
        "pr-uitest-\(storeID ?? UUID().uuidString)"
    }

    /// Sin opciones: comportamiento normal de producción.
    public static let none = UITestLaunchOptions()

    /// Resuelve las opciones. En Release siempre `.none`. Una fecha mal escrita o
    /// inexistente (p. ej. 2026-02-30) se ignora: nunca se inventa un día.
    public static func resolve(arguments: [String], isDebugBuild: Bool) -> UITestLaunchOptions {
        guard isDebugBuild else { return .none }
        return UITestLaunchOptions(
            isolatedPersistence: arguments.contains(resetArgument),
            fixedDay: fixedDay(in: arguments),
            storeID: storeID(in: arguments)
        )
    }

    /// Mediodía local del día fijado, en la zona y calendario dados; `nil` si no hay
    /// fecha fija o no es una fecha real.
    public func fixedDate(timeZone: TimeZone) -> Date? {
        guard let fixedDay else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = fixedDay
        components.hour = 12
        components.minute = 0
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(
                  year: fixedDay.year, month: fixedDay.month, day: fixedDay.day
              ) else { return nil }
        return date
    }

    /// Sólo letras, números y guiones: nunca una ruta.
    private static func storeID(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: storeIDArgument),
              arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        guard !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return value
    }

    private static func fixedDay(in arguments: [String]) -> DateComponents? {
        guard let index = arguments.firstIndex(of: fixedDateArgument),
              arguments.indices.contains(index + 1) else { return nil }
        let parts = arguments[index + 1].split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), parts[0].count == 4,
              let month = Int(parts[1]), parts[1].count == 2,
              let day = Int(parts[2]), parts[2].count == 2 else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }
}
