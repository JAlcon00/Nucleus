//
//  PersistenceSchemas.swift
//  PRCore
//
//  SCRUM-40: formato vigente de cada colección guardada.
//
//  Regla (ADR-0003): un cambio de modelo persistido que no sea solo agregar un campo
//  opcional sube `current` de su colección, agrega el paso que convierte la versión
//  anterior y guarda la muestra de la versión anterior en
//  `Tests/PRCoreTests/Fixtures/Persistence/v<N>/`. `PersistenceFormatTests` falla en
//  `make ci` hasta que las tres cosas estén.
//

import Foundation
import PRDomain

public enum PersistenceSchemas {

    /// Formato vigente de `collection` y cómo llegar a él desde la versión 1.
    public static func schema(for collection: PersistenceCollection) -> CollectionSchema {
        switch collection {
        case .workouts:
            // v2 (SCRUM-32): el dolor de cada serie en la escala única.
            return CollectionSchema(
                current: .initial.next,
                steps: [SchemaMigrationStep(from: .initial, transform: PainScaleMigration.workout)],
                isReadable: { collection.decodes($0) }
            )
        case .pendingOperations:
            // v2 (SCRUM-32): el dolor de las series pendientes en la escala única.
            return CollectionSchema(
                current: .initial.next,
                steps: [SchemaMigrationStep(from: .initial, transform: PainScaleMigration.pendingOperations)],
                isReadable: { collection.decodes($0) }
            )
        case .profile, .blocks, .exercises, .gyms, .restrictions,
             .decisions, .agentAudit, .plans, .session, .aiConsent, .checkIns:
            // Siguen en el formato de antes de SCRUM-40.
            return CollectionSchema(current: .initial, steps: [], isReadable: { collection.decodes($0) })
        }
    }
}

/// v1 → v2 (SCRUM-32): el dolor de cada serie pasa de la escala anterior (severidad 1–5 y
/// molestia/punzante) a la escala única con la tabla de `LegacyPainScale`. El modelo
/// actual lee la forma anterior y guarda la nueva, así que basta con leer y volver a
/// guardar cada registro.
enum PainScaleMigration {
    static func workout(_ data: Data) throws -> Data {
        try JSONEncoder().encode(JSONDecoder().decode(WorkoutSessionRecord.self, from: data))
    }

    /// Cada serie pendiente lleva su `SetRecord` dentro del payload de la operación.
    static func pendingOperations(_ data: Data) throws -> Data {
        let queue = try JSONDecoder().decode(PendingOperationQueue.self, from: data)
        let operations = try queue.operations.map { operation -> PendingOperation in
            switch operation.kind {
            case .saveSet:
                let save = try JSONDecoder().decode(StoredSetSave.self, from: operation.payload)
                return PendingOperation(
                    id: operation.id, idempotencyKey: operation.idempotencyKey, kind: operation.kind,
                    payload: try JSONEncoder().encode(save), createdAt: operation.createdAt
                )
            }
        }
        return try JSONEncoder().encode(PendingOperationQueue(operations: operations))
    }
}

extension PersistenceCollection {
    /// ¿`data` decodifica como el modelo vigente de esta colección?
    func decodes(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        switch self {
        case .workouts: return (try? decoder.decode(WorkoutSessionRecord.self, from: data)) != nil
        case .pendingOperations: return (try? decoder.decode(PendingOperationQueue.self, from: data)) != nil
        case .profile: return (try? decoder.decode(UserTrainingProfile.self, from: data)) != nil
        case .blocks: return (try? decoder.decode(TrainingBlock.self, from: data)) != nil
        case .exercises: return (try? decoder.decode(Exercise.self, from: data)) != nil
        case .gyms: return (try? decoder.decode(GymProfile.self, from: data)) != nil
        case .restrictions: return (try? decoder.decode(TrainingRestriction.self, from: data)) != nil
        case .decisions: return (try? decoder.decode(DecisionRecord.self, from: data)) != nil
        case .agentAudit: return (try? decoder.decode(AgentAuditRecord.self, from: data)) != nil
        case .plans: return (try? decoder.decode(StoredPlan.self, from: data)) != nil
        case .session: return (try? decoder.decode(StoredSession.self, from: data)) != nil
        case .aiConsent: return (try? decoder.decode(StoredAIConsent.self, from: data)) != nil
        case .checkIns: return (try? decoder.decode(SleepCheckIn.self, from: data)) != nil
        }
    }
}
