//
//  AboutYouViews.swift
//  PR
//
//  Created by PR.
//
//  "Sobre ti" (SCRUM-198, U5): la pantalla "Cuéntanos de ti" antes del cuestionario, el
//  formulario compartido con Perfil y la hoja para editarlo. Cada dato dice para qué se
//  usa (minimización de datos). Vistas puras: editan un `AboutYouAnswer`; qué es válido
//  (edad ≥ 18, sexo, peso) lo decide el dominio. Los datos se guardan sólo en el iPhone.
//

import SwiftUI
import PRCore
import PRDomain

// MARK: - Pantalla del cuestionario

struct AboutYouView: View {
    let answer: AboutYouAnswer
    let onChange: (AboutYouAnswer) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text("Cuéntanos de ti")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("aboutYou.title")
                Text("Con esto ajustamos tu plan. Toma menos de un minuto.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, DSpace.l)
            .padding(.top, DSpace.m)
            .padding(.bottom, DSpace.s)
            ScrollView {
                AboutYouFields(answer: answer, onChange: onChange)
                    .padding(.horizontal, DSpace.l)
                    .padding(.vertical, DSpace.s)
            }
            .scrollDismissesKeyboard(.interactively)
            Button(action: onContinue) {
                Label("Continuar", systemImage: "chevron.right")
            }
            .buttonStyle(.energy)
            .disabled(!answer.isComplete)
            .padding(.horizontal, DSpace.l)
            .padding(.vertical, DSpace.m)
            .accessibilityIdentifier("aboutYou.continue")
        }
        .screenBackground()
    }
}

// MARK: - Formulario compartido

struct AboutYouFields: View {
    let answer: AboutYouAnswer
    let onChange: (AboutYouAnswer) -> Void

    @State private var weightText = ""
    /// Unidad de la estatura en el selector (se guarda siempre en cm). Por defecto, la de la región.
    @State private var heightInFeet = Locale.current.measurementSystem == .us
    @ScaledMetric(relativeTo: .body) private var wheelHeight = DSize.wheelPicker

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.l) {
            field("Nombre", optional: true, purpose: "Para saludarte. No sale de tu iPhone.") {
                TextField("Cómo quieres que te llamemos", text: binding(\.name))
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .inputSurface()
                    .accessibilityIdentifier("aboutYou.name")
                issueText(for: .name)
            }

            field("Edad", purpose: "Para saber si el plan es para ti y cuidar la progresión.") {
                Picker("Edad", selection: binding(\.age)) {
                    Text("Elige tu edad").tag(Int?.none)
                    ForEach(AboutYou.selectableAges, id: \.self) { age in
                        Text("\(age) años").tag(Int?.some(age))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: wheelHeight)
                .accessibilityIdentifier("aboutYou.age")
                issueText(for: .age)
            }

            field("Sexo", purpose: "Para cargas iniciales de referencia. Nunca cambia las reglas de seguridad.") {
                VStack(spacing: DSpace.s) {
                    ForEach(DeclaredSex.allCases, id: \.self) { sex in
                        sexOption(sex)
                    }
                }
            }

            field("Estatura", optional: true, purpose: "Contexto de tu perfil; hoy ningún cálculo la usa.") {
                HStack(spacing: DSpace.s) {
                    heightPicker
                    Picker("Unidad de estatura", selection: $heightInFeet) {
                        Text("cm").tag(false)
                        Text("ft/in").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("aboutYou.heightUnit")
                }
                issueText(for: .height)
            }

            field("Peso", purpose: "Para ejercicios con tu peso corporal y las fases de definición o volumen.") {
                HStack(spacing: DSpace.s) {
                    TextField("Ej. 72.5", text: $weightText)
                        .keyboardType(.decimalPad)
                        .numericStyle()
                        .inputSurface()
                        .accessibilityLabel("Peso")
                        .accessibilityIdentifier("aboutYou.weight")
                    Picker("Unidad", selection: binding(\.weightUnit)) {
                        Text("kg").tag(LoadUnit.kilograms)
                        Text("lb").tag(LoadUnit.pounds)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("aboutYou.weightUnit")
                }
                if weightTextIsUnreadable {
                    issueLabel("Escribe tu peso con números, por ejemplo 72.5.", identifier: "aboutYou.issue.weight")
                } else {
                    issueText(for: .weight)
                }
            }

            Label("Se guarda solo en tu iPhone. Puedes cambiarlo en Perfil.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
        .onAppear {
            if weightText.isEmpty, let weight = answer.weight {
                weightText = weight.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
            }
        }
        .onChange(of: weightText) { _, text in
            var copy = answer
            copy.weight = Double(text.replacingOccurrences(of: ",", with: "."))
            onChange(copy)
        }
    }

    // MARK: Estatura

    /// Selector de estatura en cm o en pies y pulgadas; siempre registra centímetros.
    @ViewBuilder
    private var heightPicker: some View {
        Group {
            if heightInFeet {
                Picker("Estatura", selection: inchesBinding) {
                    Text("Sin indicar").tag(Int?.none)
                    ForEach(AboutYou.selectableInches, id: \.self) { inches in
                        Text("\(inches / 12) ft \(inches % 12) in").tag(Int?.some(inches))
                    }
                }
            } else {
                Picker("Estatura", selection: binding(\.heightCentimeters)) {
                    Text("Sin indicar").tag(Int?.none)
                    ForEach(AboutYou.heightCentimetersRange, id: \.self) { height in
                        Text("\(height) cm").tag(Int?.some(height))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .tint(Color.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inputSurface()
        .accessibilityIdentifier("aboutYou.height")
    }

    /// Pulgadas ↔ centímetros guardados (la conversión es del dominio).
    private var inchesBinding: Binding<Int?> {
        Binding(
            get: { answer.heightCentimeters.map(AboutYou.inches(fromCentimeters:)) },
            set: { inches in
                var copy = answer
                copy.heightCentimeters = inches.map(AboutYou.centimeters(fromInches:))
                onChange(copy)
            }
        )
    }

    // MARK: Problemas junto a su campo (SCRUM-198)

    private enum Field { case name, age, height, weight }

    /// El texto escrito no es un número (el campo no llega a registrar un peso).
    private var weightTextIsUnreadable: Bool {
        let trimmed = weightText.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && Double(trimmed.replacingOccurrences(of: ",", with: ".")) == nil
    }

    @ViewBuilder
    private func issueText(for field: Field) -> some View {
        ForEach(Array(answer.issues.enumerated()), id: \.offset) { _, issue in
            let message = Self.message(for: issue)
            if message.field == field {
                issueLabel(message.text, identifier: message.identifier)
            }
        }
    }

    /// Campo y texto de cada problema (exhaustivo: un problema nuevo obliga a explicarlo).
    private static func message(for issue: AboutYouIssue) -> (field: Field, text: LocalizedStringKey, identifier: String) {
        switch issue {
        case .nameTooLong(let maximum):
            return (.name, "Usa como máximo \(maximum) caracteres.", "aboutYou.issue.name")
        case .underMinimumAge(let minimum):
            return (
                .age,
                "Por ahora Nucleus es para mayores de \(minimum) años: el motor de entrenamiento no está validado para menores, así que no armaremos un plan.",
                "aboutYou.underage"
            )
        case .heightOutOfRange(let range):
            return (.height, "Elige una estatura entre \(range.lowerBound) y \(range.upperBound) cm.", "aboutYou.issue.height")
        case .weightOutOfRange(let range, let unit):
            let unitText = unit == .pounds ? "lb" : "kg"
            return (
                .weight,
                "Escribe un peso entre \(number(range.lowerBound)) y \(number(range.upperBound)) \(unitText).",
                "aboutYou.issue.weight"
            )
        }
    }

    private func issueLabel(_ text: LocalizedStringKey, identifier: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(Color.warning)
            .accessibilityIdentifier(identifier)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AboutYouAnswer, Value>) -> Binding<Value> {
        Binding(
            get: { answer[keyPath: keyPath] },
            set: { newValue in
                var copy = answer
                copy[keyPath: keyPath] = newValue
                onChange(copy)
            }
        )
    }

    private func field<Content: View>(
        _ title: LocalizedStringKey,
        optional: Bool = false,
        purpose: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                if optional {
                    Text("Opcional")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            content()
            Text(purpose)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func sexOption(_ sex: DeclaredSex) -> some View {
        let isSelected = answer.sex == sex
        return Button {
            var copy = answer
            copy.sex = sex
            onChange(copy)
        } label: {
            HStack {
                Text(Self.label(sex))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.primaryAction)
                }
            }
            .padding(DSpace.m)
            .frame(minHeight: DSize.dayChip)
            .background(RoundedRectangle(cornerRadius: DRadius.small).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: DRadius.small)
                    .strokeBorder(isSelected ? Color.primaryAction : Color.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Self.label(sex)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("aboutYou.sex.\(sex.rawValue)")
    }

    static func label(_ sex: DeclaredSex) -> LocalizedStringKey {
        switch sex {
        case .male: "Hombre"
        case .female: "Mujer"
        case .undisclosed: "Prefiero no decir"
        }
    }
}

private extension View {
    /// Campo de entrada sobre superficie elevada (texto primario: 13.7:1).
    func inputSurface() -> some View {
        padding(DSpace.m)
            .frame(minHeight: DSize.dayChip)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DRadius.small)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Edición (Perfil y aviso de Hoy)

/// Hoja para completar o editar "Sobre ti". Guarda sólo si el dominio lo acepta.
struct AboutYouEditSheet: View {
    @State var answer: AboutYouAnswer
    let onSave: (AboutYouAnswer) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSpace.m) {
                    AboutYouFields(answer: answer, onChange: { answer = $0 })
                    if saveFailed {
                        Label("No se pudo guardar. Intenta de nuevo.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Color.warning)
                    }
                }
                .padding(DSpace.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Sobre ti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saving = true
                        Task {
                            let saved = await onSave(answer)
                            saving = false
                            if saved { dismiss() } else { saveFailed = true }
                        }
                    }
                    .disabled(!answer.isComplete || saving)
                    .accessibilityIdentifier("aboutYou.save")
                }
            }
        }
        .ironEnergyTheme()
    }
}

// MARK: - Previews

#Preview("Vacío") {
    AboutYouView(answer: AboutYouAnswer(), onChange: { _ in }, onContinue: {})
        .ironEnergyTheme()
}

#Preview("Menor de 18") {
    AboutYouView(answer: AboutYouAnswer(age: 17, sex: .male, weight: 65), onChange: { _ in }, onContinue: {})
        .ironEnergyTheme()
}

#Preview("Peso fuera de rango") {
    AboutYouView(answer: AboutYouAnswer(age: 30, sex: .male, weight: 450), onChange: { _ in }, onContinue: {})
        .ironEnergyTheme()
}

#Preview("Completo · accessibility3") {
    AboutYouView(
        answer: AboutYouAnswer(name: "Ana", age: 34, sex: .female, heightCentimeters: 165, weight: 61.5),
        onChange: { _ in },
        onContinue: {}
    )
    .dynamicTypeSize(.accessibility3)
    .ironEnergyTheme()
}
