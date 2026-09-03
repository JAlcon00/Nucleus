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

    /// Callbacks (intents). `onAnswer` entrega la respuesta tipada del paso.
    let onAnswer: (OnboardingAnswer) -> Void
    let onAdvance: () -> Void
    let onGoBack: () -> Void
    let onFinish: () -> Void

    /// Valor local seleccionado para los pickers de este paso.
    @State private var selectedDays = 4
    @State private var selectedMinutes = 60

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
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paso \(indexPlusOne) de \(stepCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title(for: step))
                .font(.title2.bold())
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .goal:
            choicesPicker(TrainingGoal.self)
        case .phase:
            choicesPicker(BodyCompositionPhase.self)
        case .experience:
            choicesPicker(ExperienceLevel.self)
        case .variety:
            choicesPicker(VarietyPreference.self)
        case .daysPerWeek:
            daysStepper
        case .sessionMinutes:
            minutesStepper
        case .gym:
            gymRow
        case .restrictions:
            restrictionsRow
        }
    }

    private var daysStepper: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Días por semana")
                .font(.headline)
            Stepper(value: $selectedDays, in: 2...7) {
                Text("\(selectedDays) días")
            }
            .accessibilityLabel("Días de entrenamiento por semana")
            .onChange(of: selectedDays) { _, newValue in
                onAnswer(.daysPerWeek(newValue))
            }
        }
    }

    private var minutesStepper: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minutos por sesión")
                .font(.headline)
            Stepper(value: $selectedMinutes, in: 20...240, step: 5) {
                Text("\(selectedMinutes) min")
            }
            .accessibilityLabel("Duración habitual de cada sesión en minutos")
            .onChange(of: selectedMinutes) { _, newValue in
                onAnswer(.sessionMinutes(newValue))
            }
        }
    }

    private var gymRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gimnasio")
                .font(.headline)
            Text("Puedes omitirlo ahora y elegir tu gimnasio más adelante.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Omitir este paso") {
                onAnswer(.gym(nil))
            }
            .buttonStyle(.bordered)
        }
    }

    private var restrictionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restricciones")
                .font(.headline)
            Text("Sin restricciones por defecto; las gestionas en la app cuando quieras.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Continuar sin añadir") {
                onAnswer(.restrictions([]))
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Generic picker

    private func choicesPicker<Choice: RawRepresentable & CaseIterable & Hashable>(
        _ choices: Choice.Type
    ) -> some View
        where Choice.AllCases: RandomAccessCollection
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(for: step))
                .font(.headline)
            ForEach(choices.allCases, id: \.self) { choice in
                Button {
                    onAnswer(makeAnswer(for: choice))
                } label: {
                    HStack {
                        Text(rawName(of: choice))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rawName(of: choice))
            }
        }
    }

    private func makeAnswer(for choice: some RawRepresentable) -> OnboardingAnswer {
        let raw = "\(choice.rawValue)"
        switch step {
        case .goal:
            return .goal(TrainingGoal(rawValue: raw) ?? .generalHealth)
        case .phase:
            return .phase(BodyCompositionPhase(rawValue: raw) ?? .maintenance)
        case .experience:
            return .experience(ExperienceLevel(rawValue: raw) ?? .intermediate)
        case .variety:
            return .variety(VarietyPreference(rawValue: raw) ?? .balanced)
        default:
            return .goal(.generalHealth) // pasos no picker no llegan aquí
        }
    }

    private func rawName(of choice: some RawRepresentable) -> String {
        "\(choice.rawValue)".capitalized
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Button(action: onGoBack) {
                    Label("Atrás", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Vuelve al paso anterior sin perder tus respuestas.")
            }

            Button(action: { isAtEnd ? onFinish() : onAdvance() }) {
                Label(isAtEnd ? "Terminar" : "Siguiente", systemImage: isAtEnd ? "checkmark" : "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdvance)
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
        case .daysPerWeek: return "Días por semana"
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
            onAnswer: { _ in },
            onAdvance: {},
            onGoBack: {},
            onFinish: {}
        )
    }
}