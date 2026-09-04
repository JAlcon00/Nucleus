//
//  ExportView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla de export de datos (PR-0204, RF-030 / RNEG-006). Renderiza estado y
//  delega en `DataExportCoordinator` (caso de uso) para construir el archivo; el
//  compartido es "user-controlled" vía `ShareLink`. No contiene reglas de negocio.
//

import SwiftUI
import UniformTypeIdentifiers
import PRCore
import PRDomain

struct ExportView: View {
    let coordinator: DataExportCoordinator
    let bundle: ExportBundle
    let sessions: [WorkoutSessionRecord]

    @State private var jsonFile: DataExportFile?
    @State private var csvFile: DataExportFile?

    var body: some View {
        List {
            Section("Historial de entrenamiento") {
                Label(formatCount(bundle.sessions.count, "sesión", "sesiones"),
                      systemImage: "figure.strengthtraining.traditional")
                Label(formatCount(bundle.exercises.count, "ejercicio", "ejercicios"),
                      systemImage: "dumbbell")
            }

            Section("Exportar") {
                shareButton(for: jsonFile, title: "JSON completo", icon: "doc.richtext")
                shareButton(for: csvFile, title: "Workout sets (CSV)", icon: "tablecells")
            }
        }
        .navigationTitle("Exportar datos")
        .task { buildFiles() }
        .overlay {
            if jsonFile == nil && csvFile == nil {
                ProgressView("Preparando export…")
            }
        }
    }

    private func buildFiles() {
        jsonFile = try? coordinator.exportJSON(
            sessions: bundle.sessions,
            exercises: bundle.exercises,
            blocks: bundle.blocks,
            gyms: bundle.gyms,
            restrictions: bundle.restrictions,
            profile: bundle.profile,
            exportedAt: bundle.exportedAt
        )
        csvFile = coordinator.exportSetsCSV(sessions: sessions)
    }

    @ViewBuilder
    private func shareButton(for file: DataExportFile?, title: String, icon: String) -> some View {
        if let file {
            ShareLink(
                item: ShareableFile(file: file),
                preview: SharePreview(file.fileName)
            ) {
                Label(title, systemImage: icon)
            }
        }
    }

    private func formatCount(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}

/// Envuelve un `DataExportFile` como `Transferable`.
struct ShareableFile: Transferable {
    let file: DataExportFile

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .item) { shareable in
            shareable.file.data
        } importing: { data in
            ShareableFile(file: DataExportFile(fileName: "imported", data: data, mimeType: "application/octet-stream"))
        }
    }
}

#Preview {
    ExportView(
        coordinator: DataExportCoordinator(),
        bundle: ExportBundle(
            schemaVersion: ExportBundleVersion.current,
            exportedAt: Date(),
            blocks: [],
            sessions: [],
            exercises: [],
            gyms: [],
            restrictions: [],
            profile: nil
        ),
        sessions: []
    )
}