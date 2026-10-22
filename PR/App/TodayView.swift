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
//  workout / en curso. Funciona offline.
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

    @State private var showingOrder = false
    /// Cuenta toques de Empezar/Continuar: dispara el háptico de confirmación.
    @State private var startTaps = 0

    var body: some View {
        Group {
            switch screen {
            case .loading:
                loadingView
            case .failed:
                failedView
            case .ready(.restDay):
                restDayView
            case .ready(.readyToStart(let presentation)):
                readyView(presentation)
            case .ready(.activeWorkout(let presentation, let isPaused)):
                activeView(presentation, isPaused: isPaused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .contain)
        .safeAreaInset(edge: .top) {
            if let notice { noticeBanner(notice) }
        }
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
                Text("Hoy")
                    .font(.caption)
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
            Image(systemName: "bed.double.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.primaryAction)
            Text("Día de descanso")
                .font(.title3.bold())
            Text("Hoy toca recuperar. Vuelve mañana cuando toque entrenar.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Día de descanso.")
        .accessibilityIdentifier("today.restDay")
    }

    // MARK: - Ready to start

    private func readyView(_ presentation: SessionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hoy")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(presentation.title)
                    .font(.title2.bold())
                sessionSummary(presentation)
            }
            exerciseList
            if !order.isEmpty {
                Button {
                    showingOrder = true
                } label: {
                    Label("¿Por qué este orden?", systemImage: "questionmark.circle")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("today.whyOrder")
            }
            startButton(presentation)
        }
        .padding(24)
        .sheet(isPresented: $showingOrder) { orderSheet }
    }

    /// Hoja "¿Por qué este orden?": posición, ejercicio y motivos del motor de orden.
    private var orderSheet: some View {
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
                        if orderReorderedByFatigue {
                            Text("La fatiga acumulada cambió el orden para proteger los músculos prioritarios.")
                        }
                        Text("Precedencia: restricciones, rol funcional, prioridad muscular, demanda técnica y, al final, interferencia por fatiga.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("¿Por qué este orden?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { showingOrder = false }
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

    /// Lista de ejercicios de la sesión (con scroll: el botón Empezar siempre queda a la vista).
    private var exerciseList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSpace.s) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, line in
                    HStack {
                        Text(line.name ?? String(localized: "Ejercicio"))
                        Spacer()
                        Text("\(line.setCount) × series")
                            .foregroundStyle(Color.textSecondary)
                            .numericStyle()
                    }
                    .padding(.vertical, DSpace.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.exercise.\(index)")
                }
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
            Text(presentation.title)
                .font(.title2.bold())
            sessionSummary(presentation)
            Spacer()
            resumeButton
        }
        .padding(24)
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
                Label("Empezar \(presentation.title)", systemImage: "play.fill")
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