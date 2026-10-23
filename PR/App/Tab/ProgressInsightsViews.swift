//
//  ProgressInsightsViews.swift
//  PR
//
//  SCRUM-213 (FB-6): 4 KPIs y una gráfica de progreso en la pestaña Progreso. Los
//  números y las series los calcula `ProgressInsightsBuilder` (PRCore); aquí sólo se
//  pintan. Cada número lleva icono y texto (el color nunca es el único significado) y
//  las cifras usan `.monospacedDigit()`. La gráfica tiene descripción para VoiceOver y
//  estado vacío propio. Nunca aparece dentro del entrenamiento activo.
//

import Charts
import SwiftUI
import PRCore
import PRDomain

/// Los 4 KPIs en una cuadrícula de 2 × 2.
struct ProgressKPIGrid: View {
    let insights: ProgressInsights

    private var adherence: String {
        guard let planned = insights.plannedPerWeek else { return "\(insights.completedThisWeek)" }
        return String(localized: "\(insights.completedThisWeek) de \(planned)")
    }

    var body: some View {
        Grid(horizontalSpacing: DSpace.s, verticalSpacing: DSpace.s) {
            GridRow {
                kpi(value: adherence, label: "Entrenamientos esta semana", symbol: "calendar", tint: Color.primaryAction, id: 0)
                kpi(value: "\(insights.setsThisWeek)", label: "Series esta semana", symbol: "list.bullet", tint: Color.primaryAction, id: 1)
            }
            GridRow {
                kpi(value: streakText, label: "Racha", symbol: "flame.fill", tint: Color.accentSecondary, id: 2)
                kpi(value: "\(insights.recordsInBlock)", label: "Récords del bloque", symbol: "trophy.fill", tint: Color.accentSecondary, id: 3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.summary")
    }

    private var streakText: String {
        insights.weekStreak == 1
            ? String(localized: "1 semana")
            : String(localized: "\(insights.weekStreak) semanas")
    }

    private func kpi(value: String, label: LocalizedStringKey, symbol: String, tint: Color, id: Int) -> some View {
        VStack(alignment: .leading, spacing: DSpace.xs) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: DSize.iconBadge, height: DSize.iconBadge)
                .background(Color.surfaceElevated, in: Circle())
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .numericStyle()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSpace.m)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress.kpi.\(id)")
    }
}

/// Gráfica de progreso: series por semana o carga máxima de un ejercicio.
struct ProgressChartCard: View {
    let insights: ProgressInsights

    private enum Mode: Hashable { case weeklySets, load }
    @State private var mode = Mode.weeklySets
    @State private var selectedExercise: ExerciseID?

    private var trend: ExerciseLoadTrend? {
        insights.loadTrends.first { $0.exerciseID == selectedExercise } ?? insights.loadTrends.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.m) {
            Picker("Gráfica", selection: $mode) {
                Text("Series por semana").tag(Mode.weeklySets)
                Text("Carga máxima").tag(Mode.load)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("progress.chartMode")

            switch mode {
            case .weeklySets:
                weeklySetsChart
            case .load:
                loadChart
            }
        }
        .padding(DSpace.m)
        .cardSurface()
        .accessibilityIdentifier("progress.chart")
    }

    @ViewBuilder
    private var weeklySetsChart: some View {
        if insights.hasWeeklyData {
            Chart(insights.weeklySets) { point in
                BarMark(
                    x: .value("Semana", point.weekStart, unit: .weekOfYear),
                    y: .value("Series", point.sets)
                )
                .foregroundStyle(Color.primaryAction)
                .cornerRadius(DRadius.small / 2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .frame(minHeight: DSize.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Series por semana, últimas \(insights.weeklySets.count) semanas")
            .accessibilityValue(weeklySetsDescription)
        } else {
            emptyChart("Aún no hay datos de estas semanas. Entrena tu primera sesión y aquí verás tus series.")
        }
    }

    @ViewBuilder
    private var loadChart: some View {
        if let trend {
            if insights.loadTrends.count > 1 {
                Picker("Ejercicio", selection: Binding(
                    get: { trend.exerciseID },
                    set: { selectedExercise = $0 }
                )) {
                    ForEach(insights.loadTrends) { item in
                        Text(item.name ?? String(localized: "Ejercicio")).tag(item.exerciseID)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("progress.chartExercise")
            } else {
                Text(trend.name ?? String(localized: "Ejercicio"))
                    .font(.headline)
            }
            Chart(trend.points) { point in
                LineMark(
                    x: .value("Fecha", point.date),
                    y: .value("Carga", point.weight)
                )
                .foregroundStyle(Color.accentSecondary)
                PointMark(
                    x: .value("Fecha", point.date),
                    y: .value("Carga", point.weight)
                )
                .foregroundStyle(Color.accentSecondary)
            }
            .chartYAxisLabel(trend.unit == .pounds ? "lb" : "kg")
            .frame(minHeight: DSize.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Carga máxima de \(trend.name ?? String(localized: "Ejercicio"))")
            .accessibilityValue(loadDescription(trend))
        } else {
            emptyChart("Necesitas al menos 2 sesiones del mismo ejercicio para ver cómo sube tu carga.")
        }
    }

    private func emptyChart(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "chart.bar")
            .font(.callout)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: DSize.chartHeight / 2)
            .accessibilityIdentifier("progress.chartEmpty")
    }

    private var weeklySetsDescription: String {
        insights.weeklySets.map { point in
            String(localized: "\(point.weekStart.formatted(.dateTime.day().month(.abbreviated))): \(point.sets) series")
        }.joined(separator: ", ")
    }

    private func loadDescription(_ trend: ExerciseLoadTrend) -> String {
        let unit = trend.unit == .pounds ? "lb" : "kg"
        return trend.points.map { point in
            "\(point.date.formatted(.dateTime.day().month(.abbreviated))): \(point.weight.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        }.joined(separator: ", ")
    }
}
