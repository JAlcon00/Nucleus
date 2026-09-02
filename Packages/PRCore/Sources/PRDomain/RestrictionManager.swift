//
//  RestrictionManager.swift
//  PRDomain
//
//  Created by PR.
//
//  Operaciones deterministas de gestión de restricciones (plan §15 Fase 12,
//  promptMaster §16, PR-1401). Encapsula el CRUD/estado (crear, editar, revisar,
//  resolver) SIN reglas en Views. Reglas §16.2: nunca asumir recuperación por fecha
//  (pasa a `reviewNeeded`, no se auto-resuelve); instrucciones de profesional sólo se
//  estructuran tras confirmación explícita del usuario. No diagnostica. Determinista.
//

import Foundation

/// Borrador de restricción para crear o editar (PR-1401).
public struct RestrictionDraft: Equatable, Sendable {
    public var bodyRegion: BodyRegion
    public var side: BodySide?
    public var source: RestrictionSource
    public var reviewDate: Date?
    public var forbiddenPatterns: Set<MovementPattern>
    public var forbiddenExerciseIDs: Set<ExerciseID>
    public var allowedExerciseIDs: Set<ExerciseID>
    public var restrictionTags: Set<RestrictionTag>
    public var notes: String?

    public init(
        bodyRegion: BodyRegion,
        side: BodySide? = nil,
        source: RestrictionSource = .userReported,
        reviewDate: Date? = nil,
        forbiddenPatterns: Set<MovementPattern> = [],
        forbiddenExerciseIDs: Set<ExerciseID> = [],
        allowedExerciseIDs: Set<ExerciseID> = [],
        restrictionTags: Set<RestrictionTag> = [],
        notes: String? = nil
    ) {
        self.bodyRegion = bodyRegion
        self.side = side
        self.source = source
        self.reviewDate = reviewDate
        self.forbiddenPatterns = forbiddenPatterns
        self.forbiddenExerciseIDs = forbiddenExerciseIDs
        self.allowedExerciseIDs = allowedExerciseIDs
        self.restrictionTags = restrictionTags
        self.notes = notes
    }

    /// ¿Tiene contenido accionable (al menos un patrón/ejercicio/tag a aplicar)?
    public var isEmpty: Bool {
        forbiddenPatterns.isEmpty
            && forbiddenExerciseIDs.isEmpty
            && allowedExerciseIDs.isEmpty
            && restrictionTags.isEmpty
    }
}

/// Problemas de entrada de la gestión de restricciones.
public enum RestrictionManagerError: Error, Equatable, Sendable {
    /// Restricción sin contenido accionable.
    case emptyRestriction
    /// Restricción de origen profesional requiere confirmación explícita.
    case needsExplicitConfirmation
    /// Transición de estado no permitida (el estado anterior no la admite).
    case invalidStateTransition(from: String, to: String)
}

/// Manager determinista de restricciones (PR-1401).
///
/// - `create` valida contenido y, para `professionalGuidance`, exige confirmación
///   explícita antes de estructurarse (§16.2).
/// - `update` revalida y aplica ediciones.
/// - `review(asOf:)` sólo pasa `active` → `reviewNeeded` cuando pasa `reviewDate`;
///   NUNCA resuelve automáticamente (§16.2).
/// - `resolve` exige transición válida (sólo desde `reviewNeeded`) y, para origen
///   profesional, confirmación explícita.
public struct RestrictionManager: Sendable {
    public init() {}

    public func create(from draft: RestrictionDraft, explicitlyConfirmed: Bool, now: Date = Date()) throws -> TrainingRestriction {
        try validate(draft, explicitlyConfirmed: explicitlyConfirmed)
        let side = draft.side
        let restriction = TrainingRestriction(
            bodyRegion: draft.bodyRegion,
            side: side,
            startDate: now,
            reviewDate: draft.reviewDate,
            status: .active,
            source: draft.source,
            forbiddenPatterns: draft.forbiddenPatterns,
            forbiddenExerciseIDs: draft.forbiddenExerciseIDs,
            allowedExerciseIDs: draft.allowedExerciseIDs,
            restrictionTags: draft.restrictionTags,
            notes: draft.notes
        )
        return restriction
    }

    public func update(
        _ restriction: TrainingRestriction,
        with draft: RestrictionDraft,
        explicitlyConfirmed: Bool
    ) throws -> TrainingRestriction {
        try validate(draft, explicitlyConfirmed: explicitlyConfirmed)
        var updated = restriction
        updated.bodyRegion = draft.bodyRegion
        updated.side = draft.side
        updated.source = draft.source
        updated.reviewDate = draft.reviewDate
        updated.forbiddenPatterns = draft.forbiddenPatterns
        updated.forbiddenExerciseIDs = draft.forbiddenExerciseIDs
        updated.allowedExerciseIDs = draft.allowedExerciseIDs
        updated.restrictionTags = draft.restrictionTags
        updated.notes = draft.notes
        return updated
    }

    /// La fecha de revisión NO auto-resuelve: sólo pasa a `reviewNeeded` (§16.2).
    public func review(_ restriction: TrainingRestriction, asOf now: Date) -> TrainingRestriction {
        restriction.refreshed(asOf: now)
    }

    /// Resolver una restricción requiere acción explícita del usuario (§16.2).
    public func resolve(
        _ restriction: TrainingRestriction,
        explicitlyConfirmed: Bool = true
    ) throws -> TrainingRestriction {
        if restriction.source == .professionalGuidance && !explicitlyConfirmed {
            throw RestrictionManagerError.needsExplicitConfirmation
        }
        do {
            let next: RestrictionStatus = try restriction.status.transitioning(to: .resolved)
            return restriction.updatedStatus(next)
        } catch {
            throw RestrictionManagerError.invalidStateTransition(
                from: restriction.status.rawValue,
                to: RestrictionStatus.resolved.rawValue
            )
        }
    }

    // MARK: - Helpers

    private func validate(_ draft: RestrictionDraft, explicitlyConfirmed: Bool) throws {
        if draft.isEmpty {
            throw RestrictionManagerError.emptyRestriction
        }
        if draft.source == .professionalGuidance && !explicitlyConfirmed {
            throw RestrictionManagerError.needsExplicitConfirmation
        }
    }
}