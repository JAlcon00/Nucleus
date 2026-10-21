# Estados e interactividad

## Contenido
1. Inventario de estados
2. Modelar el estado como tipo
3. Patrones por estado
4. Feedback de interacción
5. Movimiento y animación
6. Hápticos
7. Formularios y entrada de datos
8. Acciones destructivas y toques accidentales
9. Combinar estado de carga con avisos transitorios y acciones optimistas
10. Gestos

## 1. Inventario de estados

Para cada pantalla y componente, decide cómo se ve en:

| Estado | Pregunta de diseño |
|---|---|
| Carga inicial | ¿Qué puedo mostrar ya (estructura, datos en caché)? |
| Recargando | ¿Mantengo el contenido viejo visible mientras llega el nuevo? (casi siempre sí) |
| Vacío (primera vez) | ¿Qué hace el usuario para que deje de estar vacío? Una acción clara. |
| Vacío (búsqueda/filtro) | ¿Cómo quita el filtro o cambia la búsqueda? |
| Parcial | ¿Qué parte cargó y cuál no? No bloquees todo por una sección. |
| Error recuperable | Qué pasó en lenguaje humano + acción (Reintentar). Sin códigos crudos. |
| Sin conexión | ¿Qué sigue funcionando? Indica discretamente, no bloquees si hay datos locales. |
| Deshabilitado | ¿Por qué está deshabilitado? Si no es obvio, explícalo cerca. |
| En progreso (acción) | El control que se tocó muestra el progreso; el resto sigue usable si se puede. |
| Éxito | Confirmación proporcional: un check sutil para algo pequeño, celebración para un hito. |
| Seleccionado / enfocado / presionado | Diferencia visible además de color. |

## 2. Modelar el estado como tipo

```swift
enum LoadState<Value> {
    case idle
    case loading(previous: Value?)   // conserva el contenido anterior mientras recarga
    case loaded(Value)
    case empty
    case failed(UserFacingError, previous: Value?)
}

extension LoadState {
    /// Contenido disponible para mostrar, sea actual o anterior.
    var value: Value? {
        switch self {
        case .loaded(let v): v
        case .loading(let p), .failed(_, let p): p
        case .idle, .empty: nil
        }
    }
}

struct UserFacingError: Error, Equatable {
    let title: String      // "No pudimos cargar tu historial"
    let message: String    // "Revisa tu conexión. Tus datos guardados siguen aquí."
    let canRetry: Bool
}
```

La View hace `switch` exhaustivo. Agregar un estado nuevo obliga a diseñarlo porque el compilador lo exige.

## 3. Patrones por estado

**Carga: skeleton antes que spinner.** Muestra la forma del contenido con `.redacted(reason: .placeholder)` sobre datos de ejemplo. Comunica qué viene y reduce la espera percibida.

```swift
switch state {
case .idle, .loading(previous: nil):
    HistoryList(items: .placeholders)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Cargando historial")
case .loading(previous: let items?), .loaded(let items):
    HistoryList(items: items)
case .empty:
    ContentUnavailableView {
        Label("Aún no hay entrenamientos", systemImage: "figure.strengthtraining.traditional")
    } description: {
        Text("Cuando completes tu primera sesión aparecerá aquí.")
    } actions: {
        Button("Empezar hoy") { onStart() }.buttonStyle(.borderedProminent)
    }
case .failed(let error, let previous):
    if let previous {
        HistoryList(items: previous)
            .safeAreaInset(edge: .top) { ErrorBanner(error, retry: onRetry) }
    } else {
        ContentUnavailableView {
            Label(error.title, systemImage: "wifi.exclamationmark")
        } description: { Text(error.message) } actions: {
            if error.canRetry { Button("Reintentar", action: onRetry) }
        }
    }
}
```

Tiempos guía para feedback de espera (heurística de usabilidad clásica):
- < 100 ms: se percibe instantáneo; no muestres indicador.
- 100 ms – 1 s: feedback local (el botón cambia, aparece un `ProgressView` pequeño dentro del control).
- 1 – 10 s: skeleton o progreso visible; el usuario mantiene el foco.
- > 10 s: progreso con estimación o porcentaje, y permite cancelar o seguir usando la app.

Para no hacer parpadear un indicador en cargas rápidas, retrasa su aparición ~150–300 ms.

**UI optimista.** Para acciones con alta probabilidad de éxito (marcar, me gusta, completar), refleja el resultado al instante y revierte con explicación si falla. Si la acción guarda datos importantes del usuario, persiste localmente primero y sincroniza después.

## 4. Feedback de interacción

Toda interacción recibe respuesta en el mismo frame:
- **Presionado:** escala 0.96–0.98 u opacidad, en `ButtonStyle` (`configuration.isPressed`). Los estilos del sistema y `.glass` ya lo hacen.
- **Cambio de valor:** `contentTransition(.numericText())` para números, `symbolEffect` para iconos.
- **Confirmación:** háptico + cambio visual, nunca solo uno de los dos en acciones importantes.
- **Destructivo:** `Button(role: .destructive)`, confirmación con `.confirmationDialog` solo si es irreversible; si es reversible, mejor "Deshacer" que preguntar.

## 5. Movimiento y animación

El movimiento explica **de dónde viene y a dónde va** algo. Si una animación no explica nada, sobra.

- Usa springs del sistema: `.smooth` (por defecto, sin rebote), `.snappy` (respuesta rápida), `.bouncy` (celebración, elementos lúdicos). Duraciones: 0.15–0.25 s microinteracciones, 0.3–0.45 s transiciones, hasta 0.6 s momentos expresivos.
- Transiciones de navegación con continuidad: `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)` (iOS 18+). iOS 27 añade `.crossFade` (verificar firma).
- `matchedGeometryEffect` para que un elemento "viaje" entre estados dentro de la misma vista.
- `phaseAnimator` y `keyframeAnimator` para secuencias; `scrollTransition` para efectos ligados al scroll (sutiles: escala 0.95–1, opacidad 0.6–1).
- **Reduce Motion:** con `@Environment(\.accessibilityReduceMotion)` reemplaza desplazamientos y zooms por fundidos o sin animación. No elimines el feedback, cambia su forma.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
.animation(reduceMotion ? nil : Motion.standard, value: isExpanded)
```

## 6. Hápticos

Usa `.sensoryFeedback(_:trigger:)` (iOS 17+); es declarativo y respeta la configuración del usuario.

| Momento | Feedback |
|---|---|
| Selección en picker, cambio de pestaña interno | `.selection` |
| Acción completada con éxito (guardar, completar serie) | `.success` |
| Advertencia (límite alcanzado) | `.warning` |
| Error | `.error` |
| Incremento/decremento de valor | `.increase` / `.decrease` |
| Impacto físico (snap, soltar) | `.impact(weight:intensity:)` |

```swift
Button("Completar") { model.complete() }
    .sensoryFeedback(.success, trigger: model.completedCount)
```

No pongas háptico en cada toque; pierde significado. Reserva para confirmaciones, límites y cambios de estado.

## 7. Formularios y entrada de datos

- Teclado correcto: `.keyboardType(.decimalPad)`, `.textContentType(...)`, `.submitLabel(.next)`, foco encadenado con `@FocusState`.
- Valida en línea al salir del campo, no mientras escribe. Mensaje de error debajo del campo, con icono, en lenguaje humano.
- Prefiere controles directos sobre teclado cuando el rango es acotado: `Stepper`, steppers personalizados grandes, `Picker` en rueda o menú.
- Valores por defecto inteligentes (el último usado, el sugerido) para que el caso común sea un toque.
- Nunca pierdas lo que el usuario escribió por un error o una navegación accidental.

## 8. Acciones destructivas y toques accidentales

Borrar o sobrescribir datos del usuario por un toque accidental es un fallo grave, no un detalle de UX.

- **Deshacer antes que confirmar.** Para borrados reversibles: quita el elemento de la vista al instante, muestra un banner "Eliminado · Deshacer" durante ~5 s y confirma el borrado solo al expirar. Mejor aún si el almacenamiento hace borrado lógico (recuperable) y la ventana de deshacer sobrevive a que la app se cierre.
- **Confirmar solo lo irreversible** con `.confirmationDialog`, con el botón destructivo con `role: .destructive` y el texto de lo que se pierde ("Eliminar sesión del 12 de oct · 6 ejercicios").
- **Swipe destructivo:** en contextos de prisa, movimiento o manos húmedas usa `.swipeActions(edge: .trailing, allowsFullSwipe: false)` para que un barrido largo no borre sin un segundo toque. Ofrece la misma acción en `.contextMenu` y como acción accesible.
- **Nada de iconos de papelera sueltos** en filas con `onTapGesture`: área pequeña, sin rol accesible y demasiado fácil de tocar.
- **Botones que cambian de función en el mismo lugar** (Completar → Siguiente → Iniciar descanso): un doble toque ejecuta dos acciones. Mitiga con una guarda breve tras cada cambio de fase (ignorar toques ~0.4–0.6 s), animando el cambio para que se perciba, o colocando la acción siguiente en otra posición.
- **Idempotencia visible:** si el usuario toca dos veces "Guardar", la segunda no debe duplicar el registro. Eso se garantiza en el modelo, pero la UI debe deshabilitar o mostrar progreso mientras se procesa.

## 9. Combinar estado de carga con avisos transitorios y acciones optimistas

El `LoadState` describe el contenido; los avisos (deshacer, error de guardado, sin conexión) son una capa aparte que no debe borrar el contenido.

```swift
@Observable @MainActor
final class HistoryModel {
    var content: LoadState<[Session]> = .idle
    var banner: Banner?                       // capa transitoria independiente
    private var pendingDeletion: (Session, Int)?

    enum Banner: Equatable {
        case undoDelete(Session)
        case saveFailed(UserFacingError)
    }

    func delete(_ s: Session) {
        guard case .loaded(var items) = content, let i = items.firstIndex(of: s) else { return }
        items.remove(at: i)
        content = items.isEmpty ? .empty : .loaded(items)   // optimista
        pendingDeletion = (s, i)
        banner = .undoDelete(s)
    }

    func undo() {
        guard let (s, i) = pendingDeletion else { return }
        var items = content.value ?? []
        items.insert(s, at: min(i, items.count))
        content = .loaded(items)
        pendingDeletion = nil; banner = nil
    }
}
```

En la View, el banner va en `.safeAreaInset(edge: .bottom)` (o una barra flotante de vidrio en iOS 26+) sobre el contenido, con su propia transición y `AccessibilityNotification.Announcement`. Si la acción optimista falla, revierte el contenido y cambia el banner a error con "Reintentar"; nunca hagas desaparecer en silencio algo que el usuario creó.

## 10. Gestos

- Todo gesto debe tener una alternativa visible (botón, menú contextual) y un equivalente accesible (`.accessibilityAction`).
- Swipe actions en filas: en `List` nativo; desde iOS 27 también en `ScrollView`/lazy stacks con `.swipeActionsContainer()` (verificar firma).
- Reordenar: iOS 27 añade `.reorderable()` + `.reorderContainer(for:)` fuera de `List` (verificar firma).
- `.contextMenu` con preview para acciones secundarias sobre un elemento.
- No compitas con gestos del sistema (bordes de pantalla, swipe-back).
