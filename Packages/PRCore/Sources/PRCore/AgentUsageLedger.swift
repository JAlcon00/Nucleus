//
//  AgentUsageLedger.swift
//  PRCore
//
//  SCRUM-273 (PR-I004, DI-4 A): se mide cada llamada a la IA. `MeteredLLMProvider` envuelve
//  al proveedor real y deja un `AgentUsageRecord` sin texto en la colección `agent-usage`
//  (v1, en la raíz: no hay datos de la persona). La latencia se mide con un reloj inyectado,
//  también cuando la llamada falla o se cancela. Un error al guardar se registra en el log y
//  no rompe la llamada. En Release no hay IA, así que no hay registros.
//

import Foundation
import PRDomain

/// Lee y escribe los registros de uso. Uno por archivo (clave = su ID): agregar nunca pisa.
public struct AgentUsageStore: Sendable {
    private let store: any RepositoryStore
    private let log: PersistenceLog

    public init(store: some RepositoryStore, log: PersistenceLog = .standard) {
        self.store = store
        self.log = log
    }

    public func save(_ record: AgentUsageRecord) throws {
        try store.write(key: record.id.persistenceKey, data: JSONEncoder().encode(record))
    }

    /// Todos los registros legibles, del más viejo al más nuevo. Lanza si falla la lectura.
    public func all() throws -> [AgentUsageRecord] {
        try JSONBlob.decodeAll(AgentUsageRecord.self, from: store, collection: .agentUsage, log: log)
            .items
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }
}

extension LocalPersistence {
    public func agentUsageStore() throws -> AgentUsageStore {
        AgentUsageStore(store: try store(for: .agentUsage), log: log)
    }
}

/// Mide y guarda. Un actor: las escrituras no se pisan entre llamadas simultáneas.
public actor AgentUsageRecorder {
    private let store: AgentUsageStore?
    private let clock: @Sendable () -> Date
    private let elapsedNanoseconds: @Sendable () -> UInt64
    private let newID: @Sendable () -> UUID
    private let onSaveFailure: @Sendable () -> Void
    /// La última escritura falló (se registró en el log).
    public private(set) var lastSaveFailed = false

    public init(
        store: AgentUsageStore?,
        clock: @escaping @Sendable () -> Date = { Date() },
        elapsedNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        newID: @escaping @Sendable () -> UUID = { UUID() },
        onSaveFailure: @escaping @Sendable () -> Void = {}
    ) {
        self.store = store
        self.clock = clock
        self.elapsedNanoseconds = elapsedNanoseconds
        self.newID = newID
        self.onSaveFailure = onSaveFailure
    }

    /// Marca de inicio (monótona) de una llamada.
    nonisolated func start() -> UInt64 { elapsedNanoseconds() }

    /// Guarda la llamada que empezó en `started`. Nunca lanza: un error se registra.
    func record(_ operation: AgentOperation, started: UInt64, usage: AgentUsage?, outcome: AgentCallOutcome) {
        let ended = elapsedNanoseconds()
        let milliseconds = ended >= started ? Int((ended - started) / 1_000_000) : 0
        let record = AgentUsageRecord(
            id: newID(),
            date: clock(),
            operation: operation,
            promptTokens: usage?.promptTokens,
            completionTokens: usage?.completionTokens,
            reasoningTokens: usage?.reasoningTokens,
            durationMilliseconds: milliseconds,
            outcome: outcome
        )
        guard let store else { return }
        do {
            try store.save(record)
            lastSaveFailed = false
        } catch {
            lastSaveFailed = true
            onSaveFailure()
        }
    }

    /// El resumen por operación (SCRUM-273). Sin registros, vacío. Lanza si falla la lectura.
    public func summary() throws -> [AgentUsageRow] {
        AgentUsageSummary.rows(for: try store?.all() ?? [])
    }
}

/// Proveedor que mide cada llamada del que envuelve y la guarda sin texto.
public struct MeteredLLMProvider: LLMProvider {
    private let base: any LLMProvider
    private let operation: AgentOperation
    private let recorder: AgentUsageRecorder

    public init(base: any LLMProvider, operation: AgentOperation, recorder: AgentUsageRecorder) {
        self.base = base
        self.operation = operation
        self.recorder = recorder
    }

    public func complete(_ request: AgentRequest) async throws -> AgentResponse {
        let started = recorder.start()
        do {
            let response = try await base.complete(request)
            await recorder.record(operation, started: started, usage: response.usage, outcome: .answered)
            return response
        } catch {
            await recorder.record(operation, started: started, usage: nil, outcome: .failed(Self.failure(for: error)))
            throw error
        }
    }

    static func failure(for error: any Error) -> AgentCallFailure {
        if error is CancellationError { return .cancelled }
        guard let error = error as? NVIDIAProviderError else { return .unavailable }
        switch error {
        case .timeout: return .timeout
        case .network: return .network
        case .invalidResponse, .malformedResponse, .emptyChoices: return .invalidResponse
        case .cancelled, .interrupted: return .cancelled
        case .missingAPIKey, .authentication, .forbidden, .notFound, .validation, .rateLimited, .providerError, .healthUnavailable:
            return .unavailable
        }
    }
}

extension AIConnection {
    /// La misma conexión, con cada llamada medida como `operation` (SCRUM-273). Sin IA no
    /// hay nada que medir: se devuelve igual.
    public func metered(_ operation: AgentOperation, by recorder: AgentUsageRecorder?) -> AIConnection {
        guard status.isLive, let recorder else { return self }
        return AIConnection(status: status, provider: MeteredLLMProvider(base: provider, operation: operation, recorder: recorder))
    }
}
