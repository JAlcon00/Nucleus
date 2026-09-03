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
                    onAnswer: { environment.onboarding.select($0) },
                    onAdvance: { environment.onboarding.advance() },
                    onGoBack: { environment.onboarding.goBack() },
                    onFinish: { environment.onboarding.complete() }
                )
            case .completed:
                appContent
            case .failed(let message):
                // Renderizamos un gate coherente y mostramos el error en un alert.
                Color.clear
                    .onAppear {
                        alertMessage = message
                        showAlert = true
                    }
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

    /// El contenido "de la app" tras completar el onboarding: hoy + restricciones.
    @ViewBuilder
    private var appContent: some View {
        NavigationStack {
            TodayView(
                state: TodayScreenDriver().derive(todayTemplate: nil, activeSession: nil),
                onStart: startWorkout,
                onResume: resumeWorkout
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        RestrictionManagementView(
                            restrictions: [],
                            onCreate: {},
                            onReview: { _ in },
                            onResolve: { _ in }
                        )
                    } label: {
                        Label("Restricciones", systemImage: "list.bullet.clipboard")
                    }
                }
            }
        }
    }

    private func startWorkout() {
        // Intento de empezar sesión: la capa de aplicación lo gestiona (PR-0602).
    }

    private func resumeWorkout() {
        // Intento de continuar sesión en curso.
    }
}

#Preview {
    AppRootView()
        .environment(AppEnvironment(authProvider: FakeAppleIDAuthProvider()))
}