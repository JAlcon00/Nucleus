//
//  SleepCheckIns.swift
//  PRCore
//
//  SCRUM-203 (IA-2): el check-in diario de sueño, guardado por usuario y día en su
//  propia colección (`check-ins/`), y el coordinador que lo pide en Hoy una vez al día.
//  El ajuste del entrenamiento lo decide `ReadinessEngine` (PRDomain), nunca la vista.
//

import Foundation
import Observation
import PRDomain

/// Lee y escribe el check-in de cada usuario y día.
public struct SleepCheckInStore: Sendable {
    private let store: any RepositoryStore

    public init(store: some RepositoryStore) {
        self.store = store
    }

    /// Clave por usuario y día (derivada: ni el ID de Apple ni nada personal).
    static func key(userID: String, day: String) -> String {
        SeedID.uuid(namespace: "check-in", slug: "\(userID)|\(day)").persistenceKey
    }

    /// Check-in de ese día, o `nil` si no hay o no se puede leer (sin ajuste: el día
    /// queda como estaba planeado). Lanza sólo si falla la lectura.
    public func load(userID: String, day: String) throws -> SleepCheckIn? {
        guard let data = try store.read(key: Self.key(userID: userID, day: day)) else { return nil }
        return try? JSONDecoder().decode(SleepCheckIn.self, from: data)
    }

    /// Guarda el check-in (uno por día: repetirlo lo reemplaza). Lanza si falla.
    public func save(_ checkIn: SleepCheckIn, userID: String) throws {
        try store.write(key: Self.key(userID: userID, day: checkIn.day), data: JSONEncoder().encode(checkIn))
    }
}

extension LocalPersistence {
    public func sleepCheckInStore() throws -> SleepCheckInStore {
        SleepCheckInStore(store: try store(for: .checkIns))
    }
}

/// El check-in de hoy para la app: preguntarlo una vez al día, guardarlo y decir el ajuste.
@MainActor
@Observable
public final class SleepCheckInCoordinator {
    /// Check-in de hoy, si ya se respondió.
    public private(set) var today: SleepCheckIn?
    /// La persona prefirió no responder hoy (no se vuelve a preguntar hasta mañana).
    public private(set) var skippedToday = false
    /// El último check-in no se pudo guardar.
    public private(set) var saveFailed = false

    private let store: SleepCheckInStore?
    private let engine: ReadinessEngine
    private let clock: () -> Date
    private let timeZone: () -> TimeZone
    private var userID: String?
    private var loadedDay: String?

    public init(
        store: SleepCheckInStore?,
        engine: ReadinessEngine = ReadinessEngine(),
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.store = store
        self.engine = engine
        self.clock = clock
        self.timeZone = timeZone
    }

    private var currentDay: String { SleepCheckIn.day(of: clock(), timeZone: timeZone()) }

    /// ¿Hay que preguntar hoy?
    public var needsCheckIn: Bool {
        today == nil && !skippedToday && userID != nil
    }

    /// Ajuste del día según el check-in de hoy (`.none` sin check-in).
    public var adjustment: ReadinessAdjustment { engine.adjustment(for: today) }

    /// Lee el check-in de hoy de este usuario (al iniciar o retomar sesión, y al cambiar
    /// de día). Si no se puede leer, no hay ajuste.
    public func load(userID: String?) {
        self.userID = userID
        let day = currentDay
        if loadedDay != day { skippedToday = false }
        loadedDay = day
        saveFailed = false
        guard let userID, let store else {
            today = nil
            return
        }
        today = (try? store.load(userID: userID, day: day)) ?? nil
    }

    /// Registra el check-in de hoy. Devuelve el ajuste resultante, o `nil` si las horas no
    /// son válidas o no se pudo guardar (entonces el día no cambia).
    @discardableResult
    public func record(hours: Double, quality: SleepQuality) -> ReadinessAdjustment? {
        guard let checkIn = try? SleepCheckIn(day: currentDay, hours: hours, quality: quality) else { return nil }
        do {
            if let userID, let store {
                try store.save(checkIn, userID: userID)
            }
            today = checkIn
            saveFailed = false
            return engine.adjustment(for: checkIn)
        } catch {
            saveFailed = true
            return nil
        }
    }

    /// "Hoy no": no se pregunta otra vez hasta mañana y el día queda como estaba.
    public func skip() {
        skippedToday = true
        loadedDay = currentDay
    }
}
