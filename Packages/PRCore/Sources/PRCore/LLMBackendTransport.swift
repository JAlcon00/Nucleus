//
//  LLMBackendTransport.swift
//  PRCore
//
//  Created by PR.
//
//  Adaptador que une `LLMProvider` (PRCore) con el contrato puro del dominio
//  `AgentBackendTransport` (PRDomain, PR-1603). Es la implementación HTTP/LLM del
//  transporte que `AgentGateway` usa; vive en la capa de app/CORE, nunca en el dominio.
//
//  INVARIANTES (promptMaster §20.5, AGENTS "no rely on LLM for deterministic calcs"):
//  - El LLM SÓLO interpreta y explica: nunca calcula carga/volumen/restricciones.
//    `interpret` produce un `AgentIntent` estructurado que el engine + policy validator
//    deciden. `explain` usa SÓLO los facts provistos.
//  - La salida del LLM se valida por schema local: si no decodifica como `AgentIntent`,
//    se devuelve `needsClarification` (falla seguro, §20.1); nunca se parsea texto libre.
//  - No se inyecta la API key aquí: el `LLMProvider` subyacente la maneja en runtime.
//

import Foundation
import PRDomain

/// Transporte que delega en un `LLMProvider` real. Implementa `AgentBackendTransport`.
public struct LLMBackendTransport: AgentBackendTransport, Sendable {
    private let provider: any LLMProvider
    private let schema: AgentSchema

    public init(provider: any LLMProvider, schema: AgentSchema = .current) {
        self.provider = provider
        self.schema = schema
    }

    // MARK: - interpret (texto → intent, schema validado)

    public func interpret(_ request: InterpretRequest) async throws -> InterpretResponse {
        let examples = schema.intentJSONExamples.joined(separator: "\n")
        let system = """
        Eres el intérprete estructurado de PR. El usuario habla español sobre su entrenamiento.
        Debes clasificar la intención del usuario y devolver ÚNICAMENTE un JSON válido con este
        shape (clave "intent" = tag, y clave "payload" cuyo "value" es el valor tipado).

        Los siguientes SON SOLO EJEMPLOS DE FORMATO, NO respuestas. Ignora su contenido y
        deriva el intent SOLO del mensaje del usuario:
        \(examples)

        Tags válidos: \(schema.intentTags.joined(separator: ", "))

        Restricciones de valor del payload:
        - setTimeConstraint value: string "hard:<min>" o "flexible:<target>:<tol>".
        - changeGoal value: "generalHealth"|"hypertrophy"|"strength"|"powerbuilding"|"recomposition"|"bodybuilding".
        - changePhase value: "surplus"|"deficit"|"maintenance"|"unspecified".
        - reportFatigue value: {"severity": N} con N entero 1...5.
        - reportPain value: {"level": N} con N entero 0...3 (0=ninguno,1=leve,2=moderado,3=alto). Usa solo un nivel que el dolor del texto justifique; si el usuario no lo hace claro usa 3.
        - Dolor/fatiga se reportan tal cual; NUNCA diagnostiques ni inventes niveles fuera de rango.

        Reglas:
        - No respondas texto; devuelve solo el JSON, sin comillas sobrantes ni texto extra.
        - El `payload.value` debe reflejar lo que dijo el usuario (minutos, objetivo, fase, etc.).
        - Si el usuario pide más de una cosa o no queda claro, devuelve: {"intent":"needsClarification"}
        - NO inventes números de carga, volumen ni restricciones que no estén en el texto.
        """
        let contextLine = contextDescription(request.context)
        let prompt = "Contexto (advisory, no para calcular): \(contextLine)\nUsuario: \(request.text)"
        let response = try await provider.complete(
            AgentRequest(
                messages: [AgentMessage(role: "system", content: system), AgentMessage(role: "user", content: prompt)],
                mode: .fast
            )
        )

        guard let text = response.text, !text.isEmpty else {
            return InterpretResponse(intent: nil, needsClarification: true)
        }
        return try parseInterpretation(from: text)
    }

    // MARK: - explain (facts → explicación breve)

    public func explain(_ request: ExplainRequest) async throws -> ExplainResponse {
        let factsText = request.facts.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let system = """
        Eres el explicador de PR. Explica por qué se tomó una decisión de entrenamiento.
        Devuelve UN texto breve en español con 1-4 razones concretas, separadas por líneas,
        y solo usando los facts provistos. No inventes razones.
        """
        let prompt = "Facts:\n\(factsText.isEmpty ? "(ninguno)" : factsText)"
        let response = try await provider.complete(
            AgentRequest(
                messages: [AgentMessage(role: "system", content: system), AgentMessage(role: "user", content: prompt)],
                mode: .fast
            )
        )
        guard let text = response.text, !text.isEmpty else {
            return ExplainResponse(text: nil, reasons: [])
        }
        var parsed: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parsed.append(trimmed) }
            if parsed.count == 4 { break }
        }
        return ExplainResponse(text: text, reasons: parsed)
    }

    // MARK: - Schema y parseo seguro

    private func parseInterpretation(from raw: String) throws -> InterpretResponse {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // tolera code fences ```json ... ```
        let json: String
        if trimmed.hasPrefix("```") {
            json = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8) else {
            return InterpretResponse(intent: nil, needsClarification: true)
        }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rawTag = object?["intent"] as? String ?? "needsClarification"
        guard rawTag != "needsClarification" else {
            return InterpretResponse(intent: nil, needsClarification: true)
        }
        do {
            let intent = try JSONDecoder().decode(AgentIntent.self, from: data)
            return InterpretResponse(intent: intent, needsClarification: false)
        } catch {
            return InterpretResponse(intent: nil, needsClarification: true)
        }
    }

    private func contextDescription(_ context: AgentContext) -> String {
        var parts: [String] = []
        if context.activeRestrictionCount > 0 {
            parts.append("\(context.activeRestrictionCount) restricción(es) activa(s)")
        }
        if context.painGateActive {
            parts.append("gate de dolor activo")
        }
        if context.todaySessionStarted {
            parts.append("sesión de hoy iniciada")
        }
        return parts.isEmpty ? "sin restricciones/estado particular" : parts.joined(separator: ", ")
    }
}
