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
            case .resting(let next, rest: let rest):
                liveContent(active: nil, resting: RestTimerView(
                    remainingSeconds: rest.remaining(at: now),
                    onSkip: { coordinator.skipRest() },
                    onExtend: { coordinator.extendRest() }
                ), next: next)
            case .paused(let set):
                pausedView(set)
            case .finished(let summary):
                WorkoutSummaryView(
                    summary: summary,
                    celebration: coordinator.celebration(for: summary, level: coachingLevel),
                    skipped: coordinator.skippedExercises.map(\.name),
                    onDone: onDone
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if coordinator.persistenceFailed {
                Label {
                    Text("No se pudo guardar en el dispositivo. Sigue entrenando: lo reintentamos en la siguiente serie.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warning)
                }
                    .font(.callout)
                    .padding(DSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(cornerRadius: DRadius.medium)
                    .padding(.horizontal, DSpace.m)
                    .accessibilityIdentifier("workout.persistenceWarning")
            }
        }
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
        .sheet(isPresented: $reportingPain) { painSheet }
        .sensoryFeedback(trigger: coordinator.painReport?.level, painFeedback)
        // Si la sesión termina con la hoja abierta (p. ej. saltar lo último), se cierra.
        .onChange(of: coordinator.painReport == nil) { _, isGone in
            if isGone { reportingPain = false }
        }
        .onAppear { syncTicker() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    @State private var finishTapped = false
    /// SCRUM-212: "Saltar" pide confirmación (no se puede deshacer sin "Retomar").
    @State private var confirmingSkip: String?
    /// SCRUM-226: hoja "¿Te dolió esta serie?". Abre a media altura (la escala queda al
    /// alcance del pulgar) y crece al reportar dolor, para que la recomendación se vea entera.
    @State private var reportingPain = false
    @State private var painDetent: PresentationDetent = .medium
    private let painPresenter = PainRecommendationPresenter(locale: AppEnvironment.presentationLocale)

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
    private func liveContent(
        active set: ActiveWorkoutSetUI?,
        resting restView: RestTimerView?,
        next: ActiveWorkoutSetUI? = nil
    ) -> some View {
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
                if let report = coordinator.painReport {
                    // SCRUM-226: en el descanso se puede decir si dolió la serie. Secundario:
                    // no tapa el tiempo ni lo que sigue.
                    painButton(report)
                        .padding(.horizontal, DSpace.l)
                        .padding(.bottom, DSpace.m)
                }
                if let next {
                    // En pleno descanso: qué sigue y, si la máquina está ocupada, cambiarlo.
                    queueActions(for: next, label: "Sigue: \(next.exerciseName)")
                        .padding([.horizontal, .bottom], DSpace.l)
                }
            }
        }
        .confirmationDialog(
            "¿Saltar \(confirmingSkip ?? "")?",
            isPresented: Binding(get: { confirmingSkip != nil }, set: { if !$0 { confirmingSkip = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sí, saltar") {
                _ = try? coordinator.skipCurrentExercise()
                confirmingSkip = nil
            }
            .accessibilityIdentifier("workout.skip.confirm")
            Button("Cancelar", role: .cancel) { confirmingSkip = nil }
        } message: {
            Text("Las series que ya hiciste se guardan. Puedes retomarlo antes de terminar.")
        }
    }

    /// SCRUM-212: acciones secundarias sobre el ejercicio actual (o el que sigue en el
    /// descanso) y los saltados para retomarlos. La acción principal sigue siendo
    /// "Completar serie".
    private func queueActions(for set: ActiveWorkoutSetUI, label: String? = nil) -> some View {
        VStack(spacing: DSpace.s) {
            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: DSpace.s) {
                Button {
                    _ = try? coordinator.deferCurrentExercise()
                } label: {
                    Label("Para después", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.surface)
                .accessibilityHint("Pasa este ejercicio al final, por ejemplo si la máquina está ocupada.")
                .accessibilityIdentifier("workout.defer")
                Button {
                    confirmingSkip = set.exerciseName
                } label: {
                    // "Saltar" a secas es del descanso: éste dice qué salta.
                    Label("Saltar ejercicio", systemImage: "forward.end")
                }
                .buttonStyle(.surface)
                .accessibilityIdentifier("workout.skip")
            }
            ForEach(Array(coordinator.skippedExercises.enumerated()), id: \.element.id) { index, skipped in
                HStack {
                    Label("Saltado: \(skipped.name)", systemImage: "forward.end")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Retomar") {
                        _ = try? coordinator.resumeSkipped(skipped.id)
                    }
                    .frame(minHeight: DSize.dayChip)
                    .accessibilityIdentifier("workout.resume.\(index)")
                }
            }
        }
    }

    /// SCRUM-226: botón del descanso para reportar el dolor de la serie que se acaba de
    /// hacer. Dice lo ya reportado; con moderado o alto lleva el icono de aviso.
    private func painButton(_ report: PainReportUI) -> some View {
        Button {
            painDetent = report.level.map { $0 > PainLevel.none } == true ? .large : .medium
            reportingPain = true
        } label: {
            Label(
                painPresenter.reportButtonTitle(for: report.level),
                systemImage: report.recommendation == .continueNormal ? "hand.raised" : "exclamationmark.triangle"
            )
        }
        .buttonStyle(.surface)
        .accessibilityHint("Di si te dolió la serie que acabas de hacer.")
        .accessibilityIdentifier("workout.pain")
    }

    /// Hoja del dolor. "Sin dolor" la cierra; saltar el ejercicio también. Un error aquí es
    /// de estado (la sesión ya terminó): el guardado fallido lo avisa `persistenceFailed`.
    @ViewBuilder
    private var painSheet: some View {
        if let report = coordinator.painReport {
            PainReportSheet(
                report: report,
                onReport: { level, muscle in
                    _ = try? coordinator.reportPain(level, muscleGroup: muscle)
                    if level == PainLevel.none {
                        reportingPain = false
                    } else {
                        painDetent = .large
                    }
                },
                onSkipExercise: {
                    _ = try? coordinator.skipPainfulExercise()
                    reportingPain = false
                },
                onDone: { reportingPain = false }
            )
            .presentationDetents([.medium, .large], selection: $painDetent)
            .presentationDragIndicator(.visible)
        }
    }

    /// Háptico al guardar el dolor: confirmación breve sin dolor o leve; aviso con
    /// moderado o alto (la recomendación de la hoja lo explica).
    private func painFeedback(_ old: PainLevel?, _ new: PainLevel?) -> SensoryFeedback? {
        guard let new, new != old else { return nil }
        return new.isConservativeDisruptive ? .warning : .success
    }

    /// Tarjeta de educación contextual derivada (determinista, PR-1501) del estado de
    /// la sesión: calentamiento/descanso, respetando el nivel del usuario. La
    /// recomendación por dolor va en la hoja del dolor (SCRUM-226), no aquí.
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
            queueActions(for: set)
                .padding(.horizontal, DSpace.l)
                .padding(.bottom, DSpace.m)
            PrimaryActionButton(
                "Completar serie",
                systemImage: "checkmark",
                identifier: "workout.completeSet"
            ) { completeSet(set) }
                .padding(.horizontal, DSpace.l)
        }
        .padding(.top, DSpace.l)
    }

    private func setHeader(_ set: ActiveWorkoutSetUI) -> some View {
        VStack(spacing: DSpace.xs) {
            if set.isWarmup {
                Label("CALENTAMIENTO", systemImage: "flame.fill")
                    .eyebrowStyle()
                    .foregroundStyle(Color.warning)
            }
            Text(set.exerciseName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Serie \(set.position) de \(set.total)")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            // SCRUM-200: a qué RIR llegar (lo planeó el motor) y, en la última serie de
            // trabajo, si conviene dropset.
            if let targetRIR = set.targetRIR {
                RIRTag(range: targetRIR)
                    .padding(.top, DSpace.xs)
            }
            if let dropset = set.dropset {
                DropsetNote(advice: dropset, prominent: true)
                    .padding(.horizontal, DSpace.m)
                    .padding(.vertical, DSpace.s)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: DRadius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: DRadius.medium).strokeBorder(Color.hairline, lineWidth: 1)
                    }
                    .padding(.top, DSpace.s)
            }
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
                .foregroundStyle(Color.warning)
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
            .foregroundStyle(Color.textSecondary)
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
    .ironEnergyTheme()
}

#Preview("Serie activa · accessibility3") {
    NavigationStack {
        WorkoutModeView(coordinator: makePreviewCoordinator())
    }
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}

#Preview("Descanso · dolor moderado reportado") {
    NavigationStack {
        WorkoutModeView(coordinator: makeRestingPreviewCoordinator(pain: .moderate))
    }
    .ironEnergyTheme()
}

#Preview("Descanso · sin reportar · oscuro") {
    NavigationStack {
        WorkoutModeView(coordinator: makeRestingPreviewCoordinator(pain: nil))
    }
    .ironEnergyTheme()
    .preferredColorScheme(.dark)
}

/// En el descanso tras la primera de dos series, con o sin dolor reportado (SCRUM-226).
@MainActor
private func makeRestingPreviewCoordinator(pain: PainLevel?) -> WorkoutSessionCoordinator {
    let exerciseID = ExerciseID()
    let set = try? PlannedSet(
        exerciseID: exerciseID,
        prescription: SetPrescription(targetRepRange: 8...10, targetLoad: 82.5, loadUnit: .kilograms, restSeconds: 90...120)
    )
    let coordinator = WorkoutSessionCoordinator(
        template: SessionTemplate(title: "Press banca", plannedSets: [set, set].compactMap { $0 }),
        exerciseNames: [exerciseID: "Press banca"],
        exerciseMuscles: [exerciseID: [.chest, .triceps, .shoulders]]
    )
    _ = coordinator.start()
    _ = try? coordinator.completeCurrentSet()
    if let pain { _ = try? coordinator.reportPain(pain) }
    return coordinator
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
                .foregroundStyle(Color.primaryAction)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.callout.weight(.semibold))
                Text(card.message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("Descartar consejo")
            }
        }
        .padding(DSpace.m)
        .cardSurface(cornerRadius: DRadius.medium)
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