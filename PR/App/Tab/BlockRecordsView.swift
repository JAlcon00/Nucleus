//
//  BlockRecordsView.swift
//  PR
//
//  SCRUM-265 (PR-H003): cuáles son los récords del bloque. Se abre desde la KPI "Récords
//  del bloque" de Progreso y tiene tantas filas como dice la KPI. La lista, el orden y el
//  nombre los decide `ProgressInsightsBuilder` (PRCore); aquí sólo se pintan. Estados:
//  - con récords: del más reciente al más antiguo;
//  - vacío: todavía no hay récords en el bloque, y cómo se logran;
//  - cargando, fallido y sin conexión: no aplican; se abre desde un Progreso ya leído y
//    todo es local.
//

import SwiftUI
import PRCore
import PRDomain

struct BlockRecordsView: View {
    let records: [WorkoutLogRecord]

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle("Récords del bloque")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSpace.s) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    row(record)
                        .accessibilityIdentifier("progress.records.row.\(index)")
                }
            }
            .padding(DSpace.m)
        }
        .accessibilityIdentifier("progress.records")
    }

    private func row(_ record: WorkoutLogRecord) -> some View {
        HStack(alignment: .top, spacing: DSpace.m) {
            IconBadge(systemName: "trophy.fill", isHighlighted: true)
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text(name(record))
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(load(record))
                    .font(.title3.bold())
                    .numericStyle()
                    .foregroundStyle(Color.accentSecondary)
                Label(date(record), systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Récord: \(name(record)), \(load(record)), \(date(record))"))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aún no hay récords en este bloque", systemImage: "trophy")
        } description: {
            Text("Salen cuando superas tu mejor carga en un ejercicio.")
        }
        .accessibilityIdentifier("progress.records.empty")
    }

    private func name(_ record: WorkoutLogRecord) -> String {
        record.name ?? String(localized: "Ejercicio")
    }

    private func load(_ record: WorkoutLogRecord) -> String {
        vocabulary.setText(weight: record.weight, unit: record.unit, reps: record.reps)
    }

    private func date(_ record: WorkoutLogRecord) -> String {
        record.achievedAt.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(AppEnvironment.presentationLocale)
        )
    }
}

// MARK: - Previews

#Preview("Con récords") {
    NavigationStack { BlockRecordsView(records: previewRecords()) }
        .ironEnergyTheme()
}

#Preview("Con récords · claro") {
    NavigationStack { BlockRecordsView(records: previewRecords()) }
        .ironEnergyTheme()
        .preferredColorScheme(.light)
}

#Preview("Con récords · accessibility3") {
    NavigationStack { BlockRecordsView(records: previewRecords()) }
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Vacío") {
    NavigationStack { BlockRecordsView(records: []) }
        .ironEnergyTheme()
}

#Preview("Vacío · accessibility3") {
    NavigationStack { BlockRecordsView(records: []) }
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

/// Récords calculados por PRCore a partir de tres entrenamientos de ejemplo.
private func previewRecords() -> [WorkoutLogRecord] {
    let squat = ExerciseID()
    let bench = ExerciseID()
    let monday = Date(timeIntervalSinceReferenceDate: 0)
    let calendar = Calendar(identifier: .gregorian)
    func session(_ days: Int, squatWeight: Double, benchWeight: Double) -> WorkoutSessionRecord {
        let start = calendar.date(byAdding: .day, value: days, to: monday) ?? monday
        return WorkoutSessionRecord(
            templateID: nil, startedAt: start, endedAt: start.addingTimeInterval(2_700),
            lifecycle: .completed,
            sets: (try? [
                SetRecord(exerciseID: squat, performedAt: start, weight: squatWeight, unit: .kilograms, reps: 8, lifecycle: .completed),
                SetRecord(exerciseID: bench, performedAt: start.addingTimeInterval(600), weight: benchWeight, unit: .kilograms, reps: 6, lifecycle: .completed),
            ]) ?? []
        )
    }
    return ProgressOverviewBuilder().overview(
        history: [session(0, squatWeight: 80, benchWeight: 60), session(3, squatWeight: 85, benchWeight: 62.5)],
        templateTitles: [:],
        exerciseNames: [squat: "Sentadilla con barra", bench: "Press banca con barra"],
        plannedPerWeek: 3,
        date: calendar.date(byAdding: .day, value: 3, to: monday) ?? monday,
        timeZone: .current
    ).insights.blockRecords
}
