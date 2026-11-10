//
//  CoachChatView.swift
//  PR
//
//  SCRUM-275 (PR-I006, RF-027) y SCRUM-276 (PR-I007): hablar con el entrenador. Vista pura:
//  muestra los mensajes de `CoachConversationCoordinator` y le manda lo que la persona
//  escribe o toca. Las reglas viven en PRCore (intérprete local, política y motor).
//  - DI-1 A: sin IA responde el intérprete local y lo dice bajo la respuesta.
//  - DI-5 A: la conversación vive en memoria; cerrar la hoja cancela lo que esperaba.
//  - Las frases sugeridas evitan el teclado (con una mano, entre series).
//

import PRCore
import PRDomain
import SwiftUI

struct CoachChatView: View {
    let coach: CoachConversationCoordinator
    /// El entrenador pidió abrir un flujo que ya existe: la hoja se cierra y la pantalla lo abre.
    let onRoute: (CoachFlow) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let presenter = CoachReplyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                Divider()
                suggestionsBar
                inputBar
            }
            .screenBackground()
            .navigationTitle("Entrenador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .accessibilityIdentifier("coach.done")
                }
            }
        }
        .accessibilityIdentifier("coach.sheet")
        .onChange(of: coach.route) { _, _ in
            guard let flow = coach.consumeRoute() else { return }
            dismiss()
            onRoute(flow)
        }
        .onDisappear { coach.cancel() }
    }

    // MARK: Conversación

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSpace.m) {
                    if coach.messages.isEmpty {
                        intro
                    }
                    ForEach(Array(coach.messages.enumerated()), id: \.element.id) { index, message in
                        CoachMessageRow(
                            message: message,
                            note: presenter.sourceNote(message.source),
                            isBusy: coach.isThinking,
                            identifier: "coach.message.\(index)",
                            onAction: handle
                        )
                        .id(message.id)
                    }
                    if coach.isThinking {
                        thinking
                    }
                }
                .padding(DSpace.m)
            }
            .onChange(of: coach.messages.count) { _, _ in
                guard let last = coach.messages.last?.id else { return }
                if reduceMotion {
                    proxy.scrollTo(last, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var intro: some View {
        Label {
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text("Dime qué pasa y lo ajusto con las mismas reglas de la app.")
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                Text("Lo importante siempre te lo confirmo. No diagnostico lesiones.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(Color.primaryAction)
                .accessibilityHidden(true)
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.intro")
    }

    private var thinking: some View {
        HStack(spacing: DSpace.s) {
            ProgressView()
            Text("Pensando…")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("Cancelar") { coach.cancel() }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("coach.thinking.cancel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.thinking")
    }

    // MARK: Frases sugeridas y campo

    private var suggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSpace.s) {
                ForEach(Array(coach.suggestions.enumerated()), id: \.offset) { index, phrase in
                    Button(phrase) { coach.send(phrase) }
                        .buttonStyle(.surface)
                        .disabled(coach.isThinking)
                        .accessibilityIdentifier("coach.suggestion.\(index)")
                }
            }
            .padding(.horizontal, DSpace.m)
            .padding(.vertical, DSpace.s)
        }
        .accessibilityLabel(Text("Frases sugeridas"))
    }

    private var inputBar: some View {
        HStack(spacing: DSpace.s) {
            TextField("Escribe al entrenador", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, DSpace.m)
                .padding(.vertical, DSpace.s)
                .frame(minHeight: 44)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DRadius.medium))
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .accessibilityIdentifier("coach.field")
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(Color.primaryAction)
            .disabled(coach.isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text("Enviar"))
            .accessibilityIdentifier("coach.send")
        }
        .padding(.horizontal, DSpace.m)
        .padding(.bottom, DSpace.s)
    }

    private func sendDraft() {
        guard coach.send(draft) != nil else { return }
        draft = ""
    }

    private func handle(_ action: CoachAction) {
        switch action {
        case .confirm:
            coach.confirm()
        case .cancel:
            coach.cancelPending()
        case .say(let phrase):
            coach.send(phrase)
        case .explain(let id, _):
            coach.explain(id)
        case .open(let flow):
            dismiss()
            onRoute(flow)
        }
    }
}

// MARK: - Un mensaje

/// Un mensaje con quién lo dijo, sus razones, la nota de la fuente y sus botones.
struct CoachMessageRow: View {
    let message: CoachMessage
    let note: String?
    let isBusy: Bool
    /// Va en la burbuja, que es el elemento accesible (texto, razones y nota juntos).
    let identifier: String
    let onAction: (CoachAction) -> Void

    private var isCoach: Bool { message.author == .coach }

    /// Lo que lee VoiceOver: quién lo dijo, el texto, las razones y la nota de la fuente.
    private var spokenLabel: String {
        let who = isCoach ? String(localized: "Entrenador") : String(localized: "Tú")
        return ([message.text] + message.reasons + [note].compactMap { $0 })
            .reduce("\(who):") { "\($0) \($1)" }
    }

    var body: some View {
        VStack(alignment: isCoach ? .leading : .trailing, spacing: DSpace.xs) {
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(message.reasons.enumerated()), id: \.offset) { _, reason in
                    Label {
                        Text(reason).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle").accessibilityHidden(true)
                    }
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                }
                if let note {
                    Label(note, systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(DSpace.m)
            .background(isCoach ? Color.surface : Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DRadius.medium))
            .frame(maxWidth: .infinity, alignment: isCoach ? .leading : .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(spokenLabel))
            .accessibilityIdentifier(identifier)
            if !message.actions.isEmpty {
                actions
            }
        }
    }

    private var actions: some View {
        FlowLayout(spacing: DSpace.s, lineSpacing: DSpace.s) {
            ForEach(message.actions) { action in
                Button(title(action)) { onAction(action) }
                    .buttonStyle(.surface)
                    .disabled(isBusy)
                    .accessibilityIdentifier(identifier(action))
            }
        }
    }

    private func title(_ action: CoachAction) -> String {
        switch action {
        case .confirm: return String(localized: "Confirmar")
        case .cancel: return String(localized: "Cancelar")
        case .say(let phrase): return phrase
        case .explain(_, let label): return label
        case .open(let flow):
            switch flow {
            case .painReport: return String(localized: "Registrar dolor")
            case .substitutes: return String(localized: "Ver sustitutos")
            case .goalOrPhaseChange: return String(localized: "Cambiar objetivo o fase")
            case .restrictions: return String(localized: "Agregar una restricción")
            }
        }
    }

    private func identifier(_ action: CoachAction) -> String {
        switch action {
        case .confirm: return "coach.confirm"
        case .cancel: return "coach.cancel"
        case .say: return "coach.say"
        case .explain: return "coach.explain"
        case .open(let flow): return "coach.open.\(flow.rawValue)"
        }
    }
}

// MARK: - Previews

/// Manejador de prueba para los previews: Hoy con el orden que se puede explicar.
@MainActor
private final class PreviewCoachHandler: CoachActionHandling {
    func coachSnapshot() -> CoachSnapshot { CoachSnapshot(surface: .today) }
    func adjustTodaySession(minutes: Int?) async -> CoachTimeOutcome {
        .adjusted(DecisionExplanation(title: "Por qué tu sesión es más corta", reasons: ["Quitamos Elevaciones laterales."]))
    }
    func markCurrentExerciseOccupied() -> OccupiedOutcome? { nil }
    func selectGym(_ id: GymID) async -> Bool { true }
}

@MainActor
private enum PreviewCoach {
    static let handler = PreviewCoachHandler()

    static func make(saying phrases: [String] = []) -> CoachConversationCoordinator? {
        guard let rule = try? ActionPolicyDefaults.makeRule(),
              let config = try? ActionPolicyConfig(rule: rule),
              let validator = try? ActionPolicyValidator(config: config) else { return nil }
        let coach = CoachConversationCoordinator(
            handler: handler,
            transport: { nil },
            writer: AgentActionWriter(validator: validator),
            audit: nil,
            presenter: CoachReplyPresenter(locale: AppEnvironment.presentationLocale)
        )
        for phrase in phrases { coach.send(phrase) }
        return coach
    }
}

#Preview("Vacío") {
    if let coach = PreviewCoach.make() {
        CoachChatView(coach: coach, onRoute: { _ in })
            .ironEnergyTheme()
    }
}

#Preview("Respuesta local · oscuro") {
    if let coach = PreviewCoach.make(saying: ["Tengo 30 minutos"]) {
        CoachChatView(coach: coach, onRoute: { _ in })
            .preferredColorScheme(.dark)
            .ironEnergyTheme()
    }
}

#Preview("Confirmar · accessibility3") {
    if let coach = PreviewCoach.make(saying: ["quiero ganar fuerza"]) {
        CoachChatView(coach: coach, onRoute: { _ in })
            .dynamicTypeSize(.accessibility3)
            .ironEnergyTheme()
    }
}
