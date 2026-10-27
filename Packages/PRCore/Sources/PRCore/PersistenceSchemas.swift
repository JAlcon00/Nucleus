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
        case .workouts, .pendingOperations, .profile, .blocks, .exercises, .gyms, .restrictions,
             .decisions, .agentAudit, .plans, .session, .aiConsent, .checkIns:
            // Todas siguen en el formato de antes de SCRUM-40.
            return CollectionSchema(current: .initial, steps: [], isReadable: { collection.decodes($0) })
        }
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
