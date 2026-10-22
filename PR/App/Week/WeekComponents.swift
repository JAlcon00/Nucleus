//
//  WeekComponents.swift
//  PR
//
//  Created by PR.
//
//  "Tu semana" (SCRUM-197, U4): tira de 7 días para Hoy, lista de la semana para Plan,
//  detalle de un día, fila de ejercicio con "3 × 8–12" y "última vez" (M1) y la hoja
//  "¿Por qué este orden?". Vistas puras: presentan `WeekOverview` (PRCore) y envían
//  intenciones; qué toca cada día lo decide el dominio.
//

import SwiftUI
import PRCore
import PRDomain

// MARK: - Tira de la semana (Hoy)

/// Siete círculos L…D. Hoy lleva anillo de acento; hecho, relleno de energía con ✓ (icono,
/// no sólo color); entrenamiento pendiente, borde acero; no realizado, borde punteado;
/// descanso, punto tenue. Tocar un día abre su detalle.
struct WeekStripView: View {
    let week: WeekOverview
    let onSelect: (WeekDay) -> Void

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)
    @ScaledMetric(relativeTo: .subheadline) private var dotSize = DSize.weekDot

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { entry in
                Button { onSelect(entry.day) } label: { cell(entry) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: DSize.dayChip)
                    .contentShape(Rectangle())
                    .accessibilityLabel(Text(WeekText.accessibilityLabel(entry, vocabulary: vocabulary)))
                    .accessibilityAddTraits(entry.isToday ? .isSelected : [])
                    .accessibilityIdentifier("week.strip.\(entry.day.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week.strip")
    }

    private func cell(_ entry: WeekDayEntry) -> some View {
        VStack(spacing: DSpace.xs) {
            Text(vocabulary.weekdayInitial(entry.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isToday ? Color.primaryAction : Color.textSecondary)
            ZStack {
                mark(entry)
                if entry.isToday {
                    Circle()
                        .strokeBorder(Color.primaryAction, lineWidth: DSize.markStroke)
                }
            }
            .frame(width: dotSize, height: dotSize)
        }
    }

    @ViewBuilder
    private func mark(_ entry: WeekDayEntry) -> some View {
        switch entry.status {
        case .completed:
            Circle()
                .fill(LinearGradient.energy)
                .padding(entry.isToday ? DSpace.xs : 0)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                }
        case .pending:
            Circle()
                .strokeBorder(Color.textSecondary, lineWidth: DSize.markStroke)
                .padding(entry.isToday ? DSpace.xs : 0)
        case .missed:
            Circle()
                .strokeBorder(Color.textSecondary, style: StrokeStyle(lineWidth: DSize.markStroke, dash: DSize.missedDash))
                .padding(entry.isToday ? DSpace.xs : 0)
        case .rest:
            Circle()
                .fill(Color.textSecondary.opacity(0.5))
                .frame(width: DSize.restDot, height: DSize.restDot)
        }
    }
}

// MARK: - Lista de la semana (Plan)

/// Una fila por día, de lunes a domingo. Los días de entrenamiento son tarjetas; el
/// descanso, una fila delgada para que la semana se lea de un vistazo. El CTA "Empezar"
/// sólo aparece el día de hoy (empezar otro día queda fuera del POC).
struct WeekListView: View {
    let week: WeekOverview
    var lastPerformance: [ExerciseID: LastPerformance] = [:]
    var isStartingWorkout = false
    /// `nil` = sin CTA (p. ej. en la presentación tras el cuestionario).
    var onStart: (() -> Void)?

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSpace.m) {
                ForEach(week.days) { entry in
                    if let session = entry.session {
                        sessionCard(entry, session: session)
                    } else {
                        restRow(entry)
                    }
                }
            }
            .padding(DSpace.m)
        }
        .navigationDestination(for: WeekDay.self) { day in
            if let entry = week.days.first(where: { $0.day == day }) {
                DayDetailView(
                    entry: entry,
                    lastPerformance: lastPerformance,
                    isStartingWorkout: isStartingWorkout,
                    onStart: onStart
                )
            }
        }
    }

    private func sessionCard(_ entry: WeekDayEntry, session: WeekSession) -> some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            NavigationLink(value: entry.day) {
                VStack(alignment: .leading, spacing: DSpace.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(WeekText.dayHeader(entry, vocabulary: vocabulary))
                            .eyebrowStyle()
                            .foregroundStyle(entry.isToday ? Color.primaryAction : Color.textSecondary)
                        Spacer()
                        if let minutes = session.estimatedMinutes {
                            Text("~\(minutes) min")
                                .font(.footnote)
                                .numericStyle()
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(vocabulary.sessionName(session.title))
                            .font(.title3.bold())
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    Text(WeekText.muscles(session, vocabulary: vocabulary))
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    HStack {
                        Text("\(session.exercises.count) ejercicios · \(session.workSetCount) series")
                            .font(.footnote)
                            .numericStyle()
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DayStatusLabel(status: entry.status)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("week.day.\(entry.day.rawValue)")

            if entry.isToday, entry.status == .pending, let onStart {
                Button(action: onStart) {
                    LoadingButtonLabel(isLoading: isStartingWorkout, loadingAccessibilityLabel: "Abriendo entrenamiento") {
                        Label("Empezar", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.energy)
                .disabled(isStartingWorkout)
                .accessibilityIdentifier("week.start")
            }
        }
        .padding(DSpace.m)
        .cardSurface()
    }

    private func restRow(_ entry: WeekDayEntry) -> some View {
        NavigationLink(value: entry.day) {
            HStack {
                Text(WeekText.dayHeader(entry, vocabulary: vocabulary))
                    .eyebrowStyle()
                    .foregroundStyle(entry.isToday ? Color.primaryAction : Color.textSecondary)
                Spacer()
                if entry.status == .completed {
                    DayStatusLabel(status: entry.status)
                } else {
                    Text("Descanso")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, DSpace.m)
            .frame(minHeight: DSize.dayChip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("week.day.\(entry.day.rawValue)")
    }
}

/// Estado de un día con icono + texto (nunca sólo color). "No realizado" no es un error:
/// va en gris, no en rojo.
struct DayStatusLabel: View {
    let status: WeekDayStatus

    var body: some View {
        switch status {
        case .completed:
            Label("Hecho", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.success)
        case .missed:
            Label("No realizado", systemImage: "minus.circle")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        case .pending, .rest:
            EmptyView()
        }
    }
}

// MARK: - Detalle de un día

/// Ejercicios en orden con series × reps y "última vez", "¿Por qué este orden?" y el CTA
/// "Empezar" sólo si el día es hoy.
struct DayDetailView: View {
    let entry: WeekDayEntry
    var lastPerformance: [ExerciseID: LastPerformance] = [:]
    var isStartingWorkout = false
    var onStart: (() -> Void)?

    @State private var showingOrder = false
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        Group {
            if let session = entry.session {
                sessionDetail(session)
            } else {
                restDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(Text(WeekText.dayTitle(entry, vocabulary: vocabulary)))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("day.detail")
    }

    private func sessionDetail(_ session: WeekSession) -> some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSpace.m) {
                    VStack(alignment: .leading, spacing: DSpace.xs) {
                        Text(vocabulary.sessionName(session.title))
                            .font(.title2.bold())
                        Text(WeekText.muscles(session, vocabulary: vocabulary))
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        HStack {
                            Text(WeekText.summary(session))
                                .font(.footnote)
                                .numericStyle()
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            DayStatusLabel(status: entry.status)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, line in
                            ExerciseLineRow(line: line, last: lastPerformance[line.exerciseID])
                                .padding(.vertical, DSpace.s)
                                .accessibilityIdentifier("day.exercise.\(index)")
                            if index < session.exercises.count - 1 {
                                Divider().overlay(Color.hairline)
                            }
                        }
                    }
                    .padding(.horizontal, DSpace.m)
                    .cardSurface(cornerRadius: DRadius.medium)
                    if !session.order.isEmpty {
                        Button {
                            showingOrder = true
                        } label: {
                            Label("¿Por qué este orden?", systemImage: "questionmark.circle")
                                .frame(minHeight: DSize.dayChip)
                        }
                        .accessibilityIdentifier("day.whyOrder")
                    }
                }
                .padding(DSpace.m)
            }
            if entry.isToday, entry.status == .pending, let onStart {
                Button(action: onStart) {
                    LoadingButtonLabel(isLoading: isStartingWorkout, loadingAccessibilityLabel: "Abriendo entrenamiento") {
                        Label("Empezar \(vocabulary.sessionName(session.title))", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.energy)
                .disabled(isStartingWorkout)
                .padding([.horizontal, .bottom], DSpace.m)
                .accessibilityIdentifier("day.start")
            }
        }
        .sheet(isPresented: $showingOrder) {
            OrderExplanationSheet(order: session.order, reorderedByFatigue: session.orderReorderedByFatigue)
        }
    }

    private var restDetail: some View {
        VStack(spacing: DSpace.m) {
            Image(systemName: "bed.double.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            Text("Descanso")
                .font(.title3.bold())
            Text("Este día toca recuperar.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            DayStatusLabel(status: entry.status)
        }
        .padding(DSpace.l)
    }
}

// MARK: - Fila de ejercicio (M1)

/// "Press de banca · 3 × 8–12" y, si existe, "Última vez: 60 kg × 10". Con tamaños de
/// accesibilidad las cifras pasan debajo del nombre.
struct ExerciseLineRow: View {
    let line: TodayExerciseLine
    let last: LastPerformance?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSpace.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DSpace.s))
        layout {
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text(line.name ?? String(localized: "Ejercicio"))
                    .foregroundStyle(Color.textPrimary)
                if let last {
                    Text(vocabulary.lastTime(last))
                        .font(.footnote)
                        .numericStyle()
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DSpace.s) }
            Text(vocabulary.setsAndReps(sets: line.workSetCount, repRange: line.repRange))
                .numericStyle()
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "¿Por qué este orden?"

/// Posición, ejercicio y motivos del motor de orden (SCRUM-29).
struct OrderExplanationSheet: View {
    let order: [TodayOrderLine]
    let reorderedByFatigue: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { line in
                        VStack(alignment: .leading, spacing: DSpace.xs) {
                            Text("\(line.rank). \(line.name ?? String(localized: "Ejercicio"))")
                                .font(.headline)
                            ForEach(Array(line.reasons.enumerated()), id: \.offset) { _, reason in
                                Text(Self.text(for: reason))
                                    .font(.callout)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: DSpace.xs) {
                        if reorderedByFatigue {
                            Text("La fatiga acumulada cambió el orden para proteger los músculos prioritarios.")
                        }
                        Text("Precedencia: restricciones, rol funcional, prioridad muscular, demanda técnica y, al final, interferencia por fatiga.")
                    }
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("¿Por qué este orden?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("today.orderSheet")
    }

    private static func text(for reason: TodayOrderReason) -> String {
        switch reason {
        case .functionalRole: String(localized: "Los ejercicios compuestos van primero, con los músculos frescos.")
        case .musclePriority: String(localized: "Trabaja un músculo que priorizas, por eso se adelanta.")
        case .technicalDemand: String(localized: "Es técnicamente exigente: mejor hacerlo sin fatiga.")
        }
    }
}

// MARK: - Textos de la semana

/// Textos compuestos de la semana (sólo formato; nada decide aquí).
enum WeekText {
    /// "LUNES · HOY" o "MARTES".
    static func dayHeader(_ entry: WeekDayEntry, vocabulary: TrainingVocabularyPresenter) -> String {
        let name = vocabulary.weekdayName(entry.day).uppercased()
        return entry.isToday ? "\(name) · \(String(localized: "HOY"))" : name
    }

    /// "Lunes · Hoy" o "Martes" (título del detalle).
    static func dayTitle(_ entry: WeekDayEntry, vocabulary: TrainingVocabularyPresenter) -> String {
        let name = vocabulary.weekdayName(entry.day)
        return entry.isToday ? "\(name) · \(String(localized: "Hoy"))" : name
    }

    /// "Espalda · Bíceps · Antebrazo".
    static func muscles(_ session: WeekSession, vocabulary: TrainingVocabularyPresenter) -> String {
        session.muscles.map(vocabulary.muscleName).joined(separator: " · ")
    }

    /// "5 ejercicios · 16 series · ~55 min".
    static func summary(_ session: WeekSession) -> String {
        var parts = [
            String(localized: "\(session.exercises.count) ejercicios"),
            String(localized: "\(session.workSetCount) series"),
        ]
        if let minutes = session.estimatedMinutes {
            parts.append(String(localized: "~\(minutes) min"))
        }
        return parts.joined(separator: " · ")
    }

    /// VoiceOver de un día de la tira: "Miércoles, hoy, Push, pendiente".
    static func accessibilityLabel(_ entry: WeekDayEntry, vocabulary: TrainingVocabularyPresenter) -> String {
        var parts = [vocabulary.weekdayName(entry.day)]
        if entry.isToday { parts.append(String(localized: "hoy")) }
        if let session = entry.session { parts.append(vocabulary.sessionName(session.title)) }
        switch entry.status {
        case .rest: parts.append(String(localized: "descanso"))
        case .pending: parts.append(String(localized: "pendiente"))
        case .completed: parts.append(String(localized: "hecho"))
        case .missed: parts.append(String(localized: "no realizado"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Tira y lista") {
    WeekComponentsPreview()
}

#Preview("Lista · accessibility3") {
    WeekComponentsPreview()
        .dynamicTypeSize(.accessibility3)
}

/// Semana real generada por el dominio para las previews (no se inventan datos en la vista).
private struct WeekComponentsPreview: View {
    var body: some View {
        NavigationStack {
            if let week = Self.week {
                VStack(spacing: DSpace.m) {
                    WeekStripView(week: week, onSelect: { _ in })
                        .padding(.horizontal, DSpace.m)
                    WeekListView(week: week, onStart: {})
                }
                .screenBackground()
                .navigationTitle("Tu semana")
            } else {
                Text("Sin catálogo")
            }
        }
        .ironEnergyTheme()
    }

    @MainActor
    private static var week: WeekOverview? {
        guard let catalog = try? ExerciseCatalogLoader.loadBundled(),
              let profile = try? OnboardingProfile(
                goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
                trainingDays: [.monday, .wednesday, .friday], usualSessionMinutes: 55, varietyPreference: .balanced
              ) else { return nil }
        let coordinator = TodayPlanCoordinator(catalog: catalog)
        guard coordinator.load(profile: profile) else { return nil }
        return coordinator.week
    }
}
