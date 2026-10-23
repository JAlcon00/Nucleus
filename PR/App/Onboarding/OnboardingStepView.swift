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
    /// A quién le habla el formulario (SCRUM-210): decide títulos y subtítulos.
    var audience: OnboardingAudience = .standard

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

    /// Al tocar "Terminar" el pie muestra el loader hasta que el cuestionario se cierra.
    @State private var isFinishing = false
    /// Nota de restricciones en edición: "Listo" cierra el teclado para ver "Terminar".
    @FocusState private var editingNote: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var footerState: OnboardingFooterState {
        if isFinishing { return .finishing }
        return canAdvance ? .ready : .needsAnswer
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(current: indexPlusOne, total: stepCount)
                .padding(.horizontal, DSpace.l)
                .padding(.top, DSpace.xl)
            OnboardingCenteredScroll {
                VStack(spacing: DSpace.l) {
                    OnboardingHeader(
                        icon: Self.icon(for: step),
                        eyebrow: "Paso \(indexPlusOne) de \(stepCount)",
                        title: title(for: step),
                        subtitle: subtitle(for: step),
                        titleIdentifier: "onboarding.title"
                    )
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Cada paso entra como una diapositiva nueva (sólo fundido con Reduce Motion).
                .id(step)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity)
                )
            }
            footer
        }
        .animation(DMotion.slide(reduceMotion: reduceMotion), value: step)
        .screenBackground()
        .navigationBarBackButtonHidden(true)
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
        case .priorityMuscles:
            priorityMusclesRow
        case .restrictions:
            restrictionsRow
        }
    }

    /// "¿Qué días puedes entrenar?" (SCRUM-196): 7 chips; el número sale de los elegidos.
    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
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
                            // Palomita en el color del fondo sobre el círculo del texto:
                            // contraste invertido en claro y en oscuro (17.75:1).
                            .foregroundStyle(Color.appBackground, Color.textPrimary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(vocabulary.weekdayName(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.day.\(day.rawValue)")
    }

    @ViewBuilder
    private var daysSummary: some View {
        let count = selectedDays.count
        if TrainingWeek.allowedTrainingDays.contains(count) {
            Label {
                Text("\(count) días por semana").numericStyle()
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
            }
            .font(.headline)
            .accessibilityIdentifier("onboarding.daysSummary")
        } else {
            OnboardingNote(text: "Elige al menos 2 días", tone: .warning)
                .font(.headline)
                .accessibilityIdentifier("onboarding.daysSummary")
        }
    }

    private var minutesStepper: some View {
        OnboardingField(title: "Duración de cada sesión", icon: "timer", purpose: "Ajustamos cuántos ejercicios caben. Más tiempo no suma series.") {
            Stepper(value: minutes, in: TrainingWeek.allowedSessionMinutes, step: 5) {
                Text("\(minutes.wrappedValue) min")
                    .font(.title3.bold())
                    .numericStyle()
                    .contentTransition(.numericText(value: Double(minutes.wrappedValue)))
            }
            .onboardingInput()
            .sensoryFeedback(.selection, trigger: minutes.wrappedValue)
            .accessibilityLabel("Duración habitual de cada sesión en minutos")
            .accessibilityIdentifier("onboarding.minutesStepper")
        }
    }

    /// Músculos prioritarios elegidos (avanzado, SCRUM-210).
    private var priorityMuscles: Set<MuscleGroup> {
        if case .priorityMuscles(let value)? = selected { return value }
        return []
    }

    /// SCRUM-210: hasta 2 músculos con más volumen. Al llegar al máximo, los demás se
    /// desactivan (el límite lo valida el dominio).
    private var priorityMusclesRow: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            FlowLayout(spacing: DSpace.s, lineSpacing: DSpace.s) {
                ForEach(OnboardingFlowPolicy.priorityMuscleOptions, id: \.self) { muscle in
                    priorityChip(muscle)
                }
            }
            Text("\(priorityMuscles.count) de \(OnboardingFlowPolicy.maxPriorityMuscles) elegidos")
                .font(.footnote)
                .numericStyle()
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func priorityChip(_ muscle: MuscleGroup) -> some View {
        let isSelected = priorityMuscles.contains(muscle)
        let isFull = priorityMuscles.count >= OnboardingFlowPolicy.maxPriorityMuscles
        return selectableChip(
            title: vocabulary.muscleName(muscle),
            isSelected: isSelected,
            identifier: "onboarding.priority.\(muscle.rawValue)"
        ) {
            var chosen = priorityMuscles
            if isSelected { chosen.remove(muscle) } else { chosen.insert(muscle) }
            onAnswer(.priorityMuscles(chosen))
        }
        .disabled(isFull && !isSelected)
    }

    /// Respuesta de restricciones actual (zonas, nota y las anteriores al rehacer).
    private var restrictions: RestrictionsAnswer {
        if case .restrictions(let value)? = selected { return value }
        return .none
    }

    /// SCRUM-209: zonas con molestia o lesión (opcional) y una nota libre (opcional).
    /// Qué movimientos se evitan lo decide la regla versionada del dominio, no esta vista.
    private var restrictionsRow: some View {
        VStack(alignment: .leading, spacing: DSpace.l) {
            VStack(alignment: .leading, spacing: DSpace.s) {
                Text("¿Tienes alguna molestia o lesión?")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                FlowLayout(spacing: DSpace.s, lineSpacing: DSpace.s) {
                    ForEach(BodyRegionRestrictionRule.selectableRegions, id: \.self) { region in
                        zoneChip(region)
                    }
                }
            }
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text("Cuéntanos más (opcional)")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                TextField(
                    "Ej. me molesta el hombro al subir el brazo",
                    text: Binding(
                        get: { restrictions.note },
                        set: { note in
                            var answer = restrictions
                            answer.note = note
                            onAnswer(.restrictions(answer))
                        }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($editingNote)
                .padding(.vertical, DSpace.s)
                .onboardingInput(isFocused: editingNote)
                .accessibilityIdentifier("onboarding.restrictionNote")
                if editingNote {
                    // El teclado tapa el pie ("Terminar"): se cierra aquí, a la vista.
                    Button {
                        editingNote = false
                    } label: {
                        Label("Listo", systemImage: "keyboard.chevron.compact.down")
                    }
                    .buttonStyle(.surface)
                    .accessibilityIdentifier("onboarding.restrictionNote.done")
                }
                HStack {
                    if !restrictions.isValid {
                        Label("Máximo \(RestrictionsAnswer.maxNoteLength) caracteres.", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.warning)
                    }
                    Spacer()
                    Text("\(restrictions.trimmedNote?.count ?? 0)/\(RestrictionsAnswer.maxNoteLength)")
                        .numericStyle()
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.footnote)
            }
            infoCard(
                icon: "cross.case",
                text: "Evitamos los movimientos de más riesgo para esa zona. No es un diagnóstico: si tienes dolor fuerte, consulta a un profesional. Puedes cambiarlo en Perfil."
            )
        }
    }

    /// Chip de una zona: la elegida lleva palomita además del relleno (no sólo color).
    private func zoneChip(_ region: BodyRegion) -> some View {
        let isSelected = restrictions.zones.contains(region)
        return selectableChip(
            title: vocabulary.bodyRegionName(region),
            isSelected: isSelected,
            identifier: "onboarding.zone.\(region.rawValue)"
        ) {
            var answer = restrictions
            if isSelected { answer.zones.remove(region) } else { answer.zones.insert(region) }
            onAnswer(.restrictions(answer))
        }
    }

    /// Chip seleccionable (zonas, músculos): el elegido lleva palomita además del relleno.
    private func selectableChip(
        title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark" : "plus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)
                .padding(.horizontal, DSpace.m)
                .frame(minHeight: DSize.dayChip)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentFill) : AnyShapeStyle(Color.surface),
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(isSelected ? Color.clear : Color.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func infoCard(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DSpace.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.primaryAction)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
    }

    // MARK: - Choice picker

    /// Opciones del paso: la vista sólo pinta el texto que ya viene localizado y reenvía
    /// la respuesta tipada de la opción; la elegida se marca con icono + borde + trait
    /// (no sólo con color).
    private var choicesPicker: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            ForEach(choices) { choice in
                let symbol = Self.icon(for: choice.answer)
                OnboardingChoiceRow(
                    title: Text(choice.label),
                    icon: symbol.name,
                    level: symbol.level,
                    isSelected: selected == choice.answer
                ) {
                    onAnswer(choice.answer)
                }
                .accessibilityIdentifier("onboarding.option.\(choice.id)")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DSpace.s) {
            if footerState == .needsAnswer, let hint = hint(for: step) {
                OnboardingNote(text: LocalizedStringKey(hint))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            HStack(spacing: DSpace.s) {
                if canGoBack {
                    Button(action: onGoBack) {
                        Label("Atrás", systemImage: "chevron.left")
                    }
                    .buttonStyle(SurfaceButtonStyle(minHeight: DButton.primaryHeight))
                    .disabled(isFinishing)
                    .accessibilityHint("Vuelve al paso anterior sin perder tus respuestas.")
                    .accessibilityIdentifier("onboarding.back")
                }
                OnboardingPrimaryButton(
                    title: isAtEnd ? "Terminar" : "Siguiente",
                    icon: isAtEnd ? "checkmark" : "chevron.right",
                    state: footerState
                ) {
                    if isAtEnd {
                        isFinishing = true
                        onFinish()
                    } else {
                        onAdvance()
                    }
                }
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding(.horizontal, DSpace.l)
        .padding(.bottom, DSpace.m)
        .padding(.top, DSpace.s)
        .animation(.easeOut(duration: 0.15), value: footerState)
        // Si cerrar el cuestionario falla, el paso vuelve a estar disponible.
        .onChange(of: step) { _, _ in isFinishing = false }
    }

    // MARK: - Textos e iconos (presentación)

    /// Textos del paso según la experiencia (SCRUM-210): los decide PRCore.
    private var copy: OnboardingCopy {
        OnboardingCopy(locale: AppEnvironment.presentationLocale, audience: audience)
    }

    private func title(for step: OnboardingStep) -> String { copy.title(for: step) }

    private func subtitle(for step: OnboardingStep) -> String { copy.subtitle(for: step) }

    /// Pista del pie cuando aún no se puede avanzar (los días ya explican su mínimo).
    private func hint(for step: OnboardingStep) -> String? { copy.hint(for: step) }

    static func icon(for step: OnboardingStep) -> String {
        switch step {
        case .goal: return "target"
        case .phase: return "fork.knife"
        case .experience: return "medal"
        case .daysPerWeek: return "calendar"
        case .sessionMinutes: return "timer"
        case .variety: return "shuffle"
        case .priorityMuscles: return "flame"
        case .restrictions: return "cross.case"
        }
    }

    /// Icono de cada opción (acompaña al texto; VoiceOver lee sólo el texto). La
    /// experiencia usa barras que se llenan con el nivel.
    static func icon(for answer: OnboardingAnswer) -> (name: String?, level: Double?) {
        switch answer {
        case .goal(let goal):
            switch goal {
            case .generalHealth: return ("heart", nil)
            case .hypertrophy: return ("figure.strengthtraining.traditional", nil)
            case .strength: return ("dumbbell", nil)
            case .powerbuilding: return ("bolt", nil)
            case .recomposition: return ("arrow.triangle.2.circlepath", nil)
            case .bodybuilding: return ("trophy", nil)
            }
        case .phase(let phase):
            switch phase {
            case .surplus: return ("arrow.up.right", nil)
            case .deficit: return ("arrow.down.right", nil)
            case .maintenance: return ("equal", nil)
            case .unspecified: return ("eye.slash", nil)
            }
        case .experience(let level):
            switch level {
            case .novice: return ("cellularbars", 0.2)
            case .beginner: return ("cellularbars", 0.4)
            case .intermediate: return ("cellularbars", 0.6)
            case .advanced: return ("cellularbars", 0.8)
            case .competitive: return ("cellularbars", 1)
            }
        case .variety(let variety):
            switch variety {
            case .stable: return ("pin", nil)
            case .balanced: return ("scalemass", nil)
            case .varied: return ("shuffle", nil)
            }
        case .trainingDays, .sessionMinutes, .priorityMuscles, .restrictions:
            return (nil, nil)
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingStepView(
            step: .goal,
            indexPlusOne: 1,
            stepCount: 7,
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

#Preview("Restricciones · claro") {
    NavigationStack {
        OnboardingStepView(
            step: .restrictions,
            indexPlusOne: 7,
            stepCount: 7,
            canAdvance: true,
            canGoBack: true,
            isAtEnd: true,
            choices: [],
            selected: .restrictions(RestrictionsAnswer(zones: [.shoulder, .knee], note: "Me molesta al subir el brazo")),
            onAnswer: { _ in },
            onAdvance: {},
            onGoBack: {},
            onFinish: {}
        )
    }
    .ironEnergyTheme()
    .preferredColorScheme(.light)
}

#Preview("Días · accessibility3") {
    NavigationStack {
        OnboardingStepView(
            step: .daysPerWeek,
            indexPlusOne: 4,
            stepCount: 7,
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
            stepCount: 7,
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