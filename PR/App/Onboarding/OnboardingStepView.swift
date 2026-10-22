//
//  OnboardingStepView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla de cada paso del onboarding (EPIC-04, PR-0402 wiring). Renderiza el paso
//  `OnboardingStep` con controles tipados y reenvía las respuestas al coordinador de
//  dominio (PRDomain `OnboardingFlowController`). NO contiene reglas de negocio: sólo
//  convierte la selección de la UI en un `OnboardingAnswer` tipado.
//

import SwiftUI
import PRCore
import PRDomain

struct OnboardingStepView: View {
    /// Paso actual que se está respondiendo.
    let step: OnboardingStep
    /// Progreso (1-indexado) para la cabecera.
    let indexPlusOne: Int
    /// Total de pasos.
    let stepCount: Int
    /// ¿Permite el botón "Siguiente" (paso obligatorio respondido u opcional)?
    let canAdvance: Bool
    /// ¿Hay un paso previo al que volver?
    let canGoBack: Bool
    /// ¿Es el último paso?
    let isAtEnd: Bool

    /// Opciones ya localizadas de los pasos de elección (vacío en el resto).
    let choices: [OnboardingChoice]
    /// Respuesta guardada del paso actual (marca la opción elegida y fija los selectores).
    let selected: OnboardingAnswer?

    /// Callbacks (intents). `onAnswer` entrega la respuesta tipada del paso.
    let onAnswer: (OnboardingAnswer) -> Void
    let onAdvance: () -> Void
    let onGoBack: () -> Void
    let onFinish: () -> Void

    /// Valores de los selectores: salen de la respuesta guardada (o del valor por defecto
    /// que el coordinador registra al llegar al paso); nunca de estado local desfasado.
    private var selectedDays: Set<WeekDay> {
        if case .trainingDays(let value)? = selected { return value }
        return OnboardingDefaults.trainingDays
    }

    /// Iniciales y nombres de los días (SCRUM-196).
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)
    @ScaledMetric(relativeTo: .headline) private var dayChipSize = DSize.dayChip

    private var minutes: Binding<Int> {
        Binding(
            get: {
                if case .sessionMinutes(let value)? = selected { return value }
                return OnboardingDefaults.sessionMinutes
            },
            set: { onAnswer(.sessionMinutes($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            footer
        }
        .screenBackground()
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paso \(indexPlusOne) de \(stepCount)")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text(title(for: step))
                .font(.title2.bold())
                .accessibilityIdentifier("onboarding.title")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .goal, .phase, .experience, .variety:
            choicesPicker
        case .daysPerWeek:
            daysPicker
        case .sessionMinutes:
            minutesStepper
        case .gym:
            gymRow
        case .restrictions:
            restrictionsRow
        }
    }

    /// "¿Qué días puedes entrenar?" (SCRUM-196): 7 chips; el número sale de los elegidos.
    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            Text("Dejamos descanso entre sesiones para que recuperes. Elige al menos 2 días.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSpace.xs) {
                    ForEach(WeekDay.allCases, id: \.self) { dayChip($0) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dayChipSize), spacing: DSpace.s)], spacing: DSpace.s) {
                    ForEach(WeekDay.allCases, id: \.self) { dayChip($0) }
                }
            }
            daysSummary
        }
    }

    private func dayChip(_ day: WeekDay) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            var days = selectedDays
            if isSelected { days.remove(day) } else { days.insert(day) }
            onAnswer(.trainingDays(days))
        } label: {
            Text(vocabulary.weekdayInitial(day))
                .font(.headline)
                .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: dayChipSize)
                .frame(minWidth: dayChipSize)
                .background {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(LinearGradient.energy) : AnyShapeStyle(Color.surface))
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Color.hairline, lineWidth: 1)
                }
                // El estado no lo lleva sólo el color: el día elegido lleva una palomita.
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.onAccent, Color.textPrimary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vocabulary.weekdayName(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.day.\(day.rawValue)")
    }

    @ViewBuilder
    private var daysSummary: some View {
        let count = selectedDays.count
        if TrainingWeek.allowedTrainingDays.contains(count) {
            Text("\(count) días por semana")
                .font(.headline)
                .numericStyle()
                .accessibilityIdentifier("onboarding.daysSummary")
        } else {
            Label("Elige al menos 2 días", systemImage: "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(Color.warning)
                .accessibilityIdentifier("onboarding.daysSummary")
        }
    }

    private var minutesStepper: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: minutes, in: TrainingWeek.allowedSessionMinutes, step: 5) {
                Text("\(minutes.wrappedValue) min")
            }
            .accessibilityLabel("Duración habitual de cada sesión en minutos")
            .accessibilityIdentifier("onboarding.minutesStepper")
        }
    }

    private var gymRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Por ahora armamos tu plan con equipo básico de gimnasio: barra, mancuernas, máquinas y poleas. Podrás elegir tu gimnasio más adelante.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            Button("Omitir este paso") {
                onAnswer(.gym(nil))
            }
            .buttonStyle(.surface)
            .accessibilityIdentifier("onboarding.skipGym")
        }
    }

    private var restrictionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Si tienes una molestia o algo que prefieras evitar, podrás registrarlo cuando quieras en Perfil › Restricciones.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            Button("Continuar sin añadir") {
                onAnswer(.restrictions([]))
            }
            .buttonStyle(.surface)
            .accessibilityIdentifier("onboarding.skipRestrictions")
        }
    }

    // MARK: - Choice picker

    /// Opciones del paso: la vista sólo pinta el texto que ya viene localizado y reenvía
    /// la respuesta tipada de la opción; la elegida se marca con icono + borde + trait
    /// (no sólo con color).
    private var choicesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(choices) { choice in
                let isSelected = selected == choice.answer
                Button {
                    onAnswer(choice.answer)
                } label: {
                    HStack {
                        Text(choice.label)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.primaryAction)
                        }
                    }
                    .padding(12)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DRadius.small)
                            .fill(Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DRadius.small)
                            .strokeBorder(isSelected ? Color.primaryAction : Color.hairline, lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("onboarding.option.\(choice.id)")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button(action: onGoBack) {
                    Label("Atrás", systemImage: "chevron.left")
                }
                .buttonStyle(SurfaceButtonStyle(minHeight: DButton.primaryHeight))
                .accessibilityHint("Vuelve al paso anterior sin perder tus respuestas.")
            }

            Button(action: { isAtEnd ? onFinish() : onAdvance() }) {
                Label(isAtEnd ? "Terminar" : "Siguiente", systemImage: isAtEnd ? "checkmark" : "chevron.right")
            }
            .buttonStyle(.energy)
            .disabled(!canAdvance)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: - Titles

    private func title(for step: OnboardingStep) -> String {
        switch step {
        case .goal: return "Objetivo"
        case .phase: return "Fase"
        case .experience: return "Experiencia"
        case .daysPerWeek: return "¿Qué días puedes entrenar?"
        case .sessionMinutes: return "Minutos por sesión"
        case .gym: return "Gimnasio"
        case .variety: return "Variedad"
        case .restrictions: return "Restricciones"
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingStepView(
            step: .goal,
            indexPlusOne: 1,
            stepCount: 8,
            canAdvance: false,
            canGoBack: false,
            isAtEnd: false,
            choices: OnboardingChoicePresenter().choices(for: .goal),
            selected: .goal(.hypertrophy),
            onAnswer: { _ in },
            onAdvance: {},
            onGoBack: {},
            onFinish: {}
        )
    }
    .ironEnergyTheme()
}

#Preview("Días · accessibility3") {
    NavigationStack {
        OnboardingStepView(
            step: .daysPerWeek,
            indexPlusOne: 4,
            stepCount: 8,
            canAdvance: true,
            canGoBack: true,
            isAtEnd: false,
            choices: [],
            selected: .trainingDays([.monday, .wednesday, .friday]),
            onAnswer: { _ in },
            onAdvance: {},
            onGoBack: {},
            onFinish: {}
        )
    }
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}

#Preview("Objetivo · accessibility3") {
    NavigationStack {
        OnboardingStepView(
            step: .goal,
            indexPlusOne: 1,
            stepCount: 8,
            canAdvance: true,
            canGoBack: false,
            isAtEnd: false,
            choices: OnboardingChoicePresenter().choices(for: .goal),
            selected: .goal(.hypertrophy),
            onAnswer: { _ in },
            onAdvance: {},
            onGoBack: {},
            onFinish: {}
        )
    }
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}