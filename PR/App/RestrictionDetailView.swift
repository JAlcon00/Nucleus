//
//  RestrictionDetailView.swift
//  PR
//
//  SCRUM-36: una restricción. En vigor se puede editar, evitar un ejercicio concreto,
//  permitir uno (sólo con indicación profesional) y resolverla ("Ya no me molesta", siempre
//  confirmando). Del historial sólo se lee. Lo que se confirma y los avisos los decide
//  `RestrictionScreenModel`; aquí sólo hay estado de presentación. Nunca diagnostica.
//

import SwiftUI
import PRCore
import PRDomain

struct RestrictionDetailView: View {
    let model: RestrictionScreenModel
    let id: RestrictionID

    /// A qué lista se agrega el ejercicio que se elija.
    private enum Picking: Identifiable {
        case avoid, allow
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var picking: Picking?
    /// Intención que espera confirmación, con su texto.
    @State private var pending: (copy: RestrictionCopy, retry: () async -> RestrictionScreenModel.Result)?
    @State private var failure: String?
    @State private var resolvedFeedback = false

    var body: some View {
        Group {
            if let item = model.item(id) {
                content(item)
            } else {
                ContentUnavailableView("Ya no está", systemImage: "list.bullet.clipboard")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(model.item(id)?.region ?? "")
        .alert(pending?.copy.title ?? "", isPresented: isConfirming) {
            if let pending {
                let retry = pending.retry
                Button(pending.copy.confirm) { Task { handle(await retry()) } }
                    .accessibilityIdentifier("restrictions.confirm")
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(pending?.copy.message ?? "")
        }
        .alert("No se guardó", isPresented: isFailing, presenting: failure) { _ in
            Button("Entendido", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sensoryFeedback(.success, trigger: resolvedFeedback)
    }

    private func content(_ item: RestrictionListItem) -> some View {
        List {
            Section {
                summary(item)
            }
            .listRowBackground(Color.surface)

            if item.isEditable || !item.avoided.isEmpty {
                Section {
                    ForEach(item.avoided) { line in
                        exerciseRow(line, item: item, removable: item.isEditable)
                    }
                    if item.isEditable {
                        Button {
                            picking = .avoid
                        } label: {
                            Label("Evitar un ejercicio", systemImage: "nosign")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("restrictions.avoid")
                    }
                } header: {
                    Text("También evita")
                } footer: {
                    Text("Además de lo que carga la zona, tu plan no programará estos ejercicios.")
                }
                .listRowBackground(Color.surface)
            }

            if item.canAllowExercises || !item.allowed.isEmpty {
                Section {
                    ForEach(item.allowed) { line in
                        exerciseRow(line, item: item, removable: item.isEditable)
                    }
                    if item.canAllowExercises {
                        Button {
                            picking = .allow
                        } label: {
                            Label("Permitir un ejercicio", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("restrictions.allow")
                    }
                } header: {
                    Text("Permitidos por tu profesional")
                } footer: {
                    Text("Sólo si te lo indicaron. Nunca anulan otra restricción.")
                }
                .listRowBackground(Color.surface)
            }

            if item.isEditable {
                Section {
                    Button {
                        editing = true
                    } label: {
                        Label("Editar lado, origen, revisión o nota", systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("restrictions.edit")

                    Button {
                        Task { await run { await model.resolve(item.id, confirmed: $0) } }
                    } label: {
                        Label("Ya no me molesta", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("restrictions.resolve")
                } footer: {
                    Text("Al resolverla, tu plan vuelve a incluir lo que carga la zona y queda en tu historial.")
                }
                .listRowBackground(Color.surface)
            }
        }
        .sheet(isPresented: $editing) {
            RestrictionFormSheet(model: model, editing: item, draft: RestrictionFormDraft(editing: item, now: Date()))
        }
        .sheet(item: $picking) { picking in
            RestrictionExercisePicker(
                model: model,
                title: picking == .avoid ? "Evitar un ejercicio" : "Permitir un ejercicio"
            ) { exercise in
                Task {
                    switch picking {
                    case .avoid: await run { await model.avoid(exercise, in: item.id, confirmed: $0) }
                    case .allow: await run { await model.allow(exercise, in: item.id, confirmed: $0) }
                    }
                }
            }
        }
    }

    private func summary(_ item: RestrictionListItem) -> some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            if let side = item.side {
                Text(side).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            Label {
                Text(item.source).foregroundStyle(Color.textSecondary)
            } icon: {
                Image(systemName: RestrictionSymbols.source(item.sourceKind)).foregroundStyle(Color.textSecondary)
            }
            Label {
                Text(item.resolved ?? item.status).foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: RestrictionSymbols.status(item.statusKind)).foregroundStyle(RestrictionSymbols.color(item.statusKind))
            }
            if let review = item.review {
                Label {
                    Text(review).foregroundStyle(Color.textSecondary)
                } icon: {
                    Image(systemName: "calendar").foregroundStyle(Color.textSecondary)
                }
            }
            if let note = item.note {
                Label {
                    Text(note).foregroundStyle(Color.textSecondary)
                } icon: {
                    Image(systemName: "text.quote").foregroundStyle(Color.textSecondary)
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, DSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("restrictions.detail")
    }

    private func exerciseRow(_ line: RestrictionExerciseLine, item: RestrictionListItem, removable: Bool) -> some View {
        HStack {
            Text(line.name).foregroundStyle(Color.textPrimary)
            Spacer()
            if removable {
                Button {
                    Task { await run { await model.remove(line.id, from: item.id, confirmed: $0) } }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
                .accessibilityLabel(Text("Quitar \(line.name)"))
            }
        }
    }

    /// Envía la intención sin confirmar; si hace falta confirmar, la guarda para repetirla
    /// confirmada desde la alerta.
    private func run(_ intent: @escaping (_ confirmed: Bool) async -> RestrictionScreenModel.Result) async {
        let result = await intent(false)
        if case .needsConfirmation(let copy) = result {
            pending = (copy, { await intent(true) })
        } else {
            handle(result)
        }
    }

    private func handle(_ result: RestrictionScreenModel.Result) {
        switch result {
        case .done:
            // Resuelta: pasa al historial y se vuelve a la lista.
            if model.item(id)?.isEditable == false {
                resolvedFeedback.toggle()
                dismiss()
            }
        case .needsConfirmation, .openExisting:
            break
        case .failed(let message):
            failure = message
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var isFailing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
