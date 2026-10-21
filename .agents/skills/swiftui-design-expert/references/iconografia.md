# Iconografía

## SF Symbols primero

SF Symbols escala con Dynamic Type, se alinea con la línea base del texto, se adapta a peso y tiene variantes accesibles. Úsalo salvo que la marca exija un icono propio.

- **Mismo peso que el texto adyacente.** Un `Label` ya lo resuelve. Si usas `Image(systemName:)` suelto, aplica la misma `.font` que el texto.
- **Escala:** `.imageScale(.small/.medium/.large)` para ajustar sin romper alineación.
- **Variantes:** `.fill` para estados seleccionados o activos, contorno para inactivos (patrón de tab bar). `.symbolVariant(.fill)` lo aplica a todo un subárbol.
- **Modos de renderizado:**
  - `.monochrome` — por defecto, toma el color de primer plano.
  - `.hierarchical` — un color con niveles de opacidad; da profundidad con sobriedad. Muy buena opción por defecto en UI moderna.
  - `.palette` — dos o tres colores explícitos; para iconos de marca o estado.
  - `.multicolor` — colores intrínsecos del símbolo (clima, banderas); úsalo con moderación.
- **Valores variables:** `Image(systemName: "wifi", variableValue: 0.6)` para niveles (señal, volumen, progreso de algo simple).

## Animación de símbolos

`symbolEffect` (iOS 17+, efectos extra en iOS 18) da vida sin assets:

```swift
Image(systemName: "checkmark.circle.fill")
    .symbolEffect(.bounce, value: completedCount)          // al cambiar
Image(systemName: "bell")
    .symbolEffect(.wiggle, value: newAlerts)               // iOS 18+
Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    .contentTransition(.symbolEffect(.replace))            // cambio entre símbolos
```

Usa `.pulse` o `.breathe` (iOS 18+) para estados "en curso" en lugar de un spinner cuando el icono ya representa la actividad. Respeta Reduce Motion (el sistema atenúa muchos efectos, pero verifica).

## Iconos propios

- Exporta como **símbolo personalizado** (plantilla de SF Symbols app) para heredar escala, peso y alineación; evita PNG sueltos.
- Rejilla y grosor coherentes con SF Symbols para que convivan.
- Un icono sin etiqueta solo es aceptable si es universal (cerrar, compartir, buscar, añadir). Todo lo demás lleva texto o al menos `accessibilityLabel`.

## Ícono de la app

Desde iOS 26 los iconos son multicapa y el sistema aplica modos claro, oscuro, tintado y transparente (vidrio); iOS 27 refina este look. Diseña con **Icon Composer** (capas separadas, fondo, primer plano) para que el sistema genere variantes legibles. Silueta simple y reconocible; evita texto y detalle fino.

## Reglas rápidas

- Un concepto, un icono, en toda la app.
- No mezcles estilos de iconos (contorno vs. relleno) en el mismo nivel jerárquico sin razón de estado.
- Iconos decorativos: `.accessibilityHidden(true)`. Iconos informativos: etiqueta que diga el significado, no la forma ("Completado", no "palomita verde").
