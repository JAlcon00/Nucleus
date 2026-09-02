//
//  AgentSchema.swift
//  PRCore
//
//  Created by PR.
//
//  Schema local de intenciones que el `LLMBackendTransport` pasa al LLM para que
//  emita JSON válido, y contra el que se valida la salida (PR-1608, Phase N2).
//
//  Vive en la capa de core (no dominio): es un prompt/schema de interpretación, no
//  lógica de negocio ni cálculo determinista. El dominio (`AgentIntent`) sigue siendo
//  la única fuente de verdad de la estructura; aquí sólo se expone la forma wire.
//

/// Descripción del schema de intents para guiar (y acotar) la salida del LLM.
public struct AgentSchema: Sendable {
    /// Lista de ejemplos ilustrativos del shape wire esperado (formato, no contenido).
    public let intentJSONExamples: [String]
    /// Lista de tags de intent válidos.
    public let intentTags: [String]

    public init(intentJSONExamples: [String], intentTags: [String]) {
        self.intentJSONExamples = intentJSONExamples
        self.intentTags = intentTags
    }

    /// Schema vigente acorde a `AgentIntent` (PR-1601). Mantener en sincronía con él.
    public static let current = AgentSchema(
        intentJSONExamples: [
            #"{"intent":"setTimeConstraint","payload":{"value":"hard:30"}}"#,
            #"{"intent":"changeGoal","payload":{"value":"hypertrophy"}}"#,
            #"{"intent":"reportPain","payload":{"value":{"level":3}}}"#,
            #"{"intent":"reportFatigue","payload":{"value":{"severity":4}}}"#,
        ],
        intentTags: [
            "setTimeConstraint", "equipmentUnavailable", "requestExerciseSwap",
            "reportFatigue", "reportPain", "changeGoal", "changePhase", "changeGym",
            "askWhy", "updateRestriction", "requestPlanAdjustment", "needsClarification",
        ]
    )
}
