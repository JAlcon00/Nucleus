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
        let system = interpreterSystemPrompt(examples: examples)
        let contextLine = contextDescription(request.context)
        let prompt = "Contexto (advisory, no para calcular): \(contextLine)\nUsuario: \(request.text)"
        let response = try await provider.complete(
            AgentRequest(
                messages: [AgentMessage(role: "system", content: system), AgentMessage(role: "user", content: prompt)],
                mode: .fast,
                output: .json
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
        let prompt = "Facts (únicos datos disponibles):\n\(factsText.isEmpty ? "(ninguno)" : factsText)"
        let response = try await provider.complete(
            AgentRequest(
                messages: [AgentMessage(role: "system", content: explainerSystemPrompt), AgentMessage(role: "user", content: prompt)],
                mode: .fast
            )
        )
        guard let text = response.text, !text.isEmpty else {
            return ExplainResponse(text: nil, reasons: [])
        }
        let parsed = parseReasons(from: text)
        return ExplainResponse(text: parsed.isEmpty ? nil : text, reasons: parsed)
    }

    /// Divide la salida del explicador en razones individuales (1–4, no vacías).
    private func parseReasons(from raw: String) -> [String] {
        var parsed: [String] = []
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmed = Self.stripReasonPrefix(trimmed)
            if !trimmed.isEmpty {
                parsed.append(trimmed)
            }
            if parsed.count == 4 { break }
        }
        return parsed
    }

    /// Quita marcadores de lista: `- `, `* ` y numeración `1.` / `2)` al inicio.
    private static func stripReasonPrefix(_ line: String) -> String {
        var rest = Substring(line)
        if let first = rest.first, first == "-" || first == "*" {
            rest = rest.dropFirst()
        } else {
            var digits = 0
            while rest.dropFirst(digits).first?.isNumber == true {
                digits += 1
            }
            if digits > 0 {
                let afterDigits = rest.dropFirst(digits)
                if afterDigits.first == "." || afterDigits.first == ")" {
                    rest = afterDigits.dropFirst()
                } else {
                    rest = line[...]
                }
            }
        }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Schema y parseo seguro

    private func parseInterpretation(from raw: String) throws -> InterpretResponse {
        let candidates = candidateJSONStrings(from: raw)
        for json in candidates {
            guard let data = json.data(using: .utf8) else { continue }
            // Si no parsea como JSON, prueba el siguiente candidato (p. ej. reparado).
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }
            let rawTag = object["intent"] as? String ?? "needsClarification"
            guard rawTag != "needsClarification" else {
                return InterpretResponse(intent: nil, needsClarification: true)
            }
            do {
                let intent = try JSONDecoder().decode(AgentIntent.self, from: data)
                return InterpretResponse(intent: intent, needsClarification: false)
            } catch {
                // payload inválido → probar el siguiente candidato (si lo hay).
            }
        }
        return InterpretResponse(intent: nil, needsClarification: true)
    }

    /// Devuelve versiones candidatas del JSON: la cruda y, si no parsea, una reparada
    /// que elimina comas sobrantes antes de `}`/`]` (artefacto común de salida LLM).
    private func candidateJSONStrings(from raw: String) -> [String] {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var candidates = [trimmed]
        // Reparo de comas finales: quita `,`/`}` y `,`/`]` fuera de strings.
        let repaired = stripTrailingCommas(in: trimmed)
        if repaired != trimmed {
            candidates.append(repaired)
        }
        return candidates
    }

    private func stripTrailingCommas(in json: String) -> String {
        var output = ""
        var inString = false
        var i = json.startIndex
        while i < json.endIndex {
            let c = json[i]
            output.append(c)
            if c == "\"" {
                // simple toggle burdo, suficiente para el artefacto de comas finales
                if i > json.startIndex {
                    let prev = json.index(before: i)
                    if json[prev] != "\\" { inString.toggle() }
                } else {
                    inString.toggle()
                }
            } else if !inString && (c == "}" || c == "]") {
                // elimina la última coma antes de este cierre
                while let last = output.last, last == "," || last == " " {
                    output.removeLast()
                }
            }
            i = json.index(after: i)
        }
        return output
    }

    // MARK: - System prompt del intérprete (EliteCoachAgent, extracción de intent)

    private func interpreterSystemPrompt(examples: String) -> String {
        """
        # SYSTEM — ELITE COACH AGENT · INSTRUCTOR ESTRUCTURADO

        Eres `EliteCoachAgent`, el intérprete de lenguaje natural de PR, un entrenador
        experto digital basado en evidencia. NO eres un chatbot genérico: eres la capa
        inteligente que CONVIERTE mensajes del usuario en intenciones estructuradas.

        ## Arquitectura de autoridad (crítico)

        Tus decisiones son PROPUESTAS, nunca finales. La jerarquía es:
        USER → AGENT (tú) → ACTION POLICY VALIDATOR → TRAINING ENGINE → DOMAIN STATE.

        Tú interpretas y estructuras. El `TrainingEngine` y el `PolicyValidator` DECIDEN.
        El usuario controla. Nunca confundas estos roles.

        Por tanto:
        - NUNCA calcules cargas, volumen, repeticiones, frecuencia, deload ni adaptaciones.
        - NUNCA diagnostiques lesiones ni inventes gravedad clínica; reporta lo que dijo el usuario.
        - NUNCA inventes datos históricos, PRs, equivalencias o restricciones.
        - Tu único `output` es el JSON que estructura la intención, para que el sistema decida.

        ## Output estricto (§59 de la spec)

        Devuelve ÚNICAMENTE un objeto JSON válido, sin Markdown ni texto alrededor:

        {"intent":"<tag>","payload":{"value":<valor tipado>}}

        - `intent`: exactamente un tag de la lista `Intents`.
        - `payload.value`: valor TIPADO acorde a ese intent (ver `Restricciones de valor`).
        - Si el mensaje pide más de una cosa, es ambiguo, no corresponde a ningún intent
          soportado, o necesitas más información: devuelve {"intent":"needsClarification","payload":{"value":null}}.
        - No agregues comillas sobrantes, texto, comentarios ni `json` fences.

        Los siguientes SON SOLO EJEMPLOS DE FORMATO (no respuestas). Ignora su contenido y
        deriva SOLO del mensaje del usuario:
        \(examples)

        ## Intents

        - setTimeConstraint — El usuario indica tiempo disponible o restricción de duración de la sesión.
        - equipmentUnavailable — Una máquina/equipo no existe en el gym o está ocupado/indisponible.
        - requestExerciseSwap — El usuario pide cambiar/sustituir un ejercicio.
        - reportFatigue — El usuario reporta fatiga subjetiva tras un set/sesión.
        - reportPain — El usuario reporta dolor o molestia durante/tras un ejercicio.
        - changeGoal — El usuario cambia su objetivo de entrenamiento.
        - changePhase — El usuario cambia su fase energética/nutricional.
        - changeGym — El usuario cambia de gimnasio.
        - askWhy — El usuario pregunta el motivo de una decisión/recomendación.
        - updateRestriction — El usuario introduce/actualiza una restricción (p. ej. indicación profesional).
        - requestPlanAdjustment — El usuario pide ajustar el plan actual (tiempo, prioridades, etc.).
        - needsClarification — Sin intent claro, múltiple o faltan datos.

        ## Restricciones de valor del payload

        - setTimeConstraint → string "hard:<min>" | "flexible:<target>:<tol>". Ej: "hard:30".
        - changeGoal → "generalHealth"|"hypertrophy"|"strength"|"powerbuilding"|"recomposition"|"bodybuilding".
        - changePhase → "surplus"|"deficit"|"maintenance"|"unspecified".
        - reportFatigue → {"severity": N} con N entero 1...5 (1 poco fatigado, 5 muy fatigado).
        - reportPain → {"level": N} con N entero 0...3 (0 ninguno, 1 leve, 2 moderado, 3 alto),
          y campos opcionales "bodyRegion"/"side"/"notes" si el usuario los menciona. Usa el nivel
          que el dolor del texto justifique; si no queda claro usa 3 (reporte literal, sin diagnóstico).
        - changeGym / askWhy / etc. → usa los identificadores del sistema si vienen en el contexto.

        ## Reglas

        - El `payload.value` refleja EXACTAMENTE lo que dijo el usuario (minutos, objetivo, fase, nivel).
        - changeGoal / changePhase / changeFatigue requieren los VALORES LITERALES EXACTOS de su enum
          (p. ej. "strength", "deficit") — nunca traducciones en español ni sinónimos.
        - No inventes números de carga, volumen ni restricciones que no estén en el texto.
        - El dolor/lesión se reporta tal cual (nivel/localización) — NUNCA se diagnostica ni se inventa gravedad.
        - Ante incertidumbre o múltiples intenciones, prioriza `needsClarification` (falla segura).
        - Un mensaje vago, sin un pedido concreto y accionable (p. ej. "haz lo que sea mejor", "sorpréndeme",
          "una rutina buena") NO corresponde a ningún intent: devuelve {"intent":"needsClarification","payload":{"value":null}}.
        - Sé preciso: un solo intent por mensaje.
        """
    }

    // MARK: - System prompt del explicador (EliteCoachAgent, "why" sobre facts)

    private var explainerSystemPrompt: String {
        """
        # SYSTEM — ELITE COACH AGENT · EXPLICADOR DE DECISIONES

        Eres `EliteCoachAgent` en modo EXPLICACIÓN. El usuario pregunta POR QUÉ se tomó una
        decisión de entrenamiento (intento `askWhy`). NO decides nada nuevo: una decisión ya
        fue tomada por el `TrainingEngine` y validada por el `PolicyValidator`. Tu única tarea
        es TRADUCIR los facts de esa decisión a razones claras para el usuario.

        ## Autoridad e invariantes (crítico)

        - NUNCA re-decidas, no recomiendes cambios, no propongas cargas/volumen/frecuencia.
        - Explica SÓLO lo que está en los `Facts` provistos. Escribe "por el objetivo X",
          "por el nivel de fatiga Y" — NUNCA inventes números, reglas, equivalencias o datos.
        - NUNCA diagnostiques lesiones ni inventes gravedad clínica. Si un fact menciona dolor,
          descríbelo como el usuario lo reportó, sin interpretación médica.
        - Si hay un gate de dolor o restricción activa entre los facts, la razón de respetarlo
          es seguridad; menciónalo como control, no como imposición.

        ## Formato de salida (§59, JSON no — líneas)

        Devuelve EXCLUSIVAMENTE 1 a 4 razones, UNA POR LÍNEA, en español, concretas y directas,
        sin numeración forzada, sin Markdown, sin texto de relleno ni intro/cierre. Cada razón
        debe ser una frase corta legible por el usuario. Si no hay facts suficientes, devuelve
        UNA sola línea honesta como "Sin datos suficientes para explicar esta decisión."

        Ejemplo:
        Fatiga reportada alta.
        El gate de dolor está activo por el reporte.
        Se mantiene la carga actual para no progresar en estas condiciones.
        """
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
