//
//  DesignTokens.swift
//  PR
//
//  Created by PR.
//
//  Tokens de diseño semánticos (SKILL apple-product-designer §74). Centraliza
//  spacing, radios, movimiento y color para no hardcodear estilos por pantalla.
//
//  Color (SCRUM-194, U1): paleta Iron Energy, tema oscuro fijo en la v1. Es la ÚNICA
//  fuente de color de la app: ningún hex ni color del sistema fuera de este archivo.
//  Contrastes medidos con `contrast_check.py` (docs/ux/auditoria-ui-2026-10-22.md §4.1):
//  - textPrimary 17.75:1 (fondo) · 15.52:1 (tarjeta); textSecondary 5.98 · 5.22.
//  - Sobre el acento SIEMPRE `onAccent`: 5.51:1 sobre el rojo, 6.29:1 a mitad del
//    degradado, 7.44:1 sobre el naranja. Blanco sobre el rojo da 3.22:1: prohibido.
//  - `surface` contra el fondo da 1.14:1: las tarjetas llevan borde `hairline`.
//

import SwiftUI

/// Tokens de espaciado semántico (SKILL §74).
enum DSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

/// Tokens de radio de esquina (SKILL §74).
enum DRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 22
}

/// Tamaños de piezas gráficas que no son texto (escalan con `@ScaledMetric` donde se usan).
enum DSize {
    /// Anillo de progreso de un loader de paso completo.
    static let progressRing: CGFloat = 96
    /// Grosor del trazo de anillos de progreso.
    static let ringStroke: CGFloat = 6
    /// Hueco del icono de estado de una fila (✓, en curso, pendiente).
    static let statusIcon: CGFloat = 28
    /// Cifras del temporizador de descanso (escala con Dynamic Type).
    static let timerDigits: CGFloat = 64
    /// Botones [−] [+] de peso y reps: más grandes que el mínimo de 44 pt.
    static let stepperButton: CGFloat = 56
    /// Chip de un día de la semana (L, M, Mi…): el mínimo táctil de 44 pt.
    static let dayChip: CGFloat = 44
    /// Círculo de un día en la tira de la semana (el área de toque es `dayChip`).
    static let weekDot: CGFloat = 32
    /// Punto tenue de un día de descanso en la tira de la semana.
    static let restDot: CGFloat = 6
    /// Trazo de los círculos de la tira de la semana.
    static let markStroke: CGFloat = 2
    /// Trazo punteado de un día no realizado (no es un error: sólo se informa).
    static let missedDash: [CGFloat] = [3, 3]
}

/// Tokens de movimiento. Con Reduce Motion se sustituye el desplazamiento/escala por un
/// fundido breve (mismo significado, sin movimiento).
enum DMotion {
    /// Aparición de un logro (PR-1004): spring corto, sin rebote exagerado.
    static let celebration: Animation = .spring(duration: 0.4)
    /// Variante con Reduce Motion: sólo opacidad.
    static let celebrationReduced: Animation = .easeOut(duration: 0.2)

    static func celebration(reduceMotion: Bool) -> Animation {
        reduceMotion ? celebrationReduced : celebration
    }

    /// Tiempo mínimo en pantalla de un loader de paso completo ("Armando tu semana"):
    /// evita el parpadeo. Nunca se espera más de esto si la operación ya terminó.
    static let minimumLoaderDuration: Duration = .milliseconds(800)
    /// Espera tras la que el inicio de sesión ofrece "Reintentar".
    static let slowSignInThreshold: Duration = .seconds(10)
    /// Barrido del skeleton de carga (sin él con Reduce Motion).
    static let shimmer: Animation = .linear(duration: 1.4).repeatForever(autoreverses: false)
}

/// Paleta Iron Energy (valores crudos). Privada: las pantallas usan los roles de abajo.
nonisolated private enum IronEnergy {
    static let carbon = Color(red: 13 / 255, green: 13 / 255, blue: 15 / 255)       // #0D0D0F
    static let graphite = Color(red: 28 / 255, green: 28 / 255, blue: 33 / 255)     // #1C1C21
    static let graphiteHigh = Color(red: 38 / 255, green: 38 / 255, blue: 45 / 255) // #26262D
    static let ember = Color(red: 255 / 255, green: 61 / 255, blue: 46 / 255)       // #FF3D2E
    static let fire = Color(red: 255 / 255, green: 122 / 255, blue: 26 / 255)       // #FF7A1A
    static let steel = Color(red: 138 / 255, green: 143 / 255, blue: 152 / 255)     // #8A8F98
    static let bone = Color(red: 245 / 255, green: 245 / 255, blue: 240 / 255)      // #F5F5F0
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)       // #30D158
    static let amber = Color(red: 255 / 255, green: 197 / 255, blue: 61 / 255)      // #FFC53D
    static let coral = Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255)     // #FF6B6B
}

/// Roles de color (SKILL §74). Deciden el significado; nunca un color por pantalla.
extension Color {
    /// Fondo de todas las pantallas (negro carbón).
    static let appBackground = IronEnergy.carbon
    /// Tarjetas, filas y hojas (gris grafito). Necesita borde `hairline` sobre el fondo.
    static let surface = IronEnergy.graphite
    /// Campos de entrada, botones secundarios y estado presionado.
    /// `textSecondary` encima queda justo (4.6:1): usar `textPrimary`.
    static let surfaceElevated = IronEnergy.graphiteHigh
    /// Borde de tarjetas (decorativo).
    static let hairline = IronEnergy.bone.opacity(0.08)
    /// Títulos y texto (blanco hueso).
    static let textPrimary = IronEnergy.bone
    /// Texto secundario e iconos inactivos (gris acero).
    static let textSecondary = IronEnergy.steel
    /// Acción primaria: fondo de CTA, progreso, selección, iconos activos.
    static let primaryAction = IronEnergy.ember
    /// Acción secundaria / neutra (bordes e iconos de controles secundarios).
    static let secondaryAction = IronEnergy.steel
    /// Logros, rachas y récords (naranja fuego). Reservado: así se reconocen al instante.
    static let accentSecondary = IronEnergy.fire
    /// Texto e iconos SOBRE el rojo, el naranja o el degradado (nunca blanco).
    static let onAccent = IronEnergy.carbon
    /// Serie completada, guardado.
    static let success = IronEnergy.green
    /// Avisos (máquina ocupada, calentamiento, pausa). Distinto del naranja de logros.
    static let warning = IronEnergy.amber
    /// Abandonar, borrar. Se parece al acento: nunca va relleno y siempre lleva texto o
    /// icono (`xmark`/`trash`) y confirmación.
    static let destructive = IronEnergy.coral
}

extension LinearGradient {
    /// Degradado de energía: anillos de progreso, rachas y el CTA principal.
    /// El texto encima va siempre en `onAccent`.
    static let energy = LinearGradient(
        colors: [IronEnergy.ember, IronEnergy.fire],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Superficies

extension View {
    /// Tema Iron Energy en la raíz: oscuro fijo (v1) y acento de marca para los controles
    /// del sistema. El texto sin color explícito queda en el primario del sistema oscuro.
    func ironEnergyTheme() -> some View {
        preferredColorScheme(.dark)
            .tint(Color.primaryAction)
    }

    /// Fondo carbón de pantalla completa.
    func screenBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }

    /// Tarjeta: grafito con borde `hairline` (sin borde se confunde con el fondo).
    func cardSurface(cornerRadius: CGFloat = DRadius.large) -> some View {
        background(Color.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Botones

/// Alto mínimo de los botones de acción (área de toque holgada para usar con una mano).
enum DButton {
    /// CTA principal ("Empezar", "Completar serie"): más grande que el mínimo de 44 pt.
    static let primaryHeight: CGFloat = 56
    /// Botones secundarios de pantalla completa.
    static let secondaryHeight: CGFloat = 50
}

/// CTA principal: relleno de energía, etiqueta en negro carbón (≥ 5.5:1) y respuesta
/// inmediata al toque. Una sola acción rellena por pantalla.
struct EnergyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: DButton.primaryHeight)
            .padding(.horizontal, DSpace.m)
            .background(LinearGradient.energy, in: RoundedRectangle(cornerRadius: DRadius.medium))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DRadius.medium))
    }
}

/// Acción secundaria: superficie elevada con borde, etiqueta en texto primario.
struct SurfaceButtonStyle: ButtonStyle {
    var minHeight: CGFloat = DButton.secondaryHeight
    /// `false` para botones cuadrados (p. ej. [−] [+] de peso y reps).
    var fillsWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.textPrimary)
            .frame(minWidth: fillsWidth ? nil : minHeight, maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
            .padding(.horizontal, fillsWidth ? DSpace.m : 0)
            .background(
                configuration.isPressed ? Color.surface : Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: DRadius.medium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DRadius.medium)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DRadius.medium))
    }
}

extension ButtonStyle where Self == EnergyButtonStyle {
    /// CTA principal con el degradado de energía.
    static var energy: EnergyButtonStyle { EnergyButtonStyle() }
}

extension ButtonStyle where Self == SurfaceButtonStyle {
    /// Acción secundaria sobre superficie elevada.
    static var surface: SurfaceButtonStyle { SurfaceButtonStyle() }
}

// MARK: - Tipografía

extension View {
    /// Cifras (peso, reps, temporizador, minutos): redondeadas y de ancho fijo.
    func numericStyle() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }

    /// Etiquetas cortas en mayúsculas ("CALENTAMIENTO", "LUNES · HOY").
    func eyebrowStyle() -> some View {
        font(.caption.weight(.semibold)).tracking(0.8)
    }
}

#Preview("Iron Energy") {
    VStack(spacing: DSpace.m) {
        Text("Push").font(.title2.bold())
        Text("5 ejercicios · 15 series").foregroundStyle(Color.textSecondary)
        Button {} label: { Label("Empezar", systemImage: "play.fill") }
            .buttonStyle(.energy)
        Button("Atrás") {}
            .buttonStyle(.surface)
        Text("CALENTAMIENTO").eyebrowStyle().foregroundStyle(Color.warning)
        Text("82.5 kg").font(.largeTitle.bold()).numericStyle()
    }
    .padding(DSpace.l)
    .cardSurface()
    .padding(DSpace.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .screenBackground()
    .ironEnergyTheme()
}
