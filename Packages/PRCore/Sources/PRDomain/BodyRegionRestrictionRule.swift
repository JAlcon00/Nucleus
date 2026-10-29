//
//  BodyRegionRestrictionRule.swift
//  PRDomain
//
//  SCRUM-209 (FB-2): en el formulario la persona marca zonas con molestia o lesión
//  (hombro, rodilla…) y, si quiere, escribe una nota. Cada zona se convierte en una
//  restricción activa de origen `userReported` que prohíbe los patrones de movimiento de
//  riesgo para esa zona.
//
//  Reglas:
//  - La tabla zona → patrones es una regla VERSIONADA (`version`): cambiarla sube la
//    versión; nunca vive en una View.
//  - Es conservadora y no diagnostica: evita los movimientos que más suelen cargar la
//    zona sin vaciar grupos musculares enteros. Una restricción más fina (ejercicios
//    concretos, revisión profesional) se registra en Perfil › Restricciones.
//  - Si aun así una zona deja a un músculo sin ejercicios permitidos, el planificador
//    omite ese músculo y lo explica: nunca evade la restricción.
//  - El catálogo actual no trae tags de contraindicación; el tag se guarda igual para
//    el motor de sustituciones (`RestrictionPolicyEngine`) y catálogos futuros.
//  - La nota NO va en la restricción ni cambia el plan: vive en el perfil
//    (`OnboardingProfile.restrictionNote`) y nunca va a logs ni a la IA.
//

import Foundation

/// Lo que se contesta en el paso "Restricciones": zonas elegidas y nota opcional.
public struct RestrictionsAnswer: Equatable, Sendable {
    public var zones: Set<BodyRegion>
    public var note: String
    /// Restricciones ya guardadas (al rehacer el cuestionario): se reutilizan las de la
    /// misma zona para que el plan no cambie sin motivo.
    public var previous: [TrainingRestriction]

    public init(zones: Set<BodyRegion> = [], note: String = "", previous: [TrainingRestriction] = []) {
        self.zones = zones
        self.note = note
        self.previous = previous
    }

    /// Sin zonas ni nota.
    public static let none = RestrictionsAnswer()

    /// Máximo de caracteres de la nota.
    public static let maxNoteLength = 280

    /// Nota limpia (`nil` si está vacía).
    public var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// ¿Se puede continuar? Todo es opcional; sólo una nota demasiado larga lo impide.
    public var isValid: Bool {
        (trimmedNote?.count ?? 0) <= Self.maxNoteLength
    }
}

/// Regla versionada zona → patrones de movimiento que se evitan.
public enum BodyRegionRestrictionRule {
    /// Versión de la tabla. Súbela al cambiar cualquier patrón.
    public static let version = 1

    /// Zonas que ofrece el formulario, en orden de la cabeza a los pies.
    public static let selectableRegions: [BodyRegion] = [
        .neck, .shoulder, .elbow, .wrist, .lumbar, .hip, .knee, .ankle,
    ]

    /// Patrones de movimiento que se evitan con molestia en `region`.
    public static func forbiddenPatterns(for region: BodyRegion) -> Set<MovementPattern> {
        switch region {
        case .neck: return [.verticalPress, .carry]
        case .shoulder: return [.verticalPress, .shoulderAbduction]
        case .elbow: return [.elbowFlexion, .elbowExtension]
        case .wrist, .hand: return [.carry]
        case .thoracic: return [.trunkRotation]
        case .lumbar: return [.hinge, .trunkExtension, .trunkRotation]
        case .hip, .groin: return [.lunge]
        case .knee: return [.lunge, .kneeExtension]
        case .ankle, .foot: return [.lunge, .calfPlantarFlexion]
        case .core: return [.trunkFlexion, .trunkRotation]
        }
    }

    /// Tag de contraindicación de la zona (para el motor de sustituciones).
    public static func tag(for region: BodyRegion) -> RestrictionTag? {
        switch region {
        case .neck: return .neck
        case .shoulder: return .shoulder
        case .elbow: return .elbow
        case .wrist, .hand: return .wrist
        case .lumbar: return .lowerBack
        case .hip, .groin: return .hip
        case .knee: return .knee
        case .ankle, .foot: return .ankle
        case .core: return .coreStability
        case .thoracic: return nil
        }
    }

    /// Restricciones para las zonas elegidas (orden estable por zona). Reutiliza la
    /// restricción EN VIGOR de una zona si existe (mismo ID y fecha); una resuelta es
    /// historial, así que volver a marcar su zona crea una activa nueva (SCRUM-36).
    /// Nada se borra (SCRUM-36, decisión 2 de Jesús):
    /// - una declarada por la persona cuya zona se desmarcó queda resuelta, en el historial;
    /// - las de zonas que el formulario no muestra, las de origen profesional y las resueltas
    ///   se conservan tal cual: desmarcar nunca debilita una restricción profesional.
    public static func restrictions(
        for answer: RestrictionsAnswer,
        now: Date,
        newID: () -> RestrictionID = { RestrictionID() }
    ) -> [TrainingRestriction] {
        let inForceByRegion = Dictionary(
            answer.previous.filter(\.isInForce).map { ($0.bodyRegion, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let chosen = BodyRegion.allCases.filter(answer.zones.contains).map { region in
            if let previous = inForceByRegion[region] { return previous }
            return TrainingRestriction(
                id: newID(),
                bodyRegion: region,
                startDate: now,
                status: .active,
                source: .userReported,
                forbiddenPatterns: forbiddenPatterns(for: region),
                restrictionTags: tag(for: region).map { [$0] } ?? []
            )
        }
        let chosenIDs = Set(chosen.map(\.id))
        let kept = answer.previous.filter { !chosenIDs.contains($0.id) }.map { restriction in
            let unmarked = restriction.isInForce
                && restriction.source == .userReported
                && selectableRegions.contains(restriction.bodyRegion)
                && !answer.zones.contains(restriction.bodyRegion)
            guard unmarked else { return restriction }
            var resolved = restriction.updatedStatus(.resolved)
            resolved.resolvedDate = now
            return resolved
        }
        return chosen + kept
    }
}
