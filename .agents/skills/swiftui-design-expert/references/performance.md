# Performance y cargas rápidas

## Contenido
1. Presupuestos
2. Arranque y primera pantalla
3. Renderizado y actualizaciones de SwiftUI
4. Listas y scroll
5. Imágenes
6. Efectos visuales caros
7. Medir

## 1. Presupuestos

Define metas medibles; "que sea rápido" no se puede verificar.

| Métrica | Meta orientativa |
|---|---|
| Respuesta visual a un toque | mismo frame (≤ 16 ms a 60 Hz, ≤ 8 ms a 120 Hz) |
| Arranque en frío hasta primer frame | ≤ 400 ms (guía de Apple para lanzamientos) |
| Contenido útil visible tras abrir pantalla | ≤ 1 s con datos locales |
| Hitch ratio durante scroll/animación | < 5 ms/s bueno; 5–10 advertencia; > 10 crítico |
| Memoria por imagen en pantalla | proporcional al tamaño mostrado, no al original |

Valida en el dispositivo más lento que soportas, no en el simulador ni en el último iPhone.

## 2. Arranque y primera pantalla

- Nada pesado en `init` de la `App`, del `Scene` o de las Views. Inicializa servicios de forma perezosa o en `.task`.
- Muestra la estructura de la pantalla inmediatamente con datos locales/caché; trae lo remoto después.
- Carga con `.task(id:)` (se cancela sola al salir o cambiar el id) en vez de `onAppear` + `Task {}`.
- Decodificación, ordenamiento y cálculo fuera del main actor; regresa al main solo para asignar el resultado.

## 3. Renderizado y actualizaciones de SwiftUI

SwiftUI re-evalúa `body` cuando cambia algo que la View lee. El costo viene de re-evaluar demasiado o demasiado arriba.

- Usa `@Observable` (Observation): cada View solo se invalida por las propiedades que realmente lee. Evita `ObservableObject` con `@Published` masivos en código nuevo.
- Pasa a las subvistas solo lo que necesitan (valores, no el modelo entero) para que su `body` no dependa de cambios ajenos.
- Mantén `body` barato: sin formateadores creados en cada evaluación (cachea `FormatStyle`/`Formatter`), sin filtrados o sorts de colecciones grandes, sin I/O.
- Identidad estable: `ForEach` con `id` estable (nunca `\.self` sobre valores que cambian, ni índices si la colección muta). Evita `AnyView`.
- Prefiere modificadores condicionales (`.opacity(isVisible ? 1 : 0)`) sobre `if` que destruye y recrea vistas cuando se alterna rápido y la vista es costosa; usa `if` cuando la vista oculta no debe existir.
- `Self._printChanges()` dentro de `body` (solo en debug) revela qué provoca cada re-render.
- iOS 27 introduce inicialización perezosa de estado para tipos `@Observable` y `@State` como macro (verificar detalles); aprovecha que el estado costoso ya no se construye en cada `init` de la View.

## 4. Listas y scroll

- `List` o `LazyVStack`/`LazyVGrid` para colecciones que pueden crecer. `VStack` dentro de `ScrollView` solo para pocas filas fijas.
- Filas de altura predecible y livianas: evita `GeometryReader` en cada fila, sombras grandes con blur y efectos de vidrio por fila.
- Paginación o carga incremental al acercarse al final (`.onAppear` de las últimas filas o `onScrollVisibilityChange`), con fila de "cargando más" diseñada.
- `scrollTransition` y efectos ligados al scroll: mantenlos simples (escala, opacidad); nada que re-dibuje imágenes.

## 5. Imágenes

- Nunca decodifiques una imagen de 4000 px para mostrarla a 80 pt. Genera miniaturas (downsampling con ImageIO o `UIImage.preparingThumbnail(of:)`) fuera del main actor.
- Formatos: HEIC/AVIF/WebP según soporte; assets en catálogo con escalas o vectores (PDF/SVG con "Preserve Vector Data").
- `AsyncImage`: desde iOS 27 tiene caché configurable con `URLSession` propia (verificar API `asyncImageURLSession`). Para targets menores o necesidades de prefetch y prioridad, usa una caché propia o una librería probada.
- Reserva el espacio de la imagen (`aspectRatio`, `frame`) antes de que cargue para evitar saltos de layout.
- Placeholder con color dominante o degradado suave, transición de opacidad corta al aparecer.

## 6. Efectos visuales caros

- **Liquid Glass:** agrupa elementos de vidrio cercanos en un `GlassEffectContainer` (mejor rendimiento y morphing correcto). Limita cuántos efectos de vidrio hay en pantalla a la vez y nunca uno por fila de una lista.
- Sombras: `shadow` con radio grande sobre muchas vistas es costoso; usa pocas o superficies con borde sutil.
- Blur y materiales: uno o dos niveles, no apilados.
- `.drawingGroup()` puede acelerar composiciones vectoriales complejas (gráficas, partículas) al rasterizarlas con Metal; no lo uses en vistas con texto o controles interactivos sin medir.
- `.compositingGroup()` antes de aplicar opacidad a un grupo evita artefactos y trabajo repetido.
- `.geometryGroup()` para que hijos animen con la geometría del padre sin saltos.
- Shaders (`.colorEffect`, `.layerEffect`, `.distortionEffect`) son rápidos, pero son decoración: úsalos en momentos puntuales.

## 7. Medir

- Instruments: plantilla **SwiftUI** (cuerpos evaluados, causas de actualización), **Hitches/Animation Hitches**, **Time Profiler**, **Allocations** para imágenes.
- Xcode 27 añade comparaciones de ejecución contra una línea base para detectar regresiones y MetricKit renovado con API Swift (verificar nombres) para métricas en campo.
- Antes de optimizar, mide; después, mide otra vez. Reporta números, no impresiones.
