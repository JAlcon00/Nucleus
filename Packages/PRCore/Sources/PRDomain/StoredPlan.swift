//
//  StoredPlan.swift
//  PRDomain
//
//  SCRUM-26: lo que la app recuerda del plan de UN usuario entre arranques. Es un
//  registro pequeño que apunta a los bloques (que viven en su propia colección): el
//  perfil del cuestionario, el bloque activo, el historial de bloques y la versión del
//  generador con el que se hizo el plan (para migrar planes viejos, p. ej. con volumen
//  inflado antes de SCRUM-28). Puro: sin persistencia ni reloj.
//

import Foundation

/// Plan guardado de un usuario. `userID` es el identificador opaco de Apple (nunca un
/// token ni un correo).
public struct StoredPlan: Codable, Sendable, Equatable {
    /// Versión actual del generador de bloques. Subirla fuerza la migración de los
    /// planes guardados con una versión menor.
    /// 1 = volumen inflado (antes de SCRUM-28, nunca se llegó a guardar así);
    /// 2 = volumen real repartido por día y orden por rol/fatiga (SCRUM-28/29);
    /// 3 = ejercicios de referencia por músculo (sentadilla, press, remo… en vez del primer
    ///     candidato por coincidencia de datos);
    /// 4 = composición de sesión (SCRUM-218): rango de ejercicios por duración, nunca 1 serie,
    ///     el ancla al menos 2 veces por semana;
    /// 5 = pantorrilla y core en mantenimiento (SCRUM-215), si caben en el tiempo;
    /// 6 = catálogo bien clasificado (SCRUM-37): las restricciones ya no dejan pasar
    ///     ejercicios mal clasificados (p. ej. tríceps con cuerda con restricción de codo);
    /// 7 = selección por slots, objetivo, experiencia y fase (SCRUM-219), con rotables que
    ///     cambian de un bloque al siguiente.
    public static let currentGeneratorVersion = 7

    public let userID: String
    public var profile: OnboardingProfile
    public var activeBlockID: TrainingBlockID
    /// Todos los bloques del usuario (activo incluido), del más antiguo al más reciente.
    public var blockHistory: [TrainingBlockID]
    public var generatorVersion: Int
    /// Explicación del bloque activo (orden de cada sesión), para "¿Por qué este orden?".
    public var explanation: BlockExplanation
    public var updatedAt: Date
    /// Lo que la IA personalizó y la explicación "Por qué tu plan es así" (SCRUM-205).
    /// Opcional: los planes guardados antes no lo traen y siguen leyéndose igual.
    public var personalization: PlanPersonalizationRecord?
    /// Orden propio de los ejercicios por sesión (SCRUM-211), clave = ID de la sesión. El
    /// bloque guardado conserva el orden del motor. Opcional: los planes anteriores no lo
    /// traen.
    public var customOrders: [String: [ExerciseID]]?
    /// Tiempo elegido para la sesión del día (SCRUM-30). Se guarda para que un
    /// entrenamiento empezado con la sesión recortada se retome igual tras un cierre; sólo
    /// aplica el día en que se eligió. Opcional: los planes anteriores no lo traen.
    public var timeBudget: SessionTimeChoice?

    /// Órdenes propios con su ID de sesión tipado (los inválidos se ignoran).
    public var sessionOrders: [SessionTemplate.ID: [ExerciseID]] {
        Dictionary(uniqueKeysWithValues: (customOrders ?? [:]).compactMap { key, order in
            UUID(uuidString: key).map { ($0, order) }
        })
    }

    public init(
        userID: String,
        profile: OnboardingProfile,
        activeBlockID: TrainingBlockID,
        blockHistory: [TrainingBlockID],
        generatorVersion: Int = StoredPlan.currentGeneratorVersion,
        explanation: BlockExplanation,
        updatedAt: Date,
        personalization: PlanPersonalizationRecord? = nil
    ) {
        self.userID = userID
        self.profile = profile
        self.activeBlockID = activeBlockID
        self.blockHistory = blockHistory
        self.generatorVersion = generatorVersion
        self.explanation = explanation
        self.updatedAt = updatedAt
        self.personalization = personalization
    }

    /// ¿Se generó con un generador anterior al actual (hay que regenerarlo)?
    public var needsMigration: Bool { generatorVersion < Self.currentGeneratorVersion }

    /// Lugar de `blockID` en el historial (0 = el primero), para regenerarlo igual
    /// (SCRUM-219). Si no está, el último.
    public func blockSequence(of blockID: TrainingBlockID) -> Int {
        blockHistory.firstIndex(of: blockID) ?? max(0, blockHistory.count - 1)
    }
}

/// Sesión recordada entre arranques: SOLO el identificador opaco del usuario (más la
/// versión del formato, que además hace el registro inconfundible con un `StoredPlan`
/// al clasificar archivos por contenido).
public struct StoredSession: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public let userID: String
    public let formatVersion: Int

    public init(userID: String, formatVersion: Int = StoredSession.currentFormatVersion) {
        self.userID = userID
        self.formatVersion = formatVersion
    }
}

/// Qué hacer con el plan cuando el usuario vuelve a contestar el cuestionario.
public enum PlanChange: Equatable, Sendable {
    /// Mismo perfil: se conserva el bloque tal cual.
    case unchanged
    /// Cambió algo que no define el bloque (minutos, variedad, experiencia, restricciones):
    /// se regenera el MISMO bloque (mismo ID e historial).
    case regenerateInPlace
    /// Cambió objetivo, fase o los días de entrenamiento (cuántos o cuáles, SCRUM-196):
    /// bloque nuevo; el anterior se cierra y se conserva.
    case newBlock
    /// Sólo cambió "Sobre ti" (SCRUM-198): se guarda el perfil; el bloque sigue igual.
    case updateProfileOnly
}

public enum PlanChangeDecider {
    public static func decide(old: OnboardingProfile, new: OnboardingProfile) -> PlanChange {
        if old.goal != new.goal || old.phase != new.phase
            || old.trainingDaysPerWeek != new.trainingDaysPerWeek
            || old.trainingWeekdays != new.trainingWeekdays {
            return .newBlock
        }
        if old.trainingFields == new.trainingFields {
            return old.aboutYou == new.aboutYou ? .unchanged : .updateProfileOnly
        }
        return .regenerateInPlace
    }
}
