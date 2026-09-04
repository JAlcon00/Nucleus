//
//  WorkoutSync.swift
//  PRDomain
//
//  Created by PR.
//
//  Coordinación multidevice del workout (plan §14 Fase 11, EPIC-12, PR-1203).
//  iPhone y Watch comparten el MISMO workout lógico mediante un modelo determinista
//  e idempotente de eventos (RNF-014): cada comando (`SetEvent`) es idempotente por
//  su clave estable, los conflictos sobre el mismo set lógico NO duplican sets
//  (supersede por newest, empate por device), y cualquier dispositivo puede seguir
//  trabajando si el otro está temporalmente desconectado (merging commutativo y
//  offline-first). Motor puro, sin Apple APIs ni reglas en Views.
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

    public init(
        id: SetRecordID = SetRecordID(),
        device: WorkoutDeviceKey,
        emittedAt: Date = Date(),
        slot: SetSlot? = nil,
        action: SetEventAction
    ) {
        self.id = id
        self.device = device
        self.emittedAt = emittedAt
        self.slot = slot
        self.action = action
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
public struct WorkoutSyncLedger: Equatable, Sendable {
    /// Sets canónicos, en orden determinista (plan: slot y luego timestamp/device).
    public var canonicalSets: [SetRecord]
    /// Ranura lógica de cada set por su id (para resolver conflictos entre slots).
    public var slotsBySetID: [SetRecordID: SetSlot]
    /// Dispositivo que originó cada set (para desempate determinista en conflicto).
    public var devicesBySetID: [SetRecordID: WorkoutDeviceKey]
    /// Conjunto de claves ya aplicadas (para idempotencia en re-aplicar).
    public let appliedKeys: Set<String>
    /// Revisión monótona (nº de eventos efectivamente aplicados).
    public let revision: Int

    public init(
        canonicalSets: [SetRecord],
        slotsBySetID: [SetRecordID: SetSlot] = [:],
        devicesBySetID: [SetRecordID: WorkoutDeviceKey] = [:],
        appliedKeys: Set<String>,
        revision: Int
    ) {
        self.canonicalSets = canonicalSets
        self.slotsBySetID = slotsBySetID
        self.devicesBySetID = devicesBySetID
        self.appliedKeys = appliedKeys
        self.revision = revision
    }

    public static let empty = WorkoutSyncLedger(canonicalSets: [], appliedKeys: [], revision: 0)
}

/// Resultado de aplicar un evento al ledger.
public enum SetEventEffect: Equatable, Sendable {
    /// Primeras modificaciones del estado canónico.
    case appliedNewlyAddedSet
    /// Un set existente fue supersede (conflicto resuelto) o modificado.
    case supersededExisting
    /// El set fue revocado.
    case revoked
    /// Evento ya aplicado (idempotente): se ignora sin cambios.
    case duplicateNoOp
}

// MARK: - Engine

/// Motor determinista de coordinación del workout compartido (PR-1203).
///
/// Reglas (RNF-014):
/// 1. **Idempotencia**: un evento con la misma clave (`dedupKey`) se aplica una sola
///    vez; reintentar es un no-op (nunca duplica sets).
/// 2. **Conflicto sin duplicar**: dos eventos que graban el MISMO `SetSlot` son el
///    mismo set lógico; gana el de `performedAt` más reciente (empate ⇒ mayor
///    `device.rawValue`) y quedá EXACTAMENTE uno. Nunca se añaden dos.
/// 3. **Mismo workout lógico**: el merge es commutativo/idempotente ⇒ cualquier
///    orden de llegada converge al mismo estado.
/// 4. **Desconexión tolerante**: cada dispositivo aplica offline sus propios eventos;
///    al reconectar, el merge del peer converge sobre el estado local existente.
public struct WorkoutSyncEngine: Sendable {

    public init() {}

    public func apply(events: [SetEvent], to ledger: WorkoutSyncLedger = .empty) -> WorkoutSyncLedger {
        var out = ledger
        // Orden global determinista: emitido ASC, device ASC, id ASC — para que ambos
        // dispositivos converjan aunque los eventos lleguen desordenados.
        let ordered = events.sorted { a, b in
            if a.emittedAt == b.emittedAt {
                if a.device == b.device { return a.id.rawValue < b.id.rawValue }
                return a.device < b.device
            }
            return a.emittedAt < b.emittedAt
        }
        for event in ordered {
            out = applySingle(event, to: out).ledger
        }
        return out
    }

    public func applySingle(_ event: SetEvent, to ledger: WorkoutSyncLedger) -> (ledger: WorkoutSyncLedger, effect: SetEventEffect) {
        var keys = ledger.appliedKeys
        var sets = ledger.canonicalSets
        var slotsBySetID = ledger.slotsBySetID
        var devicesBySetID = ledger.devicesBySetID

        guard !keys.contains(event.dedupKey) else {
            return (ledger, .duplicateNoOp)
        }
        keys.insert(event.dedupKey)

        var effect: SetEventEffect = .appliedNewlyAddedSet
        switch event.action {
        case .recorded(let record):
            // Conflicto sobre el mismo slot lógico: dos eventos nombran el MISMO
            // `SetSlot`, así que representan el mismo set lógico. Gana el más reciente;
            // el perdedor NO se añade ⇒ nunca se duplica el set.
            if let slot = event.slot,
               let existingID = slotsBySetID.first(where: { $0.value == slot })?.key {
                let existingIndex = sets.firstIndex(where: { $0.id == existingID })
                guard let existingIndex else {
                    sets.append(record)
                    slotsBySetID[record.id] = slot
                    devicesBySetID[record.id] = event.device
                    effect = .appliedNewlyAddedSet
                    break
                }
                let existing = sets[existingIndex]
                if Self.isNewer(record, than: existing, forDevice: event.device, existingDevice: devicesBySetID[existingID]) {
                    sets[existingIndex] = record
                    slotsBySetID[record.id] = slot
                    slotsBySetID[existingID] = nil
                    devicesBySetID[record.id] = event.device
                    devicesBySetID[existingID] = nil
                    effect = .supersededExisting
                } else {
                    // El existente es el ganador; el set no se añade (sin duplicado).
                    effect = .duplicateNoOp
                }
            } else {
                sets.append(record)
                if let slot = event.slot {
                    slotsBySetID[record.id] = slot
                }
                devicesBySetID[record.id] = event.device
                effect = .appliedNewlyAddedSet
            }
        case .revoked(let id):
            if let index = sets.firstIndex(where: { $0.id == id }) {
                sets.remove(at: index)
                slotsBySetID[id] = nil
                devicesBySetID[id] = nil
                effect = .revoked
            } else {
                effect = .duplicateNoOp
            }
        }

        let next = WorkoutSyncLedger(
            canonicalSets: sets,
            slotsBySetID: slotsBySetID,
            devicesBySetID: devicesBySetID,
            appliedKeys: keys,
            revision: ledger.revision + 1
        )
        return (next, effect)
    }

    /// Estado por defecto del set a mostrar si su ranura aún no tiene set grabado.
    public func view(for template: SessionTemplate, ledger: WorkoutSyncLedger) -> [SetSlot: SetRecord?] {
        var slotValue: [SetSlot: SetRecord?] = [:]
        var indexByExercise: [ExerciseID: Int] = [:]
        for planned in template.plannedSets {
            let slotIndex = (indexByExercise[planned.exerciseID] ?? 0) + 1
            indexByExercise[planned.exerciseID] = slotIndex
            let slot = SetSlot(exerciseID: planned.exerciseID, slotIndex: slotIndex)
            slotValue[slot] = nil
        }
        for record in ledger.canonicalSets {
            if let slot = ledger.slotsBySetID[record.id] {
                slotValue[slot] = record
            }
        }
        return slotValue
    }

    // MARK: - Helpers

    private static func isNewer(_ candidate: SetRecord, than existing: SetRecord, forDevice device: WorkoutDeviceKey, existingDevice: WorkoutDeviceKey?) -> Bool {
        if candidate.performedAt == existing.performedAt {
            // Empate de tiempo: el device de mayor rawValue gana de forma determinista.
            guard let existingDevice else { return true }
            return device > existingDevice
        }
        return candidate.performedAt > existing.performedAt
    }
}