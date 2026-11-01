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

/// Parseador incremental de Server-Sent Events. Consume bytes por fragmentos y entrega
/// eventos `data:` como string (p. ej. un JSON, o `[DONE]`). Maneja líneas parciales y
/// separadores `\n`/`\r\n`.
///
/// SCRUM-34: junta los bytes de cada línea y decodifica UTF-8 sólo con la línea completa.
/// El byte `\n` nunca aparece dentro de un carácter multibyte, así que un carácter partido
/// entre fragmentos (á, ñ, ¿, emoji) llega entero. Cada byte se procesa una vez: el costo
/// es lineal aunque la línea sea muy larga.
public struct SSEEventDecoder: Sendable {
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private var lineBytes: [UInt8] = []
    private var pendingLines: [String] = []

    public init() {}

    /// Alimenta un fragmento de bytes y devuelve los eventos `data:` completos encontrados.
    /// Un evento SSE es uno o más campos `data:` separados por una línea en blanco;
    /// los acumula y los entrega como un único string (las líneas `data:` se concatenan).
    public mutating func append(bytes fragment: some Sequence<UInt8>) -> [String] {
        var events: [String] = []
        for byte in fragment {
            guard byte == Self.lineFeed else {
                lineBytes.append(byte)
                continue
            }
            if lineBytes.last == Self.carriageReturn {
                lineBytes.removeLast()
            }
            consumeLine(String(decoding: lineBytes, as: UTF8.self), into: &events)
            lineBytes.removeAll(keepingCapacity: true)
        }
        // Un evento final puede carecer de línea en blanco al terminar la entrada.
        if lineBytes.isEmpty {
            flushPending(into: &events)
        }
        return events
    }

    /// Igual que `append(bytes:)` con el texto en UTF-8.
    public mutating func append(_ fragment: String) -> [String] {
        append(bytes: fragment.utf8)
    }

    /// Fin de la entrada: procesa la última línea aunque no traiga salto final y entrega el
    /// evento pendiente. Llamarlo otra vez no repite nada.
    public mutating func finish() -> [String] {
        var events: [String] = []
        if !lineBytes.isEmpty {
            consumeLine(String(decoding: lineBytes, as: UTF8.self), into: &events)
            lineBytes.removeAll()
        }
        flushPending(into: &events)
        return events
    }

    private mutating func consumeLine(_ line: String, into events: inout [String]) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Línea en blanco → cierra el evento acumulado.
        if trimmed.isEmpty {
            flushPending(into: &events)
            return
        }
        // Sólo interesan las líneas `data:`; el resto se descarta.
        if trimmed.hasPrefix("data:") {
            let cleaned = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty {
                pendingLines.append(cleaned)
            }
        }
    }

    private mutating func flushPending(into events: inout [String]) {
        guard !pendingLines.isEmpty else { return }
        events.append(pendingLines.joined(separator: ""))
        pendingLines = []
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
        events(from: decoder.append(fragment))
    }

    /// Fragmento de bytes tal como llega de la red (SCRUM-34): no se decodifica aquí.
    public static func parse(
        decoder: inout SSEEventDecoder,
        bytes: some Sequence<UInt8>
    ) -> [AgentStreamEvent] {
        events(from: decoder.append(bytes: bytes))
    }

    /// Fin del stream: entrega el último evento aunque no traiga salto final.
    public static func finish(decoder: inout SSEEventDecoder) -> [AgentStreamEvent] {
        events(from: decoder.finish())
    }

    /// Lee los bytes de la red y entrega cada evento en cuanto se completa (SCRUM-34).
    /// Si la conexión se corta, lo que llegó ya se entregó, la línea a medias se descarta y
    /// lanza `.interrupted`; si la tarea se canceló, `.cancelled`. Está separado de
    /// `URLSession` para probarlo sin red.
    static func relay<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        yield: (AgentStreamEvent) -> Void
    ) async throws where Bytes.Element == UInt8 {
        var decoder = SSEEventDecoder()
        do {
            for try await byte in bytes {
                if Task.isCancelled { throw NVIDIAProviderError.cancelled }
                for event in parse(decoder: &decoder, bytes: CollectionOfOne(byte)) {
                    yield(event)
                }
            }
        } catch let error as NVIDIAProviderError {
            throw error
        } catch {
            let cancelled = (error as? URLError)?.code == .cancelled || error is CancellationError
            throw (cancelled || Task.isCancelled) ? NVIDIAProviderError.cancelled : NVIDIAProviderError.interrupted
        }
        for event in finish(decoder: &decoder) {
            yield(event)
        }
    }

    private static func events(from rawEvents: [String]) -> [AgentStreamEvent] {
        var out: [AgentStreamEvent] = []
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
