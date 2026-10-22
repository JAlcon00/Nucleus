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
                            Label("~\(minutes) min", systemImage: "clock")
                                .font(.footnote)
                                .numericStyle()
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    HStack(alignment: .center, spacing: DSpace.s) {
                        IconBadge(
                            systemName: entry.status == .completed ? "checkmark" : "figure.strengthtraining.traditional",
                            isHighlighted: entry.isToday || entry.status == .completed
                        )
                        Text(vocabulary.sessionName(session.title))
                            .font(.title3.bold())
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    MuscleChips(muscles: session.muscles)
                    HStack {
                        Label("\(session.exercises.count) ejercicios · \(session.workSetCount) series", systemImage: "list.bullet")
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
                    Label("Descanso", systemImage: "moon.zzz")
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
                        HStack(spacing: DSpace.s) {
                            IconBadge(systemName: "figure.strengthtraining.traditional", scale: 1.25)
                            Text(vocabulary.sessionName(session.title))
                                .font(.title2.bold())
                        }
                        MuscleChips(muscles: session.muscles)
                        HStack {
                            Label(WeekText.summary(session), systemImage: "list.bullet")
                                .font(.footnote)
                                .numericStyle()
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            DayStatusLabel(status: entry.status)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, line in
                            ExerciseLineRow(line: line, last: lastPerformance[line.exerciseID], number: index + 1)
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
            IconBadge(systemName: "bed.double.fill", scale: 2.5)
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

// MARK: - Chips de músculos

/// Músculos principales de una sesión como chips ("Espalda", "Bíceps"…). Texto primario
/// sobre superficie elevada (13.7:1); bajan de línea si no caben.
struct MuscleChips: View {
    let muscles: [MuscleGroup]

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        FlowLayout(spacing: DSpace.xs) {
            ForEach(muscles, id: \.self) { muscle in
                Text(vocabulary.muscleName(muscle))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DSpace.s)
                    .padding(.vertical, DSpace.xs)
                    .background(Color.surfaceElevated, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.hairline, lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(muscles.map(vocabulary.muscleName).joined(separator: ", ")))
        .accessibilityIdentifier("week.muscles")
    }
}

// MARK: - Fila de ejercicio (M1)

/// Ejercicio de la sesión: número de orden, nombre, etiqueta "Compuesto" o "Aislado" y,
/// a la derecha, "3 series" sobre "8–12 reps". Si existe, "Última vez: 60 kg × 10". Con
/// tamaños de accesibilidad las cifras pasan debajo del nombre.
struct ExerciseLineRow: View {
    let line: TodayExerciseLine
    let last: LastPerformance?
    /// Posición en la sesión (1, 2, 3…): un número en círculo marca el orden de un vistazo.
    var number: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSpace.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DSpace.s))
        HStack(alignment: .firstTextBaseline, spacing: DSpace.s) {
            // Los símbolos numerados existen del 0 al 50: más allá, sin número.
            if let number, (0...50).contains(number) {
                Image(systemName: "\(number).circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, Color.primaryAction)
                    .accessibilityHidden(true)
            }
            layout {
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    // La etiqueta sigue al nombre como una palabra más: si no cabe en la
                    // línea, baja completa (nunca aprieta el nombre ni se corta).
                    FlowLayout(spacing: DSpace.xs, lineSpacing: 0) {
                        ForEach(Array(nameWords.enumerated()), id: \.offset) { _, word in
                            Text(word).foregroundStyle(Color.textPrimary)
                        }
                        if let jointClass = line.jointClass {
                            ExerciseKindTag(jointClass: jointClass)
                        }
                    }
                    if let last {
                        Label {
                            Text(vocabulary.lastTime(last))
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .font(.footnote)
                        .numericStyle()
                        .foregroundStyle(Color.textSecondary)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DSpace.s) }
                prescription
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// El nombre por palabras, para que la etiqueta fluya justo después de la última.
    private var nameWords: [String] {
        (line.name ?? String(localized: "Ejercicio")).split(separator: " ").map(String.init)
    }

    /// "3 series" (destacado) y debajo "8–12 reps": explícito, sin el "3 × 8–12" que hay
    /// que saber leer.
    private var prescription: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: DSpace.xs) {
            Text(vocabulary.workSets(line.workSetCount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            if let repRange = line.repRange {
                Text(vocabulary.reps(repRange))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .numericStyle()
        .fixedSize()
    }
}

/// Etiqueta del tipo de ejercicio, compacta como etiqueta de precio junto al nombre.
/// Compuesto (varias articulaciones): rellena con el acento y texto `onAccent` (5.51:1).
/// Aislado (una articulación): superficie elevada y texto primario. Icono + texto, nunca
/// sólo color.
struct ExerciseKindTag: View {
    let jointClass: JointClass

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        let isCompound = jointClass == .multiJoint
        HStack(spacing: DSpace.xs / 2) {
            Image(systemName: isCompound ? "square.stack.3d.up.fill" : "scope")
                .imageScale(.small)
            Text(vocabulary.exerciseKind(jointClass).uppercased(with: AppEnvironment.presentationLocale))
                .tracking(0.4)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(isCompound ? Color.onAccent : Color.textPrimary)
        .padding(.horizontal, DSpace.xs + DSpace.xs / 2)
        .padding(.vertical, DSpace.xs / 2)
        .background(
            isCompound ? AnyShapeStyle(Color.primaryAction) : AnyShapeStyle(Color.surfaceElevated),
            in: RoundedRectangle(cornerRadius: DRadius.small / 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DRadius.small / 2)
                .strokeBorder(isCompound ? Color.clear : Color.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vocabulary.exerciseKind(jointClass))
        .accessibilityIdentifier("exercise.kind")
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
