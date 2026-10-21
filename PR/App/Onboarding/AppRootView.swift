//
//  AppRootView.swift
//  PR
//
//  Created by PR.
//
//  Vista raíz que enruta según la fase del `OnboardingCoordinator` (EPIC-04 wiring):
//  sign-in → onboarding → app. Renderiza estado y reenvía intents; no contiene reglas
//  de negocio. Tras completar el onboarding muestra la pantalla "Hoy".
//

import SwiftUI
import PRCore
import PRDomain

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Group {
            switch phase {
            case .signedOut:
                SignInView(onSignIn: { await environment.onboarding.signIn() })
            case .signingIn:
                ProgressView("Conectando…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .onboarding(let step, let index, let canGoBack, let canAdvance, let isAtEnd):
                OnboardingStepView(
                    step: step,
                    indexPlusOne: index + 1,
                    stepCount: OnboardingStep.ordered.count,
                    canAdvance: canAdvance,
                    canGoBack: canGoBack,
                    isAtEnd: isAtEnd,
                    choices: OnboardingChoicePresenter(locale: AppEnvironment.presentationLocale).choices(for: step),
                    selected: environment.onboarding.currentAnswer,
                    onAnswer: { environment.onboarding.select($0) },
                    onAdvance: { environment.onboarding.advance() },
                    onGoBack: { environment.onboarding.goBack() },
                    onFinish: { environment.onboarding.complete() }
                )
            case .completed(let profile):
                appContent
                    .onAppear {
                        // Deriva el plan real de hoy a partir del perfil (PR-0601 wiring).
                        _ = environment.todayPlan.load(profile: profile)
                    }
            case .failed(let message):
                // Renderizamos un gate coherente y mostramos el error en un alert.
                Color.clear
                    .onAppear {
                        alertMessage = message
                        showAlert = true
                    }
            }
        }
        .task { await environment.startIfNeeded() }
        .alert("No se pudo continuar", isPresented: $showAlert) {
            Button("OK") {
                environment.onboarding.dismissFailure()
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var phase: OnboardingPhase {
        environment.onboarding.phase
    }

    /// Coordinador de WORKOUT MODE activo (nil hasta que se empieza una sesión).
    /// Si no es nil, WORKOUT MODE se presenta a pantalla completa (`fullScreenCover(item:)`
    /// entrega el coordinador ya no opcional: antes la cubierta quedaba vacía/negra).
    @State private var workout: WorkoutSessionCoordinator?
    @State private var selectedTab = AppTab.today
    /// Carga en curso del coordinador (lee historial local). Una sola a la vez: un
    /// doble toque no crea dos sesiones.
    @State private var workoutLoad: Task<Void, Never>?

    /// El contenido "de la app" tras completar el onboarding: tab bar + WORKOUT MODE.
    /// La sesión activa se presenta a nivel raíz (fullScreenCover) para reemplazar la
    /// navegación temporalmente (SKILL §6). Vista de composición: sin reglas de negocio.
    @ViewBuilder
    private var appContent: some View {
        AppTabBarView(
            selectedTab: $selectedTab,
            onStart: { startWorkout() },
            onResume: { resumeWorkout() }
        )
        .fullScreenCover(item: $workout) { coordinator in
            NavigationStack {
                WorkoutModeView(
                    coordinator: coordinator,
                    onDone: { workout = nil },
                    coachingLevel: coachingLevel
                )
            }
        }
    }

    /// Nivel de detalle de coaching derivado (determinista, PR-0403) del perfil de
    /// onboarding completado. Default `guided` si aún no hay perfil (nunca inventa).
    private var coachingLevel: CoachingDetailLevel {
        guard case .completed(let profile) = environment.onboarding.phase else {
            return .guided
        }
        return CoachingDetailMapper().initialDefault(for: profile.experience)
    }

    private func startWorkout() {
        presentWorkout(startingNewSession: true)
    }

    private func resumeWorkout() {
        // Restaura el workout activo (si se conserva) o inicia uno nuevo con el estado
        // actual de la plantilla de hoy. En este slice la sesión se empieza/persiste en
        // memoria; el reload desde persistencia es el cableado de PR-0201/0202.
        presentWorkout(startingNewSession: false)
    }

    private func presentWorkout(startingNewSession: Bool) {
        guard workoutLoad == nil else { return }
        workoutLoad = Task {
            defer { workoutLoad = nil }
            guard let coordinator = await environment.makeWorkoutCoordinator(),
                  !Task.isCancelled else { return }
            if startingNewSession {
                _ = coordinator.start()
            }
            workout = coordinator
        }
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment(authProvider: FakeAppleIDAuthProvider()))
}