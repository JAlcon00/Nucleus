//
//  PlanBuildingView.swift
//  PR
//
//  Created by PR.
//
//  "Armando tu semana" (SCRUM-193): se ve al terminar el cuestionario mientras el motor de
//  entrenamiento genera y guarda el bloque. Cada paso se marca cuando ocurre de verdad
//  (`PlanGeneration` del coordinador). Se queda un mínimo de `DMotion.minimumLoaderDuration`
//  para no parpadear y nunca alarga la espera más allá de eso. El plan lo arma el motor,
//  no la IA: el texto no dice otra cosa. Vista pura.
//

import SwiftUI
import PRCore
import PRDomain

struct PlanBuildingView: View {
    let generation: PlanGeneration
    let screen: TodayScreen
    /// El plan terminó (listo o fallido) y pasó el tiempo mínimo: se puede cerrar.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownAt: ContinuousClock.Instant?
    @State private var spinning = false
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize = DSize.progressRing
    @ScaledMetric(relativeTo: .body) private var statusIconSize = DSize.statusIcon

    private enum Step: CaseIterable, Identifiable {
        case volume, order, ready
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .volume: "Repartiendo tu volumen"
            case .order: "Ordenando ejercicios"
            case .ready: "Listo"
            }
        }
    }

    private enum StepStatus { case pending, inProgress, done }

    private var isFinished: Bool {
        switch screen {
        case .ready, .failed: true
        case .loading: false
        }
    }

    var body: some View {
        VStack(spacing: DSpace.xl) {
            Spacer()
            ring
            Text("Armando tu semana")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: DSpace.m) {
                ForEach(Step.allCases) { step in
                    stepRow(step)
                }
            }
            Spacer()
        }
        .padding(DSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.building")
        .onAppear {
            if shownAt == nil { shownAt = .now }
            if !reduceMotion { spinning = true }
        }
        .task(id: isFinished) {
            guard isFinished else { return }
            // Sólo lo que falte para el mínimo; si ya pasó, se cierra en seguida.
            if let shownAt {
                try? await Task.sleep(until: shownAt.advanced(by: DMotion.minimumLoaderDuration), clock: .continuous)
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.surfaceElevated, lineWidth: DSize.ringStroke)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(LinearGradient.energy, style: StrokeStyle(lineWidth: DSize.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : nil, value: spinning)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
                .foregroundStyle(Color.primaryAction)
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityHidden(true)
    }

    private func stepRow(_ step: Step) -> some View {
        let status = status(of: step)
        return HStack(spacing: DSpace.s) {
            Group {
                switch status {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                case .inProgress:
                    ProgressView()
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: statusIconSize, height: statusIconSize)
            .accessibilityHidden(true)
            Text(step.title)
                .font(.body)
                .foregroundStyle(status == .pending ? Color.textSecondary : Color.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(accessibilityValue(status)))
    }

    /// Pasos marcados según lo que el coordinador ya terminó (nunca por tiempo).
    private func status(of step: Step) -> StepStatus {
        if case .ready = screen { return .done }
        switch (step, generation) {
        case (.volume, .reading), (.volume, .generating), (.volume, .idle):
            return .inProgress
        case (.order, .reading), (.order, .generating), (.order, .idle):
            return .pending
        case (.volume, .saving), (.order, .saving):
            return .done
        case (.ready, .saving):
            return .inProgress
        case (.ready, _), (_, .failed):
            return .pending
        }
    }

    private func accessibilityValue(_ status: StepStatus) -> LocalizedStringKey {
        switch status {
        case .done: "Hecho"
        case .inProgress: "En curso"
        case .pending: "Pendiente"
        }
    }
}

#Preview("Generando") {
    PlanBuildingView(generation: .generating, screen: .loading, onFinished: {})
        .ironEnergyTheme()
}

#Preview("Guardando") {
    PlanBuildingView(generation: .saving, screen: .loading, onFinished: {})
        .ironEnergyTheme()
}

#Preview("Listo · accessibility3") {
    PlanBuildingView(generation: .idle, screen: .ready(.restDay), onFinished: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
