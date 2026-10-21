# Accesibilidad

Diseñar accesible hace la app mejor para todos: texto grande al sol, una mano ocupada, poca atención. Trátalo como restricción de diseño, no como parche.

## Dynamic Type
- Todo texto con estilos o `Font.custom(_:size:relativeTo:)`.
- Métricas que acompañan al texto (tamaño de iconos, alturas de filas, paddings internos): `@ScaledMetric(relativeTo: .body) var iconSize = 24`.
- Prueba hasta `.accessibility5`. Los layouts horizontales deben reorganizarse a vertical con tamaños de accesibilidad:

```swift
@Environment(\.dynamicTypeSize) private var typeSize

var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading))
                                              : AnyLayout(HStackLayout())
    layout { title; Spacer(minLength: 0); value }
}
```

- Si un componente realmente no puede crecer (por ejemplo, una barra compacta), limita con `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` en ese componente, no en toda la app, y ofrece el contenido completo en otro lugar.
- Nunca trunques información crítica; permite varias líneas (`.lineLimit(nil)` o rangos) y `.minimumScaleFactor` solo como último recurso para números cortos.

## VoiceOver
- Etiquetas que dicen el significado: `accessibilityLabel("Serie 3 completada, 80 kilos, 8 repeticiones")`.
- Agrupa elementos que forman una unidad: `.accessibilityElement(children: .combine)` o `.ignore` + etiqueta propia.
- Valores y acciones: `accessibilityValue`, `accessibilityAdjustableAction` para steppers propios, `accessibilityAction(named:)` para gestos.
- Rasgos: `.accessibilityAddTraits(.isHeader)` en títulos de sección, `.isButton` en vistas tocables que no son `Button` (mejor: usa `Button`).
- Orden de lectura lógico; corrige con `accessibilitySortPriority` si el layout visual lo altera.
- Iconos decorativos y separadores: `.accessibilityHidden(true)`.
- Anuncia cambios importantes que ocurren sin acción del usuario (`AccessibilityNotification.Announcement`).

## Preferencias visuales
- **Reduce Motion** (`\.accessibilityReduceMotion`): fundidos en lugar de desplazamientos, sin parallax ni zoom.
- **Reduce Transparency** (`\.accessibilityReduceTransparency`): fondos opacos en tus superficies personalizadas; el vidrio del sistema ya se adapta.
- **Increase Contrast** (`\.colorSchemeContrast == .increased`): variantes de alto contraste, bordes visibles.
- **Bold Text** (`\.legibilityWeight == .bold`): los estilos del sistema lo respetan; tus fuentes fijas no.
- **Differentiate Without Color** (`\.accessibilityDifferentiateWithoutColor`).
- **Smart Invert:** marca imágenes y medios con `.accessibilityIgnoresInvertColors()`.

## Motor y toque
- 44×44 pt mínimo; más en acciones críticas o contextos de movimiento.
- Ninguna acción depende solo de un gesto complejo, de mantener presionado o de precisión.
- Soporta Voice Control: etiquetas visibles coinciden con las de accesibilidad; `accessibilityInputLabels` para nombres alternativos.

## Verificación
- Accessibility Inspector y la auditoría de accesibilidad de Xcode (también en UI tests: `XCUIApplication().performAccessibilityAudit()`).
- Recorre la pantalla con VoiceOver activado en dispositivo real al menos una vez por flujo principal.
- Previews con `.dynamicTypeSize(.accessibility3)`, `.environment(\.colorScheme, .dark)` y `\.legibilityWeight`.
- `\.colorSchemeContrast`, `\.accessibilityReduceMotion` y `\.accessibilityReduceTransparency` son de solo lectura: no se inyectan con `.environment` en un preview. Pruébalos con Variants / Environment Overrides del canvas de Xcode o en el dispositivo; si necesitas previews automáticos, haz que tus vistas reciban esos flags como parámetros desde un contenedor.
