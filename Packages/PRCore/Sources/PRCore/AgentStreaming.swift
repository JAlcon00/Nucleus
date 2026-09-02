//
//  AgentStreaming.swift
//  PRCore
//
//  Created by PR.
//
//  Streaming del provider LLM (NEMOTRON_3_5_LIGHTNING_API.md §19, Phase N5).
//
//  - `SSEEventDecoder`: parser puro de Server-Sent-Events, testeable sin red.
//  - `NVIDIAStreamChunk`: DTO del delta de Chat Completions en streaming.
//  - `NVIDIAHostedProvider.stream(_:)`: lee `URLSession.AsyncBytes`, alimenta el decoder,
//    emite `AgentStreamEvent` por delta y traduce cancelación/desconexión a errores.
//
//  Reglas de la app (spec §19): el reasoning trace NUNCA se muestra al usuario; las
//  decisiones críticas derivan de tool results auditables, no del reasoning. Aquí el
//  reasoning se emite como `.reasoning` para que el cliente lo descarte o use internamente.
//

import Foundation

// MARK: - SSE decoder (puro)

/// Parseador incremental de Server-Sent Events. Consume bytes/strings por fragmentos y
/// entrega eventos `data:` como string (p. ej. un JSON, o `[DONE]`). Maneja líneas
/// parciales (buffer) y separadores `\n`/`\r\n`.
public struct SSEEventDecoder: Sendable {
    private var buffer: String = ""
    private var pendingLines: [String] = []

    public init() {}

    /// Alimenta un fragmento y devuelve los eventos `data:` completos encontrados.
    /// Un evento SSE es uno o más campos `data:` separados por una línea en blanco;
    /// los acumula y los entrega como un único string (las líneas `data:` se concatenan).
    public mutating func append(_ fragment: String) -> [String] {
        buffer += fragment
        return drainEvents()
    }

    private mutating func drainEvents() -> [String] {
        var events: [String] = []
        // Normaliza CRLF a LF para simplificar el split de líneas.
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = buffer.components(separatedBy: "\n")
        // Conserva la última línea incompleta (sin \n) para el siguiente fragmento.
        if buffer.hasSuffix("\n") {
            buffer = ""
        } else if let partial = lines.popLast() {
            buffer = partial
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Línea en blanco → cierra el evento acumulado.
            if trimmed.isEmpty {
                if !pendingLines.isEmpty {
                    events.append(pendingLines.joined(separator: ""))
                    pendingLines = []
                }
                continue
            }
            // Sólo interesan las líneas `data:`; el resto se descarta.
            if trimmed.hasPrefix("data:") {
                let cleaned = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    pendingLines.append(cleaned)
                }
            }
        }
        // Un evento final puede carecer de línea en blanco al terminar la entrada.
        if buffer.isEmpty, !pendingLines.isEmpty {
            events.append(pendingLines.joined(separator: ""))
            pendingLines = []
        }
        return events
    }
}

// MARK: - DTO del delta en streaming (transport)

/// Delta de un `choice` en una respuesta streaming (OpenAI-compatible).
public struct NVIDIAStreamDelta: Decodable, Sendable {
    public var content: String?
    public var reasoningContent: String?
    public var toolCalls: [NVIDIAToolCall]?

    public enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

public struct NVIDIAStreamChoice: Decodable, Sendable {
    public var index: Int?
    public var delta: NVIDIAStreamDelta?
    public var finishReason: String?

    public enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

public struct NVIDIAStreamChunk: Decodable, Sendable {
    public var id: String?
    public var choices: [NVIDIAStreamChoice]?

    /// ¿Es el marcador de fin `[DONE]`? Se evalúa por el string, no este tipo.
    public enum DoneMarker {
        static let value = "[DONE]"
    }
}

// MARK: - Decoder del delta a evento

/// Traduce un fragmento SSE a uno o más `AgentStreamEvent`, dado el chunk decodificado.
/// Existe como función pura y testeable (sin I/O).
public enum NVIDIAStreamEventMapper {
    public static func events(forChunk chunk: NVIDIAStreamChunk) -> [AgentStreamEvent] {
        var out: [AgentStreamEvent] = []
        guard let choice = chunk.choices?.first, let delta = choice.delta else {
            return out
        }
        if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
            out.append(.reasoning(reasoning))
        }
        if let content = delta.content, !content.isEmpty {
            out.append(.text(content))
        }
        if let toolCalls = delta.toolCalls {
            for call in toolCalls {
                guard let name = call.function?.name else { continue }
                out.append(.toolCall(AgentToolCall(
                    id: call.id,
                    name: name,
                    arguments: call.function?.arguments ?? ""
                )))
            }
        }
        if let finish = choice.finishReason {
            out.append(.finish(mapFinishReason(finish)))
        }
        return out
    }

    static func mapFinishReason(_ raw: String) -> AgentFinishReason {
        switch raw {
        case "stop": return .stop
        case "length": return .length
        case "tool_calls": return .toolCalls
        case "content_filter": return .contentFilter
        default: return .unknown
        }
    }
}

// MARK: - Parser síncrono SSE → eventos (determinista, testeable)

/// Convierte fragmentos SSE entrantes en `AgentStreamEvent`, manteniendo un decoder
/// incremental (`SSEEventDecoder`) para líneas parciales. Es SÍNCRONO y sin red, por lo
/// que se testea deterministamente; el provider lo invoca por cada fragmento de bytes.
public enum NVIDIAStreamEventParser {
    public static func parse(
        decoder: inout SSEEventDecoder,
        fragment: String
    ) -> [AgentStreamEvent] {
        var out: [AgentStreamEvent] = []
        let rawEvents = decoder.append(fragment)
        for event in rawEvents {
            if event == NVIDIAStreamChunk.DoneMarker.value {
                continue
            }
            guard let data = event.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(NVIDIAStreamChunk.self, from: data) else {
                continue
            }
            out.append(contentsOf: NVIDIAStreamEventMapper.events(forChunk: chunk))
        }
        return out
    }
}
