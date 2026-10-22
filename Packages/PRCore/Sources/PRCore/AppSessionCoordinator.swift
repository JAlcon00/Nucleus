//
//  AppSessionCoordinator.swift
//  PRCore
//
//  SCRUM-26: orquesta el arranque de la app: recordar quién es el usuario, comprobar que
//  Apple no revocó la credencial, recuperar su plan y decidir a qué pantalla se entra
//  (Hoy, cuestionario, login o "perfil ilegible"). Sin reglas de negocio en las Views ni
//  en el composition root; testeable con fakes y un directorio temporal.
//
//  Reglas:
//  - De la sesión sólo se guarda el ID opaco del usuario (nunca tokens ni correo).
//  - Credencial revocada ⇒ vuelve al login y se olvida la sesión; planes, bloques y
//    entrenamientos NO se borran.
//  - Sin conexión (`.unavailable`) la sesión se conserva: se entra directo a Hoy.
//

import Foundation
import PRDomain

@MainActor
public final class AppSessionCoordinator {
    private let onboarding: OnboardingCoordinator
    private let todayPlan: TodayPlanCoordinator
    private let planStore: PlanStore?
    /// "Reintentar" pidió relanzar el inicio de sesión al terminar el intento cancelado.
    private var retryRequested = false

    private let clock: () -> Date
    private let timeZone: () -> TimeZone

    public init(
        onboarding: OnboardingCoordinator,
        todayPlan: TodayPlanCoordinator,
        planStore: PlanStore?,
        clock: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.onboarding = onboarding
        self.todayPlan = todayPlan
        self.planStore = planStore
        self.clock = clock
        self.timeZone = timeZone
    }

    /// "Sobre ti" editado desde Perfil o completado tras el aviso (SCRUM-198). Actualiza el
    /// perfil de la sesión; la activación lo guarda sin tocar el bloque. Devuelve `false` si
    /// la respuesta no es válida (p. ej. menos de 18 años): no se guarda nada.
    @discardableResult
    public func updateAboutYou(_ answer: AboutYouAnswer) async -> Bool {
        guard case .completed(var profile) = onboarding.phase,
              answer.isComplete,
              let aboutYou = try? answer.aboutYou(on: clock(), timeZone: timeZone()) else {
            return false
        }
        profile.aboutYou = aboutYou
        onboarding.showCompleted(profile)
        return await todayPlan.activate(profile: profile, userID: onboarding.auth.profile?.userIdentifier)
    }

    /// Arranque de la app. `autoSignIn` es el modo simulado de Debug.
    public func start(autoSignIn: Bool) async {
        guard onboarding.phase == .signedOut else { return }
        if let userID = planStore?.loadSession() {
            let state = await onboarding.auth.provider.credentialState(forUserIdentifier: userID)
            if state.requiresSignIn {
                forgetSession()
            } else {
                await resume(userID: userID)
                return
            }
        }
        if autoSignIn {
            await signIn()
        }
    }

    /// Inicio de sesión (botón de Apple o modo simulado): recuerda al usuario y busca su plan.
    public func signIn() async {
        await onboarding.signIn()
        // "Reintentar" canceló el intento colgado: se lanza uno nuevo cuando el anterior ya
        // terminó (nunca dos flujos de Apple a la vez).
        if retryRequested {
            retryRequested = false
            if onboarding.phase == .signedOut { await onboarding.signIn() }
        }
        guard case .signedIn(let user) = onboarding.auth.flowState else { return }
        try? planStore?.saveSession(userID: user.userIdentifier)
        await resume(userID: user.userIdentifier)
    }

    /// El inicio de sesión tarda demasiado (SCRUM-193): cancela el intento en curso y, en
    /// cuanto termina, `signIn()` lo vuelve a lanzar.
    public func retrySignIn() async {
        guard onboarding.phase == .signingIn else { return }
        retryRequested = true
        await onboarding.auth.provider.cancelAuthentication()
    }

    /// El usuario terminó el cuestionario (primera vez o "Rehacer"): activa y guarda el plan.
    @discardableResult
    public func planCompleted(profile: OnboardingProfile) async -> Bool {
        await todayPlan.activate(profile: profile, userID: onboarding.auth.profile?.userIdentifier)
    }

    /// "Rehacer cuestionario": mismo flujo que un cambio de plan.
    public func redoQuestionnaire() {
        var current: OnboardingProfile?
        if case .completed(let profile) = onboarding.phase { current = profile }
        onboarding.redo(from: current)
    }

    /// Comprobación en caliente (p. ej. al volver a primer plano): si Apple revocó la
    /// credencial, vuelve al login sin borrar datos.
    public func verifyCredential() async {
        guard let userID = onboarding.auth.profile?.userIdentifier else { return }
        let state = await onboarding.auth.provider.credentialState(forUserIdentifier: userID)
        guard state.requiresSignIn else { return }
        forgetSession()
        todayPlan.reset()
        onboarding.returnToSignIn()
    }

    // MARK: - Privado

    private func resume(userID: String) async {
        onboarding.resumeSession(userIdentifier: userID)
        switch await todayPlan.restore(userID: userID) {
        case .none: onboarding.beginOnboarding()
        case .restored(let profile): onboarding.showCompleted(profile)
        case .unreadable: onboarding.showPlanUnreadable()
        }
    }

    private func forgetSession() {
        try? planStore?.clearSession()
    }
}
