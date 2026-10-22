//
//  AppTabBarView.swift
//  PR
//
//  Created by PR.
//
//  Pestañas raíz de la app (SKILL §6: Hoy / Progreso / Plan / Perfil).
//  Hoy tiene una sola acción (Empezar o Continuar, SCRUM-195): restricciones, rehacer
//  cuestionario y exportar viven en Perfil. La sesión activa se presenta a nivel raíz
//  (fullScreenCover en AppRootView) para reemplazar la navegación temporalmente.
//  Vista de composición: no contiene reglas de negocio.
//

import SwiftUI
import PRCore
import PRDomain

struct AppTabBarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var selectedTab: AppTab
    /// Intento: empezar la sesión planeada hoy (envía al composition root).
    var onStart: () -> Void
    /// Intento: continuar la sesión en curso (idem).
    var onResume: () -> Void
    /// Intento: rehacer el cuestionario (mismo flujo que un cambio de plan).
    var onRedoQuestionnaire: () -> Void
    /// El entrenamiento se está abriendo: Empezar/Continuar quedan "en curso".
    var isStartingWorkout = false
    /// Intento: volver a generar el plan tras un fallo (SCRUM-193).
    var onRetryPlan: () -> Void = {}

    var body: some View {
        TabView(selection: $selectedTab) {
            todayTab
                .tabItem { tabLabel(.today) }
                .tag(AppTab.today)
            ProgressTabView()
                .tabItem { tabLabel(.progress) }
                .tag(AppTab.progress)
            PlanView(
                screen: environment.todayPlan.screen,
                week: environment.todayPlan.week,
                lastPerformance: environment.todayPlan.lastPerformance,
                isStartingWorkout: isStartingWorkout,
                onStart: canStartToday ? onStart : nil,
                onRedoQuestionnaire: onRedoQuestionnaire
            )
                .tabItem { tabLabel(.plan) }
                .tag(AppTab.plan)
            ProfileView(onRedoQuestionnaire: onRedoQuestionnaire)
                .tabItem { tabLabel(.profile) }
                .tag(AppTab.profile)
        }
        .tint(Color.primaryAction)
    }

    private var todayTab: some View {
        NavigationStack {
            TodayView(
                screen: environment.todayPlan.screen,
                order: environment.todayPlan.plan?.todayOrder ?? [],
                orderReorderedByFatigue: environment.todayPlan.plan?.todayOrderReorderedByFatigue ?? false,
                exercises: environment.todayPlan.plan?.todayExercises ?? [],
                notice: environment.todayPlan.notice,
                onDismissNotice: { environment.todayPlan.dismissNotice() },
                onStart: onStart,
                onResume: onResume,
                isStartingWorkout: isStartingWorkout,
                onRetry: onRetryPlan,
                week: environment.todayPlan.week,
                lastPerformance: environment.todayPlan.lastPerformance
            )
            .navigationTitle(AppTab.today.title)
        }
    }

    /// Hoy tiene una sesión lista para empezar (no hay un entrenamiento en curso).
    private var canStartToday: Bool {
        if case .ready(.readyToStart) = environment.todayPlan.screen { return true }
        return false
    }

    @ViewBuilder
    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}