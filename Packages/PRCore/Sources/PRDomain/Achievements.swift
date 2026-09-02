//
//  Achievements.swift
//  PRDomain
//
//  Created by PR.
//
//  Achievement framework (PR-1703). Detecta logros de forma DETERMINISTA a partir de
//  señales declarativas ya calculadas por otros motores del dominio (nunca por el LLM):
//  PR detector (PR-1003), consistency (PR-1702), working sets (WorkoutSummary), sustitución
//  (PR-0904), bloques y deload (BlockPlanner/DeloadEngine). El motor solo baja umbrales;
//  la política y los datos los deciden los motores de entrenamiento.
//
//  INVARIANTE: idempotente y auditable. Dado el mismo snapshot + el conjunto de logros ya
//  desbloqueados, devuelve el mismo resultado; un logro ya desbloqueado no se re-unlockea.
//

import Foundation

/// Identificador canónico de cada logro (PR-1703).
public enum AchievementID: String, Codable, Sendable, CaseIterable, Hashable {
    case firstWorkout
    case firstPR
    case consistency4Weeks
    case consistency8Weeks
    case blockComplete
    case deloadComplete
    case firstSmartSubstitution
    case workingSets100
    case workingSets500
    case workingSets1000
}

/// Definición legible de un logro (para UI, sin reglas de negocio en Views).
public struct AchievementDefinition: Equatable, Sendable, Codable {
    public let id: AchievementID
    public let title: String
    public let description: String

    public init(id: AchievementID, title: String, description: String) {
        self.id = id
        self.title = title
        self.description = description
    }
}

/// Estado actual de un logro.
public struct AchievementStatus: Equatable, Sendable {
    public let definition: AchievementDefinition
    public let unlocked: Bool
    /// Fecha de desbloqueo (nil si aún no unlocked).
    public let unlockedAt: Date?

    public init(definition: AchievementDefinition, unlocked: Bool, unlockedAt: Date? = nil) {
        self.definition = definition
        self.unlocked = unlocked
        self.unlockedAt = unlockedAt
    }
}

/// Snapshot declarativo de las señales que alimentan el reconocimiento de logros.
/// Todas las métricas ya las computan otros motores del dominio.
public struct AchievementSnapshot: Sendable {
    public let totalWorkouts: Int
    public let totalWorkingSets: Int
    /// El usuario ha conseguido al menos un PR (PR-1003).
    public let hasAnyPR: Bool
    /// Racha máxima de consistency en semanas (PR-1702).
    public let longestConsistencyWeeks: Int
    /// Bloques completados (BlockPlanner).
    public let completedBlocks: Int
    /// Deloads completados (DeloadEngine).
    public let completedDeloads: Int
    /// Sustituciones inteligentes usadas (PR-0904).
    public let smartSubstitutionsUsed: Int

    public init(
        totalWorkouts: Int = 0,
        totalWorkingSets: Int = 0,
        hasAnyPR: Bool = false,
        longestConsistencyWeeks: Int = 0,
        completedBlocks: Int = 0,
        completedDeloads: Int = 0,
        smartSubstitutionsUsed: Int = 0
    ) {
        self.totalWorkouts = totalWorkouts
        self.totalWorkingSets = totalWorkingSets
        self.hasAnyPR = hasAnyPR
        self.longestConsistencyWeeks = longestConsistencyWeeks
        self.completedBlocks = completedBlocks
        self.completedDeloads = completedDeloads
        self.smartSubstitutionsUsed = smartSubstitutionsUsed
    }
}

/// Resultado del motor de logros.
public struct AchievementEngineResult: Equatable, Sendable {
    /// Estado de TODOS los logros (ordenado por ID).
    public let statuses: [AchievementStatus]
    /// Logros desbloqueados en ESTA evaluación.
    public let newlyUnlocked: [AchievementDefinition]

    public init(statuses: [AchievementStatus], newlyUnlocked: [AchievementDefinition]) {
        self.statuses = statuses
        self.newlyUnlocked = newlyUnlocked
    }
}

/// Motor determinista de reconocimiento de logros (PR-1703).
public struct AchievementEngine: Sendable {

    public init() {}

    /// Evalúa el snapshot y devuelve el estado de cada logro.
    ///
    /// - Parameters:
    ///   - snapshot: señales declarativas (de motores del dominio o de la app).
    ///   - now: instante usado como `unlockedAt`.
    ///
    /// Cada logro se desbloquea cuando su umbral se alcanza. `alreadyUnlocked` evita
    /// re-desbloqueos: si un logro ya estaba unlocked, se mantiene con su estado previo.
    public func evaluate(
        snapshot: AchievementSnapshot,
        alreadyUnlocked: Set<AchievementID> = [],
        now: Date = Date()
    ) throws -> AchievementEngineResult {
        guard snapshot.totalWorkouts >= 0,
              snapshot.totalWorkingSets >= 0,
              snapshot.longestConsistencyWeeks >= 0,
              snapshot.completedBlocks >= 0,
              snapshot.completedDeloads >= 0,
              snapshot.smartSubstitutionsUsed >= 0 else {
            throw DomainValidationError.invalidAchievementSnapshot
        }

        let definitions = Self.definitionsOrdered()
        var newlyUnlocked: [AchievementDefinition] = []
        var statuses: [AchievementStatus] = []

        func unlocked(_ id: AchievementID) -> Bool {
            if alreadyUnlocked.contains(id) { return true }
            return shouldUnlock(id, in: snapshot)
        }

        for definition in definitions {
            let didUnlock = unlocked(definition.id)
            if didUnlock, !alreadyUnlocked.contains(definition.id) {
                newlyUnlocked.append(definition)
            }
            statuses.append(AchievementStatus(
                definition: definition,
                unlocked: didUnlock,
                unlockedAt: didUnlock ? now : nil
            ))
        }

        return AchievementEngineResult(statuses: statuses, newlyUnlocked: newlyUnlocked)
    }

    /// ¿Se cumple el umbral de un logro dado el snapshot?
    public func shouldUnlock(_ id: AchievementID, in snapshot: AchievementSnapshot) -> Bool {
        switch id {
        case .firstWorkout:
            return snapshot.totalWorkouts >= 1
        case .firstPR:
            return snapshot.hasAnyPR
        case .consistency4Weeks:
            return snapshot.longestConsistencyWeeks >= 4
        case .consistency8Weeks:
            return snapshot.longestConsistencyWeeks >= 8
        case .blockComplete:
            return snapshot.completedBlocks >= 1
        case .deloadComplete:
            return snapshot.completedDeloads >= 1
        case .firstSmartSubstitution:
            return snapshot.smartSubstitutionsUsed >= 1
        case .workingSets100:
            return snapshot.totalWorkingSets >= 100
        case .workingSets500:
            return snapshot.totalWorkingSets >= 500
        case .workingSets1000:
            return snapshot.totalWorkingSets >= 1000
        }
    }

    /// Definiciones de todos los logros en orden estable.
    public static func definitionsOrdered() -> [AchievementDefinition] {
        [
            AchievementDefinition(id: .firstWorkout, title: "Primer entrenamiento", description: "Completa tu primera sesión."),
            AchievementDefinition(id: .firstPR, title: "Primer récord", description: "Consigue tu primer PR de carga, reps o e1RM."),
            AchievementDefinition(id: .consistency4Weeks, title: "Constancia 4 semanas", description: "Cumple tu plan 4 semanas seguidas."),
            AchievementDefinition(id: .consistency8Weeks, title: "Constancia 8 semanas", description: "Cumple tu plan 8 semanas seguidas."),
            AchievementDefinition(id: .blockComplete, title: "Bloque completado", description: "Termina un bloque completo."),
            AchievementDefinition(id: .deloadComplete, title: "Deload completado", description: "Completa un deload."),
            AchievementDefinition(id: .firstSmartSubstitution, title: "Sustitución inteligente", description: "Usa tu primera sustitución recomendada."),
            AchievementDefinition(id: .workingSets100, title: "100 work sets", description: "Acumula 100 working sets."),
            AchievementDefinition(id: .workingSets500, title: "500 work sets", description: "Acumula 500 working sets."),
            AchievementDefinition(id: .workingSets1000, title: "1000 work sets", description: "Acumula 1000 working sets."),
        ]
    }
}