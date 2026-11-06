//
//  WorkoutSync.swift
//  PRDomain
//
//  Created by PR.
//
//  Coordinación multidevice del workout (plan §14 Fase 11, EPIC-12, PR-1203).
//  iPhone y Watch comparten el MISMO workout lógico mediante un modelo determinista
//  e idempotente de eventos (RNF-014): cada comando (`SetEvent`) es idempotente por
//  su clave estable, los conflictos sobre el mismo set lógico NO duplican ni pierden sets
//  (el más reciente queda canónico y el otro se guarda aparte, DG-3), y cualquier
//  dispositivo puede seguir trabajando si el otro está temporalmente desconectado (merging
//  commutativo y offline-first). Motor puro, sin Apple APIs ni reglas en Views.
//

import Foundation

// MARK: - Device

/// Devuelve una clave estable para un dispositivo participante del workout.
public struct WorkoutDeviceKey: RawRepresentable, Hashable, Sendable, Codable,
    CustomStringConvertible, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: WorkoutDeviceKey, rhs: WorkoutDeviceKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Participantes canónicos del workout compartido (iPhone y Watch).
public enum WorkoutDevice {
    /// Dispositivo principal (iPhone).
    public static let phone = WorkoutDeviceKey(rawValue: "phone")
    /// Dispositivo companion (Watch).
    public static let watch = WorkoutDeviceKey(rawValue: "watch")
}

// MARK: - Set slot lógico

/// Ranura de set lógico del plan: (exerciseID, índice 1-based dentro del ejercicio).
/// Permite resolver el conflicto "dos devices graban el mismo set lógico".
public struct SetSlot: Hashable, Sendable, Codable, Comparable {
    public let exerciseID: ExerciseID
    /// Índice del set dentro del ejercicio (1-based).
    public let slotIndex: Int

    public init(exerciseID: ExerciseID, slotIndex: Int) {
        self.exerciseID = exerciseID
        self.slotIndex = slotIndex
    }

    public static func < (lhs: SetSlot, rhs: SetSlot) -> Bool {
        if lhs.slotIndex == rhs.slotIndex { return lhs.exerciseID.rawValue < rhs.exerciseID.rawValue }
        return lhs.slotIndex < rhs.slotIndex
    }
}

// MARK: - Evento idempotente

/// Comando de un dispositivo sobre el workout lógico. Idempotente por su clave estable.
public enum SetEventAction: Codable, Sendable, Hashable {
    /// Graba (o re-graba) un set. `recorded.id` es la clave de idempotencia.
    case recorded(SetRecord)
    /// Revoca un set grabado por su id (reintento seguro: revocar dos veces = no-op).
    case revoked(SetRecordID)
}

/// Evento de set de un dispositivo. `id` = clave de idempotencia (persistible, estable).
public struct SetEvent: Codable, Sendable, Hashable {
    /// Clave estable del evento para dedup/retry.
    public let id: SetRecordID
    /// Dispositivo que originó el comando.
    public let device: WorkoutDeviceKey
    /// Marca de tiempo de emisión (orden global determinista).
    public let emittedAt: Date
    /// Ranura lógica del set en el plan (si se conoce; usada para resolver conflictos).
    public let slot: SetSlot?
    public let action: SetEventAction
    /// Sesión a la que pertenece (SCRUM-254). `nil` si no se indica.
    public let sessionID: WorkoutID?

    public init(
        id: SetRecordID = SetRecordID(),
        device: WorkoutDeviceKey,
        emittedAt: Date = Date(),
        slot: SetSlot? = nil,
        action: SetEventAction,
        sessionID: WorkoutID? = nil
    ) {
        self.id = id
        self.device = device
        self.emittedAt = emittedAt
        self.slot = slot
        self.action = action
        self.sessionID = sessionID
    }

    /// Clave canónica para dedup (evita duplicados en retry y entre slots).
    public var dedupKey: String {
        switch action {
        case .recorded(let record): return "record|\(record.id.rawValue)"
        case .revoked(let id): return "revoke|\(id.rawValue)"
        }
    }
}

// MARK: - Ledger / vista canónica

/// Ledger canónico del workout lógico tras aplicar una serie de `SetEvent`.
public struct WorkoutSyncLedger: Equatable, Sendable, Codable {
    /// Sesión del ledger: un evento de otra se rechaza. `nil` = cualquiera.
    public let sessionID: WorkoutID?
    /// Sets canónicos, en orden determinista (hora, dispositivo e id).
    public var canonicalSets: [SetRecord]
    /// Series que perdieron su ranura contra una más reciente. No se pierden (DG-3, RNF-004).
    public var conflictingSets: [SetRecord]
    /// Ranura lógica de cada set por su id (canónicos y en conflicto).
    public var slotsBySetID: [SetRecordID: SetSlot]
    /// Dispositivo que originó cada set (para desempate determinista en conflicto).
    public var devicesBySetID: [SetRecordID: WorkoutDeviceKey]
    /// Sets revocados. Se recuerdan por si la serie llega después que su revocación.
    public var revokedSetIDs: Set<SetRecordID>
    /// Conjunto de claves ya aplicadas (para idempotencia en re-aplicar).
    public let appliedKeys: Set<String>
    /// Revisión monótona (nº de eventos efectivamente aplicados).
    public let revision: Int

    public init(
        sessionID: WorkoutID? = nil,
        canonicalSets: [SetRecord] = [],
        conflictingSets: [SetRecord] = [],
        slotsBySetID: [SetRecordID: SetSlot] = [:],
        devicesBySetID: [SetRecordID: WorkoutDeviceKey] = [:],
        revokedSetIDs: Set<SetRecordID> = [],
        appliedKeys: Set<String> = [],
        revision: Int = 0
    ) {
        self.sessionID = sessionID
        self.canonicalSets = canonicalSets
        self.conflictingSets = conflictingSets
        self.slotsBySetID = slotsBySetID
        self.devicesBySetID = devicesBySetID
        self.revokedSetIDs = revokedSetIDs
        self.appliedKeys = appliedKeys
        self.revision = revision
    }

    public static let empty = WorkoutSyncLedger()
}

/// Resultado de aplicar un evento al ledger.
public enum SetEventEffect: Equatable, Sendable {
    /// Primeras modificaciones del estado canónico.
    case appliedNewlyAddedSet
    /// Un set existente fue supersede (conflicto resuelto) o modificado.
    case supersededExisting
    /// El set perdió su ranura contra uno más reciente: queda guardado aparte (DG-3).
    case keptAsConflict
    /// El set fue revocado.
    case revoked
    /// Evento ya aplicado (idempotente): se ignora sin cambios.
    case duplicateNoOp
    /// El evento es de otra sesión: se rechaza sin cambios.
    case rejectedOtherSession
}

// MARK: - Engine

/// Motor determinista de coordinación del workout compartido (PR-1203, SCRUM-254).
///
/// El resultado depende sólo del CONJUNTO de eventos, nunca del orden en que llegan:
/// WatchConnectivity entrega de uno en uno y no garantiza orden entre dispositivos.
///
/// Reglas (RNF-014):
/// 1. **Idempotencia**: un evento con la misma clave (`dedupKey`) se aplica una sola
///    vez; reintentar es un no-op (nunca duplica sets).
/// 2. **Conflicto sin perder**: dos sets distintos en el MISMO `SetSlot` son el mismo set
///    lógico. El más reciente (`performedAt`, empate ⇒ mayor `device`) queda como canónico y
///    el otro pasa a `conflictingSets`: una serie confirmada nunca se descarta (RNF-004).
/// 3. **Revocar**: gana sobre su serie aunque llegue antes; si revoca a la ganadora de un
///    conflicto, vuelve la otra.
/// 4. **Desconexión tolerante**: cada dispositivo aplica offline sus propios eventos;
///    al reconectar, el merge del peer converge sobre el estado local existente.
public struct WorkoutSyncEngine: Sendable {

    public init() {}

    public func apply(events: [SetEvent], to ledger: WorkoutSyncLedger = .empty) -> WorkoutSyncLedger {
        events.reduce(ledger) { applySingle($1, to: $0).ledger }
    }

    public func applySingle(_ event: SetEvent, to ledger: WorkoutSyncLedger) -> (ledger: WorkoutSyncLedger, effect: SetEventEffect) {
        if let own = ledger.sessionID, let other = event.sessionID, own != other {
            return (ledger, .rejectedOtherSession)
        }
        guard !ledger.appliedKeys.contains(event.dedupKey) else {
            return (ledger, .duplicateNoOp)
        }
        var records = ledger.canonicalSets + ledger.conflictingSets
        var slots = ledger.slotsBySetID
        var devices = ledger.devicesBySetID
        var revokedIDs = ledger.revokedSetIDs
        let touched: SetRecordID
        switch event.action {
        case .recorded(let record):
            touched = record.id
            if !revokedIDs.contains(record.id), !records.contains(where: { $0.id == record.id }) {
                records.append(record)
                slots[record.id] = event.slot
                devices[record.id] = event.device
            }
        case .revoked(let id):
            touched = id
            revokedIDs.insert(id)
            records.removeAll { $0.id == id }
            slots[id] = nil
            devices[id] = nil
        }
        let resolved = Self.resolve(records, slots: slots, devices: devices)
        let next = WorkoutSyncLedger(
            sessionID: ledger.sessionID,
            canonicalSets: resolved.canonical,
            conflictingSets: resolved.conflicting,
            slotsBySetID: slots,
            devicesBySetID: devices,
            revokedSetIDs: revokedIDs,
            appliedKeys: ledger.appliedKeys.union([event.dedupKey]),
            revision: ledger.revision + 1
        )
        return (next, Self.effect(of: event, touched: touched, before: ledger, after: next))
    }

    /// Canónicos y en conflicto, sólo a partir de lo que hay: por eso el orden no importa.
    private static func resolve(
        _ records: [SetRecord],
        slots: [SetRecordID: SetSlot],
        devices: [SetRecordID: WorkoutDeviceKey]
    ) -> (canonical: [SetRecord], conflicting: [SetRecord]) {
        let ordered = records.sorted { isOlder($0, than: $1, devices: devices) }
        var winners: [SetSlot: SetRecordID] = [:]
        for record in ordered {
            if let slot = slots[record.id] { winners[slot] = record.id }
        }
        var canonical: [SetRecord] = []
        var conflicting: [SetRecord] = []
        for record in ordered {
            if let slot = slots[record.id], winners[slot] != record.id {
                conflicting.append(record)
            } else {
                canonical.append(record)
            }
        }
        return (canonical, conflicting)
    }

    /// Orden total: hora, dispositivo (empate ⇒ gana el mayor) e id.
    private static func isOlder(
        _ first: SetRecord,
        than second: SetRecord,
        devices: [SetRecordID: WorkoutDeviceKey]
    ) -> Bool {
        if first.performedAt != second.performedAt { return first.performedAt < second.performedAt }
        let firstDevice = devices[first.id]?.rawValue ?? ""
        let secondDevice = devices[second.id]?.rawValue ?? ""
        if firstDevice != secondDevice { return firstDevice < secondDevice }
        return first.id.rawValue.uuidString < second.id.rawValue.uuidString
    }

    private static func effect(
        of event: SetEvent,
        touched: SetRecordID,
        before: WorkoutSyncLedger,
        after: WorkoutSyncLedger
    ) -> SetEventEffect {
        switch event.action {
        case .revoked:
            let existed = (before.canonicalSets + before.conflictingSets).contains { $0.id == touched }
            return existed ? .revoked : .duplicateNoOp
        case .recorded:
            if after.conflictingSets.contains(where: { $0.id == touched }) {
                let wasConflict = before.conflictingSets.contains { $0.id == touched }
                return wasConflict ? .duplicateNoOp : .keptAsConflict
            }
            guard after.canonicalSets.contains(where: { $0.id == touched }),
                  !before.canonicalSets.contains(where: { $0.id == touched }) else { return .duplicateNoOp }
            return after.conflictingSets.count > before.conflictingSets.count ? .supersededExisting : .appliedNewlyAddedSet
        }
    }

    /// Cada ranura de la plantilla con su set; la que aún no tiene ninguno queda en `nil`.
    public func view(for template: SessionTemplate, ledger: WorkoutSyncLedger) -> [SetSlot: SetRecord?] {
        var slotValue: [SetSlot: SetRecord?] = [:]
        var indexByExercise: [ExerciseID: Int] = [:]
        for planned in template.plannedSets {
            let slotIndex = (indexByExercise[planned.exerciseID] ?? 0) + 1
            indexByExercise[planned.exerciseID] = slotIndex
            let slot = SetSlot(exerciseID: planned.exerciseID, slotIndex: slotIndex)
            slotValue.updateValue(nil, forKey: slot)
        }
        for record in ledger.canonicalSets {
            if let slot = ledger.slotsBySetID[record.id] {
                slotValue.updateValue(record, forKey: slot)
            }
        }
        return slotValue
    }
}

// MARK: - Sesión guardada

/// Une al registro de la sesión una serie que llegó de otro dispositivo (SCRUM-255). La sesión
/// guardada es la fuente de verdad del iPhone: el ledger se arma a partir de ella, se aplica
/// el evento con `WorkoutSyncEngine` y el resultado vuelve a la sesión.
///
/// Las ranuras de lo ya hecho salen del orden de las series de cada ejercicio. Eso vale porque
/// `transferUserInfo` entrega en orden; si no, lo peor es un conflicto de más, nunca una
/// serie perdida.
public enum SessionSetMerger {

    /// Devuelve la sesión con la serie aplicada. Idempotente: repetirla no cambia nada.
    public static func merging(
        _ set: SetRecord,
        slot: SetSlot,
        device: WorkoutDeviceKey,
        into session: WorkoutSessionRecord,
        engine: WorkoutSyncEngine = WorkoutSyncEngine()
    ) -> (session: WorkoutSessionRecord, effect: SetEventEffect) {
        if let updated = updatingPain(of: set, in: session) { return (updated, .duplicateNoOp) }
        let event = SetEvent(device: device, emittedAt: set.performedAt, slot: slot, action: .recorded(set), sessionID: session.id)
        let result = engine.applySingle(event, to: ledger(of: session))
        guard result.ledger != ledger(of: session) else { return (session, .duplicateNoOp) }
        var merged = session
        let canonical = Set(result.ledger.canonicalSets.map(\.id))
        let kept = session.sets.filter { canonical.contains($0.id) }
        let added = result.ledger.canonicalSets.filter { candidate in !kept.contains { $0.id == candidate.id } }
        merged.sets = inPerformedOrder(kept + added)
        let conflicts = result.ledger.conflictingSets.compactMap { conflict in
            result.ledger.slotsBySetID[conflict.id].map { SessionSetConflict(set: conflict, slot: $0) }
        }
        merged.setConflicts = conflicts.isEmpty ? nil : conflicts
        return (merged, result.effect)
    }

    /// La ranura de cada serie hecha: el orden dentro de su ejercicio.
    public static func slots(of sets: [SetRecord]) -> [SetRecordID: SetSlot] {
        var counts: [ExerciseID: Int] = [:]
        var result: [SetRecordID: SetSlot] = [:]
        for set in sets {
            let index = (counts[set.exerciseID] ?? 0) + 1
            counts[set.exerciseID] = index
            result[set.id] = SetSlot(exerciseID: set.exerciseID, slotIndex: index)
        }
        return result
    }

    /// Una serie ya guardada sólo puede cambiar en el dolor reportado después (SCRUM-260),
    /// también si quedó en conflicto: el reporte nunca se ignora.
    private static func updatingPain(of set: SetRecord, in session: WorkoutSessionRecord) -> WorkoutSessionRecord? {
        guard let pain = set.painFeedback else { return nil }
        var updated = session
        if let index = session.sets.firstIndex(where: { $0.id == set.id }) {
            guard session.sets[index].painFeedback != pain else { return nil }
            updated.sets[index].painFeedback = pain
            return updated
        }
        guard var conflicts = session.setConflicts,
              let index = conflicts.firstIndex(where: { $0.set.id == set.id }),
              conflicts[index].set.painFeedback != pain else { return nil }
        var conflicted = conflicts[index].set
        conflicted.painFeedback = pain
        conflicts[index] = SessionSetConflict(set: conflicted, slot: conflicts[index].slot)
        updated.setConflicts = conflicts
        return updated
    }

    private static func ledger(of session: WorkoutSessionRecord) -> WorkoutSyncLedger {
        let conflicts = session.setConflicts ?? []
        var slots = Self.slots(of: session.sets)
        for conflict in conflicts { slots[conflict.set.id] = conflict.slot }
        let records = session.sets + conflicts.map(\.set)
        return WorkoutSyncLedger(
            sessionID: session.id,
            canonicalSets: session.sets,
            conflictingSets: conflicts.map(\.set),
            slotsBySetID: slots,
            devicesBySetID: Dictionary(uniqueKeysWithValues: records.map { ($0.id, WorkoutDevice.phone) }),
            appliedKeys: Set(records.map { "record|\($0.id.rawValue)" })
        )
    }

    /// Por hora y, si empatan, en el orden en que estaban.
    private static func inPerformedOrder(_ sets: [SetRecord]) -> [SetRecord] {
        sets.enumerated().sorted { first, second in
            first.element.performedAt == second.element.performedAt
                ? first.offset < second.offset
                : first.element.performedAt < second.element.performedAt
        }.map(\.element)
    }
}
