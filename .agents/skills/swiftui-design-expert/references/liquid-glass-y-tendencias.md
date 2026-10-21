# Liquid Glass y tendencias de diseño 2026+

Estado verificado a octubre de 2026. Las tendencias cambian cada WWDC: si el usuario pregunta por "lo último" o por una versión posterior a iOS 27, busca en la web antes de responder.

## Contenido
1. Línea de tiempo
2. Principios de Liquid Glass
3. API SwiftUI de Liquid Glass (iOS 26+)
4. Novedades de iOS 27 relevantes para diseño
5. Gating y fallback para targets anteriores
6. Tendencias 2026 en adelante
7. Antitendencias

## 1. Línea de tiempo

- **WWDC25 (junio 2025):** Apple presenta Liquid Glass, el mayor rediseño desde iOS 7. Llega con iOS 26 (septiembre 2025) en todas las plataformas.
- **iOS 26.x:** ajustes de legibilidad; iOS 26.1 añade un interruptor de transparencia para el usuario.
- **WWDC26 (8 de junio de 2026):** Apple mantiene Liquid Glass y lo refina en iOS/iPadOS/macOS/watchOS/visionOS/tvOS 27: cimientos reconstruidos para legibilidad (difumina más el contenido complejo detrás), **control del usuario desde ultra transparente hasta totalmente tintado**, iconos de app más refinados y con capas de vidrio.
- **Xcode 27:** se reporta que desactiva la opción de diferir la adopción (el modo de compatibilidad que permitía seguir con el look anterior). Compilar con el SDK nuevo implica Liquid Glass. Verifica en las notas de Xcode del proyecto.
- **Otoño 2026:** primer iPhone plegable; refuerza el diseño adaptativo por size classes.

## 2. Principios de Liquid Glass

- **El vidrio es la capa de navegación, no el contenido.** Barras, tab bars, toolbars, controles flotantes, sheets. El contenido (listas, texto, fotos, datos) va debajo, sin vidrio.
- **Nunca vidrio sobre vidrio.** El vidrio no puede muestrear otro vidrio; se ve sucio y confuso. Agrupa con `GlassEffectContainer`.
- **Color con moderación.** Tinta solo para prominencia (la acción principal). No para marca.
- **Concentricidad.** Formas que comparten centro con su contenedor y con las esquinas del hardware.
- **El contenido llega a los bordes.** Deja que el contenido se extienda bajo las barras; el vidrio y los efectos de borde de scroll garantizan legibilidad.
- **Adaptativo y del usuario.** El vidrio cambia con el fondo y con la preferencia del usuario (iOS 27). Diseña para todo el rango.
- **Respeta accesibilidad:** con Reduce Transparency el vidrio se vuelve más opaco; con Increase Contrast aparecen bordes. Los componentes del sistema lo hacen solos; los tuyos deben comprobarse.

## 3. API SwiftUI de Liquid Glass (iOS 26+)

Componentes estándar (`NavigationStack`, `TabView`, `.toolbar`, sheets, `Menu`, controles) adoptan el vidrio al compilar con el SDK. Empieza por ahí antes de aplicar efectos a mano.

```swift
// Botones
Button("Guardar") { }.buttonStyle(.glass)            // secundario
Button("Empezar") { }.buttonStyle(.glassProminent)   // principal (toma el tint)

// Vidrio en vista propia: aplicar DESPUÉS de padding/frame/font
Label("En pausa", systemImage: "pause.fill")
    .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
    .glassEffect()                                    // .regular en Capsule por defecto

.glassEffect(in: .rect(cornerRadius: 16))            // otra forma
.glassEffect(.regular.tint(.orange).interactive())   // tinte + reacción al toque
// Variantes de Glass: .regular, .clear (más transparente, sobre medios ricos), .identity (sin efecto, útil para alternar)

// Varios elementos de vidrio cercanos: un contenedor
@Namespace private var glassNS

GlassEffectContainer(spacing: 20) {
    HStack(spacing: 20) {
        controlA.glassEffect().glassEffectID("a", in: glassNS)
        if showB {
            controlB.glassEffect().glassEffectID("b", in: glassNS)   // morphing al aparecer/desaparecer
        }
    }
}
// Unir formas separadas en una sola cápsula: .glassEffectUnion(id:namespace:)
// Transiciones: .glassEffectTransition(.matchedGeometry) (por defecto, cercanos) o .materialize (lejanos)
```

Otras APIs de iOS 26 relacionadas (verificar firmas al usarlas):
- `TabView`: `Tab(role: .search)`, `.tabBarMinimizeBehavior(.onScrollDown)`, `.tabViewBottomAccessory { }`.
- Toolbars: `ToolbarSpacer` para agrupar ítems en grupos de vidrio.
- Bordes de scroll: `.scrollEdgeEffectStyle(.soft/.hard, for:)`.
- `.backgroundExtensionEffect()` para extender una imagen bajo barras y sidebars.
- `.safeAreaBar(edge:)` para una barra propia (por ejemplo, acciones inferiores) que participa del efecto de borde de scroll como las barras del sistema. Fallback en iOS < 26: `.safeAreaInset(edge:)` con fondo `.bar` o material.

Morphing en barras de botones: los ejemplos oficiales aplican `glassEffectID` a vistas con `.glassEffect()`. No está documentado que combine con `.buttonStyle(.glass)`; si necesitas morphing garantizado, usa `Button` con estilo plano y aplica `.glassEffect(.regular.interactive())` + `glassEffectID` dentro de un `GlassEffectContainer`. Verifica en dispositivo.

Contraste sobre vidrio: no se puede medir con un solo par de colores porque depende del fondo. Mide el texto contra el tono de tinte base (peor caso sin contenido detrás), luego prueba en dispositivo sobre contenido claro, oscuro y con mucho detalle, en los extremos del control de opacidad (iOS 27) y con Reduce Transparency. Si falla en algún caso, sube el peso del texto, usa tinte más opaco o deja ese control fuera del vidrio.

Errores típicos:
- `.glassEffect()` antes del padding → el vidrio queda pegado al texto.
- Contenedores anidados o un contenedor por elemento → peor rendimiento, sin morphing.
- Vidrio en cada tarjeta de una lista → ruido visual y costo de render.
- Texto pequeño o de bajo contraste sobre `.clear`.

## 4. Novedades de iOS 27 relevantes para diseño

Reportadas tras WWDC26; confirma firma y disponibilidad en la documentación antes de usarlas:
- Liquid Glass refinado: el sistema aplica automáticamente los nuevos tintes y ajustes en componentes estándar.
- `Tab(..., role: .prominent)` para una pestaña destacada y separada al final (como búsqueda).
- `.swipeActionsContainer()` para `swipeActions` en `ScrollView`, lazy stacks y layouts propios.
- `.reorderable()` + `.reorderContainer(for:)` para reordenar fuera de `List`.
- `.navigationTransition(.crossFade)` además de `.zoom`.
- Toolbars: `ToolbarItem(placement: .topBarPinnedTrailing)`, `.visibilityPriority(.high)`, `ToolbarOverflowMenu`.
- `AsyncImage` con caché configurable vía `URLSession`.
- `@State` como macro e inicialización perezosa de estado `@Observable`.
- Xcode 27 incluye skills de agente para SwiftUI y para adaptar a nuevos tamaños de pantalla.

## 5. Gating y fallback para targets anteriores

Si la app soporta iOS < 26, encapsula el vidrio en un modificador propio con fallback a materiales:

```swift
extension View {
    @ViewBuilder
    func floatingSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}
```

Lo mismo para estilos de botón (`.glassProminent` vs. `.borderedProminent`). Así las pantallas no se llenan de `if #available` y el día que subas el target mínimo borras el fallback en un solo lugar.

## 6. Tendencias 2026 en adelante

Adóptalas cuando sirvan a la tarea:

1. **Materialidad y profundidad funcional.** Capas que separan navegación de contenido (herencia de visionOS). La profundidad comunica jerarquía, no decora.
2. **Movimiento físico y continuo.** Springs, transiciones con origen (zoom desde la tarjeta tocada), morphing de controles. Interfaces que se sienten "líquidas" pero predecibles.
3. **Personalización por el usuario.** Intensidad del vidrio, iconos tintados, modo oscuro, tamaño de texto. Tu diseño es un rango, no una imagen fija.
4. **Contenido a sangre.** Contenido edge-to-edge con controles flotantes; menos cromo, más contenido.
5. **Adaptatividad real.** Plegables, iPad con ventanas redimensionables, Mac. Layouts fluidos por size class y contenedor.
6. **Interfaces nativas de IA.** Texto que se transmite progresivamente, estados de "pensando" honestos, explicaciones de por qué se recomendó algo, control para aceptar/editar/descartar sugerencias, nunca presentar una inferencia como hecho.
7. **Superficies fuera de la app.** Widgets interactivos, Live Activities, controles en Centro de Control, complicaciones del Watch y App Intents. Parte del diseño vive fuera de la pantalla principal.
8. **Tipografía con carácter.** Anchos variables (`.fontWidth`), diseño redondeado o serif del sistema, titulares grandes y números protagonistas en apps de datos.
9. **Calma y densidad justa.** Menos notificaciones y badges, más resúmenes. "Calm tech": la app hace el trabajo y muestra lo necesario.
10. **Hápticos como lenguaje.** Confirmaciones táctiles coherentes, especialmente en Watch y en acciones sin mirar la pantalla.
11. **Accesibilidad como estética.** Contraste alto bien diseñado, texto grande con layouts que se reorganizan, sin depender del color.

## 7. Antitendencias (evitar)

- Glassmorphism hecho a mano sobre todo (tarjetas de vidrio en el contenido).
- Neumorfismo, sombras infladas, degradados arcoíris sin propósito.
- Texto gris claro de bajo contraste "porque se ve elegante".
- Animaciones largas que retrasan la tarea.
- Copiar Material Design o patrones web (hamburguesa, FAB genérico) en apps iOS sin razón.
- Ignorar la configuración del usuario (forzar modo oscuro, tamaños fijos).
