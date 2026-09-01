//
//  Restriction.swift
//  PRDomain
//
//  Created by PR.
//
//  Dominio de restricciones de entrenamiento (promptMaster §16, PR-0106).
//  Una restricción no se autoelimina al llegar su reviewDate: pasa a
//  `reviewNeeded` hasta que el usuario la confirma o resuelve.
//

import Foundation

// MARK: - Enums (promptMaster §16.1)

/// Región corporal afectada por la restricción.
public enum BodyRegion: String, Codable, Sendable, CaseIterable, Hashable {
    case neck
    case shoulder
    case elbow
    case wrist
    case hand
    case thoracic
    case lumbar
    case hip
    case knee
    case ankle
    case foot
    case groin
    case core
}

/// Lateralidad de la restricción.
public enum BodySide: String, Codable, Sendable, CaseIterable, Hashable {
    case left
    case right
    case bilateral
}

/// Origen de la restricción.
public enum RestrictionSource: String, Codable, Sendable, CaseIterable, Hashable {
    case userReported
    case professionalGuidance
}

/// Estado del ciclo de vida de una restricción.
public enum RestrictionStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case active
    case reviewNeeded
    case resolved

    private static let transitions: [RestrictionStatus: Set<RestrictionStatus>] = [
        .active: [.reviewNeeded],
        .reviewNeeded: [.active, .resolved],
        .resolved: [],
    ]

    public var allowedNext: Set<RestrictionStatus> {
        Self.transitions[self] ?? []
    }

    public func canTransition(to next: RestrictionStatus) -> Bool {
        allowedNext.contains(next)
    }

    @discardableResult
    public func transitioning(to next: RestrictionStatus) throws -> RestrictionStatus {
        guard canTransition(to: next) else {
            throw DomainValidationError.invalidStateTransition(from: rawValue, to: next.rawValue)
        }
        return next
    }
}

// MARK: - TrainingRestriction (promptMaster §16.1)

/// Una restricción de entrenamiento persistible.
public struct TrainingRestriction: Identifiable, Codable, Sendable, Hashable {
    public typealias ID = RestrictionID

    public let id: RestrictionID
    public var bodyRegion: BodyRegion
    public var side: BodySide?
    public var startDate: Date
    public var reviewDate: Date?
    public var status: RestrictionStatus
    public var source: RestrictionSource
    public var forbiddenPatterns: Set<MovementPattern>
    public var forbiddenExerciseIDs: Set<ExerciseID>
    public var allowedExerciseIDs: Set<ExerciseID>
    public var restrictionTags: Set<RestrictionTag>
    public var notes: String?

    public init(
        id: RestrictionID = RestrictionID(),
        bodyRegion: BodyRegion,
        side: BodySide? = nil,
        startDate: Date = Date(),
        reviewDate: Date? = nil,
        status: RestrictionStatus = .active,
        source: RestrictionSource = .userReported,
        forbiddenPatterns: Set<MovementPattern> = [],
        forbiddenExerciseIDs: Set<ExerciseID> = [],
        allowedExerciseIDs: Set<ExerciseID> = [],
        restrictionTags: Set<RestrictionTag> = [],
        notes: String? = nil
    ) {
        self.id = id
        self.bodyRegion = bodyRegion
        self.side = side
        self.startDate = startDate
        self.reviewDate = reviewDate
        self.status = status
        self.source = source
        self.forbiddenPatterns = forbiddenPatterns
        self.forbiddenExerciseIDs = forbiddenExerciseIDs
        self.allowedExerciseIDs = allowedExerciseIDs
        self.restrictionTags = restrictionTags
        self.notes = notes
    }

    /// Devuelve la restricción "refrescada" frente a la fecha actual.
    /// Si el `reviewDate` ya pasó y está `active`, pasa a `reviewNeeded`
    /// (NUNCA se autoelimina por el simple paso del tiempo).
    public func refreshed(asOf now: Date) -> TrainingRestriction {
        guard status == .active, let reviewDate, now >= reviewDate else { return self }
        return updatedStatus(.reviewNeeded)
    }

    /// Aplica una transición de estado validada.
    public func updatedStatus(_ newStatus: RestrictionStatus) -> TrainingRestriction {
        guard newStatus != status else { return self }
        var copy = self
        do {
            copy.status = try status.transitioning(to: newStatus)
            return copy
        } catch {
            return self
        }
    }

    /// Indica si un patrón de movimiento está prohibido por esta restricción.
    public func forbids(_ pattern: MovementPattern) -> Bool {
        forbiddenPatterns.contains(pattern)
    }

    /// Indica si un ejercicio está explícitamente prohibido.
    public func forbids(exercise exerciseID: ExerciseID) -> Bool {
        forbiddenExerciseIDs.contains(exerciseID)
    }
}
