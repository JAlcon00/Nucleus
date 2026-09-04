//
//  ExportDataView.swift
//  PR
//
//  Created by PR.
//
//  Carga del export (PR-0204 wiring): acumula el historial real persistido en el
//  almacén local durabile y lo vuelca en `ExportView`. La UI del export es "user-
//  controlled" (`ShareLink`) y NO exporta secrets (el motor de PRDomain lo garantiza).
//  I/O async; ninguna regla de negocio viva en la vista.
//

import SwiftUI
import PRCore
import PRDomain

struct ExportDataView: View {
    @Environment(AppEnvironment.self) private var environment

    enum LoadState {
        case loading
        case ready(coordinator: DataExportCoordinator, bundle: ExportBundle, sessions: [WorkoutSessionRecord])
    }

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Cargando historial…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let coordinator, let bundle, let sessions):
                ExportView(coordinator: coordinator, bundle: bundle, sessions: sessions)
            }
        }
        .navigationTitle("Exportar datos")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        do {
            let sessions = try await loadSessions()
            let bundle = Self.makeBundle(sessions: sessions, exercises: environment.catalog.exercises)
            state = .ready(
                coordinator: DataExportCoordinator(),
                bundle: bundle,
                sessions: sessions
            )
        } catch {
            // Sin historial accesible → bundle vacío (nunca un crash ni datos por defecto).
            let bundle = Self.makeBundle(sessions: [], exercises: environment.catalog.exercises)
            state = .ready(
                coordinator: DataExportCoordinator(),
                bundle: bundle,
                sessions: []
            )
        }
    }

    private func loadSessions() async throws -> [WorkoutSessionRecord] {
        guard let store = environment.localRepositoryStore else { return [] }
        return try await FileWorkoutRepository(store: store).allSessions()
    }

    private static func makeBundle(
        sessions: [WorkoutSessionRecord],
        exercises: [Exercise]
    ) -> ExportBundle {
        ExportBundle(
            schemaVersion: ExportBundleVersion.current,
            exportedAt: Date(),
            blocks: [],
            sessions: sessions,
            exercises: exercises,
            gyms: [],
            restrictions: [],
            profile: nil
        )
    }
}

#Preview {
    ExportDataView()
        .environment(AppEnvironment(authProvider: FakeAppleIDAuthProvider()))
}