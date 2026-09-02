//
//  AgentIntent.swift
//  PRDomain
//
//  Created by PR.
//
//  Schema de intenciones del agente (promptMaster §20.1-20.2, PR-1601).
//
//  El LLM interpreta texto a estructuras (`interpret`), pero NUNCA decide por sí
//  mismo: sólo propone `AgentIntent`. Todo lo que el engine decide pasa por
//  `ActionPolicyValidator` (PR-1602). Este archivo es puro dominio: Codable,
//  Sendable y **independiente de backend** para que la representación wire pueda
//  viajar hacia/desde un servidor o usarse offline.
//
//  Decodificación segura: un tag desconocido (por ejemplo producido por un
//  backend más nuevo) NUNCA crea basura; falla con `AgentIntentError.unsupported`
//  para que el caller pida reformulación o degrade a fallback seguro (PR-1603).
//

import Foundation

// MARK: - Soporte (wire types que aún no vivían en el dominio)

/// Referencia a un equipamiento para intents de disponibilidad (§20.2:
/// `equipmentUnavailable`). Puede ser un tipo genérico o una instancia concreta
/// de máquina (para el historial por instancia).
public struct EquipmentReference: Codable, Sendable, Hashable {
    public var equipmentType: EquipmentType
    public var machineInstanceID: MachineProfileID?

    public init(equipmentType: EquipmentType, machineInstanceID: MachineProfileID? = nil) {
        self.equipmentType = equipmentType
        self.machineInstanceID = machineInstanceID
    }
}

/// Razón por la que un equipamiento no está disponible. Mapea al estado de
/// disponibilidad ya existente en el dominio (`EquipmentAvailabilityState`):
/// `doesNotExist` (persistente en ese gym) u `occupied` (sólo de sesión).
public enum UnavailabilityReason: String, Codable, Sendable, Hashable {
    case doesNotExist
    case occupied
}

/// Payload del intent `equipmentUnavailable` (referencia + razón).
internal struct UnavailabilityPayload: Codable, Sendable, Hashable {
    public var reference: EquipmentReference
    public var reason: UnavailabilityReason
}

/// Feedback declarado por el usuario tras un set (fatiga subjetiva).
/// Es un valor de reporte, NO un diagnóstico.
public struct UserFatigueFeedback: Codable, Sendable, Hashable {
    public var severity: Int

    /// `severity` en 1...5 (1 = apenas fatigado, 5 = muy fatigado).
    public init(severity: Int) {
        self.severity = severity
    }

    public static func validSeverity(_ value: Int) -> Bool {
        (1...5).contains(value)
    }
}

/// Reporte de dolor del usuario durante un set. No diagnostica: expresa nivel y
/// localización tal cual lo reporta el usuario. Reusa el nivel de PR-1403.
public struct PainReport: Codable, Sendable, Hashable {
    public var level: PainLevel
    public var bodyRegion: BodyRegion?
    public var side: BodySide?
    public var notes: String?

    public init(level: PainLevel, bodyRegion: BodyRegion? = nil, side: BodySide? = nil, notes: String? = nil) {
        self.level = level
        self.bodyRegion = bodyRegion
        self.side = side
        self.notes = notes
    }
}

/// Borrador de una restricción que el agente propone (PR-1404). No es el tipo
/// persistente `TrainingRestriction`: falta id/estado/fechas; el usuario debe
/// confirmarlo antes de guardar vía `RestrictionManager`.
public struct TrainingRestrictionDraft: Codable, Sendable, Hashable {
    public var bodyRegion: BodyRegion
    public var side: BodySide?
    public var source: RestrictionSource
    public var forbiddenPatterns: Set<MovementPattern>
    public var forbiddenExerciseIDs: Set<ExerciseID>
    public var allowedExerciseIDs: Set<ExerciseID>
    public var restrictionTags: Set<RestrictionTag>
    public var notes: String?

    public init(
        bodyRegion: BodyRegion,
        side: BodySide? = nil,
        source: RestrictionSource = .userReported,
        forbiddenPatterns: Set<MovementPattern> = [],
        forbiddenExerciseIDs: Set<ExerciseID> = [],
        allowedExerciseIDs: Set<ExerciseID> = [],
        restrictionTags: Set<RestrictionTag> = [],
        notes: String? = nil
    ) {
        self.bodyRegion = bodyRegion
        self.side = side
        self.source = source
        self.forbiddenPatterns = forbiddenPatterns
        self.forbiddenExerciseIDs = forbiddenExerciseIDs
        self.allowedExerciseIDs = allowedExerciseIDs
        self.restrictionTags = restrictionTags
        self.notes = notes
    }
}

/// Criterios para que el engine re-trabaje el plan (ajuste de volumen, de carga,
/// o rebarrido completo). El engine decide la magnitud, no el agente.
public struct PlanAdjustmentRequest: Codable, Sendable, Hashable {
    public enum Scope: String, Codable, Sendable, Hashable {
        case volume
        case loadTarget
        case fullRebuild
    }

    public var scope: Scope
    public var rationale: String?

    public init(scope: Scope, rationale: String? = nil) {
        self.scope = scope
        self.rationale = rationale
    }
}

// MARK: - Intents

/// Intención estructurada que el LLM propone a partir del texto del usuario
/// (promptMaster §20.2). El engine y el `ActionPolicyValidator` son quienes
/// deciden; el intent sólo expresa la intención.
public enum AgentIntent: Sendable, Hashable {
    case setTimeConstraint(TimeConstraint)
    case equipmentUnavailable(EquipmentReference, UnavailabilityReason)
    case requestExerciseSwap(ExerciseID)
    case reportFatigue(UserFatigueFeedback)
    case reportPain(PainReport)
    case changeGoal(TrainingGoal)
    case changePhase(BodyCompositionPhase)
    case changeGym(GymID)
    case askWhy(DecisionID)
    case updateRestriction(TrainingRestrictionDraft)
    case requestPlanAdjustment(PlanAdjustmentRequest)

    // MARK: Decodificación segura

    /// Etiqueta estable para el wire format (independiente del orden de casos).
    public var tag: String {
        switch self {
        case .setTimeConstraint: return "setTimeConstraint"
        case .equipmentUnavailable: return "equipmentUnavailable"
        case .requestExerciseSwap: return "requestExerciseSwap"
        case .reportFatigue: return "reportFatigue"
        case .reportPain: return "reportPain"
        case .changeGoal: return "changeGoal"
        case .changePhase: return "changePhase"
        case .changeGym: return "changeGym"
        case .askWhy: return "askWhy"
        case .updateRestriction: return "updateRestriction"
        case .requestPlanAdjustment: return "requestPlanAdjustment"
        }
    }

    /// Descripción corta legible para log/auditoría.
    public var displayName: String {
        switch self {
        case .setTimeConstraint: return "Restricción de tiempo"
        case .equipmentUnavailable: return "Equipo no disponible"
        case .requestExerciseSwap: return "Solicitar cambio de ejercicio"
        case .reportFatigue: return "Reportar fatiga"
        case .reportPain: return "Reportar dolor"
        case .changeGoal: return "Cambiar objetivo"
        case .changePhase: return "Cambiar fase"
        case .changeGym: return "Cambiar gym"
        case .askWhy: return "Preguntar por qué"
        case .updateRestriction: return "Actualizar restricción"
        case .requestPlanAdjustment: return "Ajustar plan"
        }
    }
}

/// Error de decodificación de un `AgentIntent`.
public enum AgentIntentError: Error, Equatable, Sendable {
    /// El tag no corresponde a ningún intent conocido (backend más nuevo).
    case unsupported(tag: String)
    /// El payload del intent no decodificó (shape inválida).
    case malformedPayload
}

// MARK: - Codable (wire format)

private struct IntentCodingKeys {
    static let type = "intent"
    static let payload = "payload"
}

extension AgentIntent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let rawTag = try container.decode(String.self, forKey: DynamicCodingKey(stringValue: IntentCodingKeys.type))
        let payload = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: DynamicCodingKey(stringValue: IntentCodingKeys.payload))

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            // El payload contiene una única clave sintética representando el valor.
            // Lo codificamos como un diccionario de 1 elemento: { "value": <T> }.
            try payload.decode(T.self, forKey: DynamicCodingKey(stringValue: "value"))
        }

        switch rawTag {
        case "setTimeConstraint": self = .setTimeConstraint(try decode(TimeConstraint.self))
        case "equipmentUnavailable":
            let payload = try decode(UnavailabilityPayload.self)
            self = .equipmentUnavailable(payload.reference, payload.reason)
        case "requestExerciseSwap": self = .requestExerciseSwap(try decode(ExerciseID.self))
        case "reportFatigue": self = .reportFatigue(try decode(UserFatigueFeedback.self))
        case "reportPain": self = .reportPain(try decode(PainReport.self))
        case "changeGoal": self = .changeGoal(try decode(TrainingGoal.self))
        case "changePhase": self = .changePhase(try decode(BodyCompositionPhase.self))
        case "changeGym": self = .changeGym(try decode(GymID.self))
        case "askWhy": self = .askWhy(try decode(DecisionID.self))
        case "updateRestriction": self = .updateRestriction(try decode(TrainingRestrictionDraft.self))
        case "requestPlanAdjustment": self = .requestPlanAdjustment(try decode(PlanAdjustmentRequest.self))
        default:
            throw AgentIntentError.unsupported(tag: rawTag)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(self.tag, forKey: DynamicCodingKey(stringValue: IntentCodingKeys.type))

        var payload = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: DynamicCodingKey(stringValue: IntentCodingKeys.payload))
        let valueKey = DynamicCodingKey(stringValue: "value")

        switch self {
        case .setTimeConstraint(let v): try payload.encode(v, forKey: valueKey)
        case .equipmentUnavailable(let ref, let reason):
            try payload.encode(UnavailabilityPayload(reference: ref, reason: reason), forKey: valueKey)
        case .requestExerciseSwap(let v): try payload.encode(v, forKey: valueKey)
        case .reportFatigue(let v): try payload.encode(v, forKey: valueKey)
        case .reportPain(let v): try payload.encode(v, forKey: valueKey)
        case .changeGoal(let v): try payload.encode(v, forKey: valueKey)
        case .changePhase(let v): try payload.encode(v, forKey: valueKey)
        case .changeGym(let v): try payload.encode(v, forKey: valueKey)
        case .askWhy(let v): try payload.encode(v, forKey: valueKey)
        case .updateRestriction(let v): try payload.encode(v, forKey: valueKey)
        case .requestPlanAdjustment(let v): try payload.encode(v, forKey: valueKey)
        }
    }
}

// MARK: - DynamicCodingKey

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
