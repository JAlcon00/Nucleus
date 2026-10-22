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
            OnboardingCenteredScroll {
                VStack(spacing: DSpace.l) {
                    OnboardingHeader(
                        icon: "person.crop.circle",
                        eyebrow: "Antes de empezar",
                        title: "Cuéntanos de ti",
                        subtitle: "Con esto ajustamos tu plan. Toma menos de un minuto.",
                        titleIdentifier: "aboutYou.title"
                    )
                    .padding(.top, DSpace.l)
                    AboutYouFields(answer: answer, onChange: onChange)
                }
            }
            VStack(spacing: DSpace.s) {
                if !answer.isComplete {
                    OnboardingNote(text: "Completa los datos obligatorios para continuar.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                OnboardingPrimaryButton(
                    title: "Continuar",
                    icon: "chevron.right",
                    state: answer.isComplete ? .ready : .needsAnswer,
                    action: onContinue
                )
                .accessibilityIdentifier("aboutYou.continue")
            }
            .padding(.horizontal, DSpace.l)
            .padding(.vertical, DSpace.m)
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
    @FocusState private var focused: Focus?
    @ScaledMetric(relativeTo: .body) private var wheelHeight = DSize.wheelPicker
    /// Mismo ancho para los dos selectores de unidad (cm/ft-in y kg/lb): quedan alineados.
    @ScaledMetric(relativeTo: .body) private var unitWidth = DSize.unitPicker

    private enum Focus { case name, weight }

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.l) {
            OnboardingField(title: "Nombre", icon: "person.text.rectangle", optional: true, purpose: "Para saludarte. No sale de tu iPhone.") {
                TextField("Cómo quieres que te llamemos", text: binding(\.name))
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .name)
                    .onSubmit { focused = .weight }
                    .onboardingInput(isFocused: focused == .name)
                    .accessibilityIdentifier("aboutYou.name")
                issueText(for: .name)
            }

            OnboardingField(title: "Edad", icon: "birthday.cake", purpose: "Para saber si el plan es para ti y cuidar la progresión.") {
                Picker("Edad", selection: binding(\.age)) {
                    Text("Elige tu edad").tag(Int?.none)
                    ForEach(AboutYou.selectableAges, id: \.self) { age in
                        Text("\(age) años").tag(Int?.some(age))
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: wheelHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: DRadius.medium).strokeBorder(Color.hairline, lineWidth: 1)
                }
                .accessibilityIdentifier("aboutYou.age")
                issueText(for: .age)
            }

            OnboardingField(title: "Sexo", icon: "person.2", purpose: "Para cargas iniciales de referencia. Nunca cambia las reglas de seguridad.") {
                VStack(spacing: DSpace.s) {
                    ForEach(DeclaredSex.allCases, id: \.self) { sex in
                        sexOption(sex)
                    }
                }
            }

            OnboardingField(title: "Estatura", icon: "ruler", optional: true, purpose: "Contexto de tu perfil; hoy ningún cálculo la usa.") {
                HStack(spacing: DSpace.s) {
                    heightPicker
                    unitPicker("Unidad de estatura", selection: $heightInFeet, options: [(false, "cm"), (true, "ft/in")])
                        .accessibilityIdentifier("aboutYou.heightUnit")
                }
                issueText(for: .height)
            }

            OnboardingField(title: "Peso", icon: "scalemass", purpose: "Para ejercicios con tu peso corporal y las fases de definición o volumen.") {
                HStack(spacing: DSpace.s) {
                    TextField("Ej. 72.5", text: $weightText)
                        .keyboardType(.decimalPad)
                        .numericStyle()
                        .focused($focused, equals: .weight)
                        .onboardingInput(isFocused: focused == .weight)
                        .accessibilityLabel("Peso")
                        .accessibilityIdentifier("aboutYou.weight")
                    unitPicker("Unidad", selection: binding(\.weightUnit), options: [(LoadUnit.kilograms, "kg"), (LoadUnit.pounds, "lb")])
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

    /// Selector de unidad junto a un campo: segmentado, con el mismo alto que el campo.
    private func unitPicker<Value: Hashable>(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        options: [(Value, String)]
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].1).tag(options[index].0)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(width: unitWidth)
    }

    // MARK: Estatura

    /// Selector de estatura en cm o en pies y pulgadas; siempre registra centímetros.
    /// Menú con etiqueta propia: el texto arranca en el mismo margen que los demás campos.
    private var heightPicker: some View {
        Menu {
            if heightInFeet {
                Picker("Estatura", selection: inchesBinding) {
                    Text("Sin indicar").tag(Int?.none)
                    ForEach(AboutYou.selectableInches, id: \.self) { inches in
                        Text(Self.feetAndInches(inches)).tag(Int?.some(inches))
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
        } label: {
            HStack(spacing: DSpace.s) {
                heightText
                    .numericStyle()
                    .foregroundStyle(answer.heightCentimeters == nil ? Color.textSecondary : Color.textPrimary)
                Spacer(minLength: DSpace.s)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            .onboardingInput()
            .contentShape(RoundedRectangle(cornerRadius: DRadius.medium))
        }
        .accessibilityLabel("Estatura")
        .accessibilityValue(heightText)
        .accessibilityIdentifier("aboutYou.height")
    }

    /// Estatura elegida en la unidad del selector, o "Sin indicar".
    private var heightText: Text {
        guard let centimeters = answer.heightCentimeters else { return Text("Sin indicar") }
        if heightInFeet {
            return Text(Self.feetAndInches(AboutYou.inches(fromCentimeters: centimeters)))
        }
        return Text("\(centimeters) cm")
    }

    private static func feetAndInches(_ inches: Int) -> String {
        "\(inches / 12) ft \(inches % 12) in"
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
        OnboardingNote(text: text, tone: .warning)
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

    private func sexOption(_ sex: DeclaredSex) -> some View {
        OnboardingChoiceRow(title: Text(Self.label(sex)), icon: Self.icon(sex), isSelected: answer.sex == sex) {
            var copy = answer
            copy.sex = sex
            onChange(copy)
        }
        .accessibilityIdentifier("aboutYou.sex.\(sex.rawValue)")
    }

    private static func icon(_ sex: DeclaredSex) -> String {
        switch sex {
        case .male: "figure.stand"
        case .female: "figure.stand.dress"
        case .undisclosed: "hand.raised"
        }
    }

    static func label(_ sex: DeclaredSex) -> LocalizedStringKey {
        switch sex {
        case .male: "Hombre"
        case .female: "Mujer"
        case .undisclosed: "Prefiero no decir"
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
