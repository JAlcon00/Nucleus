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
    /// Textos del ajuste del día (SCRUM-203).
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)
    @Binding var selectedTab: AppTab
    /// El aviso "Completa tu perfil" se muestra una sola vez (SCRUM-198).
    @AppStorage("profile.aboutYouPromptShown") private var aboutYouPromptShown = false
    @State private var editingAboutYou = false
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
            ProgressTabView(
                screen: environment.todayPlan.progress,
                onRetry: { Task { await environment.refreshHistory() } }
            )
                .tabItem { tabLabel(.progress) }
                .tag(AppTab.progress)
            PlanView(
                screen: environment.todayPlan.screen,
                week: environment.todayPlan.week,
                lastPerformance: environment.todayPlan.lastPerformance,
                isStartingWorkout: isStartingWorkout,
                onStart: canStartToday ? onStart : nil,
                onRedoQuestionnaire: onRedoQuestionnaire,
                rationale: environment.todayPlan.personalization
            )
                .tabItem { tabLabel(.plan) }
                .tag(AppTab.plan)
            ProfileView(
                aboutYou: environment.completedProfile?.aboutYou,
                now: environment.now,
                onEditAboutYou: { editingAboutYou = true },
                onRedoQuestionnaire: onRedoQuestionnaire,
                aiConsentGranted: environment.aiConsent.consent.allowsSharing,
                onSetAIConsent: { granted in
                    if granted { environment.aiConsent.grant() } else { environment.aiConsent.decline() }
                },
                aiStatus: environment.aiConnection.status
            )
                .tabItem { tabLabel(.profile) }
                .tag(AppTab.profile)
        }
        .tint(Color.primaryAction)
        .sheet(isPresented: $editingAboutYou) {
            AboutYouEditSheet(answer: aboutYouDraft) { answer in
                await environment.session.updateAboutYou(answer)
            }
        }
    }

    /// Lo guardado de "Sobre ti" para editarlo (vacío en un perfil anterior).
    private var aboutYouDraft: AboutYouAnswer {
        guard let aboutYou = environment.completedProfile?.aboutYou else { return AboutYouAnswer() }
        return AboutYouAnswer(aboutYou, on: environment.now, timeZone: .current)
    }

    /// Perfil anterior sin "Sobre ti": se pide completarlo una vez, sin bloquear Hoy.
    private var asksToCompleteProfile: Bool {
        guard let profile = environment.completedProfile else { return false }
        return profile.aboutYou == nil && !aboutYouPromptShown
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
                lastPerformance: environment.todayPlan.lastPerformance,
                greetingName: environment.completedProfile?.aboutYou?.name,
                asksToCompleteProfile: asksToCompleteProfile,
                onCompleteProfile: {
                    aboutYouPromptShown = true
                    editingAboutYou = true
                },
                onDismissProfilePrompt: { aboutYouPromptShown = true },
                asksSleepCheckIn: environment.asksSleepCheckIn,
                onSleepCheckIn: { hours, quality in environment.recordSleep(hours: hours, quality: quality) },
                onSkipSleepCheckIn: { environment.sleepCheckIns.skip() },
                readinessNote: environment.todayPlan.plan.flatMap { vocabulary.readinessNote($0.readiness) }
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