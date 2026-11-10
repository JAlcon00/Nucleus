//
//  CoachConversation.swift
//  PRCore
//
//  SCRUM-272 (PR-I003, RF-027): el entrenador conversacional, de la frase a la acción.
//
//  "LLM interprets/explains, Training Engine decides, Policy Validator protects":
//  1. Una pregunta de diagnóstico no se responde (`MedicalBoundary`).
//  2. Primero el intérprete local (SCRUM-271): sin red, sin costo y determinista. Sólo si no
//     entiende y hay transporte (Debug con llave y consentimiento) se le pregunta al LLM por
//     `AgentGateway`, que cae al local si no responde a tiempo. En Release no hay
//     transporte: cuando ADR-0005 decida el backend, sólo cambia `transport`.
//  3. Toda intención pasa por `AgentActionWriter` y `ActionPolicyValidator`. Lo importante
//     pide confirmar y abre el flujo que ya existe; el chat nunca escribe el perfil ni series.
//  4. "¿Por qué?" sale del registro de la decisión (SCRUM-270), nunca del LLM.
//  5. Cada turno deja su auditoría sin texto (`agent-audit`). La conversación vive en memoria
//     (DI-5 A): cerrar la app a mitad no deja nada aplicado sin confirmar.
//

import Foundation
import Observation
import PRDomain

// MARK: - Lo que la app le da al entrenador

/// Dónde se habla con el entrenador.
public enum CoachSurface: String, Sendable, Hashable {
    case today
    case workout
}

/// Lo que el entrenador necesita saber del momento. Lo arma la app con lo que ya tiene.
public struct CoachSnapshot: Sendable, Equatable {
    public var surface: CoachSurface
    /// El ejercicio de la serie actual (sólo en el entrenamiento).
    public var currentExercise: AgentExerciseContext?
    public var gyms: [AgentGymContext]
    public var activeGymID: GymID?
    /// Lo que se puede explicar ahora (SCRUM-270).
    public var decisions: [ExplainableDecision]
    /// El dolor reportado en las series de esta sesión: la política deriva el gate de aquí.
    public var recentPain: [PainFeedback]
    public var activeRestrictionCount: Int
    /// ¿Ya hay una serie hecha? El dolor se reporta sobre la última.
    public var hasCompletedSet: Bool

    public init(
        surface: CoachSurface,
        currentExercise: AgentExerciseContext? = nil,
        gyms: [AgentGymContext] = [],
        activeGymID: GymID? = nil,
        decisions: [ExplainableDecision] = [],
        recentPain: [PainFeedback] = [],
        activeRestrictionCount: Int = 0,
        hasCompletedSet: Bool = false
    ) {
        self.surface = surface
        self.currentExercise = currentExercise
        self.gyms = gyms
        self.activeGymID = activeGymID
        self.decisions = decisions
        self.recentPain = recentPain
        self.activeRestrictionCount = activeRestrictionCount
        self.hasCompletedSet = hasCompletedSet
    }

    var agentContext: AgentContext {
        AgentContext(
            activeRestrictionCount: activeRestrictionCount,
            painGateActive: recentPain.contains(where: \.blocksProgression),
            todaySessionStarted: surface == .workout,
            currentExercise: currentExercise,
            gyms: gyms,
            explainableDecisions: decisions.map { AgentDecisionContext(id: $0.id, topic: $0.topic) }
        )
    }
}

/// Un flujo que ya existe en la app y que el entrenador abre en vez de decidir él.
public enum CoachFlow: String, Sendable, Hashable, CaseIterable {
    /// "¿Te dolió?" (SCRUM-226).
    case painReport
    /// La hoja de sustitutos y "No hay esta máquina aquí" (SCRUM-234, SCRUM-236).
    case substitutes
    /// "Cambiar objetivo o fase": el cuestionario prellenado (SCRUM-266).
    case goalOrPhaseChange
    /// Perfil › Restricciones (SCRUM-36).
    case restrictions
}

/// Cómo terminó ajustar la sesión de hoy al tiempo (SCRUM-30).
public enum CoachTimeOutcome: Sendable, Equatable {
    /// Ajustada; la explicación del registro del tiempo, si hay.
    case adjusted(DecisionExplanation?)
    case workoutInProgress
    case outOfRange
    case saveFailed
}

/// Lo que la app sabe hacer por el entrenador, con los coordinadores que ya existen.
@MainActor
public protocol CoachActionHandling: AnyObject {
    func coachSnapshot() -> CoachSnapshot
    /// `setTimeBudget` (SCRUM-30); `nil` quita el ajuste.
    func adjustTodaySession(minutes: Int?) async -> CoachTimeOutcome
    /// "Máquina ocupada" sobre el ejercicio actual (SCRUM-233); `nil` sin entrenamiento.
    func markCurrentExerciseOccupied() -> OccupiedOutcome?
    /// Cambiar de gimnasio (SCRUM-238). `false` si no se pudo guardar.
    func selectGym(_ id: GymID) async -> Bool
}

// MARK: - Mensajes

/// Quién respondió.
public enum CoachReplySource: Sendable, Equatable {
    /// Lo entendió el intérprete local (o no hacía falta la IA).
    case engine
    /// Lo interpretó la IA.
    case ai
    /// La IA no estaba o no respondió: respondió el intérprete local.
    case offline(AgentGatewayFallback)
}

/// Un botón del mensaje.
public enum CoachAction: Sendable, Hashable, Identifiable {
    case confirm
    case cancel
    case open(CoachFlow)
    /// Una frase sugerida: tocarla la manda.
    case say(String)
    /// Explica esa decisión (cuando hay varias del mismo tema).
    case explain(DecisionID, label: String)

    public var id: String {
        switch self {
        case .confirm: return "confirm"
        case .cancel: return "cancel"
        case .open(let flow): return "open.\(flow.rawValue)"
        case .say(let text): return "say.\(text)"
        case .explain(let id, _): return "explain.\(id.rawValue.uuidString)"
        }
    }
}

public struct CoachMessage: Identifiable, Sendable, Equatable {
    public enum Author: Sendable, Equatable {
        case person
        case coach
    }

    public let id: UUID
    public let author: Author
    public let text: String
    /// Razones de "¿Por qué?" o de lo que cambió.
    public let reasons: [String]
    public let source: CoachReplySource?
    public let actions: [CoachAction]

    public init(id: UUID, author: Author, text: String, reasons: [String] = [], source: CoachReplySource? = nil, actions: [CoachAction] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.reasons = reasons
        self.source = source
        self.actions = actions
    }
}

// MARK: - Coordinador

@MainActor
@Observable
public final class CoachConversationCoordinator {
    /// Máximo de caracteres por mensaje; lo demás se corta y se avisa.
    public static let maximumCharacters = 500

    public private(set) var messages: [CoachMessage] = []
    /// Esperando la respuesta: no se manda otro mensaje.
    public private(set) var isThinking = false
    /// Un flujo que la pantalla debe abrir ahora (la hoja se cierra). Se consume una vez.
    public private(set) var route: CoachFlow?
    /// La última auditoría no se pudo guardar (se registró en el log).
    public private(set) var auditSaveFailed = false

    @ObservationIgnored private weak var handler: (any CoachActionHandling)?
    @ObservationIgnored private let transport: @MainActor () -> (any AgentBackendTransport)?
    @ObservationIgnored private let timing: AgentGatewayTiming
    @ObservationIgnored private let writer: AgentActionWriter
    @ObservationIgnored private let audit: (any AgentAuditRepository)?
    @ObservationIgnored private let onAuditFailure: @MainActor () -> Void
    @ObservationIgnored private let presenter: CoachReplyPresenter
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let newID: () -> UUID
    @ObservationIgnored private let conversationID: UUID
    @ObservationIgnored private var pending: PendingConfirmation?
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Qué tarea es la vigente: una cancelada que termina tarde no toca el estado de la nueva.
    @ObservationIgnored private var workToken = UUID()

    /// Lo que espera confirmación: la intención y el estado con que se validó.
    private struct PendingConfirmation {
        let intent: AgentIntent
        let snapshot: CoachSnapshot
        let source: CoachReplySource
    }

    public init(
        handler: (any CoachActionHandling)?,
        transport: @escaping @MainActor () -> (any AgentBackendTransport)?,
        timing: AgentGatewayTiming = .standard,
        writer: AgentActionWriter,
        audit: (any AgentAuditRepository)?,
        onAuditFailure: @escaping @MainActor () -> Void = {},
        presenter: CoachReplyPresenter = CoachReplyPresenter(),
        clock: @escaping () -> Date = { Date() },
        newID: @escaping () -> UUID = { UUID() }
    ) {
        self.handler = handler
        self.transport = transport
        self.timing = timing
        self.writer = writer
        self.audit = audit
        self.onAuditFailure = onAuditFailure
        self.presenter = presenter
        self.clock = clock
        self.newID = newID
        self.conversationID = newID()
    }

    /// Conecta la app después de crear el coordinador (la app es dueña de los dos).
    public func attach(_ handler: any CoachActionHandling) {
        self.handler = handler
    }

    /// Frases sugeridas para el momento.
    public var suggestions: [String] {
        presenter.suggestions(for: handler?.coachSnapshot())
    }

    /// Hay algo esperando "Confirmar" o "Cancelar".
    public var awaitsConfirmation: Bool { pending != nil }

    // MARK: Intenciones de la pantalla

    /// Manda un mensaje. Devuelve la tarea para esperarla; `nil` si no se mandó (vacío o
    /// mientras responde otro). Un mensaje nuevo cancela lo que esperaba confirmación.
    @discardableResult
    public func send(_ text: String) -> Task<Void, Never>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isThinking, !trimmed.isEmpty else { return nil }
        let clipped = String(trimmed.prefix(Self.maximumCharacters))
        append(.person, clipped)
        if trimmed.count > Self.maximumCharacters {
            append(.coach, presenter.clipped(Self.maximumCharacters), source: .engine)
        }
        pending = nil
        return start { coordinator in await coordinator.process(clipped) }
    }

    /// "Confirmar": valida otra vez con la confirmación de la persona y, si queda permitido,
    /// abre el flujo que corresponde.
    @discardableResult
    public func confirm() -> Task<Void, Never>? {
        guard !isThinking, let pending else { return nil }
        self.pending = nil
        isThinking = true
        // Se revalida con el estado de ahora: el dolor pudo llegar mientras se decidía.
        let snapshot = handler?.coachSnapshot() ?? pending.snapshot
        return start { coordinator in
            await coordinator.run(pending.intent, snapshot: snapshot, source: pending.source, confirmed: true)
        }
    }

    /// Corre `body` como la tarea vigente: sólo ella apaga "pensando" al terminar.
    private func start(_ body: @escaping @MainActor (CoachConversationCoordinator) async -> Void) -> Task<Void, Never> {
        let token = UUID()
        workToken = token
        isThinking = true
        let task = Task { [weak self] in
            guard let self else { return }
            await body(self)
            if self.workToken == token { self.isThinking = false }
        }
        work = task
        return task
    }

    /// "Cancelar": no cambia nada.
    public func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        append(.coach, presenter.cancelled(), source: .engine)
        let record = AgentAuditRecord.result(command: "cancelled", conversationID: conversationID, date: clock())
        Task { [self] in await self.saveAudit([record]) }
    }

    /// Cerrar la hoja o "Cancelar" mientras piensa: corta la espera y no aplica nada.
    public func cancel() {
        work?.cancel()
        work = nil
        workToken = UUID()
        isThinking = false
        pending = nil
    }

    /// "Por qué…" de una decisión concreta (botón de `.explain`). Sólo del registro.
    public func explain(_ id: DecisionID) {
        guard !isThinking, let snapshot = handler?.coachSnapshot() else { return }
        guard let decision = snapshot.decisions.first(where: { $0.id == id }) else {
            let reply = presenter.clarification(.nothingToExplain(nil), snapshot: snapshot)
            append(.coach, reply.text, source: .engine, actions: reply.actions)
            return
        }
        let explanation = presenter.explanation(for: decision)
        append(.coach, explanation.title, reasons: explanation.reasons, source: .engine)
    }

    /// La pantalla abrió el flujo.
    public func consumeRoute() -> CoachFlow? {
        defer { route = nil }
        return route
    }

    // MARK: Pipeline

    private func process(_ text: String) async {
        guard let snapshot = handler?.coachSnapshot() else { return }
        let context = snapshot.agentContext
        if MedicalBoundary.asksForDiagnosis(text) {
            await declineDiagnosis(snapshot)
            return
        }
        let local = LocalFallbackInterpreter().analyze(text: text, context: context)
        var interpretation = local.interpretation
        var source = CoachReplySource.engine
        let backend = transport()
        if case .needsClarification = local.interpretation, let backend {
            let reply = await AgentGateway(transport: backend, timing: timing).interpretReply(text: text, context: context)
            guard !Task.isCancelled else { return }
            source = reply.fallback.map(CoachReplySource.offline) ?? .ai
            interpretation = reply.value
        } else if backend == nil {
            source = .offline(.noBackend)
        }
        guard !Task.isCancelled else { return }
        switch interpretation {
        case .declinesDiagnosis:
            await declineDiagnosis(snapshot)
        case .needsClarification:
            let clarification = local.clarification ?? .general
            // "Me duele" sin nivel: en el entrenamiento el nivel se elige en "¿Te dolió?"; en Hoy
            // se ofrece una restricción.
            if case .painLevel = clarification {
                reportPain(snapshot: snapshot, source: source)
            } else {
                let reply = presenter.clarification(clarification, snapshot: snapshot)
                append(.coach, reply.text, source: source, actions: reply.actions)
            }
            await saveAudit([.needsClarification(conversationID: conversationID, date: clock())])
        case .intent(let intent):
            await run(intent, snapshot: snapshot, source: source, confirmed: false)
        }
    }

    private func run(_ intent: AgentIntent, snapshot: CoachSnapshot, source: CoachReplySource, confirmed: Bool) async {
        // Cancelado: no se aplica nada.
        guard !Task.isCancelled else { return }
        let result: AgentActionPipelineResult
        do {
            result = try writer.execute(
                intent: intent,
                context: ActionPolicyContext(recentPain: snapshot.recentPain),
                userConfirmed: confirmed,
                conversationID: conversationID,
                knownDecisions: snapshot.decisions.map(\.record)
            )
        } catch {
            // La política no se pudo leer: no se hace nada (falla segura).
            append(.coach, presenter.policyUnavailable(), source: source)
            return
        }
        await saveAudit(result.auditRecords)
        guard !Task.isCancelled else { return }
        switch result.decision {
        case .execute(let command, _, _):
            await dispatch(command, snapshot: snapshot, source: source)
        case .confirm(let command, _, let preview):
            pending = PendingConfirmation(intent: intent, snapshot: snapshot, source: source)
            append(.coach, presenter.confirmation(for: command, preview: preview), source: source, actions: [.confirm, .cancel])
        case .rejected(_, let verdict, _):
            append(.coach, presenter.rejection(verdict), source: source)
        case .clarify:
            let reply = presenter.clarification(.whichDecision(snapshot.agentContext.explainableDecisions), snapshot: snapshot)
            append(.coach, reply.text, source: source, actions: reply.actions)
        }
    }

    /// El comando ya validado, con lo que la app ya sabe hacer.
    private func dispatch(_ command: AgentWriteCommand, snapshot: CoachSnapshot, source: CoachReplySource) async {
        switch command {
        case .recomputeSession(let constraint):
            await adjustTime(constraint, snapshot: snapshot, source: source)
        case .markEquipmentUnavailable(let reference, let reason):
            markUnavailable(reference, reason: reason, snapshot: snapshot, source: source)
        case .requestSubstitution:
            guard snapshot.surface == .workout else {
                append(.coach, presenter.substitutionNeedsWorkout(), source: source)
                return
            }
            route = .substitutes
            append(.coach, presenter.openingSubstitutes(), source: source)
        case .recordPain:
            reportPain(snapshot: snapshot, source: source)
        case .recordFatigue:
            append(.coach, presenter.fatigueNotHandled(surface: snapshot.surface), source: source)
        case .changeGoal, .changePhase, .adjustPlan:
            route = .goalOrPhaseChange
            append(.coach, presenter.openingGoalChange(), source: source)
        case .saveRestriction:
            route = .restrictions
            append(.coach, presenter.openingRestrictions(), source: source)
        case .changeGym(let id):
            guard let gym = snapshot.gyms.first(where: { $0.id == id }) else {
                let reply = presenter.clarification(.whichGym(snapshot.gyms), snapshot: snapshot)
                append(.coach, reply.text, source: source, actions: reply.actions)
                return
            }
            guard snapshot.activeGymID != id else {
                append(.coach, presenter.alreadyInGym(gym.name), source: source)
                return
            }
            let saved = await handler?.selectGym(id) ?? false
            append(.coach, saved ? presenter.gymSelected(gym.name) : presenter.gymNotSaved(), source: source)
        case .presentExplanation(let id, _):
            guard let decision = snapshot.decisions.first(where: { $0.id == id }) else {
                let reply = presenter.clarification(.nothingToExplain(nil), snapshot: snapshot)
                append(.coach, reply.text, source: source, actions: reply.actions)
                return
            }
            let explanation = presenter.explanation(for: decision)
            append(.coach, explanation.title, reasons: explanation.reasons, source: .engine)
        case .recommendRest, .rescheduleWorkout:
            append(.coach, presenter.notHandledHere(), source: source)
        }
    }

    private func adjustTime(_ constraint: TimeConstraint, snapshot: CoachSnapshot, source: CoachReplySource) async {
        guard snapshot.surface == .today else {
            append(.coach, presenter.timeDuringWorkout(), source: source)
            return
        }
        let minutes: Int?
        switch constraint {
        case .hard(let value): minutes = value
        case .flexible(let target, _): minutes = target
        case .unconstrained: minutes = nil
        }
        let outcome = await handler?.adjustTodaySession(minutes: minutes) ?? .saveFailed
        let reply = presenter.time(outcome, minutes: minutes)
        append(.coach, reply.text, reasons: reply.reasons, source: source)
    }

    private func markUnavailable(_ reference: EquipmentReference, reason: UnavailabilityReason, snapshot: CoachSnapshot, source: CoachReplySource) {
        guard snapshot.surface == .workout, let current = snapshot.currentExercise else {
            append(.coach, presenter.equipmentOutsideWorkout(reason), source: source)
            return
        }
        // Sólo se marca la máquina del ejercicio actual ("la máquina" en general es ésa); otra
        // pide aclarar.
        guard reference.equipmentType == current.equipment || reference.equipmentType == .machine else {
            append(.coach, presenter.equipmentMismatch(current.name), source: source, actions: [.say(presenter.occupiedPhrase())])
            return
        }
        switch reason {
        case .doesNotExist:
            // "No hay esta máquina aquí" vive en la hoja de sustitutos (SCRUM-236).
            route = .substitutes
            append(.coach, presenter.openingMissingMachine(), source: source)
        case .occupied:
            guard let outcome = handler?.markCurrentExerciseOccupied() else {
                append(.coach, presenter.equipmentOutsideWorkout(reason), source: source)
                return
            }
            if case .needsChoice = outcome { route = .substitutes }
            append(.coach, presenter.occupied(outcome), source: source)
        }
    }

    private func reportPain(snapshot: CoachSnapshot, source: CoachReplySource) {
        switch snapshot.surface {
        case .workout where snapshot.hasCompletedSet:
            route = .painReport
            append(.coach, presenter.openingPainReport(), source: source)
        case .workout:
            append(.coach, presenter.painNeedsASet(), source: source)
        case .today:
            append(.coach, presenter.painOutsideWorkout(), source: source, actions: [.open(.restrictions)])
        }
    }

    private func declineDiagnosis(_ snapshot: CoachSnapshot) async {
        let action: CoachAction = snapshot.surface == .workout && snapshot.hasCompletedSet ? .open(.painReport) : .open(.restrictions)
        append(.coach, presenter.declinedDiagnosis(), source: .engine, actions: [action])
        await saveAudit([.result(command: "declinesDiagnosis", conversationID: conversationID, date: clock())])
    }

    // MARK: Utilidades

    private func append(
        _ author: CoachMessage.Author,
        _ text: String,
        reasons: [String] = [],
        source: CoachReplySource? = nil,
        actions: [CoachAction] = []
    ) {
        messages.append(CoachMessage(id: newID(), author: author, text: text, reasons: reasons, source: source, actions: actions))
    }

    /// Guarda la auditoría. Un error no se traga: se registra y se avisa; la acción no se deshace.
    private func saveAudit(_ records: [AgentAuditRecord]) async {
        guard let audit, !records.isEmpty else { return }
        do {
            try await audit.save(contentsOf: records)
            auditSaveFailed = false
        } catch {
            auditSaveFailed = true
            onAuditFailure()
        }
    }
}

extension LocalPersistence {
    /// La auditoría del agente (`agent-audit`, PR-1607): filas sin texto, append-only.
    public func agentAuditRepository() throws -> FileAgentAuditRepository {
        FileAgentAuditRepository(store: try store(for: .agentAudit), log: log)
    }
}
