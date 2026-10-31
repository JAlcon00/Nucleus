//
//  WorkoutComponents.swift
//  PR
//
//  Created by PR.
//
//  Componentes reutilizables del modo entrenamiento (SKILL §73): `PrimaryActionButton`
//  (botón primario grande), `SetInputControl` (peso/reps con [−] [+] y edición táctil,
//  SKILL §11/§12), `RestTimerView` (descanso con skip/+30, SKILL §41) y `SupersetTag`
//  (la serie va en superset, SCRUM-224). Vistas puras: renderizan estado y envían
//  intents; no contienen reglas de negocio.
//

import SwiftUI
import PRCore

// MARK: - PrimaryActionButton (SKILL §73)

/// Botón de acción primaria: grande, prominente, con valor por defecto (color no como
/// único indicador) y mínimo de 44pt de área táctil (SKILL §12).
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String?
    let identifier: String?
    let action: () -> Void

    /// `identifier` es el `accessibilityIdentifier` que usan las pruebas de UI.
    init(_ title: String, systemImage: String? = nil, identifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
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
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.energy)
        .accessibilityHint(title)
        .accessibilityIdentifier(identifier ?? "")
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
                .eyebrowStyle()
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: DSpace.m) {
                Button {
                    value = max(0, value - step)
                } label: {
                    minusLabel
                }
                .buttonStyle(SurfaceButtonStyle(minHeight: DSize.stepperButton, fillsWidth: false))
                .accessibilityLabel("Reducir \(label.lowercased())")

                Button { presentEditor() } label: {
                    VStack(spacing: 0) {
                        Text((suffix.isEmpty ? formatted : "\(formatted) \(suffix)"))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        if !suffix.isEmpty {
                            Text(suffix)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
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
                .buttonStyle(SurfaceButtonStyle(minHeight: DSize.stepperButton, fillsWidth: false))
                .accessibilityLabel("Aumentar \(label.lowercased())")
            }

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
    }

    private var plusLabel: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.bold))
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

    @ScaledMetric(relativeTo: .largeTitle) private var digitsSize = DSize.timerDigits

    private var minutes: Int { remainingSeconds / 60 }
    private var seconds: Int { remainingSeconds % 60 }
    private var text: String {
        String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: DSpace.l) {
            Text("Descanso")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)

            Text(text)
                .font(.system(size: digitsSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Descanso \(minutes) minutos \(seconds) segundos")

            HStack(spacing: DSpace.m) {
                Button("Saltar", action: onSkip)
                    .buttonStyle(.surface)
                    .accessibilityHint("Termina el descanso ahora")
                Button("+30 s", action: onExtend)
                    .buttonStyle(.surface)
                    .accessibilityHint("Añade 30 segundos de descanso")
            }
            .padding(.horizontal, DSpace.l)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - SupersetTag (SCRUM-224)

/// La serie va en superset: de qué lado del par (A1/A2) y con quién se alterna. El ícono y
/// el texto dicen lo mismo, así el color nunca va solo (primaryAction mide 5.51:1 sobre el
/// fondo oscuro y 5.09:1 sobre el claro).
struct SupersetTag: View {
    let superset: ActiveSupersetUI

    var body: some View {
        VStack(spacing: DSpace.xs) {
            Label(superset.isFirst ? "SUPERSET · A1" : "SUPERSET · A2", systemImage: "arrow.left.arrow.right")
                .eyebrowStyle()
                .foregroundStyle(Color.primaryAction)
            Text("Alterna con \(superset.partnerName); descansas después de los dos.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.superset")
    }
}

// MARK: - Previews

#Preview("Botón primario") {
    PrimaryActionButton("Completar serie", systemImage: "checkmark") {}
        .padding()
        .screenBackground()
        .ironEnergyTheme()
}

#Preview("Peso") {
    SetInputControl(label: "Peso", value: .constant(82.5), step: 2.5, suffix: "kg")
        .padding()
        .screenBackground()
        .ironEnergyTheme()
}

#Preview("Reps · accessibility3") {
    SetInputControl(label: "Repeticiones", value: .constant(8), step: 1, suffix: "")
        .padding()
        .screenBackground()
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Descanso") {
    RestTimerView(remainingSeconds: 138, onSkip: {}, onExtend: {})
        .padding()
        .screenBackground()
        .ironEnergyTheme()
}

#Preview("Superset · A1") {
    SupersetTag(superset: ActiveSupersetUI(isFirst: true, partnerName: "Extensión de tríceps en polea"))
        .padding()
        .screenBackground()
        .ironEnergyTheme()
}

#Preview("Superset · A2 · oscuro · accessibility3") {
    SupersetTag(superset: ActiveSupersetUI(isFirst: false, partnerName: "Curl con barra"))
        .padding()
        .screenBackground()
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
        .preferredColorScheme(.dark)
}
