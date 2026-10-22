//
//  ExportView.swift
//  PR
//
//  Created by PR.
//
//  Pantalla de export con historial (PR-0204, SCRUM-23). Muestra el conteo real de
//  sesiones guardadas, avisa de registros ilegibles y ofrece compartir JSON y CSV
//  (user-controlled, `ShareLink`). Los archivos los construye `DataExportCoordinator`;
//  si el JSON no se puede generar (p. ej. el guard de secretos lo rechaza) se dice,
//  nunca se oculta. Sin reglas de negocio.
//

import SwiftUI
import UniformTypeIdentifiers
import PRCore
import PRDomain

struct ExportView: View {
    let sessions: [WorkoutSessionRecord]
    let exercises: [Exercise]
    let unreadableCount: Int

    private let coordinator = DataExportCoordinator()

    /// Archivos de export (se construyen una vez al aparecer).
    private enum Files {
        case preparing
        case ready(json: DataExportFile?, csv: DataExportFile)
    }

    @State private var files: Files = .preparing

    var body: some View {
        List {
            Section("Historial de entrenamiento") {
                Label {
                    sessionCount
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
                if unreadableCount > 0 {
                    UnreadableRecordsNotice(count: unreadableCount)
                }
            }

            Section("Exportar") {
                switch files {
                case .preparing:
                    ProgressView("Preparando archivos…")
                case .ready(let json, let csv):
                    if let json {
                        shareLink(json, title: "JSON completo", icon: "doc.richtext")
                    } else {
                        Label("No se pudo preparar el JSON.", systemImage: "exclamationmark.triangle")
                    }
                    shareLink(csv, title: "Series (CSV)", icon: "tablecells")
                }
            }
        }
        .task { buildFiles() }
    }

    private var sessionCount: Text {
        sessions.count == 1 ? Text("1 sesión") : Text("\(sessions.count) sesiones")
    }

    private func buildFiles() {
        let json: DataExportFile?
        do {
            json = try coordinator.exportJSON(
                sessions: sessions,
                exercises: exercises,
                blocks: [],
                gyms: [],
                restrictions: [],
                profile: nil
            )
        } catch {
            json = nil
        }
        files = .ready(json: json, csv: coordinator.exportSetsCSV(sessions: sessions))
    }

    private func shareLink(_ file: DataExportFile, title: LocalizedStringKey, icon: String) -> some View {
        ShareLink(item: ShareableFile(file: file), preview: SharePreview(file.fileName)) {
            Label(title, systemImage: icon)
        }
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

// MARK: - Previews

private func previewSessions(_ count: Int) -> [WorkoutSessionRecord] {
    (0..<count).map { index in
        WorkoutSessionRecord(
            startedAt: Date(timeIntervalSinceReferenceDate: Double(index) * 86_400),
            lifecycle: .completed
        )
    }
}

#Preview("2 sesiones") {
    NavigationStack {
        ExportView(sessions: previewSessions(2), exercises: [], unreadableCount: 0)
            .navigationTitle("Exportar datos")
    }
}

#Preview("1 sesión + ilegible · oscuro") {
    NavigationStack {
        ExportView(sessions: previewSessions(1), exercises: [], unreadableCount: 1)
            .navigationTitle("Exportar datos")
    }
    .preferredColorScheme(.dark)
}

#Preview("3 sesiones · accessibility3") {
    NavigationStack {
        ExportView(sessions: previewSessions(3), exercises: [], unreadableCount: 2)
            .navigationTitle("Exportar datos")
    }
    .dynamicTypeSize(.accessibility3)
}
