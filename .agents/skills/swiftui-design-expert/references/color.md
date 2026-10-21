# Color: psicología, semántica y contraste

## Contenido
1. Psicología del color aplicada con mesura
2. Sistema de roles semánticos
3. Paleta: estructura y proporción
4. Modo claro, oscuro y aumento de contraste
5. Color sobre Liquid Glass
6. Implementación en SwiftUI
7. Verificación de contraste

## 1. Psicología del color aplicada con mesura

Las asociaciones de color son **reales pero modestas, culturales y dependientes del contexto**. Úsalas para reforzar un mensaje que la UI ya comunica con forma, texto e iconos; nunca como único mecanismo. Evita afirmaciones del tipo "el azul aumenta conversiones un X %": la evidencia no lo sostiene de forma general.

Asociaciones frecuentes en contextos occidentales y latinoamericanos (verifica si la app apunta a otras culturas):

| Familia | Suele evocar | Úsalo para | Cuidado con |
|---|---|---|---|
| Azul | confianza, calma, estabilidad | acciones primarias, finanzas, salud, productividad | es el default de todo; diferencia con matiz o saturación |
| Verde | éxito, progreso, naturaleza, "adelante" | confirmaciones, metas cumplidas, tendencias positivas | confusión rojo/verde para daltonismo |
| Rojo | urgencia, error, peligro, energía | destructivo, errores, alertas críticas | usarlo como acento de marca diluye su señal de peligro |
| Naranja / ámbar | energía, calidez, advertencia | advertencias, CTAs enérgicos, fitness, comida | sobre blanco suele fallar contraste en texto |
| Amarillo | atención, optimismo | resaltar, marcas temporales | casi nunca legible como texto sobre claro |
| Morado / índigo | premium, creatividad, IA | funciones avanzadas, IA, suscripciones | puede leerse frío o "tech genérico" |
| Rosa / magenta | juventud, expresividad | marcas audaces, social | baja seriedad en contextos críticos |
| Neutros (grises, negro) | sofisticación, foco | 80–90 % de cualquier UI | gris claro sobre blanco = ilegible |

Reglas prácticas:
- **Reserva el rojo para lo destructivo y los errores.** Si la marca es roja, usa un rojo distinto (otro matiz o luminosidad) para errores, y acompaña siempre con icono y texto.
- **Saturación comunica intensidad.** Alta saturación = atención, acción; baja = soporte, fondo. Una pantalla con todo saturado no tiene foco.
- **Calidez y contexto de uso.** Apps de energía (deporte, juegos) toleran acentos cálidos y saturados; apps de calma (salud mental, finanzas) piden matices fríos y saturación media.
- **Consistencia > psicología.** Que el mismo color signifique siempre lo mismo dentro de la app pesa más que cualquier asociación general.

## 2. Sistema de roles semánticos

Nombra colores por **función**, no por apariencia. `Color.danger`, no `Color.red2`.

Roles mínimos:
- `accent` — acción principal y selección. Uno solo.
- `accentSecondary` (opcional) — para un segundo nivel de énfasis de marca.
- `success`, `warning`, `danger`, `info` — estados.
- Superficies: usa las del sistema (`Color(.systemBackground)`, `.secondarySystemBackground`, `.systemGroupedBackground`) o define `surface`, `surfaceElevated`.
- Texto: usa estilos jerárquicos del sistema (`.primary`, `.secondary`, `.tertiary`, `.quaternary` vía `.foregroundStyle`). Se adaptan a modo oscuro y contraste automáticamente.
- Datos/gráficas: una paleta categórica aparte, validada para daltonismo, que no reutilice los colores de estado.

## 3. Paleta: estructura y proporción

Regla 60-30-10 como punto de partida (no ley): ~60 % neutros de superficie, ~30 % neutros de texto y separación, ~10 % acento y estado. En la práctica las mejores apps de Apple usan aún menos acento.

- Un solo acento de marca. Si hay dos, uno domina claramente.
- El acento debe tener contraste ≥ 3:1 contra la superficie si es un control, ≥ 4.5:1 si lleva texto encima o es texto.
- Para cada color propio define 3 variantes: claro, oscuro, y alto contraste de cada uno.
- Construye rampas (tonos 50–900) solo si las necesitas; para la mayoría de apps bastan el tono base y una versión "sutil" (fondo de chip, 12–18 % de opacidad sobre superficie).

## 4. Modo claro, oscuro y aumento de contraste

- El modo oscuro no es invertir colores. Superficies gris muy oscuro (no negro puro salvo en watchOS/OLED intencional), acentos con algo menos de saturación y más luminosidad para no "vibrar".
- La elevación en oscuro se comunica aclarando la superficie, no con sombras.
- Con **Aumentar contraste** activo (`@Environment(\.colorSchemeContrast) == .increased`), los colores del sistema se ajustan solos; los tuyos deben tener su variante de alto contraste en el Asset Catalog.
- Con **Diferenciar sin color** (`\.accessibilityDifferentiateWithoutColor`), añade forma, patrón o icono a lo que distingues por color.

## 5. Color sobre Liquid Glass

Guía de Apple: **usa poco color en Liquid Glass**. No tiñas barras y controles de vidrio solo para "poner la marca".
- Tinta (`.tint(...)` en `Glass` o `.glassProminent`) solo para indicar prominencia: la acción principal de una barra, no todas.
- El contenido debajo del vidrio cambia; un tinte que funciona sobre una foto clara puede fallar sobre una oscura. Prueba sobre contenido variado.
- Desde iOS 27 el usuario regula la opacidad del vidrio (de muy transparente a totalmente tintado). Tu diseño debe ser legible en todo el rango: no confíes en la transparencia para comunicar nada.

## 6. Implementación en SwiftUI

Preferencia: Asset Catalog con variantes Any/Dark y High Contrast. Es declarativo, lo ve el diseñador y soporta todos los rasgos.

```swift
// Colors.swift — tokens semánticos
extension Color {
    static let accentPrimary = Color("AccentPrimary")   // Asset Catalog con variantes
    static let success = Color("Success")
    static let warning = Color("Warning")
    static let danger  = Color("Danger")
}

extension ShapeStyle where Self == Color {
    static var accentPrimary: Color { .accentPrimary }
}
```

Si necesitas color dinámico en código (sin asset), usa `UIColor` con trait collection:

```swift
extension Color {
    static let surfaceElevated = Color(uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let high = traits.accessibilityContrast == .high
        switch (dark, high) {
        case (false, false): return UIColor(white: 1.00, alpha: 1)
        case (false, true):  return UIColor(white: 0.97, alpha: 1)
        case (true, false):  return UIColor(white: 0.13, alpha: 1)
        case (true, true):   return UIColor(white: 0.18, alpha: 1)
        }
    })
}
```

Fija el acento global una vez (`.tint(.accentPrimary)` en la raíz o AccentColor del catálogo) en lugar de colorear cada control.

Degradados: `LinearGradient` con dos tonos del mismo matiz se ve moderno y sobrio. `MeshGradient` (iOS 18+) para fondos expresivos de pantallas hero o vacías; nunca detrás de texto denso.

## 7. Verificación de contraste

Mínimos (WCAG 2.x, que Apple referencia):
- Texto normal: **4.5:1**. Texto grande (≥ 18 pt regular o ≥ 14 pt bold aprox.): **3:1**.
- Iconos y bordes de controles que transmiten información: **3:1**.
- Objetivo recomendado para texto principal: 7:1.

Usa el script incluido:

```bash
python3 scripts/contrast_check.py "#FF6B35" "#FFFFFF"
python3 scripts/contrast_check.py "#8E8E93" "#1C1C1E" --alpha 0.85
```

Recuerda: el contraste sobre vidrio o imágenes no es fijo. Mide contra el peor fondo realista o añade una capa (material, sombra de texto suave, scrim) que lo garantice.
