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
//  - `-PRUITestPlanDelay <segundos>` (1…10): demora la activación del plan para probar que,
//    mientras está pendiente, nunca se muestra "Día de descanso" (SCRUM-193).
//  - `-PRUITestProfile <perfil>` (SCRUM-228; p. ej. `intermedio-lmv`): arranca con el
//    cuestionario ya contestado con ese perfil (`UITestProfileSeeder`), para que sólo los
//    recorridos del cuestionario lo contesten a mano. Sólo junto con `-PRUITestReset`: nunca
//    sobre los datos reales. Un perfil desconocido se ignora.
//  La decisión es pura y testeable; la app sólo pasa sus argumentos y si es Debug.
//

import Foundation

public struct UITestLaunchOptions: Equatable, Sendable {
    public static let resetArgument = "-PRUITestReset"
    public static let fixedDateArgument = "-PRFixedDate"
    public static let storeIDArgument = "-PRUITestStoreID"
    public static let planDelayArgument = "-PRUITestPlanDelay"
    public static let profileArgument = "-PRUITestProfile"
    /// Demoras aceptadas, en segundos (fuera de este rango se ignora).
    public static let allowedPlanDelaySeconds: ClosedRange<Int> = 1...10

    /// Usar persistencia aislada en un directorio temporal nuevo.
    public let isolatedPersistence: Bool
    /// Fecha local (año, mes, día) que reemplaza a "hoy"; `nil` = reloj real.
    public let fixedDay: DateComponents?

    /// Identificador del directorio aislado; `nil` = uno nuevo en cada arranque.
    public let storeID: String?
    /// Demora artificial de la activación del plan (sólo pruebas de UI); `nil` = ninguna.
    public let planDelay: Duration?
    /// Perfil con el que el cuestionario se contesta solo; `nil` = se contesta a mano.
    public let seededProfile: UITestSeededProfile?

    public init(
        isolatedPersistence: Bool = false,
        fixedDay: DateComponents? = nil,
        storeID: String? = nil,
        planDelay: Duration? = nil,
        seededProfile: UITestSeededProfile? = nil
    ) {
        self.isolatedPersistence = isolatedPersistence
        self.fixedDay = fixedDay
        self.storeID = storeID
        self.planDelay = planDelay
        self.seededProfile = seededProfile
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
        let isolated = arguments.contains(resetArgument)
        return UITestLaunchOptions(
            isolatedPersistence: isolated,
            fixedDay: fixedDay(in: arguments),
            storeID: storeID(in: arguments),
            planDelay: planDelay(in: arguments),
            // Sin datos temporales el perfil se ignora: nunca se contesta sobre los reales.
            seededProfile: isolated ? seededProfile(in: arguments) : nil
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

    /// Segundos enteros dentro de `allowedPlanDelaySeconds`; cualquier otro valor se ignora.
    private static func planDelay(in arguments: [String]) -> Duration? {
        guard let index = arguments.firstIndex(of: planDelayArgument),
              arguments.indices.contains(index + 1),
              let seconds = Int(arguments[index + 1]),
              allowedPlanDelaySeconds.contains(seconds) else { return nil }
        return .seconds(seconds)
    }

    /// Uno de los perfiles conocidos; cualquier otro valor se ignora.
    private static func seededProfile(in arguments: [String]) -> UITestSeededProfile? {
        guard let index = arguments.firstIndex(of: profileArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return UITestSeededProfile(rawValue: arguments[index + 1])
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
