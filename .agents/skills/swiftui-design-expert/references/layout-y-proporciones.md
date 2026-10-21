# Layout, proporciones y tipografía

## Contenido
1. Retícula y escala de espaciado
2. Proporciones y escalas modulares
3. Tipografía
4. Radios y concentricidad
5. Áreas de toque y zonas del pulgar
6. Layout adaptativo (size classes, iPad, plegables)
7. Plantilla de tokens

## 1. Retícula y escala de espaciado

Base 4 pt, ritmo 8 pt. Escala recomendada:

| Token | pt | Uso típico |
|---|---|---|
| `xxs` | 4 | icono-texto muy pegado, separación interna de chips |
| `xs` | 8 | entre elementos relacionados |
| `s` | 12 | padding interno compacto |
| `m` | 16 | margen lateral estándar iPhone, padding de tarjeta |
| `l` | 24 | entre grupos |
| `xl` | 32 | entre secciones |
| `xxl` | 48 | separación hero, respiración |
| `xxxl` | 64 | pantallas vacías, onboarding |

Ley de proximidad: el espacio **dentro** de un grupo debe ser claramente menor que el espacio **entre** grupos (al menos 1.5–2×). Es lo que hace que una pantalla se "lea" sin líneas divisorias.

Usa `.contentMargins`, `.safeAreaPadding` y los márgenes del sistema cuando aplique, en lugar de sumar paddings manuales que no respetan el safe area ni el layout readable.

## 2. Proporciones y escalas modulares

Las proporciones dan coherencia porque crean relaciones repetidas que el ojo reconoce. Elige **una** razón y úsala para tamaños relacionados (tipografía display, alturas de tarjeta, imágenes):

- 1.25 (tercera mayor) — interfaces densas, datos.
- 1.333 (cuarta) — equilibrio general.
- 1.5 (quinta) — editorial, marketing, pantallas hero.
- 1.618 (áurea) — composición de bloques grandes (imagen vs. texto, columnas). Es una herramienta más, no magia.

Relaciones de aspecto para medios: 1:1 (avatares, miniaturas), 4:3 o 3:2 (tarjetas), 16:9 (video, banners), 3:4 o 9:16 (vertical/stories). Usa `.aspectRatio(_:contentMode:)` y `containerRelativeFrame` para que escalen con el contenedor:

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: Spacing.m) {
        ForEach(items) { item in
            CardView(item)
                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: Spacing.m) // 80 % del ancho
                .aspectRatio(3/2, contentMode: .fit)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.contentMargins(.horizontal, Spacing.m, for: .scrollContent)
```

## 3. Tipografía

- Usa los **estilos de texto del sistema** (`.largeTitle` … `.caption2`). Escalan con Dynamic Type y ya siguen una escala armónica.
- Fuentes propias: `Font.custom("Nombre", size: 17, relativeTo: .body)` para que escalen.
- Jerarquía con **peso y tamaño**, no con color solamente. Máximo 3–4 niveles por pantalla.
- Números que cambian (temporizadores, pesos, contadores): `.monospacedDigit()` evita que el layout "baile"; `.contentTransition(.numericText())` anima el cambio.
- Variantes del sistema con personalidad sin cargar fuentes: `.fontDesign(.rounded)` (amigable, fitness, salud), `.fontDesign(.serif)` (editorial), `.fontWidth(.condensed / .expanded)` para titulares con carácter.
- Longitud de línea legible: 50–75 caracteres. En pantallas anchas limita el ancho del texto (`.frame(maxWidth: 680)` o layout readable) en vez de dejarlo correr.
- Interlineado: deja el del sistema salvo en titulares grandes, donde un `.lineSpacing` ligeramente negativo o `.tracking` ajustado da look editorial. No toques el interlineado del cuerpo.

## 4. Radios y concentricidad

Regla de concentricidad: **radio interior = radio exterior − padding**. Si una tarjeta tiene radio 24 y padding 12, un botón dentro lleva radio 12. Esto es parte central del lenguaje de Liquid Glass, que alinea las formas con las esquinas del hardware.

- Usa `RoundedRectangle(cornerRadius:style: .continuous)` (curvatura continua tipo Apple), nunca `.circular` para tarjetas.
- iOS 26 añade formas concéntricas que se ajustan a su contenedor (`ConcentricRectangle`, `.containerShape`) — **verificar firma y disponibilidad** antes de usarlas; con target menor, calcula el radio a mano.
- Escala de radios sugerida: 6 (chips), 10–12 (botones, campos), 16–20 (tarjetas), 24–32 (hojas, contenedores grandes), cápsula para acciones flotantes.

## 5. Áreas de toque y zonas del pulgar

- Mínimo **44×44 pt** de área táctil en iOS aunque el elemento visible sea menor (`.contentShape(Rectangle())` + `.frame(minWidth: 44, minHeight: 44)`).
- Separación ≥ 8 pt entre objetivos táctiles adyacentes.
- Acciones frecuentes en el tercio inferior (alcance del pulgar); destructivas o raras, lejos de las frecuentes.
- En contextos de movimiento, prisa, guantes o sudor, sube a 56–64 pt las acciones críticas.

## 6. Layout adaptativo

- **Nunca** uses `UIScreen.main.bounds` ni `UIDevice.current.userInterfaceIdiom` para decidir layout. Usa size classes (`@Environment(\.horizontalSizeClass)`), el tamaño del contenedor y `ViewThatFits`.
- Plegables (iPhone plegable lanzado en 2026): pasa de compacto (plegado) a regular (desplegado) en vivo. Si tu app ya adapta a iPad por size classes, casi todo funciona. `TabView` con `.tabViewStyle(.sidebarAdaptable)` y `NavigationSplitView` se adaptan solos.
- Cambia de layout sin perder identidad con `AnyLayout`:

```swift
@Environment(\.horizontalSizeClass) private var hSize

var body: some View {
    let layout = hSize == .compact ? AnyLayout(VStackLayout(spacing: Spacing.m))
                                   : AnyLayout(HStackLayout(spacing: Spacing.l))
    layout { Summary(); Detail() }
        .animation(.smooth, value: hSize)
}
```

- `ViewThatFits` para alternar entre versión larga y corta de un control según el espacio (útil también con Dynamic Type grande).
- `Grid` para tablas alineadas; `Layout` personalizado solo si ningún contenedor estándar sirve.

## 7. Plantilla de tokens

```swift
// DesignTokens.swift
import SwiftUI

enum Spacing {
    static let xxs: CGFloat = 4,  xs: CGFloat = 8,  s: CGFloat = 12, m: CGFloat = 16
    static let l: CGFloat = 24,   xl: CGFloat = 32, xxl: CGFloat = 48, xxxl: CGFloat = 64
}

enum Radius {
    static let chip: CGFloat = 6, control: CGFloat = 12, card: CGFloat = 20, sheet: CGFloat = 28
    /// Radio para un elemento anidado dentro de un contenedor con padding.
    static func nested(outer: CGFloat, padding: CGFloat) -> CGFloat { max(outer - padding, 0) }
}

enum Motion {
    static let quick: Animation = .snappy(duration: 0.2)
    static let standard: Animation = .smooth(duration: 0.35)
    static let expressive: Animation = .bouncy(duration: 0.5)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(.tint, in: .rect(cornerRadius: Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
```

Mantén los tokens en un solo módulo o archivo; si el proyecto tiene paquete de UI compartido, ahí.
