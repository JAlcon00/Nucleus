//
//  AIConsentView.swift
//  PR
//
//  Created by PR.
//
//  SCRUM-202 (IA-1): tras el formulario, antes de armar el plan, la persona decide si la
//  IA puede usar sus datos para personalizarlo. Dice qué datos, para qué y que se puede
//  retirar en Perfil. "Ahora no" no bloquea nada: el motor arma el plan igual.
//  Vista pura: la decisión la guarda `AIConsentCoordinator`.
//

import SwiftUI

struct AIConsentView: View {
    /// La última decisión no se pudo guardar.
    var saveFailed = false
    let onAccept: () -> Void
    let onDecline: () -> Void

    /// Qué datos usa la IA, con su icono (los mismos del formulario).
    private static let items: [(icon: String, text: LocalizedStringKey)] = [
        ("birthday.cake", "Edad y sexo"),
        ("ruler", "Estatura y peso"),
        ("target", "Objetivo, fase y experiencia"),
        ("cross.case", "Lesiones y restricciones"),
        ("calendar", "Días, minutos y variedad"),
        ("bed.double", "Tu check-in diario de sueño"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingCenteredScroll {
                VStack(spacing: DSpace.l) {
                    OnboardingHeader(
                        icon: "sparkles",
                        eyebrow: "Último paso",
                        title: "Personaliza tu plan con IA",
                        subtitle: "Con tus datos, la IA adapta tu rutina a tu estilo de vida y te explica cada decisión.",
                        titleIdentifier: "aiConsent.title"
                    )
                    VStack(alignment: .leading, spacing: DSpace.m) {
                        ForEach(Self.items, id: \.icon) { item in
                            Label {
                                Text(item.text).foregroundStyle(Color.textPrimary)
                            } icon: {
                                Image(systemName: item.icon).foregroundStyle(Color.primaryAction)
                            }
                            .font(.body)
                        }
                    }
                    .padding(DSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(cornerRadius: DRadius.medium)
                    VStack(alignment: .leading, spacing: DSpace.s) {
                        OnboardingNote(text: "La rutina la calcula siempre el motor de Nucleus; la IA propone y explica.")
                        OnboardingNote(text: "Nunca usamos tu nombre. No va a registros ni a publicidad.")
                        OnboardingNote(text: "Puedes retirarlo cuando quieras en Perfil.")
                    }
                }
            }
            VStack(spacing: DSpace.s) {
                if saveFailed {
                    OnboardingNote(text: "No se pudo guardar tu decisión. Intenta de nuevo.", tone: .warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                OnboardingPrimaryButton(title: "Sí, personalizar con IA", icon: "sparkles", state: .ready, action: onAccept)
                    .accessibilityIdentifier("aiConsent.accept")
                Button("Ahora no", action: onDecline)
                    .buttonStyle(.surface)
                    .accessibilityHint("Tu plan se arma igual, sin compartir datos.")
                    .accessibilityIdentifier("aiConsent.decline")
            }
            .padding(.horizontal, DSpace.l)
            .padding(.vertical, DSpace.m)
        }
        .screenBackground()
    }
}

#Preview("Consentimiento") {
    AIConsentView(onAccept: {}, onDecline: {})
        .ironEnergyTheme()
}

#Preview("No se pudo guardar · accessibility3") {
    AIConsentView(saveFailed: true, onAccept: {}, onDecline: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}
