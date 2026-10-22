//
//  PlanView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Plan" (SCRUM-197, U4): "Tu semana" completa, de lunes a domingo, con la sesión
//  de cada día de entrenamiento y el descanso intercalado. Estados:
//  - cargando: skeleton de 3 tarjetas;
//  - fallido: se reutiliza `PlanUnreadableView` (rehacer el cuestionario, sin tocar el
//    historial);
//  - vacío (sin semana válida): invita a responder el cuestionario;
//  - sin conexión: no aplica, todo es local.
//  Vista de composición: no contiene reglas de negocio.
//

import SwiftUI
import PRCore
import PRDomain

struct PlanView: View {
    let screen: TodayScreen
    let week: WeekOverview?
    var lastPerformance: [ExerciseID: LastPerformance] = [:]
    var isStartingWorkout = false
    /// Empezar la sesión de hoy; `nil` si hoy no hay nada que empezar.
    var onStart: (() -> Void)?
    var onRedoQuestionnaire: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .loading:
                    skeleton
                case .failed:
                    PlanUnreadableView(onRedo: onRedoQuestionnaire)
                case .ready:
                    if let week {
                        WeekListView(
                            week: week,
                            lastPerformance: lastPerformance,
                            isStartingWorkout: isStartingWorkout,
                            onStart: onStart
                        )
                    } else {
                        emptyState
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(AppTab.plan.title)
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: DSpace.s) {
                    Text("LUNES · HOY").eyebrowStyle()
                    Text("Sesión de la semana").font(.title3.bold())
                    Text("Pecho · Hombro · Tríceps").font(.subheadline)
                    Text("5 ejercicios · 15 series").font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSpace.m)
                .cardSurface()
            }
            Spacer()
        }
        .padding(DSpace.m)
        .redacted(reason: .placeholder)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cargando tu semana"))
        .accessibilityIdentifier("plan.loading")
    }

    private var emptyState: some View {
        VStack(spacing: DSpace.l) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.primaryAction)
                .accessibilityHidden(true)
            Text("Responde el cuestionario para armar tu semana")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Button(action: onRedoQuestionnaire) {
                Text("Responder cuestionario")
            }
            .buttonStyle(.energy)
            .accessibilityIdentifier("plan.empty.redo")
        }
        .padding(DSpace.l)
        .accessibilityIdentifier("plan.empty")
    }
}

#Preview("Cargando") {
    PlanView(screen: .loading, week: nil)
        .ironEnergyTheme()
}

#Preview("Fallido · accessibility3") {
    PlanView(screen: .failed, week: nil)
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Vacío") {
    PlanView(screen: .ready(.restDay), week: nil)
        .ironEnergyTheme()
}
