//
//  WatchWorkoutView.swift
//  PRWatch
//
//  Created by PR.
//
//  SCRUM-257 (PR-G006): entrenar desde el reloj. La vista sólo muestra `WatchScreen` y manda
//  intenciones a `WatchSessionController`: las reglas viven en PRCore. Una acción principal,
//  "Completar", y el háptico confirma cuando la persona no está mirando.
//

import PRCore
import PRDomain
import SwiftUI

struct WatchWorkoutView: View {
    @Bindable var controller: WatchSessionController

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sensoryFeedback(.success, trigger: controller.confirmedTaps)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.screen {
        case .idle:
            WatchMessageView(
                symbol: "iphone",
                title: "Empieza en el iPhone",
                detail: "Abre Nucleus y toca Empezar."
            )
        case .active(let screen):
            WatchSetView(controller: controller, screen: screen, restEndsAt: nil)
        case .resting(let screen, let endsAt):
            // Una sola actualización al terminar: nada de temporizadores por segundo.
            TimelineView(.explicit([endsAt])) { _ in
                WatchSetView(controller: controller, screen: screen, restEndsAt: endsAt)
            }
        case .paused(let screen):
            WatchPausedView(controller: controller, exerciseName: screen.set.exerciseName)
        case .allDone:
            WatchAllDoneView(controller: controller)
        case .finished:
            WatchFinishedView(summary: controller.finishedSummary)
        case .failed:
            WatchMessageView(
                symbol: "exclamationmark.triangle",
                title: "No se pudo leer la sesión",
                detail: "Sigue en el iPhone. Lo guardado no se borró."
            )
        }
    }
}

/// La serie actual: qué toca, cuánto, y el botón de completar.
private struct WatchSetView: View {
    @Bindable var controller: WatchSessionController
    let screen: WatchSetScreen
    let restEndsAt: Date?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var showsPain = false

    private var set: WatchPlannedSet { screen.set }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchMetric.spacing) {
                if let restEndsAt { restRow(restEndsAt) }
                if controller.canReportPain { painButton }
                header
                weightRow
                repsRow
                completeButton
                if controller.saveFailed { saveFailedNotice }
                if !controller.isPhoneReachable { offlineNotice }
                WatchSessionActions(controller: controller)
            }
            .padding(.horizontal, WatchMetric.spacing)
        }
        .sheet(isPresented: $showsPain) {
            WatchPainView(controller: controller)
        }
    }

    /// Opcional y fuera del camino de "Completar": no agrega pasos a una serie normal.
    private var painButton: some View {
        Button {
            showsPain = true
        } label: {
            Text(PainRecommendationPresenter().reportButtonTitle(for: controller.reportedPain))
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
        }
        .buttonStyle(.bordered)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.exerciseName)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("Serie \(set.slot.slotIndex) de \(set.totalInExercise)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let partner = set.supersetPartner {
                Text("Superset con \(partner)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// La Corona ajusta el peso: la mano sudada no tiene que acertarle a un botón chico.
    private var weightRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(weightText)
                .font(.system(size: WatchType.setValueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(unitText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .focusable(true)
        .digitalCrownRotation(
            weightBinding, from: 0, through: 1_000, by: controller.weightStep,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peso")
        .accessibilityValue("\(weightText) \(unitText)")
        .accessibilityAdjustableAction { direction in
            let step = controller.weightStep
            switch direction {
            case .increment: controller.draftWeight = (controller.draftWeight ?? 0) + step
            case .decrement: controller.draftWeight = max(0, (controller.draftWeight ?? 0) - step)
            @unknown default: break
            }
        }
    }

    private var repsRow: some View {
        HStack(spacing: WatchMetric.spacing) {
            repsButton(symbol: "minus", label: "Menos repeticiones", delta: -1)
            VStack(spacing: 0) {
                Text("\(controller.draftReps)")
                    .font(.system(size: WatchType.setValueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("reps")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            repsButton(symbol: "plus", label: "Más repeticiones", delta: 1)
        }
    }

    private func repsButton(symbol: String, label: LocalizedStringKey, delta: Int) -> some View {
        Button {
            controller.adjustReps(by: delta)
        } label: {
            Image(systemName: symbol)
                .frame(minWidth: WatchMetric.touchTarget, minHeight: WatchMetric.touchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var completeButton: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await controller.completeCurrentSet() }
            } label: {
                Label("Completar", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(WatchColor.onAction)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.completeHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchColor.action)
            .disabled(!controller.canComplete)
            if controller.draftWeight == nil {
                Text("Gira la Corona para poner el peso.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func restRow(_ endsAt: Date) -> some View {
        HStack {
            Image(systemName: "timer")
                .accessibilityHidden(true)
            // Con la muñeca abajo no se muestra el contador que cambia cada segundo.
            if isLuminanceReduced {
                Text("Descanso")
            } else {
                Text(endsAt, style: .timer)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Button("Saltar") { controller.skipRest() }
                .buttonStyle(.plain)
                .frame(minWidth: WatchMetric.touchTarget, minHeight: WatchMetric.touchTarget)
                .accessibilityLabel("Saltar descanso")
        }
    }

    private var saveFailedNotice: some View {
        Label("No se guardó. Inténtalo otra vez.", systemImage: "exclamationmark.triangle")
            .font(.footnote)
    }

    /// Discreto: se entrena igual. Lleva texto e ícono, nunca sólo color.
    private var offlineNotice: some View {
        Label("Sin iPhone: se guarda aquí", systemImage: "iphone.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var weightText: String {
        controller.draftWeight.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—"
    }

    private var unitText: LocalizedStringKey {
        switch set.unit {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { controller.draftWeight ?? 0 },
            set: { controller.draftWeight = $0 }
        )
    }
}

/// Pausar y terminar: secundarias, debajo de la acción principal.
private struct WatchSessionActions: View {
    let controller: WatchSessionController
    @State private var confirmsFinish = false

    var body: some View {
        HStack(spacing: WatchMetric.spacing) {
            Button {
                Task { await controller.pause() }
            } label: {
                Label("Pausar", systemImage: "pause")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
            }
            .accessibilityLabel("Pausar")
            Button {
                confirmsFinish = true
            } label: {
                Label("Terminar", systemImage: "stop")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
            }
            .accessibilityLabel("Terminar sesión")
        }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmsFinish) {
            Button("Terminar") { Task { await controller.finish() } }
            Button("Seguir", role: .cancel) {}
        }
    }
}

private struct WatchPausedView: View {
    let controller: WatchSessionController
    let exerciseName: String

    var body: some View {
        VStack(spacing: WatchMetric.spacing) {
            WatchMessageView(symbol: "pause.circle", title: "En pausa", detail: exerciseName)
            Button {
                Task { await controller.resume() }
            } label: {
                Text("Reanudar")
                    .foregroundStyle(WatchColor.onAction)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchColor.action)
        }
    }
}

private struct WatchAllDoneView: View {
    let controller: WatchSessionController

    var body: some View {
        VStack(spacing: WatchMetric.spacing) {
            WatchMessageView(symbol: "checkmark.circle", title: "Series completas", detail: nil)
            Button {
                Task { await controller.finish() }
            } label: {
                Text("Terminar")
                    .foregroundStyle(WatchColor.onAction)
                    .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchColor.action)
        }
    }
}

/// Resumen corto. No dice "guardado" hasta que el iPhone lo confirme.
private struct WatchFinishedView: View {
    let summary: WatchFinishedSummary?

    var body: some View {
        VStack(spacing: WatchMetric.spacing) {
            Image(systemName: summary?.isSaved == false ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                .imageScale(.large)
                .accessibilityHidden(true)
            Text(summary?.isSaved == false ? "Se guardará al ver el iPhone" : "Entrenamiento guardado")
                .font(.headline)
                .multilineTextAlignment(.center)
            if let summary {
                Text("\(summary.sets) series")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let seconds = summary.durationSeconds {
                    Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, WatchMetric.spacing)
        .accessibilityElement(children: .combine)
    }
}

/// "¿Te dolió?": la misma escala que el iPhone. El reloj no decide ni diagnostica: muestra lo
/// que dice el motor, y con moderado o alto manda a seguir en el iPhone.
private struct WatchPainView: View {
    @Bindable var controller: WatchSessionController
    @Environment(\.dismiss) private var dismiss

    private let presenter = PainRecommendationPresenter()
    private static let levels: [PainLevel] = [.none, .mild, .moderate, .high]

    var body: some View {
        ScrollView {
            VStack(spacing: WatchMetric.spacing) {
                if let reported = controller.reportedPain, let recommendation = controller.painRecommendation {
                    result(level: reported, recommendation: recommendation)
                } else {
                    Text("¿Te dolió?")
                        .font(.headline)
                    ForEach(Self.levels, id: \.self) { level in
                        Button {
                            Task { await controller.reportPain(level) }
                        } label: {
                            Text(presenter.levelName(level))
                                .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
                        }
                    }
                }
            }
            .padding(.horizontal, WatchMetric.spacing)
        }
    }

    @ViewBuilder
    private func result(level: PainLevel, recommendation: PainRecommendation) -> some View {
        Text(presenter.levelName(level))
            .font(.headline)
        if let message = presenter.message(for: recommendation) {
            Text(message)
                .font(.footnote)
        }
        if level.isConservativeDisruptive {
            Label("Sigue en el iPhone", systemImage: "iphone")
                .font(.footnote)
        }
        Button("Listo") { dismiss() }
            .frame(maxWidth: .infinity, minHeight: WatchMetric.touchTarget)
    }
}

/// Un mensaje con su ícono: todo lo que no es una serie.
struct WatchMessageView: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    init(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey?) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    init(symbol: String, title: LocalizedStringKey, detail: String) {
        self.init(symbol: symbol, title: title, detail: LocalizedStringKey(detail))
    }

    var body: some View {
        VStack(spacing: WatchMetric.spacing) {
            Image(systemName: symbol)
                .imageScale(.large)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, WatchMetric.spacing)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func previewController(
    stage: WatchSessionStage = .active,
    weight: Double? = 62.5,
    resting: Bool = false,
    empty: Bool = false
) -> WatchSessionController {
    let exercise = ExerciseID()
    let set = WatchPlannedSet(
        slot: SetSlot(exerciseID: exercise, slotIndex: 2),
        exerciseName: "Press de banca con barra", totalInExercise: 4, targetRepRange: 8...12, targetReps: 8,
        weight: weight, unit: .kilograms, isWarmup: false, restSecondsAfter: 90, supersetPartner: nil
    )
    let snapshot = WatchSessionSnapshot(
        sessionID: WorkoutID(), revision: 1, title: "Torso", stage: stage, confirmedSetIDs: [],
        restEndsAt: resting ? Date().addingTimeInterval(75) : nil, remaining: empty ? [] : [set]
    )
    let store = MemoryRepositoryStore()
    let local = WatchLocalStore(store: store)
    do {
        try local.save(WatchLocalState(snapshot: snapshot, restEndsAt: snapshot.restEndsAt))
    } catch {
        assertionFailure("Vista previa sin datos")
    }
    return WatchSessionController(store: local, link: FakeWorkoutLink())
}

#Preview("Sin sesión") {
    WatchWorkoutView(controller: WatchSessionController(store: WatchLocalStore(store: MemoryRepositoryStore()), link: FakeWorkoutLink()))
}

#Preview("Serie") {
    WatchWorkoutView(controller: previewController())
}

#Preview("Sin peso") {
    WatchWorkoutView(controller: previewController(weight: nil))
}

#Preview("Descanso") {
    WatchWorkoutView(controller: previewController(resting: true))
}

#Preview("En pausa") {
    WatchWorkoutView(controller: previewController(stage: .paused))
}

#Preview("Series completas") {
    WatchWorkoutView(controller: previewController(empty: true))
}

#Preview("Guardado") {
    WatchWorkoutView(controller: previewController(stage: .finished))
}

#Preview("Letra grande") {
    WatchWorkoutView(controller: previewController())
        .dynamicTypeSize(.accessibility3)
}
#endif
