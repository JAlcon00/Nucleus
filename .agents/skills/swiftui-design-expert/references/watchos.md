# Apple Watch (watchOS)

El reloj se usa en segundos y a menudo sin mirarlo con calma (caminando, entrenando). Diseña para un vistazo.

## Principios
- **Una tarea por pantalla, una acción principal.** Lo demás en scroll o en otra vista.
- **Información de vistazo:** el dato más importante con el tipo más grande; números con `.monospacedDigit()` y `.fontDesign(.rounded)` combinan bien con el sistema.
- **Fondos oscuros, alto contraste.** El negro puro es intencional en OLED y ahorra batería.
- **Toques grandes:** botones de ancho completo; evita filas de muchos botones pequeños.
- **Digital Crown** para ajustar valores (`.digitalCrownRotation`) y para scroll; da precisión sin tapar la pantalla.
- **Hápticos** como canal principal de confirmación cuando el usuario no mira (`.sensoryFeedback` o `WKInterfaceDevice.current().play(_:)`).

## Estructura
- `NavigationStack` y `TabView` con estilo vertical paginado (`.tabViewStyle(.verticalPage)`) para secciones.
- `.containerBackground(_:for: .navigation)` / `.tabView` para fondos con color que comunican contexto (ej. un color por tipo de actividad).
- Toolbars con `topBarLeading`/`topBarTrailing`/`bottomBar` para acciones secundarias.
- Liquid Glass llega también a watchOS 26/27: controles y barras del sistema lo adoptan; mismas reglas (navegación, no contenido).

## Always On y luminancia reducida
- `@Environment(\.isLuminanceReduced)`: en modo atenuado, elimina animaciones, reduce brillo de colores, oculta datos sensibles o que se actualizan cada segundo y muestra lo esencial (por ejemplo, tiempo transcurrido con menor frecuencia vía `TimelineView`).

## Performance
- Presupuesto de batería y CPU muy estricto: evita timers por segundo innecesarios; usa `TimelineView(.periodic(...))` o actualizaciones del sistema.
- Imágenes pequeñas y pre-escaladas; nada de decodificar fotos grandes.

## Superficies
- Complicaciones y widgets (WidgetKit) y Smart Stack: a menudo son la interfaz principal. Diseña el dato más útil en el menor espacio.
- Live Activities del iPhone se reflejan en el reloj: cuídalas en tamaño mínimo.
