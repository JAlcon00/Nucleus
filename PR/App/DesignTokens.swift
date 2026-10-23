//
//  DesignTokens.swift
//  PR
//
//  Created by PR.
//
//  Tokens de diseño semánticos (SKILL apple-product-designer §74). Centraliza
//  spacing, radios, movimiento y color para no hardcodear estilos por pantalla.
//
//  Color (SCRUM-194, U1; modo claro SCRUM-208): paleta Iron Energy. Es la ÚNICA fuente
//  de color de la app: ningún hex ni color del sistema fuera de este archivo. Cada rol
//  tiene variante oscura (la de marca, por defecto) y clara; la apariencia la elige la
//  persona en Perfil (`AppearancePreference`).
//  Contrastes medidos con `contrast_check.py` (docs/ux/auditoria-ui-2026-10-22.md §4.1):
//  - Oscuro: textPrimary 17.75:1 (fondo) · 15.52:1 (tarjeta); textSecondary 5.98 · 5.22.
//  - Claro (fondo hueso / tarjeta blanca / elevada): textPrimary 17.75 · 19.42 · 16.08;
//    textSecondary 5.77 · 6.31 · 5.23; primaryAction 5.09 · 5.56 · 4.61;
//    accentSecondary 5.27 · 5.76 · 4.77; success 5.12 (elevada); warning ≥ 5.30;
//    destructive ≥ 4.93. Los colores de marca rojo, naranja y acero NO alcanzan 4.5:1
//    sobre fondo claro: en claro se usan sus versiones oscurecidas.
//  - Sobre el acento SIEMPRE `onAccent`: 5.51:1 sobre el rojo, 6.29:1 a mitad del
//    degradado, 7.44:1 sobre el naranja. Blanco sobre el rojo da 3.22:1: prohibido. Un
//    relleno con texto encima usa `accentFill` (rojo de marca en los dos modos), nunca
//    `primaryAction` (en claro es más oscuro y con carbón da 3.49:1).
//  - `surface` contra el fondo da 1.14:1 (oscuro) y 1.09:1 (claro): las tarjetas llevan
//    borde `hairline`.
//

import SwiftUI
import PRCore

/// Tokens de espaciado semántico (SKILL §74).
nonisolated enum DSpace {
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
    /// Alto del selector de rueda (edad en "Sobre ti").
    static let wheelPicker: CGFloat = 120
    /// Alto de un campo o una opción del formulario inicial: todos iguales para que se alineen.
    static let inputHeight: CGFloat = 52
    /// Insignia del icono de un paso o una opción (círculo detrás del símbolo).
    static let iconBadge: CGFloat = 32
    /// Columna fija del icono junto al título de un campo (alinea los títulos entre sí).
    static let fieldIcon: CGFloat = 24
    /// Ancho de los selectores de unidad (cm/ft-in, kg/lb) junto a un campo.
    static let unitPicker: CGFloat = 116
    /// Grosor de cada segmento del indicador de pasos.
    static let progressSegment: CGFloat = 4
    /// Ancho del logo horizontal en el inicio de sesión (mínimo de marca: 96 pt).
    static let brandLogo: CGFloat = 220
    /// Isotipo de la marca en pantallas de espera (mínimo de marca: 20 pt).
    static let brandIsotype: CGFloat = 72
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
    /// Cambio de paso del cuestionario: el contenido nuevo entra desde la derecha.
    static let slide: Animation = .spring(duration: 0.35)
    /// Variante con Reduce Motion: sólo fundido.
    static let slideReduced: Animation = .easeOut(duration: 0.2)

    static func slide(reduceMotion: Bool) -> Animation {
        reduceMotion ? slideReduced : slide
    }

    /// Barrido del skeleton de carga (sin él con Reduce Motion).
    static let shimmer: Animation = .linear(duration: 1.4).repeatForever(autoreverses: false)
}

/// Paleta Iron Energy (valores crudos). Privada: las pantallas usan los roles de abajo.
/// SCRUM-199: los seis colores de marca salen del catálogo de assets (`Brand Colors`, la
/// misma fuente que el ícono y la pantalla de arranque); el resto de estados y la
/// superficie elevada no son de marca y se quedan aquí. Se leen por nombre porque los
/// símbolos generados (`Color.ironRed`…) están aislados al main actor y esta paleta no.
nonisolated private enum IronEnergy {
    static let carbon = Color("IronCharcoal", bundle: .main)
    static let graphite = Color("IronGraphite", bundle: .main)
    static let graphiteHigh = Color(red: 38 / 255, green: 38 / 255, blue: 45 / 255) // #26262D
    static let ember = Color("IronRed", bundle: .main)
    static let fire = Color("IronFire", bundle: .main)
    static let steel = Color("IronSteel", bundle: .main)
    static let bone = Color("IronBone", bundle: .main)
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)       // #30D158
    static let amber = Color(red: 255 / 255, green: 197 / 255, blue: 61 / 255)      // #FFC53D
    static let coral = Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255)     // #FF6B6B

    // Modo claro (SCRUM-208): superficies claras y versiones oscurecidas de los acentos
    // para que el texto y los iconos pasen AA sobre fondo claro.
    static let white = Color(red: 1, green: 1, blue: 1)                              // #FFFFFF
    static let boneHigh = Color(red: 234 / 255, green: 234 / 255, blue: 228 / 255)  // #EAEAE4
    static let steelDeep = Color(red: 91 / 255, green: 96 / 255, blue: 106 / 255)    // #5B606A
    static let emberDeep = Color(red: 200 / 255, green: 40 / 255, blue: 27 / 255)    // #C8281B
    static let fireDeep = Color(red: 168 / 255, green: 74 / 255, blue: 0 / 255)      // #A84A00
    static let greenDeep = Color(red: 23 / 255, green: 112 / 255, blue: 47 / 255)    // #17702F
    static let amberDeep = Color(red: 134 / 255, green: 84 / 255, blue: 0 / 255)     // #865400
    static let coralDeep = Color(red: 185 / 255, green: 48 / 255, blue: 45 / 255)    // #B9302D

    /// Un color por apariencia. Sin apariencia definida se usa la oscura (la de marca).
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(light) : UIColor(dark)
        })
    }
}

/// Roles de color (SKILL §74). Deciden el significado; nunca un color por pantalla.
extension Color {
    /// Fondo de todas las pantallas (negro carbón · blanco hueso).
    static let appBackground = IronEnergy.adaptive(light: IronEnergy.bone, dark: IronEnergy.carbon)
    /// Tarjetas, filas y hojas (grafito · blanco). Necesita borde `hairline` sobre el fondo.
    static let surface = IronEnergy.adaptive(light: IronEnergy.white, dark: IronEnergy.graphite)
    /// Campos de entrada, botones secundarios y estado presionado.
    /// En oscuro `textSecondary` encima queda justo (4.6:1): usar `textPrimary`.
    static let surfaceElevated = IronEnergy.adaptive(light: IronEnergy.boneHigh, dark: IronEnergy.graphiteHigh)
    /// Borde de tarjetas (decorativo).
    static let hairline = IronEnergy.adaptive(light: IronEnergy.carbon.opacity(0.12), dark: IronEnergy.bone.opacity(0.08))
    /// Títulos y texto (blanco hueso · negro carbón).
    static let textPrimary = IronEnergy.adaptive(light: IronEnergy.carbon, dark: IronEnergy.bone)
    /// Texto secundario e iconos inactivos (gris acero).
    static let textSecondary = IronEnergy.adaptive(light: IronEnergy.steelDeep, dark: IronEnergy.steel)
    /// Acción primaria como texto o icono: progreso, selección, iconos activos. Para un
    /// relleno con texto encima usa `accentFill`.
    static let primaryAction = IronEnergy.adaptive(light: IronEnergy.emberDeep, dark: IronEnergy.ember)
    /// Relleno de acento con texto `onAccent` encima (rojo de marca en los dos modos, 5.51:1).
    static let accentFill = IronEnergy.ember
    /// Acción secundaria / neutra (bordes e iconos de controles secundarios).
    static let secondaryAction = IronEnergy.adaptive(light: IronEnergy.steelDeep, dark: IronEnergy.steel)
    /// Logros, rachas y récords (naranja fuego). Reservado: así se reconocen al instante.
    static let accentSecondary = IronEnergy.adaptive(light: IronEnergy.fireDeep, dark: IronEnergy.fire)
    /// Texto e iconos SOBRE el rojo, el naranja o el degradado (nunca blanco).
    static let onAccent = IronEnergy.carbon
    /// Serie completada, guardado.
    static let success = IronEnergy.adaptive(light: IronEnergy.greenDeep, dark: IronEnergy.green)
    /// Avisos (máquina ocupada, calentamiento, pausa). Distinto del naranja de logros.
    static let warning = IronEnergy.adaptive(light: IronEnergy.amberDeep, dark: IronEnergy.amber)
    /// Abandonar, borrar. Se parece al acento: nunca va relleno y siempre lleva texto o
    /// icono (`xmark`/`trash`) y confirmación.
    static let destructive = IronEnergy.adaptive(light: IronEnergy.coralDeep, dark: IronEnergy.coral)
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

/// Aplica la apariencia elegida en Perfil (SCRUM-208) y el acento de marca.
private struct IronEnergyTheme: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.fallback.rawValue

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(AppearancePreference.resolve(appearance).colorScheme)
            .tint(Color.primaryAction)
    }
}

extension AppearancePreference {
    /// `nil` = sigue al sistema.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// Tema Iron Energy: la apariencia elegida en Perfil (oscuro por defecto) y el acento
    /// de marca para los controles del sistema. Va en la raíz y en cada hoja presentada.
    func ironEnergyTheme() -> some View {
        modifier(IronEnergyTheme())
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
