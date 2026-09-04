//
//  WorkoutModeView.swift
//  PR
//
//  Created by PR.
//
//  WORKOUT MODE (SKILL §9/§10/§41): pantalla del entrenamiento activo. Presenta el
//  estado derivado por `WorkoutSessionCoordinator` (active/resting/paused/finished) y
//  reenvía intents (completar serie, editar peso/reps, saltar/extender descanso, pausar,
//  terminar). NO contiene reglas de negocio: sólo renderiza `WorkoutSessionPhase`.
//  Funciona offline.
//

import SwiftUI
import PRCore
import PRDomain

struct WorkoutModeView: View {
    @Bindable var coordinator: WorkoutSessionCoordinator
    /// Intento: tras terminar la sesión, volver al plan (cierra el fullScreenCover).
    var onDone: () -> Void = {}
    /// Nivel de detalle de coaching (PR-1501); derivado del perfil, nunca inventado.
    var coachingLevel: CoachingDetailLevel = .guided

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var now: Date = Date()
    @State private var timer: Timer?
    @State private var dismissedCards: Set<CoachingCardID> = []

    private let coachingDriver = CoachingCardDriver()

    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle:
                emptyView
            case .active(let set):
                liveContent(active: set, resting: nil)
            case .resting(_, rest: let rest):
                liveContent(active: nil, resting: RestTimerView(
                    remainingSeconds: rest.remaining(at: now),
                    onSkip: { coordinator.skipRest() },
                    onExtend: { coordinator.extendRest() }
                ))
            case .paused(let set):
                pausedView(set)
            case .finished(let summary):
                WorkoutSummaryView(summary: summary, onDone: onDone)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isLive {
                    Button("Terminar", role: .destructive) { finishTapped = true }
                }
            }
        }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $finishTapped, titleVisibility: .visible) {
            Button("Completar sesión") {
                _ = try? coordinator.complete()
            }
            Button("Abandonar", role: .destructive) {
                _ = try? coordinator.abandon()
            }
            Button("Seguir entrenando", role: .cancel) {}
        }
        .onAppear { syncTicker() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    @State private var finishTapped = false

    private var isLive: Bool {
        switch coordinator.phase {
        case .active, .resting, .paused: return true
        default: return false
        }
    }

    /// Compone el contenido en curso (set o descanso) con una tarjeta de coaching
    /// contextual descartable (PR-1501): educación ligada al contexto, descartable,
    /// y reducida en nivel advanced por el driver.
    @ViewBuilder
    private func liveContent(active set: ActiveWorkoutSetUI?, resting restView: RestTimerView?) -> some View {
        VStack(spacing: 0) {
            if let card = coachingCard, !dismissedCards.contains(card.id) {
                CoachingCardBanner(card: card) {
                    dismissedCards.insert(card.id)
                }
                .padding(DSpace.m)
            }
            if let set {
                setView(set)
            } else if let restView {
                restView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Tarjeta de educación contextual derivada (determinista, PR-1501) del estado de
    /// la sesión. Sin molestia reportada (PR-1403 no está cableado aún) salvo que la UI
    /// lo ofrezca; aquí sólo calentamiento/descanso, respetando el nivel del usuario.
    private var coachingCard: CoachingCard? {
        var isWarmup = false
        var restActive = false
        switch coordinator.phase {
        case .active(let set):
            isWarmup = set.isWarmup
        case .resting:
            restActive = true
        default:
            break
        }
        return coachingDriver.card(for: CoachingContext(
            level: coachingLevel,
            isWarmup: isWarmup,
            restActive: restActive,
            painRecommendation: .continueNormal
        ))
    }

    @ViewBuilder
    private func setView(_ set: ActiveWorkoutSetUI) -> some View {
        VStack(spacing: 0) {
            setHeader(set)
            Spacer()
            inputControls(for: set)
            Spacer()
            PrimaryActionButton(
                "Completar serie",
                systemImage: "checkmark"
            ) { completeSet(set) }
                .padding(.horizontal, DSpace.l)
        }
        .padding(.top, DSpace.l)
    }

    private func setHeader(_ set: ActiveWorkoutSetUI) -> some View {
        VStack(spacing: DSpace.xs) {
            if set.isWarmup {
                Text("CALENTAMIENTO")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            Text(set.exerciseName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Serie \(set.index + 1) de \(set.total)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSpace.l)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func inputControls(for set: ActiveWorkoutSetUI) -> some View {
        VStack(spacing: DSpace.l) {
            SetInputControl(
                label: "Peso",
                value: $weight,
                step: set.draft.targetWeight < 25 ? 2.5 : 5,
                suffix: set.draft.targetUnit == .pounds ? "lb" : "kg"
            )

            SetInputControl(
                label: "Repeticiones",
                value: Binding(
                    get: { Double(reps) },
                    set: { reps = Int($0.rounded()) }
                ),
                step: 1,
                suffix: ""
            )
            .accessibilityLabel("Repeticiones")
        }
        .padding(.horizontal, DSpace.l)
        .onAppear { loadTarget(from: set) }
        .onChange(of: coordinator.phase) { _, _ in loadTarget(from: set) }
    }

    private func loadTarget(from set: ActiveWorkoutSetUI) {
        weight = set.draft.targetWeight
        reps = set.draft.targetReps
    }

    private func completeSet(_ set: ActiveWorkoutSetUI) {
        // Uno-tap (SKILL §10): si el usuario no cambió nada, registrar sin fricción.
        // Si editó peso/reps (SKILL §11), capturar el valor editado. Compara contra el
        // objetivo derivado para evitar depender de flags que compiten con onChange.
        let matchesTarget = weight == set.draft.targetWeight && reps == set.draft.targetReps
        if matchesTarget {
            _ = try? coordinator.completeCurrentSet()
        } else {
            _ = try? coordinator.recordEditedSet(weight: weight, reps: reps)
        }
    }

    private func pausedView(_ set: ActiveWorkoutSetUI) -> some View {
        VStack(spacing: DSpace.l) {
            Label("En pausa", systemImage: "pause.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(set.exerciseName)
                .font(.title2.bold())
            PrimaryActionButton("Reanudar", systemImage: "play.fill") {
                _ = try? coordinator.resume()
            }
        }
        .padding(DSpace.l)
    }

    private var emptyView: some View {
        Text("Sin sesión activa")
            .foregroundStyle(.secondary)
    }

    // MARK: - Ticker para el descanso (cuenta desde wall-clock, SKILL §41/§42)

    private func syncTicker() {
        now = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                now = Date()
                coordinator.tick()
            }
        }
    }
}

#Preview("Serie activa") {
    NavigationStack {
        WorkoutModeView(coordinator: makePreviewCoordinator())
    }
}

@MainActor
private func makePreviewCoordinator() -> WorkoutSessionCoordinator {
    let exerciseID = ExerciseID()
    let template = SessionTemplate(
        title: "Press banca",
        plannedSets: (try? [
            PlannedSet(
                exerciseID: exerciseID,
                prescription: SetPrescription(
                    targetRepRange: 8...10,
                    targetLoad: 82.5,
                    loadUnit: .kilograms,
                    restSeconds: 90...120
                )
            )
        ]) ?? []
    )
    let coordinator = WorkoutSessionCoordinator(
        template: template,
        exerciseNames: [exerciseID: "Press banca"]
    )
    _ = coordinator.start()
    return coordinator
}

/// Banner de educación contextual descartable (PR-1501). Vista pura: presenta la
/// tarjeta que decidió `CoachingCardDriver` y reenvía el intent de descartar.
private struct CoachingCardBanner: View {
    let card: CoachingCard
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DSpace.s) {
            Image(systemName: icon(for: card.kind))
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                Text(card.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Descartar consejo")
            }
        }
        .padding(DSpace.m)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DRadius.medium))
        .accessibilityElement(children: .contain)
    }

    private func icon(for kind: CoachingCardKind) -> String {
        switch kind {
        case .warmup: return "flame"
        case .rest: return "timer"
        case .painSafety: return "heart.text.square"
        }
    }
}