//
//  TodayView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla "Hoy" (plan §8, RF-005, PR-0601). Presenta el estado derivado por
//  `TodayScreenDriver` (PRDomain) y reenvía intents (empezar/continuar). NO contiene
//  reglas de negocio: sólo renderiza `TodayScreen` (SCRUM-193: cargando, listo o
//  fallido; nunca descanso mientras carga) y, ya listo, los estados de descanso / sin
//  workout / en curso. SCRUM-197: arriba, la tira de la semana (tocar un día abre su
//  detalle) y cada ejercicio con "3 × 8–12" y "última vez". Funciona offline.
//

import SwiftUI
import PRCore
import PRDomain

struct TodayView: View {
    /// Estado de la pantalla (se inyecta desde el composition root).
    let screen: TodayScreen
    /// Explicación del orden de hoy (SCRUM-29).
    var order: [TodayOrderLine] = []
    var orderReorderedByFatigue = false
    /// Ejercicios de la sesión de hoy (ya con nombre del catálogo), en orden.
    var exercises: [TodayExerciseLine] = []
    /// Aviso breve cuando la app actualizó el plan guardado (SCRUM-26).
    var notice: TodayPlanNotice?
    var onDismissNotice: () -> Void = {}
    /// Intento: empezar la sesión planeada.
    let onStart: () -> Void
    /// Intento: continuar la sesión en curso.
    let onResume: () -> Void
    /// El entrenamiento se está abriendo (lee historial): el botón queda "en curso".
    var isStartingWorkout = false
    /// Intento: volver a generar el plan tras un fallo.
    var onRetry: () -> Void = {}
    /// "Tu semana" (SCRUM-197): tira de 7 días arriba; `nil` sin plan.
    var week: WeekOverview?
    /// "Última vez" por ejercicio (M1).
    var lastPerformance: [ExerciseID: LastPerformance] = [:]
    /// Nombre para el saludo ("Hola, Ana"), si la persona lo dio (SCRUM-198).
    var greetingName: String?
    /// Perfil anterior sin "Sobre ti": aviso único para completarlo (no bloquea Hoy).
    var asksToCompleteProfile = false
    var onCompleteProfile: () -> Void = {}
    var onDismissProfilePrompt: () -> Void = {}
    /// SCRUM-203: preguntar "¿Cómo dormiste?" (sólo en día de entrenamiento, una vez al día).
    var asksSleepCheckIn = false
    var onSleepCheckIn: (Double, SleepQuality) -> Void = { _, _ in }
    var onSkipSleepCheckIn: () -> Void = {}
    /// Aviso del ajuste del día que decidió el motor (ya traducido); `nil` sin ajuste.
    var readinessNote: String?
    /// SCRUM-211: sesión de hoy (para ordenarla) y si su orden lo eligió la persona.
    var todayTemplateID: SessionTemplate.ID?
    var orderIsCustom = false
    /// SCRUM-30: minutos elegidos para hoy (`nil` = sesión completa), la frase del ajuste
    /// (ya traducida), si la sesión resultante cabe y si el ajuste quitó ejercicios.
    var timeBudget: Int?
    var timeNote: String?
    var timeFits = true
    var timeRemovedExercises = false
    /// Intento: ajustar la sesión a esos minutos (`nil` = quitar el ajuste).
    var onChooseTime: (Int?) -> Void = { _ in }
    @Environment(\.sessionOrderActions) private var orderActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reordering = false

    @State private var showingOrder = false
    /// Día de la tira abierto en detalle.
    @State private var selectedDay: WeekDay?
    /// Nombres de sesión en español (Push, Pull, Pierna…): el planificador guarda claves estables.
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)
    /// Cuenta toques de Empezar/Continuar: dispara el háptico de confirmación.
    @State private var startTaps = 0

    var body: some View {
        Group {
            switch screen {
            case .loading:
                loadingView
            case .failed:
                failedView
            case .ready(let state):
                VStack(spacing: 0) {
                    if let week {
                        // Con fondo y encima: lo que se desplaza en Hoy pasa por debajo (SCRUM-222).
                        WeekStripView(week: week, onSelect: { selectedDay = $0 })
                            .padding(.horizontal, DSpace.m)
                            .padding(.top, DSpace.s)
                            .padding(.bottom, DSpace.s)
                            .background(Color.appBackground)
                            .zIndex(1)
                    }
                    readyContent(state)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationDestination(item: $selectedDay) { day in
            if let entry = week?.days.first(where: { $0.day == day }) {
                DayDetailView(
                    entry: entry,
                    lastPerformance: lastPerformance,
                    isStartingWorkout: isStartingWorkout,
                    onStart: canStartToday(entry) ? onStart : nil
                )
            }
        }
        .accessibilityElement(children: .contain)
        .safeAreaInset(edge: .top) {
            if let notice {
                noticeBanner(notice)
            } else if asksToCompleteProfile, case .ready = screen {
                profilePrompt
            }
        }
    }

    @ViewBuilder
    private func readyContent(_ state: TodayScreenState) -> some View {
        switch state {
        case .restDay:
            restDayView
        case .readyToStart(let presentation):
            readyView(presentation)
        case .activeWorkout(let presentation, let isPaused):
            activeView(presentation, isPaused: isPaused)
        }
    }

    /// Desde el detalle sólo se empieza el día de hoy con su sesión lista (nunca con un
    /// entrenamiento en curso: para eso está "Continuar").
    private func canStartToday(_ entry: WeekDayEntry) -> Bool {
        guard entry.isToday, case .ready(.readyToStart) = screen else { return false }
        return true
    }

    private func noticeBanner(_ notice: TodayPlanNotice) -> some View {
        HStack(alignment: .top, spacing: DSpace.s) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityHidden(true)
            Text(Self.text(for: notice))
                .font(.callout)
            Spacer(minLength: 0)
            Button("Entendido", action: onDismissNotice)
                .font(.callout.bold())
                .frame(minHeight: 44)
                .accessibilityIdentifier("today.notice.dismiss")
        }
        .padding(DSpace.m)
        .cardSurface(cornerRadius: DRadius.medium)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.notice")
    }

    /// "Completa tu perfil" (SCRUM-198): una sola vez y sin bloquear Hoy.
    private var profilePrompt: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            Label("Completa tu perfil", systemImage: "person.crop.circle.badge.plus")
                .font(.headline)
            Text("Edad, sexo y peso ayudan a ajustar tus cargas iniciales. Se guardan solo en tu iPhone.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: DSpace.m) {
                Button("Completar", action: onCompleteProfile)
                    .font(.callout.bold())
                    .frame(minHeight: DSize.dayChip)
                    .accessibilityIdentifier("today.profilePrompt.complete")
                Button("Ahora no", action: onDismissProfilePrompt)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: DSize.dayChip)
                    .accessibilityIdentifier("today.profilePrompt.dismiss")
            }
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.profilePrompt")
    }

    private static func text(for notice: TodayPlanNotice) -> String {
        switch notice {
        case .planUpdated: String(localized: "Actualizamos tu plan: ahora trae mejores ejercicios y un volumen más realista.")
        }
    }

    // MARK: - Loading (SCRUM-193)

    /// Skeleton con la forma de la tarjeta de hoy: título, resumen y 4 filas.
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sesión de hoy")
                    .font(.title2.bold())
                Text("16 series · ~60 min")
                    .font(.callout)
            }
            ForEach(0..<4, id: \.self) { _ in
                HStack {
                    Text("Ejercicio de la sesión")
                    Spacer()
                    Text("3 × 8–12")
                }
                .padding(.vertical, DSpace.xs)
            }
            Spacer()
            RoundedRectangle(cornerRadius: DRadius.medium)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        }
        .padding(24)
        .redacted(reason: .placeholder)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cargando tu plan de hoy"))
        .accessibilityIdentifier("today.loading")
    }

    // MARK: - Failed (SCRUM-193)

    private var failedView: some View {
        VStack(spacing: DSpace.l) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)
            Text("No pudimos armar tu plan")
                .font(.title3.bold())
            Text("Tus entrenamientos guardados siguen intactos. Intenta de nuevo.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Label("Reintentar", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.energy)
            .accessibilityIdentifier("today.retry")
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.failed")
    }

    // MARK: - Rest day

    private var restDayView: some View {
        VStack(spacing: 12) {
            IconBadge(systemName: "bed.double.fill", scale: 2.5)
            Text("Día de descanso")
                .font(.title3.bold())
            Text("Hoy toca recuperar.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let next = nextSessionText {
                Label(next, systemImage: "calendar.badge.clock")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DSpace.m)
                    .padding(.vertical, DSpace.s)
                    .background(Color.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.restDay")
    }

    /// "Próxima sesión: Miércoles · Push" (la primera de la semana después de hoy).
    private var nextSessionText: String? {
        guard let week, let todayIndex = week.days.firstIndex(where: \.isToday) else { return nil }
        guard let next = week.days[(todayIndex + 1)...].first(where: { $0.session != nil }),
              let session = next.session else { return nil }
        let day = vocabulary.weekdayName(next.day)
        return String(localized: "Próxima sesión: \(day) · \(vocabulary.sessionName(session.title))")
    }

    // MARK: - Ready to start

    /// SCRUM-222: todo se desplaza junto (saludo, resumen, "¿Cómo dormiste?", nota de tiempo y
    /// ejercicios) y las acciones quedan fijas abajo. Antes la lista tenía su propio scroll con
    /// el alto que sobraba: en iPhone, con la tarjeta de sueño, apenas 24 pt.
    private func readyView(_ presentation: SessionPresentation) -> some View {
        ScrollView {
            readyDetails(presentation)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, DSpace.m)
                .animation(DMotion.slide(reduceMotion: reduceMotion), value: asksSleepCheckIn)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("today.content")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            readyActions(presentation)
        }
        .sheet(isPresented: $showingOrder) {
            OrderExplanationSheet(order: order, reorderedByFatigue: orderReorderedByFatigue, isCustom: orderIsCustom)
        }
        .sheet(isPresented: $reordering) {
            if let orderActions, let todayTemplateID {
                ReorderExercisesSheet(templateID: todayTemplateID, lines: exercises, actions: orderActions)
            }
        }
    }

    private func readyDetails(_ presentation: SessionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: DSpace.m) {
                IconBadge(systemName: "figure.strengthtraining.traditional", scale: 1.6, isHighlighted: true)
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    if let greetingName {
                        Label("Hola, \(greetingName)", systemImage: "hand.wave")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text(vocabulary.sessionName(presentation.title))
                        .font(.title2.bold())
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSpace.s) {
                    sessionSummary(presentation)
                    Spacer(minLength: DSpace.s)
                    timeMenu
                }
                VStack(alignment: .leading, spacing: DSpace.s) {
                    sessionSummary(presentation)
                    timeMenu
                }
            }
            if asksSleepCheckIn {
                SleepCheckInCard(onRecord: onSleepCheckIn, onSkip: onSkipSleepCheckIn)
            } else if let readinessNote {
                Label {
                    Text(readinessNote).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Color.warning)
                }
                .font(.callout)
                .padding(DSpace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(cornerRadius: DRadius.medium)
                .accessibilityIdentifier("today.readiness")
            }
            if let timeNote {
                timeNoteCard(timeNote)
            }
            exerciseList
        }
    }

    /// Acciones fijas abajo (SCRUM-222): siempre a la vista, aunque la sesión sea larga.
    private func readyActions(_ presentation: SessionPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            HStack {
                if !order.isEmpty {
                    Button {
                        showingOrder = true
                    } label: {
                        Label("¿Por qué este orden?", systemImage: "questionmark.circle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("today.whyOrder")
                }
                Spacer()
                // Sólo antes de empezar: dentro del entrenamiento se usa "dejar en espera".
                // Con ejercicios quitados por tiempo la lista no está completa: primero se
                // vuelve a la sesión completa (SCRUM-30).
                if let orderActions, let todayTemplateID, orderActions.canReorder(todayTemplateID), !timeRemovedExercises {
                    Button {
                        reordering = true
                    } label: {
                        Label("Ordenar", systemImage: "arrow.up.arrow.down")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("today.reorder")
                }
            }
            startButton(presentation)
        }
        .padding(.horizontal, 24)
        .padding(.top, DSpace.s)
        .padding(.bottom, DSpace.m)
        .background(Color.appBackground)
    }

    /// Ejercicios de la sesión, dentro del scroll de la pantalla (SCRUM-222).
    private var exerciseList: some View {
        LazyVStack(alignment: .leading, spacing: DSpace.s) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, line in
                ExerciseLineRow(line: line, last: lastPerformance[line.exerciseID], number: index + 1)
                    .padding(.vertical, DSpace.xs)
                    .accessibilityIdentifier("today.exercise.\(index)")
            }
        }
    }

    // MARK: - Active

    private func activeView(_ presentation: SessionPresentation, isPaused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(isPaused ? "En pausa" : "En curso", systemImage: isPaused ? "pause.circle.fill" : "figure.strengthtraining.traditional")
                .font(.headline)
                .foregroundStyle(isPaused ? Color.warning : Color.success)
            Text("Tienes un entrenamiento en curso")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier("today.activeBanner")
            HStack(spacing: DSpace.m) {
                IconBadge(systemName: isPaused ? "pause.fill" : "bolt.fill", scale: 1.6, isHighlighted: !isPaused)
                Text(vocabulary.sessionName(presentation.title))
                    .font(.title2.bold())
            }
            sessionSummary(presentation)
            Spacer()
            resumeButton
        }
        .padding(24)
    }

    // MARK: - SCRUM-30: ajustar a mi tiempo

    /// "Ajustar a mi tiempo": 30, 45, 60 o 90 min, o volver a la sesión completa. Control
    /// secundario (la acción principal sigue siendo Empezar).
    private var timeMenu: some View {
        Menu {
            ForEach(SessionTimeChoice.quickMinutes, id: \.self) { minutes in
                Button {
                    onChooseTime(minutes)
                } label: {
                    if timeBudget == minutes {
                        Label("Tengo \(minutes) min", systemImage: "checkmark")
                    } else {
                        Text("Tengo \(minutes) min")
                    }
                }
            }
            if timeBudget != nil {
                Divider()
                Button {
                    onChooseTime(nil)
                } label: {
                    Label("Sesión completa", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label {
                Text(timeBudget.map { String(localized: "Tengo \($0) min") } ?? String(localized: "Ajustar a mi tiempo"))
                    .numericStyle()
            } icon: {
                Image(systemName: "timer")
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, DSpace.m)
            .frame(minHeight: 44)
            .background(Color.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
        }
        .sensoryFeedback(.selection, trigger: timeBudget)
        .accessibilityHint("Ajusta la sesión de hoy a los minutos que tienes.")
        .accessibilityIdentifier("today.timeBudget")
    }

    /// Qué cambió por el tiempo elegido. Si no cabe ni recortada, el ícono y el color de
    /// advertencia acompañan al texto (el color nunca va solo).
    private func timeNoteCard(_ note: String) -> some View {
        Label {
            Text(note).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: timeFits ? "timer" : "exclamationmark.triangle.fill")
                .foregroundStyle(timeFits ? Color.primaryAction : Color.warning)
        }
        .font(.callout)
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.timeNote")
    }

    private func sessionSummary(_ presentation: SessionPresentation) -> some View {
        HStack(spacing: 12) {
            Label("\(presentation.workSetCount) series", systemImage: "list.number")
            if presentation.warmupSetCount > 0 {
                Label("\(presentation.warmupSetCount) cal.", systemImage: "flame")
            }
            if let minutes = presentation.estimatedMinutes {
                Label("~\(minutes) min", systemImage: "clock")
            }
        }
        .font(.callout)
        .numericStyle()
        .foregroundStyle(Color.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.sessionSummary")
    }

    private func startButton(_ presentation: SessionPresentation) -> some View {
        Button {
            startTaps += 1
            onStart()
        } label: {
            LoadingButtonLabel(isLoading: isStartingWorkout, loadingAccessibilityLabel: "Abriendo entrenamiento") {
                Label("Empezar \(vocabulary.sessionName(presentation.title))", systemImage: "play.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.energy)
        .disabled(isStartingWorkout)
        .sensoryFeedback(.impact(weight: .light), trigger: startTaps)
        .accessibilityHint("Inicia la sesión de hoy.")
        .accessibilityIdentifier("today.start")
    }

    private var resumeButton: some View {
        Button {
            startTaps += 1
            onResume()
        } label: {
            LoadingButtonLabel(isLoading: isStartingWorkout, loadingAccessibilityLabel: "Abriendo entrenamiento") {
                Label("Continuar", systemImage: "arrow.right.circle.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.energy)
        .disabled(isStartingWorkout)
        .sensoryFeedback(.impact(weight: .light), trigger: startTaps)
        .accessibilityHint("Reanuda la sesión en curso.")
        .accessibilityIdentifier("today.resume")
    }
}

/// "¿Cómo dormiste?" (SCRUM-203): horas y si dormiste bien o mal. Opcional ("Ahora no").
/// Sólo registra la respuesta; el ajuste lo decide el motor.
private struct SleepCheckInCard: View {
    let onRecord: (Double, SleepQuality) -> Void
    let onSkip: () -> Void

    /// Rango y paso del selector (las horas válidas las valida el dominio).
    private static let hoursRange: ClosedRange<Double> = 3...12
    @State private var hours: Double = 7

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            HStack(spacing: DSpace.s) {
                IconBadge(systemName: "bed.double.fill")
                Text("¿Cómo dormiste?")
                    .font(.headline)
                Spacer(minLength: DSpace.s)
                Button("Ahora no", action: onSkip)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: DSize.dayChip)
                    .accessibilityIdentifier("today.sleep.skip")
            }
            Stepper(value: $hours, in: Self.hoursRange, step: 0.5) {
                Text("\(hours.formatted(.number.precision(.fractionLength(0...1)))) h")
                    .font(.title3.bold())
                    .numericStyle()
            }
            .accessibilityLabel("Horas que dormiste")
            .accessibilityIdentifier("today.sleep.hours")
            HStack(spacing: DSpace.s) {
                Button { onRecord(hours, .good) } label: {
                    Label("Dormí bien", systemImage: "sun.max.fill")
                }
                .buttonStyle(.surface)
                .accessibilityIdentifier("today.sleep.good")
                Button { onRecord(hours, .poor) } label: {
                    Label("Dormí mal", systemImage: "cloud.moon.fill")
                }
                .buttonStyle(.surface)
                .accessibilityIdentifier("today.sleep.poor")
            }
        }
        .padding(DSpace.m)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.sleep")
    }
}

private let previewPresentation = SessionPresentation(
    templateID: UUID(),
    title: "Push",
    workSetCount: 15,
    warmupSetCount: 2,
    estimatedMinutes: 55
)

#Preview("Cargando") {
    TodayView(screen: .loading, onStart: {}, onResume: {})
        .ironEnergyTheme()
}

#Preview("Cargando · accessibility3") {
    TodayView(screen: .loading, onStart: {}, onResume: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Error · accessibility3") {
    TodayView(screen: .failed, onStart: {}, onResume: {})
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Abriendo entrenamiento") {
    TodayView(screen: .ready(.readyToStart(previewPresentation)), onStart: {}, onResume: {}, isStartingWorkout: true)
        .ironEnergyTheme()
}

#Preview("Lista · con semana") {
    TodayWeekPreview()
}

#Preview("Lista · con semana · accessibility3") {
    TodayWeekPreview()
        .dynamicTypeSize(.accessibility3)
}

// SCRUM-222: con "¿Cómo dormiste?" los ejercicios siguen a la vista (todo se desplaza junto y
// Empezar queda fijo abajo), del iPhone más chico al más grande.
#Preview("¿Cómo dormiste? · iPhone chico", traits: .fixedLayout(width: 375, height: 667)) {
    TodayWeekPreview(asksSleepCheckIn: true)
}

#Preview("¿Cómo dormiste? · iPhone grande · oscuro", traits: .fixedLayout(width: 402, height: 874)) {
    TodayWeekPreview(asksSleepCheckIn: true)
        .preferredColorScheme(.dark)
}

#Preview("¿Cómo dormiste? · accessibility3", traits: .fixedLayout(width: 402, height: 874)) {
    TodayWeekPreview(asksSleepCheckIn: true)
        .dynamicTypeSize(.accessibility3)
}

/// Hoy con una semana real generada por el dominio (lunes, miércoles y viernes).
private struct TodayWeekPreview: View {
    var asksSleepCheckIn = false

    var body: some View {
        NavigationStack {
            if let coordinator = Self.coordinator, let plan = coordinator.plan {
                TodayView(
                    screen: coordinator.screen,
                    order: plan.todayOrder,
                    exercises: plan.todayExercises,
                    onStart: {},
                    onResume: {},
                    week: coordinator.week,
                    asksSleepCheckIn: asksSleepCheckIn
                )
                .navigationTitle("Hoy")
            }
        }
        .ironEnergyTheme()
    }

    @MainActor
    private static var coordinator: TodayPlanCoordinator? {
        guard let catalog = try? ExerciseCatalogLoader.loadBundled(),
              let profile = try? OnboardingProfile(
                goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
                trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 55, varietyPreference: .balanced
              ) else { return nil }
        let coordinator = TodayPlanCoordinator(catalog: catalog)
        return coordinator.load(profile: profile) ? coordinator : nil
    }
}

#Preview("Día de descanso") {
    TodayView(screen: .ready(.restDay), onStart: {}, onResume: {})
        .ironEnergyTheme()
}

#Preview("Lista para empezar") {
    TodayView(
        screen: .ready(.readyToStart(
            SessionPresentation(
                templateID: UUID(),
                title: "Torso y tríceps",
                workSetCount: 12,
                warmupSetCount: 2,
                estimatedMinutes: 55
            )
        )),
        onStart: {},
        onResume: {}
    )
    .ironEnergyTheme()
}

#Preview("Ajustada a 30 min") {
    TodayView(
        screen: .ready(.readyToStart(previewPresentation)),
        onStart: {},
        onResume: {},
        timeBudget: 30,
        timeNote: "Para caber en 30 min quitamos Curl martillo y dejamos menos series de Elevaciones laterales; los ejercicios principales se quedan.",
        timeRemovedExercises: true
    )
    .ironEnergyTheme()
}

#Preview("No cabe en 30 min · oscuro") {
    TodayView(
        screen: .ready(.readyToStart(previewPresentation)),
        onStart: {},
        onResume: {},
        timeBudget: 30,
        timeNote: "Aun recortada, esta sesión necesita unos 36 min y no cabe en 30; conservamos los ejercicios principales.",
        timeFits: false,
        timeRemovedExercises: true
    )
    .ironEnergyTheme()
    .preferredColorScheme(.dark)
}

#Preview("Con tiempo de sobra · accessibility3") {
    TodayView(
        screen: .ready(.readyToStart(previewPresentation)),
        onStart: {},
        onResume: {},
        timeBudget: 90,
        timeNote: "Tu sesión dura unos 55 min; no agregamos series, pero con el tiempo que sobra puedes sumar movilidad."
    )
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}

#Preview("En curso") {
    TodayView(
        screen: .ready(.activeWorkout(
            SessionPresentation(
                templateID: UUID(),
                title: "Torso y tríceps",
                workSetCount: 5,
                warmupSetCount: 0,
                estimatedMinutes: nil
            ),
            isPaused: false
        )),
        onStart: {},
        onResume: {}
    )
    .ironEnergyTheme()
}