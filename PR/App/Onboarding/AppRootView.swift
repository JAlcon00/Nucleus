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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Group {
            switch phase {
            case .signedOut:
                SignInView(onSignIn: { await environment.session.signIn() })
            case .signingIn:
                SigningInView(onRetry: { Task { await environment.session.retrySignIn() } })
            case .onboarding where environment.onboarding.needsAboutYou:
                // "Sobre ti" va antes del primer paso (SCRUM-198).
                AboutYouView(
                    answer: environment.onboarding.aboutYouAnswer,
                    onChange: { environment.onboarding.updateAboutYou($0) },
                    onContinue: { environment.onboarding.confirmAboutYou() }
                )
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
                    onFinish: { finishOnboarding() }
                )
            case .completed where environment.aiConsent.needsDecision:
                // SCRUM-202: antes de armar el plan, la persona decide si la IA usa sus datos.
                AIConsentView(
                    saveFailed: environment.aiConsent.saveFailed,
                    onAccept: { environment.aiConsent.grant() },
                    onDecline: { environment.aiConsent.decline() }
                )
            case .completed(let profile):
                appContent
                    .task(id: PlanActivation(profile: profile, attempt: planAttempt)) {
                        // Sólo pruebas de UI (Debug): plan pendiente a propósito (SCRUM-193).
                        if let delay = environment.uiTestPlanDelay {
                            try? await Task.sleep(for: delay)
                        }
                        // Activa y guarda el plan del perfil (SCRUM-26). Si venimos de un
                        // plan recordado, ya está activo y no se regenera.
                        _ = await environment.session.planCompleted(profile: profile)
                        // Retoma el entrenamiento que quedó abierto, si lo hay (SCRUM-24).
                        await environment.recoverWorkout()
                        // Historial para "Tu semana" y "última vez" (SCRUM-197).
                        await environment.refreshHistory()
                    }
            case .planUnreadable:
                PlanUnreadableView(onRedo: { environment.session.redoQuestionnaire() })
            case .failed(let message):
                // Renderizamos un gate coherente y mostramos el error en un alert.
                Color.clear
                    .onAppear {
                        alertMessage = message
                        showAlert = true
                    }
            }
        }
        .screenBackground()
        .task { await environment.startIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in
            // Si Apple revocó la credencial mientras la app estaba en segundo plano.
            if newPhase == .active {
                Task { await environment.session.verifyCredential() }
            }
        }
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
    /// Reintentos de generar el plan tras un fallo (relanza la activación).
    @State private var planAttempt = 0
    /// Recién terminado el cuestionario: se muestra "Armando tu semana" hasta que el plan
    /// esté listo (o falle).
    @State private var buildingWeek = false
    /// Tras armar la semana, se presenta "Tu semana" (SCRUM-197).
    @State private var showingWeekIntro = false

    /// El contenido "de la app" tras completar el onboarding: tab bar + WORKOUT MODE.
    /// La sesión activa se presenta a nivel raíz (fullScreenCover) para reemplazar la
    /// navegación temporalmente (SKILL §6). Vista de composición: sin reglas de negocio.
    @ViewBuilder
    private var appContent: some View {
        AppTabBarView(
            selectedTab: $selectedTab,
            onStart: { startWorkout() },
            onResume: { resumeWorkout() },
            onRedoQuestionnaire: { environment.session.redoQuestionnaire() },
            isStartingWorkout: workoutLoad != nil,
            onRetryPlan: { planAttempt += 1 }
        )
        // Mientras "Armando tu semana" está encima, Hoy no se puede tocar ni leer con
        // VoiceOver (sólo existe el loader).
        .accessibilityHidden(buildingWeek)
        .overlay {
            if buildingWeek {
                PlanBuildingView(
                    generation: environment.todayPlan.generation,
                    screen: environment.todayPlan.screen,
                    usesAI: environment.personalizesWithAI,
                    // Sin fundido de salida: Hoy vuelve a ser tocable y legible para
                    // VoiceOver en el mismo instante en que el loader desaparece.
                    onFinished: {
                        buildingWeek = false
                        if case .ready = environment.todayPlan.screen { showingWeekIntro = true }
                    }
                )
            }
        }
        .sheet(isPresented: $showingWeekIntro) {
            WeekIntroView(
                week: environment.todayPlan.week,
                rationale: environment.todayPlan.personalization,
                onDone: { showingWeekIntro = false }
            )
        }
        .fullScreenCover(item: $workout) { coordinator in
            NavigationStack {
                WorkoutModeView(
                    coordinator: coordinator,
                    onDone: {
                        workout = nil
                        environment.workoutEnded()
                        // La semana marca el día como hecho.
                        Task { await environment.refreshHistory() }
                    },
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

    /// "Terminar" del cuestionario: si el perfil es válido, se arma la semana con loader.
    private func finishOnboarding() {
        environment.onboarding.complete()
        if case .completed = environment.onboarding.phase {
            buildingWeek = true
        }
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

/// Identidad de la activación del plan: cambia con el perfil o con un reintento.
private struct PlanActivation: Hashable {
    let profile: OnboardingProfile
    let attempt: Int
}

/// "Tu semana" recién armada (SCRUM-197): se presenta al terminar el cuestionario.
private struct WeekIntroView: View {
    let week: WeekOverview?
    let rationale: PlanPersonalizationRecord?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let week {
                    WeekListView(week: week, rationale: rationale)
                }
                Button(action: onDone) {
                    Label("Ir a Hoy", systemImage: "arrow.right")
                }
                .buttonStyle(.energy)
                .padding(DSpace.m)
                .accessibilityIdentifier("weekIntro.done")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Tu semana")
        }
        .ironEnergyTheme()
        .accessibilityIdentifier("weekIntro")
    }
}

/// El perfil o el bloque guardados no se pueden leer: se ofrece rehacer el cuestionario.
/// No se borra el historial de entrenamientos. También es el estado de error de Plan.
struct PlanUnreadableView: View {
    let onRedo: () -> Void

    var body: some View {
        VStack(spacing: DSpace.l) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)
            Text("No pudimos leer tu plan")
                .font(.title2.bold())
            Text("Tus entrenamientos guardados siguen intactos. Contesta el cuestionario de nuevo para crear tu plan.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Button(action: onRedo) {
                Text("Rehacer cuestionario")
            }
            .buttonStyle(.energy)
            .accessibilityIdentifier("plan.unreadable.redo")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityIdentifier("plan.unreadable")
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment(authProvider: FakeAppleIDAuthProvider()))
        .ironEnergyTheme()
}