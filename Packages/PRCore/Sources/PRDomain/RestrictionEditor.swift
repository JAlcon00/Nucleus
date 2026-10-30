//
//  RestrictionEditor.swift
//  PRDomain
//
//  SCRUM-36: lo que se hace desde Perfil › Restricciones, como operaciones puras sobre la
//  lista de restricciones del perfil: agregar una zona, editarla, evitar o permitir un
//  ejercicio concreto y resolverla. Valida con `RestrictionManager` y usa la tabla
//  zona → patrones de SCRUM-209. Decisiones de Jesús (2026-10-29):
//  1. una activa se puede resolver ("Ya no me molesta"), siempre con confirmación;
//  2. desmarcar una zona en el cuestionario la resuelve y no la borra (`BodyRegionRestrictionRule`);
//  3. evitar un ejercicio vale con cualquier origen; permitirlo, sólo con origen profesional;
//  4. el lado se guarda y se muestra, pero el plan cuida la zona en los dos lados (el
//     catálogo no distingue lados).
//  Nada se borra: una resuelta queda en el historial. Cualquier cambio a una restricción de
//  origen profesional pide confirmación explícita (RN-020). No diagnostica.
//

import Foundation

/// Por qué no se aplicó un cambio de la pantalla de restricciones.
public enum RestrictionEditError: Error, Equatable, Sendable {
    /// La zona ya tiene una restricción en vigor: se abre esa para editarla, no se duplica.
    case alreadyInForce(RestrictionID)
    case notFound
    /// Una resuelta es historial: no se edita.
    case alreadyResolved
    /// Falta la confirmación explícita (origen profesional o resolver).
    case needsExplicitConfirmation
    /// Permitir un ejercicio pese a la zona sólo con indicación profesional.
    case allowRequiresProfessional
    /// La nota pasa del máximo de caracteres.
    case noteTooLong(Int)
}

/// Lo que se edita de una restricción en la pantalla (la zona no cambia: se resuelve y se
/// agrega otra).
public struct RestrictionDetails: Equatable, Sendable {
    public var side: BodySide?
    public var source: RestrictionSource
    public var reviewDate: Date?
    public var notes: String?

    public init(side: BodySide? = nil, source: RestrictionSource = .userReported, reviewDate: Date? = nil, notes: String? = nil) {
        self.side = side
        self.source = source
        self.reviewDate = reviewDate
        self.notes = notes
    }

    /// Máximo de caracteres de la nota, igual que la del cuestionario.
    public static let maxNoteLength = RestrictionsAnswer.maxNoteLength

    /// Nota limpia (`nil` si está vacía).
    var trimmedNotes: String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct RestrictionEditor: Sendable {
    private let manager = RestrictionManager()

    public init() {}

    /// Agrega una restricción activa para `region` con los patrones y la etiqueta de la tabla
    /// de SCRUM-209. Si la zona ya tiene una en vigor, no duplica: lanza `alreadyInForce`.
    public func adding(
        _ region: BodyRegion,
        details: RestrictionDetails,
        to restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool,
        now: Date,
        newID: () -> RestrictionID = { RestrictionID() }
    ) throws -> [TrainingRestriction] {
        if let existing = restrictions.first(where: { $0.bodyRegion == region && $0.isInForce }) {
            throw RestrictionEditError.alreadyInForce(existing.id)
        }
        let notes = try validNotes(details)
        let draft = RestrictionDraft(
            bodyRegion: region,
            side: details.side,
            source: details.source,
            reviewDate: details.reviewDate,
            forbiddenPatterns: BodyRegionRestrictionRule.forbiddenPatterns(for: region),
            restrictionTags: BodyRegionRestrictionRule.tag(for: region).map { [$0] } ?? [],
            notes: notes
        )
        let created = try mapped { try manager.create(from: draft, explicitlyConfirmed: explicitlyConfirmed, now: now, id: newID()) }
        return restrictions + [created]
    }

    /// Cambia el lado, el origen, la fecha de revisión o la nota. Los patrones y los
    /// ejercicios concretos se conservan.
    public func updating(
        _ id: RestrictionID,
        details: RestrictionDetails,
        in restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool
    ) throws -> [TrainingRestriction] {
        let notes = try validNotes(details)
        return try modifying(id, in: restrictions) { restriction in
            let draft = RestrictionDraft(
                bodyRegion: restriction.bodyRegion,
                side: details.side,
                source: details.source,
                reviewDate: details.reviewDate,
                forbiddenPatterns: restriction.forbiddenPatterns,
                forbiddenExerciseIDs: restriction.forbiddenExerciseIDs,
                allowedExerciseIDs: restriction.allowedExerciseIDs,
                restrictionTags: restriction.restrictionTags,
                notes: notes
            )
            return try mapped { try manager.update(restriction, with: draft, explicitlyConfirmed: explicitlyConfirmed) }
        }
    }

    /// Evita un ejercicio concreto (cualquier origen). Si estaba permitido en esta misma
    /// restricción, deja de estarlo.
    public func avoiding(
        _ exercise: ExerciseID,
        in id: RestrictionID,
        restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool
    ) throws -> [TrainingRestriction] {
        try modifying(id, in: restrictions) { restriction in
            try requireConfirmation(for: restriction, explicitlyConfirmed)
            var updated = restriction
            updated.allowedExerciseIDs.remove(exercise)
            updated.forbiddenExerciseIDs.insert(exercise)
            return updated
        }
    }

    /// Permite un ejercicio pese a la zona. Sólo con origen profesional y confirmación: el
    /// permiso refina esta restricción y nunca anula otra (SCRUM-31).
    public func allowing(
        _ exercise: ExerciseID,
        in id: RestrictionID,
        restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool
    ) throws -> [TrainingRestriction] {
        try modifying(id, in: restrictions) { restriction in
            guard restriction.source == .professionalGuidance else {
                throw RestrictionEditError.allowRequiresProfessional
            }
            try requireConfirmation(for: restriction, explicitlyConfirmed)
            var updated = restriction
            updated.forbiddenExerciseIDs.remove(exercise)
            updated.allowedExerciseIDs.insert(exercise)
            return updated
        }
    }

    /// Quita un ejercicio de los evitados o los permitidos de la restricción.
    public func removing(
        _ exercise: ExerciseID,
        from id: RestrictionID,
        restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool
    ) throws -> [TrainingRestriction] {
        try modifying(id, in: restrictions) { restriction in
            try requireConfirmation(for: restriction, explicitlyConfirmed)
            var updated = restriction
            updated.forbiddenExerciseIDs.remove(exercise)
            updated.allowedExerciseIDs.remove(exercise)
            return updated
        }
    }

    /// "Ya no me molesta": la resuelve con su fecha (siempre con confirmación). Deja de
    /// limitar el plan y queda en el historial.
    public func resolving(
        _ id: RestrictionID,
        in restrictions: [TrainingRestriction],
        explicitlyConfirmed: Bool,
        now: Date
    ) throws -> [TrainingRestriction] {
        try modifying(id, in: restrictions) { restriction in
            try mapped { try manager.resolve(restriction, explicitlyConfirmed: explicitlyConfirmed, now: now) }
        }
    }

    // MARK: - Helpers

    /// Aplica `change` a la restricción `id` en su lugar de la lista. Una resuelta no se edita.
    private func modifying(
        _ id: RestrictionID,
        in restrictions: [TrainingRestriction],
        _ change: (TrainingRestriction) throws -> TrainingRestriction
    ) throws -> [TrainingRestriction] {
        guard let index = restrictions.firstIndex(where: { $0.id == id }) else {
            throw RestrictionEditError.notFound
        }
        guard restrictions[index].isInForce else { throw RestrictionEditError.alreadyResolved }
        var updated = restrictions
        updated[index] = try change(restrictions[index])
        return updated
    }

    private func requireConfirmation(for restriction: TrainingRestriction, _ explicitlyConfirmed: Bool) throws {
        if restriction.source == .professionalGuidance && !explicitlyConfirmed {
            throw RestrictionEditError.needsExplicitConfirmation
        }
    }

    private func validNotes(_ details: RestrictionDetails) throws -> String? {
        let notes = details.trimmedNotes
        if let notes, notes.count > RestrictionDetails.maxNoteLength {
            throw RestrictionEditError.noteTooLong(RestrictionDetails.maxNoteLength)
        }
        return notes
    }

    /// Traduce los errores del manager a los de la pantalla.
    private func mapped<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch RestrictionManagerError.needsExplicitConfirmation {
            throw RestrictionEditError.needsExplicitConfirmation
        } catch RestrictionManagerError.invalidStateTransition {
            throw RestrictionEditError.alreadyResolved
        }
    }
}
