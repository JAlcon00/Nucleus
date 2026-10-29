//
//  RestrictionFormSheet.swift
//  PR
//
//  SCRUM-36: agregar una restricción (zona, lado, origen, fecha de revisión y nota) o
//  editar una existente (todo menos la zona: para otra zona se resuelve y se agrega otra).
//  Si la zona elegida ya está en vigor se abre esa en vez de duplicarla. Con origen
//  profesional se confirma antes de guardar (RN-020). Lo que decide (confirmar, abrir la
//  existente, avisos) viene de `RestrictionScreenModel`; aquí sólo hay estado del formulario.
//

import SwiftUI
import PRCore
import PRDomain

/// Lo que se está escribiendo en el formulario (estado de la vista, sin reglas).
struct RestrictionFormDraft: Equatable {
    var region: BodyRegion?
    var side: BodySide?
    var professional = false
    var hasReview = false
    var reviewDate: Date
    var notes = ""

    /// Vacío para agregar; con lo guardado para editar. La revisión propuesta es en dos semanas.
    init(editing: RestrictionListItem?, now: Date) {
        let details = editing?.details
        region = editing?.bodyRegion
        side = details?.side
        professional = details?.source == .professionalGuidance
        hasReview = details?.reviewDate != nil
        reviewDate = details?.reviewDate ?? now.addingTimeInterval(14 * 86_400)
        notes = details?.notes ?? ""
    }

    var details: RestrictionDetails {
        RestrictionDetails(
            side: side,
            source: professional ? .professionalGuidance : .userReported,
            reviewDate: hasReview ? reviewDate : nil,
            notes: notes
        )
    }
}

struct RestrictionFormSheet: View {
    let model: RestrictionScreenModel
    /// `nil` = agregar; si no, la restricción que se edita.
    let editing: RestrictionListItem?
    @State var draft: RestrictionFormDraft
    /// La zona elegida ya tenía una restricción en vigor: se abre esa.
    var onOpenExisting: (RestrictionID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: RestrictionCopy?
    @State private var failure: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil { zoneSection }
                Section {
                    Picker("Lado", selection: $draft.side) {
                        Text("Sin indicar").tag(BodySide?.none)
                        Text("Izquierdo").tag(BodySide?.some(.left))
                        Text("Derecho").tag(BodySide?.some(.right))
                        Text("Ambos").tag(BodySide?.some(.bilateral))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("restrictions.form.side")
                } header: {
                    Text("Lado")
                } footer: {
                    Text("Se guarda para ti; tu plan cuida la zona en los dos lados.")
                }

                Section {
                    Toggle("Me lo indicó un profesional de la salud", isOn: $draft.professional)
                        .accessibilityIdentifier("restrictions.form.professional")
                } footer: {
                    Text("Si lo marcas, te pediremos confirmar antes de guardar.")
                }

                Section {
                    Toggle("Fecha de revisión", isOn: $draft.hasReview.animation())
                    if draft.hasReview {
                        DatePicker("Revisar el", selection: $draft.reviewDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Al llegar la fecha te pediremos revisarla. Mientras, tu plan la sigue cuidando.")
                }

                Section {
                    TextField("Opcional", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("restrictions.form.note")
                } header: {
                    Text("Nota")
                } footer: {
                    Text("\(draft.notes.count)/\(RestrictionDetails.maxNoteLength) · Solo para ti: no cambia tu plan ni se comparte con la IA.")
                        .monospacedDigit()
                        .foregroundStyle(draft.notes.count > RestrictionDetails.maxNoteLength ? Color.warning : Color.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(editing.map { Text($0.region) } ?? Text("Agregar restricción"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save(confirmed: false) } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("restrictions.form.save")
                }
            }
            .alert(confirmation?.title ?? "", isPresented: isConfirming, presenting: confirmation) { copy in
                Button(copy.confirm) { Task { await save(confirmed: true) } }
                    .accessibilityIdentifier("restrictions.confirm")
                Button("Cancelar", role: .cancel) {}
            } message: { copy in
                Text(copy.message)
            }
            .alert("No se guardó", isPresented: isFailing, presenting: failure) { _ in
                Button("Entendido", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private var zoneSection: some View {
        Section {
            ForEach(model.zones) { zone in
                Button {
                    if let existing = zone.existing {
                        dismiss()
                        onOpenExisting(existing)
                    } else {
                        draft.region = zone.region
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: DSpace.xs) {
                            Text(zone.name).foregroundStyle(Color.textPrimary)
                            if zone.existing != nil {
                                Text("Ya la tienes: ábrela para editarla")
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                        if draft.region == zone.region {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.primaryAction)
                                .accessibilityHidden(true)
                        } else if zone.existing != nil {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(draft.region == zone.region ? .isSelected : [])
                .accessibilityIdentifier("restrictions.zone.\(zone.region.rawValue)")
            }
        } header: {
            Text("Zona")
        } footer: {
            Text("Tu plan evitará lo que más suele cargar la zona.")
        }
    }

    private var canSave: Bool {
        !model.isSaving && (editing != nil || draft.region != nil) && draft.notes.count <= RestrictionDetails.maxNoteLength
    }

    private func save(confirmed: Bool) async {
        let result: RestrictionScreenModel.Result
        if let editing {
            result = await model.update(editing.id, details: draft.details, confirmed: confirmed)
        } else if let region = draft.region {
            result = await model.add(region, details: draft.details, confirmed: confirmed)
        } else {
            return
        }
        switch result {
        case .done:
            saved.toggle()
            dismiss()
        case .needsConfirmation(let copy):
            confirmation = copy
        case .openExisting(let existing):
            dismiss()
            onOpenExisting(existing)
        case .failed(let message):
            failure = message
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var isFailing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}

#Preview("Agregar") {
    RestrictionFormSheet(
        model: RestrictionPreviewData.model(RestrictionPreviewData.profile), editing: nil,
        draft: RestrictionFormDraft(editing: nil, now: RestrictionPreviewData.now)
    )
        .ironEnergyTheme()
}

#Preview("Agregar · oscuro · accessibility3") {
    RestrictionFormSheet(
        model: RestrictionPreviewData.model(RestrictionPreviewData.profile), editing: nil,
        draft: RestrictionFormDraft(editing: nil, now: RestrictionPreviewData.now)
    )
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
