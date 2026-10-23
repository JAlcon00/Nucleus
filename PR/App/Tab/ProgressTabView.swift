//
//  ProgressTabView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Progreso" (SKILL §6). SCRUM-186: registro de entrenamientos desde el primero
//  completado, con un resumen corto (total, esta semana frente a lo planeado, récords) y
//  el detalle de cada sesión (ejercicios y series). Estados:
//  - cargando: skeleton;
//  - vacío: todavía no hay entrenamientos completados;
//  - con registro;
//  - fallido: el historial no se pudo leer (siguen en el dispositivo) → reintentar;
//  - sin conexión: no aplica, todo es local.
//  Lo que se cuenta lo decide `ProgressOverviewBuilder` (PRCore); la vista sólo lo pinta.
//

import SwiftUI
import PRCore
import PRDomain

struct ProgressTabView: View {
    var screen: ProgressScreen = .loading
    /// Intento: volver a leer el historial.
    var onRetry: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .loading:
                    skeleton
                case .empty(let unreadable):
                    emptyState(unreadable: unreadable)
                case .loaded(let overview, let unreadable):
                    ProgressLogView(overview: overview, unreadable: unreadable)
                case .failed:
                    failedState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(AppTab.progress.title)
        }
    }

    private func emptyState(unreadable: Int) -> some View {
        VStack(spacing: 12) {
            IconBadge(systemName: "chart.line.uptrend.xyaxis", scale: 2.5)
            Text("Tu progreso")
                .font(.title3.bold())
            Text("Cuando completes tu primer entrenamiento, aquí quedará su registro: series, cargas y récords.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if unreadable > 0 {
                UnreadableRecordsNotice(count: unreadable)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.empty")
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("No pudimos leer tu historial", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Tus entrenamientos siguen guardados en este dispositivo. Intenta de nuevo.")
        } actions: {
            Button("Reintentar", action: onRetry)
                .buttonStyle(.energy)
                .accessibilityIdentifier("progress.retry")
        }
        .accessibilityIdentifier("progress.failed")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            HStack {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: DSpace.xs) {
                        Text("12").font(.title2.bold())
                        Text("Entrenamientos").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(DSpace.m)
            .cardSurface()
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    Text("LUN 19 OCT").eyebrowStyle()
                    Text("Sesión de entrenamiento").font(.headline)
                    Text("42 min · 12 series").font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSpace.m)
                .cardSurface(cornerRadius: DRadius.medium)
            }
            Spacer()
        }
        .padding(DSpace.m)
        .redacted(reason: .placeholder)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cargando tu progreso"))
        .accessibilityIdentifier("progress.loading")
    }
}

// MARK: - Registro

/// Resumen y lista de entrenamientos, del más reciente al primero.
private struct ProgressLogView: View {
    let overview: ProgressOverview
    let unreadable: Int

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSpace.m) {
                // SCRUM-213: 4 KPIs y la gráfica de progreso.
                ProgressKPIGrid(insights: overview.insights)
                ProgressChartCard(insights: overview.insights)
                if unreadable > 0 {
                    UnreadableRecordsNotice(count: unreadable)
                        .padding(.horizontal, DSpace.xs)
                }
                Label("Registro · \(overview.totalWorkouts)", systemImage: "list.bullet.rectangle")
                    .eyebrowStyle()
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, DSpace.s)
                ForEach(Array(overview.entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: entry.id) {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.entry.\(index)")
                }
            }
            .padding(DSpace.m)
        }
        .navigationDestination(for: WorkoutID.self) { id in
            if let entry = overview.entries.first(where: { $0.id == id }) {
                WorkoutLogDetailView(entry: entry)
            }
        }
    }

    private func row(_ entry: WorkoutLogEntry) -> some View {
        HStack(alignment: .center, spacing: DSpace.m) {
            IconBadge(
                systemName: entry.recordCount > 0 ? "trophy.fill" : "checkmark",
                isHighlighted: entry.recordCount > 0
            )
            rowText(entry)
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func rowText(_ entry: WorkoutLogEntry) -> some View {
        VStack(alignment: .leading, spacing: DSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label(WorkoutLogText.date(entry), systemImage: "calendar")
                    .eyebrowStyle()
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if entry.recordCount > 0 {
                    Label(WorkoutLogText.records(entry.recordCount), systemImage: "trophy.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(WorkoutLogText.title(entry, vocabulary: vocabulary))
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            Label(WorkoutLogText.meta(entry, vocabulary: vocabulary), systemImage: "clock")
                .font(.footnote)
                .numericStyle()
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Detalle de un entrenamiento

/// Ejercicios y series tal como se hicieron.
struct WorkoutLogDetailView: View {
    let entry: WorkoutLogEntry

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSpace.m) {
                VStack(alignment: .leading, spacing: DSpace.xs) {
                    HStack(spacing: DSpace.s) {
                        IconBadge(systemName: "figure.strengthtraining.traditional", scale: 1.25)
                        Text(WorkoutLogText.title(entry, vocabulary: vocabulary))
                            .font(.title2.bold())
                    }
                    Label(WorkoutLogText.meta(entry, vocabulary: vocabulary), systemImage: "clock")
                        .font(.subheadline)
                        .numericStyle()
                        .foregroundStyle(Color.textSecondary)
                    if entry.recordCount > 0 {
                        Label(WorkoutLogText.records(entry.recordCount), systemImage: "trophy.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentSecondary)
                    }
                }
                ForEach(entry.exercises) { exercise in
                    VStack(alignment: .leading, spacing: DSpace.s) {
                        Label {
                            Text(exercise.name ?? String(localized: "Ejercicio"))
                        } icon: {
                            Image(systemName: "dumbbell.fill").foregroundStyle(Color.primaryAction)
                        }
                        .font(.headline)
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Label {
                                    Text("Serie \(index + 1)")
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                                }
                                .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text(vocabulary.setText(weight: set.weight, unit: set.unit, reps: set.reps))
                                    .numericStyle()
                            }
                            .font(.callout)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(DSpace.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(cornerRadius: DRadius.medium)
                }
            }
            .padding(DSpace.m)
        }
        .screenBackground()
        .navigationTitle(Text(WorkoutLogText.date(entry)))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("progress.detail")
    }
}

/// Textos compuestos del registro (sólo formato).
enum WorkoutLogText {
    /// "LUN 19 OCT".
    static func date(_ entry: WorkoutLogEntry) -> String {
        entry.startedAt.formatted(
            .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppEnvironment.presentationLocale)
        ).uppercased()
    }

    /// Nombre de la sesión, o "Entrenamiento" si la plantilla ya no se conoce.
    static func title(_ entry: WorkoutLogEntry, vocabulary: TrainingVocabularyPresenter) -> String {
        entry.sessionTitle.map(vocabulary.sessionName) ?? String(localized: "Entrenamiento")
    }

    /// "42 min · 12 series · 1,580 kg" (el volumen sólo si no mezcla unidades).
    static func meta(_ entry: WorkoutLogEntry, vocabulary: TrainingVocabularyPresenter) -> String {
        var parts = [
            String(localized: "\(entry.durationSeconds / 60) min"),
            String(localized: "\(entry.workingSets) series"),
        ]
        if let volume = entry.volume, let unit = entry.volumeUnit {
            parts.append(vocabulary.load(volume, unit: unit))
        }
        return parts.joined(separator: " · ")
    }

    static func records(_ count: Int) -> String {
        count == 1 ? String(localized: "1 récord") : String(localized: "\(count) récords")
    }
}

// MARK: - Previews

#Preview("Cargando") {
    ProgressTabView(screen: .loading)
        .ironEnergyTheme()
}

#Preview("Vacío") {
    ProgressTabView(screen: .empty(unreadable: 0))
        .ironEnergyTheme()
}

#Preview("Fallido · accessibility3") {
    ProgressTabView(screen: .failed)
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Con registro") {
    ProgressTabView(screen: previewScreen())
        .ironEnergyTheme()
}

#Preview("Con registro · accessibility3") {
    ProgressTabView(screen: previewScreen())
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

/// Registro calculado por el dominio a partir de dos entrenamientos de ejemplo.
private func previewScreen() -> ProgressScreen {
    let squat = ExerciseID()
    let template = SessionTemplate(title: "Legs", plannedSets: [])
    let monday = Date(timeIntervalSinceReferenceDate: 0)
    let thursday = Calendar(identifier: .gregorian).date(byAdding: .day, value: 3, to: monday) ?? monday
    func session(_ start: Date, weight: Double) -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            templateID: template.id, startedAt: start, endedAt: start.addingTimeInterval(2_520),
            lifecycle: .completed,
            sets: (try? [
                SetRecord(exerciseID: squat, performedAt: start, weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed),
                SetRecord(exerciseID: squat, performedAt: start.addingTimeInterval(180), weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed),
            ]) ?? []
        )
    }
    let overview = ProgressOverviewBuilder().overview(
        history: [session(monday, weight: 80), session(thursday, weight: 85)],
        templateTitles: [template.id: template.title],
        exerciseNames: [squat: "Sentadilla con barra"],
        plannedPerWeek: 3,
        date: thursday,
        timeZone: .current
    )
    return .loaded(overview, unreadable: 0)
}
