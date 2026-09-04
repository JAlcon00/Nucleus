//
//  WorkoutComponents.swift
//  PR
//
//  Created by PR.
//
//  Componentes reutilizables del modo entrenamiento (SKILL §73): `PrimaryActionButton`
//  (botón primario grande), `SetInputControl` (peso/reps con [−] [+] y edición táctil,
//  SKILL §11/§12) y `RestTimerView` (descanso con skip/+30, SKILL §41). Vistas puras:
//  renderizan estado y envían intents; no contienen reglas de negocio.
//

import SwiftUI

// MARK: - PrimaryActionButton (SKILL §73)

/// Botón de acción primaria: grande, prominente, con valor por defecto (color no como
/// único indicador) y mínimo de 44pt de área táctil (SKILL §12).
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSpace.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint(title)
    }
}

// MARK: - SetInputControl (SKILL §11/§12)

/// Control editable de un valor numérico (peso o reps) con stepper grande [−] [+].
/// Soportaq edición por toque de teclado numérico y valores accesibles.
struct SetInputControl: View {
    let label: String
    @Binding var value: Double
    let step: Double
    let suffix: String

    @State private var isEditing = false
    @State private var text = ""

    private var formatted: String {
        if step >= 1 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.xs) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: DSpace.m) {
                Button {
                    value = max(0, value - step)
                } label: {
                    minusLabel
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reducir \(label.lowercased())")

                Button { presentEditor() } label: {
                    VStack(spacing: 0) {
                        Text((suffix.isEmpty ? formatted : "\(formatted) \(suffix)"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        if !suffix.isEmpty {
                            Text(suffix)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(formatted)")
                .accessibilityHint("Toca para editar con teclado numérico")

                Button {
                    value = value + step
                } label: {
                    plusLabel
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Aumentar \(label.lowercased())")
            }
            .tint(.secondary)

            if isEditing {
                textField
            }
        }
        .onChange(of: value) { _, newValue in
            text = displayValue(newValue)
        }
        .onAppear { text = displayValue(value) }
    }

    private var minusLabel: some View {
        Image(systemName: "minus")
            .font(.title3.weight(.bold))
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Rectangle())
    }

    private var plusLabel: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.bold))
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Rectangle())
    }

    private var textField: some View {
        TextField("Valor", text: $text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .font(.title3.monospacedDigit())
            .onSubmit { commit() }
            .onChange(of: text) { _, newValue in
                if let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                    value = parsed
                }
            }
    }

    private func presentEditor() {
        text = displayValue(value)
        isEditing = true
    }

    private func commit() {
        isEditing = false
        if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) {
            value = max(0, parsed)
        } else {
            text = displayValue(value)
        }
    }

    private func displayValue(_ newValue: Double) -> String {
        if newValue.rounded() == newValue {
            return "\(Int(newValue.rounded()))"
        }
        return String(format: "%.1f", newValue)
    }
}

// MARK: - RestTimerView (SKILL §41)

/// Vista del descanso: tiempo restante grande + "Skip" y "+30 sec". Sólo envía intents;
/// la cuenta la hace la vista con el reloj de la UI (no posesión de estado de negocio).
struct RestTimerView: View {
    /// Segundos restantes (computados por el owner contra `RestTimerState.remaining(at:)`).
    let remainingSeconds: Int
    let onSkip: () -> Void
    let onExtend: () -> Void

    private var minutes: Int { remainingSeconds / 60 }
    private var seconds: Int { remainingSeconds % 60 }
    private var text: String {
        String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: DSpace.l) {
            Text("Descanso")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Descanso \(minutes) minutos \(seconds) segundos")

            HStack(spacing: DSpace.m) {
                Button("Saltar", action: onSkip)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Termina el descanso ahora")
                Button("+30 s", action: onExtend)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Añade 30 segundos de descanso")
            }
            .frame(minHeight: 52)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

#Preview("Botón primario") {
    PrimaryActionButton("Completar serie", systemImage: "checkmark") {}
        .padding()
}

#Preview("Peso") {
    SetInputControl(label: "Peso", value: .constant(82.5), step: 2.5, suffix: "kg")
        .padding()
}

#Preview("Reps") {
    SetInputControl(label: "Repeticiones", value: .constant(8), step: 1, suffix: "")
        .padding()
}

#Preview("Descanso") {
    RestTimerView(remainingSeconds: 138, onSkip: {}, onExtend: {})
        .padding()
}