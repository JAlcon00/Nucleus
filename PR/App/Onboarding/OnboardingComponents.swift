//
//  OnboardingComponents.swift
//  PR
//
//  Created by PR.
//
//  Piezas compartidas del formulario inicial ("Sobre ti" y los pasos del cuestionario):
//  cabecera con icono, indicador de pasos, campo estándar, opción seleccionable y pie con
//  sus estados. Todas usan los mismos tokens para que los campos queden alineados y con
//  el mismo alto. El icono acompaña al texto; nunca lo sustituye (VoiceOver lee el texto).
//  Sólo presentan: qué es válido lo decide el dominio.
//

import SwiftUI
import PRDomain

// MARK: - Indicador de pasos

/// Estado de un paso en el indicador. El color no es lo único que lo distingue: el paso
/// actual es más ancho y la cabecera dice "Paso X de N".
enum OnboardingStepStatus {
    case done, current, pending
}

/// Barra segmentada: pasos hechos, el actual (más ancho, con el degradado) y los que faltan.
struct OnboardingProgressBar: View {
    /// Paso actual, empezando en 1.
    let current: Int
    let total: Int

    @ScaledMetric(relativeTo: .caption) private var segmentHeight = DSize.progressSegment

    var body: some View {
        HStack(spacing: DSpace.xs) {
            ForEach(1...max(total, 1), id: \.self) { index in
                segment(Self.status(of: index, current: current))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso del cuestionario")
        .accessibilityValue("Paso \(current) de \(total)")
    }

    @ViewBuilder
    private func segment(_ status: OnboardingStepStatus) -> some View {
        switch status {
        case .done:
            Capsule().fill(Color.primaryAction).frame(height: segmentHeight)
        case .current:
            Capsule().fill(LinearGradient.energy).frame(height: segmentHeight)
                .layoutPriority(1)
                .frame(minWidth: segmentHeight * 6)
        case .pending:
            Capsule().fill(Color.surfaceElevated).frame(height: segmentHeight)
        }
    }

    static func status(of index: Int, current: Int) -> OnboardingStepStatus {
        if index < current { return .done }
        if index == current { return .current }
        return .pending
    }
}

// MARK: - Cabecera

/// Cabecera centrada de cada pantalla del formulario: icono del paso, "Paso X de N",
/// título y ayuda. El indicador de pasos va aparte, fijo arriba (`OnboardingProgressBar`).
struct OnboardingHeader: View {
    let icon: String
    /// "Paso 2 de 8" o "Antes de empezar".
    let eyebrow: String
    let title: String
    let subtitle: String?
    var titleIdentifier: String

    @ScaledMetric(relativeTo: .title2) private var badge = DSize.iconBadge

    var body: some View {
        VStack(spacing: DSpace.s) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.primaryAction)
                .frame(width: badge * 2, height: badge * 2)
                .background(Color.surfaceElevated, in: Circle())
                .overlay { Circle().strokeBorder(Color.hairline, lineWidth: 1) }
                .padding(.bottom, DSpace.s)
                .accessibilityHidden(true)
            Text(eyebrow)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .numericStyle()
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// Contenido de un paso centrado en vertical: si cabe, queda a media pantalla (sin un
/// hueco grande abajo); si no cabe, se desplaza normal.
struct OnboardingCenteredScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, DSpace.l)
                    .padding(.vertical, DSpace.m)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Campo estándar

/// Campo del formulario: icono + título (+ "Opcional"), el control y para qué se usa.
/// Los iconos van en una columna fija para que todos los títulos empiecen en la misma línea.
struct OnboardingField<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    var optional = false
    let purpose: LocalizedStringKey
    @ViewBuilder let content: Content

    @ScaledMetric(relativeTo: .headline) private var iconColumn = DSize.fieldIcon

    var body: some View {
        VStack(alignment: .leading, spacing: DSpace.s) {
            HStack(spacing: DSpace.s) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Color.primaryAction)
                    .frame(width: iconColumn)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Spacer(minLength: DSpace.s)
                if optional {
                    Text("Opcional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, DSpace.s)
                        .padding(.vertical, DSpace.xs)
                        .background(Color.surfaceElevated, in: Capsule())
                }
            }
            content
            Text(purpose)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Superficie de un control del formulario: mismo alto, radio y borde en todos.
    /// Con `isFocused` el borde toma el acento (el foco también lo marca el cursor).
    func onboardingInput(isFocused: Bool = false) -> some View {
        padding(.horizontal, DSpace.m)
            .frame(minHeight: DSize.inputHeight)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: DRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: DRadius.medium)
                    .strokeBorder(isFocused ? Color.primaryAction : Color.hairline, lineWidth: isFocused ? 2 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Opción seleccionable

/// Fila de opción única (objetivo, fase, sexo…). Elegida: borde y fondo con el acento,
/// palomita rellena y trait `.isSelected`; sin elegir: círculo vacío. Háptico al elegir.
struct OnboardingChoiceRow: View {
    let title: Text
    let icon: String?
    /// Nivel para símbolos de valor variable (p. ej. barras de experiencia).
    var level: Double?
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var badge = DSize.iconBadge

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSpace.m) {
                if let icon {
                    Image(systemName: icon, variableValue: level)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.onAccent : Color.primaryAction)
                        .frame(width: badge, height: badge)
                        .background {
                            Circle().fill(isSelected ? AnyShapeStyle(LinearGradient.energy) : AnyShapeStyle(Color.surfaceElevated))
                        }
                        .accessibilityHidden(true)
                }
                title
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.primaryAction : Color.secondaryAction)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DSpace.m)
            .padding(.vertical, DSpace.s)
            .frame(minHeight: DSize.inputHeight)
            .background(
                isSelected ? Color.primaryAction.opacity(0.12) : Color.surface,
                in: RoundedRectangle(cornerRadius: DRadius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DRadius.medium)
                    .strokeBorder(isSelected ? Color.primaryAction : Color.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DRadius.medium))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected) { _, selected in selected }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Aviso junto al campo o al botón

/// Texto de ayuda con icono (aviso ámbar o información neutra). Nunca sólo color.
struct OnboardingNote: View {
    enum Tone { case warning, info }

    let text: LocalizedStringKey
    var tone: Tone = .info

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone == .warning ? "exclamationmark.circle.fill" : "info.circle")
        }
        .font(.callout)
        .foregroundStyle(tone == .warning ? Color.warning : Color.textSecondary)
    }
}

// MARK: - Pie con estados

/// Estado del pie de cada paso: falta responder, listo o terminando (loader).
enum OnboardingFooterState: Equatable {
    case needsAnswer
    case ready
    case finishing
}

/// Botón principal del paso con su estado: deshabilitado con una pista, listo, o con
/// loader mientras se cierra el cuestionario (un segundo toque no hace nada).
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let icon: String
    let state: OnboardingFooterState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch state {
            case .finishing:
                HStack(spacing: DSpace.s) {
                    ProgressView()
                        .tint(Color.onAccent)
                    Text("Armando tu plan…")
                }
            case .needsAnswer, .ready:
                Label(title, systemImage: icon)
                    .labelStyle(TrailingIconLabelStyle())
            }
        }
        .buttonStyle(.energy)
        .disabled(state != .ready)
        .animation(.easeOut(duration: 0.15), value: state)
    }
}

/// "Siguiente →": el texto primero y la flecha después, como se lee la dirección.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DSpace.s) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Previews

#Preview("Piezas") {
    ScrollView {
        VStack(alignment: .leading, spacing: DSpace.l) {
            OnboardingProgressBar(current: 2, total: 8)
                .padding(.horizontal, DSpace.l)
            OnboardingHeader(
                icon: "target", eyebrow: "Paso 2 de 8", title: "Objetivo",
                subtitle: "Elige lo que más te importa ahora.", titleIdentifier: "preview"
            )
            VStack(spacing: DSpace.s) {
                OnboardingChoiceRow(title: Text("Hipertrofia"), icon: "figure.strengthtraining.traditional", isSelected: true) {}
                OnboardingChoiceRow(title: Text("Intermedio"), icon: "cellularbars", level: 0.6, isSelected: false) {}
            }
            .padding(.horizontal, DSpace.l)
            OnboardingField(title: "Peso", icon: "scalemass", purpose: "Para ejercicios con tu peso corporal.") {
                Text("72.5 kg").onboardingInput(isFocused: true)
            }
            .padding(.horizontal, DSpace.l)
            VStack(spacing: DSpace.s) {
                OnboardingNote(text: "Elige una opción para seguir.")
                OnboardingPrimaryButton(title: "Siguiente", icon: "chevron.right", state: .needsAnswer) {}
                OnboardingPrimaryButton(title: "Terminar", icon: "checkmark", state: .finishing) {}
            }
            .padding(.horizontal, DSpace.l)
        }
    }
    .screenBackground()
    .ironEnergyTheme()
}
