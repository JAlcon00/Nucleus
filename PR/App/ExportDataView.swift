//
//  ExportDataView.swift
//  PR
//
//  Created by PR.
//
//  Carga del export (PR-0204 wiring, SCRUM-23): pide a `DataExportCoordinator` el
//  historial real de la colección de workouts y presenta un estado por caso. Nunca
//  convierte un error en "0 sesiones" silencioso: lo ilegible se avisa y un fallo de
//  la colección entera se muestra con opción de reintentar. Sin reglas de negocio.
//

import SwiftUI
import PRCore
import PRDomain

struct ExportDataView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Estado de la pantalla. Sin conexión: no aplica (Export es 100 % local).
    enum LoadState {
        case loading
        case empty(unreadableCount: Int)
        case loaded(sessions: [WorkoutSessionRecord], unreadableCount: Int)
        case failed
    }

    @State private var state: LoadState = .loading
    /// Cambiarlo relanza la carga; SwiftUI es dueño de la tarea y la cancela al salir.
    @State private var loadAttempt = 0

    var body: some View {
        ExportContentView(
            state: state,
            exercises: environment.catalog.exercises,
            onRetry: { loadAttempt += 1 }
        )
        .task(id: loadAttempt) { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        guard let persistence = environment.persistence else {
            state = .failed
            return
        }
        do {
            let history = try await DataExportCoordinator().loadHistory(from: try persistence.workoutRepository())
            switch history {
            case .empty(let unreadable):
                state = .empty(unreadableCount: unreadable)
            case .loaded(let sessions, let unreadable):
                state = .loaded(sessions: sessions, unreadableCount: unreadable)
            }
        } catch {
            state = .failed
        }
    }
}

/// Render puro del estado de Export (previsualizable sin `AppEnvironment`).
struct ExportContentView: View {
    let state: ExportDataView.LoadState
    let exercises: [Exercise]
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Cargando historial…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty(let unreadable):
                ContentUnavailableView {
                    Label("Aún no tienes entrenamientos", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    VStack(spacing: DSpace.s) {
                        Text("Cuando completes tu primera sesión podrás exportarla aquí.")
                        if unreadable > 0 {
                            UnreadableRecordsNotice(count: unreadable)
                        }
                    }
                }
            case .loaded(let sessions, let unreadable):
                ExportView(sessions: sessions, exercises: exercises, unreadableCount: unreadable)
            case .failed:
                ContentUnavailableView {
                    Label("No pudimos leer tu historial", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Tus entrenamientos siguen guardados en este dispositivo. Intenta de nuevo.")
                } actions: {
                    Button("Reintentar", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Exportar datos")
    }
}

/// Aviso de registros que no se pudieron leer (icono + texto, no sólo color).
struct UnreadableRecordsNotice: View {
    let count: Int

    var body: some View {
        Label {
            if count == 1 {
                Text("1 registro no se pudo leer y no se incluye.")
            } else {
                Text("\(count) registros no se pudieron leer y no se incluyen.")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)
        }
        .font(.footnote)
    }
}

#Preview("Cargando") {
    NavigationStack {
        ExportContentView(state: .loading, exercises: [], onRetry: {})
    }
}

#Preview("Vacío") {
    NavigationStack {
        ExportContentView(state: .empty(unreadableCount: 0), exercises: [], onRetry: {})
    }
}

#Preview("Vacío con ilegibles · oscuro") {
    NavigationStack {
        ExportContentView(state: .empty(unreadableCount: 1), exercises: [], onRetry: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Error · accessibility3") {
    NavigationStack {
        ExportContentView(state: .failed, exercises: [], onRetry: {})
    }
    .dynamicTypeSize(.accessibility3)
}
