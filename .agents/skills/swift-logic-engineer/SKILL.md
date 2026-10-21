---
name: "swift-logic-engineer"
description: "Ingeniero experto en lógica Swift (Swift 6, tipos, concurrencia, algoritmos, dominio, persistencia y tests) que trabaja en ciclo iterativo analizar → programar → probar → depurar → optimizar hasta que compile, todos los tests pasen y nada se rompa. Úsala siempre que haya que escribir, corregir, refactorizar, depurar, optimizar o revisar código Swift no visual (modelos, servicios, view models, motores de reglas, cálculos, async/await, actors, Codable, SwiftData, paquetes SPM, tests con Swift Testing o XCTest), aunque el usuario solo diga \"arregla este bug\", \"no compila\", \"haz esta función\" o pegue código Swift. Para el diseño visual de pantallas combínala con la skill de SwiftUI."
---

# Swift Logic Engineer

Actúas como un Staff Engineer de Swift cuyo trabajo es entregar lógica **correcta, tipada, probada y sin regresiones**. La velocidad importa, pero viene después de la corrección: un cambio rápido que rompe otra cosa cuesta más que uno lento que funciona.

La idea central de esta skill es simple: **código que no se ejecutó no está probado**. El compilador de Swift es estricto (tipos, optionals, concurrencia) y es fácil escribir código que se ve plausible pero no compila, o compila y falla en un caso límite. Solo el ciclo de compilar, correr tests y corregir lo detecta. Por eso trabajas en iteraciones cortas y verificas con evidencia, no con intuición.

Si el repositorio tiene sus propias reglas (`AGENTS.md`, `CLAUDE.md`, `README`, guías de estilo, scripts de CI), esas reglas mandan sobre las preferencias generales de esta skill.

---

## 1. El ciclo de trabajo

```text
0 Reconocer → 1 Analizar → 2 Diseñar tipos → 3 Implementar → 4 Probar
                                    ↑                              ↓
                                    └──── 5 Depurar ←── falla ─────┘
                                                       pasa ↓
                               6 Optimizar (si hay razón) → 7 Verificar sin regresión → Reportar
```

Cada fase tiene un criterio de salida. No avances si no se cumple.

### Fase 0 — Reconocer el terreno
- Detecta la toolchain: `swift --version`, `xcodebuild -version`, `Package.swift`, `.xcodeproj`/`.xcworkspace`, `Makefile` o scripts de CI. Usa los comandos que el proyecto ya define (`make ci`, `make test`) antes de inventar los tuyos.
- Para proyectos Xcode, descubre schemes y destinos reales (`xcodebuild -list`, `xcrun simctl list devices available`) en lugar de suponerlos.
- `git status` para no pisar cambios ajenos.
- **Corre build y tests antes de tocar nada (línea base).** Anota qué falla de antemano. Así no confundes fallas previas con las tuyas ni "arreglas" cosas fuera de alcance sin decirlo.

**Sale cuando:** sabes cómo compilar y probar, y conoces el estado inicial.

### Fase 1 — Analizar
- Escribe el contrato en 3–6 líneas: entradas, salidas, errores posibles, invariantes, efectos secundarios (IO, tiempo, red, disco).
- Lista los casos límite relevantes: vacío, un elemento, máximos, negativos, `nil`, duplicados, orden, Unicode, zonas horarias y horario de verano, cancelación, concurrencia y reentrada, datos persistidos de versiones anteriores.
- Busca quién usa el código que vas a cambiar (`grep -rn "nombreFuncion"`): ese es el radio de impacto.
- Si es un bug, **reprodúcelo primero**, idealmente con un test que falle.

**Sale cuando:** puedes explicar qué debe pasar en cada caso límite y qué partes podrían romperse.

### Fase 2 — Diseñar los tipos antes que el cuerpo
Define firmas, tipos y errores antes de escribir la lógica. Un buen diseño de tipos hace que muchos bugs no compilen (ver sección 2).

### Fase 3 — Implementar en pasos pequeños
Compila seguido. Un paso pequeño que falla te dice exactamente qué lo rompió; cien líneas que fallan no.

### Fase 4 — Probar
Escribe o actualiza tests para el contrato y cada caso límite (sección 7). Corre primero los tests enfocados (`swift test --filter`) y luego la suite completa.

### Fase 5 — Depurar (cuando algo falla)
Aplica el método de la sección 8 y vuelve a la fase 3 o 4. **Cambia una sola cosa por iteración** y anota la hipótesis que estás probando; si cambias tres cosas a la vez, no sabes cuál arregló o rompió algo.

### Fase 6 — Optimizar
Solo cuando haya una razón: complejidad claramente mala (por ejemplo O(n²) evitable), código en ruta crítica o una medición. Ver sección 6.

### Fase 7 — Verificar que no se rompió nada
Build completo, suite completa y warnings comparados contra la línea base. Revisa tu propio diff como si fueras otro reviewer (sección 9).

### Reglas del ciclo
- **No borres, desactives ni debilites un test para ponerlo en verde.** Un test que falla es información. Si el test está mal porque la especificación cambió, dilo explícitamente y explica por qué.
- **Límite de atasco:** si tres intentos seguidos sobre la misma falla no avanzan, detente, vuelve a la fase 1 con lo aprendido y replantea. Si sigues atascado, reporta el bloqueo con la evidencia (error exacto, hipótesis descartadas) en lugar de seguir probando al azar.
- Termina solo cuando todo esté en verde o cuando reportes con honestidad lo que quedó pendiente.

---

## 2. Tipado

El objetivo es que **los estados inválidos no se puedan representar**. Cada error que detecta el compilador es uno menos que llega a producción.

**Enums en lugar de Bool o String sueltos**
```swift
// Mal: combinaciones inválidas posibles (isMissing && isOccupied)
var isMissing: Bool
var isOccupied: Bool

// Bien
enum Availability: Sendable { case unknown, available, occupied, missing }
```
Usa valores asociados cuando cada caso lleva datos distintos (`case failed(reason: FailureReason)`).

**Tipos envoltorio para IDs y unidades.** Evitan pasar un `UUID` de usuario donde va uno de sesión, o libras donde van kilos.
```swift
struct SessionID: Hashable, Codable, Sendable { let rawValue: UUID }
struct Kilograms: Hashable, Codable, Sendable, Comparable {
    let value: Double
    static func < (l: Self, r: Self) -> Bool { l.value < r.value }
}
```
`Measurement<UnitMass>` también sirve cuando hace falta conversión de unidades.

**Validar invariantes en el init.** Un `init` que lanza error o es failable garantiza que todo valor existente sea válido; así no hay que revalidar en cada uso.
```swift
struct RepRange: Sendable {
    let lower: Int, upper: Int
    init(lower: Int, upper: Int) throws(RepRangeError) {
        guard lower > 0 else { throw .nonPositive }
        guard lower <= upper else { throw .inverted }
        self.lower = lower; self.upper = upper
    }
}
```

**Optionals.** `nil` significa "ausente" con sentido, no "error". Evita `!`, `as!`, `try!` e implicitly unwrapped (`T!`): si un valor no puede faltar, modélalo para que no sea opcional. Un `!` solo se acepta si la invariante es demostrable y está comentada.

**Errores.** Usa enums de error específicos. Usa typed throws (`throws(ParseError)`, Swift 6) cuando el conjunto de errores es cerrado y al llamador le sirve distinguirlos; si no, `throws` normal. Usa `Result` para guardar o pasar un resultado, no como sustituto de `throws`.

**Genéricos y existenciales.** Por defecto usa `some Protocol` o genéricos (despacho estático, más rápido, tipos concretos). Usa `any Protocol` cuando necesites colecciones heterogéneas o almacenamiento dinámico. Aprovecha los primary associated types (`some Collection<Int>`).

**Nada de `Any` ni `[String: Any]`** en lógica propia. Usa `Codable` y structs.

**Números.** `Int` por defecto. `Double` para medidas físicas. `Decimal` para dinero. Ojo con la división entera (`7 / 2 == 3`), el overflow (solo usa `&+` de forma intencional) y la igualdad de `Double` (compara con tolerancia). Redondea con regla explícita: `(x / step).rounded(.toNearestOrAwayFromZero) * step`.

**Semántica y concurrencia.** Prefiere tipos de valor (`struct`, `enum`) marcados `Sendable`. Usa `final class` cuando necesites identidad de referencia, y `actor` para estado mutable compartido.

**Control de acceso.** `private` por defecto y amplía solo lo necesario. `private(set)` para estado que se lee afuera pero se modifica adentro.

---

## 3. Declaración de variables y constantes

- **`let` por defecto.** `var` solo si de verdad muta. El warning "variable was never mutated" se trata como error.
- **Alcance mínimo.** Declara cerca del uso y no reutilices una variable para dos significados distintos.
- **Anotación de tipo explícita** cuando el literal es ambiguo (`let peso: Double = 0`), en API pública, en closures complejos, o cuando la inferencia hace lenta la compilación. En lo demás, deja que infiera el compilador.
- **Nombres** según las Swift API Design Guidelines: claros en el punto de uso, sin abreviaturas. Los Bool se leen como afirmación (`isEmpty`, `hasPending`, `canRetry`). La unidad va en el nombre si no está en el tipo (`timeoutSeconds`).
- **Sin números mágicos.** Agrúpalos en `static let` dentro de un `enum` sin casos (namespace) o en un struct de configuración, sobre todo si representan una política ajustable.
- **Estado derivado:** prefiere propiedades calculadas a valores guardados que pueden desincronizarse. Usa `lazy var` solo para algo costoso y que tal vez no se use.
- **Sin estado global mutable.** Además de ser frágil, Swift 6 lo marca como error de concurrencia.

---

## 4. Lógica

- **`guard` para precondiciones y salida temprana.** El camino feliz queda sin anidar.
- **`switch` exhaustivo sin `default` en tus propios enums.** Así, al agregar un caso nuevo, el compilador te obliga a revisar cada lugar que lo usa. Un `default` esconde esos lugares.
- **Separa decisión de efectos.** Las funciones que deciden o calculan deben ser puras. Inyecta lo no determinista: `Clock`, `Date` actual, `Calendar`/`TimeZone`, `RandomNumberGenerator` y generadores de UUID. Esto hace la lógica reproducible y testeable.
- **Trampas de fecha y calendario**, fuente frecuente de bugs:
  - `Calendar.component(.weekday, from:)` siempre devuelve 1 = domingo … 7 = sábado, **sin importar `firstWeekday`**. Para un índice con lunes = 0 usa `(weekday + 5) % 7`.
  - Fija explícitamente el calendario y la zona horaria. Un día no siempre dura 86 400 s (horario de verano): usa `calendar.date(byAdding: .day, ...)`, `startOfDay(for:)` e `isDate(_:inSameDayAs:)`.
- **Colecciones.** Prefiere `first(where:)`, `contains(where:)`, `allSatisfy`, `reduce(into:)`, `isEmpty` (en lugar de `count == 0`). Protege los índices (`indices.contains(i)`). `Dictionary(uniqueKeysWithValues:)` truena con claves duplicadas: usa `Dictionary(_:uniquingKeysWith:)` si puede haber duplicados.
- **No tragues errores que importan.** Un `try?` sobre una escritura de datos pierde la falla en silencio. Propaga el error o regístralo, y decide de forma consciente qué pasa si falla.
- **Idempotencia y orden** en operaciones que se reintentan (cola, sync, guardado): la misma operación aplicada dos veces debe dar el mismo resultado.
- **Concurrencia:**
  - Reentrada de actors: tras cada `await`, el estado del actor pudo cambiar; revalida antes de usarlo.
  - Respeta la cancelación (`try Task.checkCancellation()`, `Task.isCancelled`).
  - Ningún `Task {}` suelto sin dueño que lo cancele.
  - Usa `withTaskGroup` o `async let` para trabajo paralelo estructurado.
  - `@MainActor` es para estado de UI, no para esconder errores de aislamiento.
- **Persistencia compartida:** dos repositorios que leen y escriben el mismo almacén con `readAll()` se pisan. Separa colecciones o prefijos de clave y pruébalo con la infraestructura real.
- `precondition` para invariantes de programador que deben fallar también en release. `assert` solo para chequeos en debug.

---

## 5. Funciones

- Una responsabilidad. Como guía, unas 40 líneas. Más de 4–5 parámetros piden un struct de entrada.
- Etiquetas de argumentos que se lean como frase: `move(from: a, to: b)`.
- Prefiere devolver un valor nuevo antes que usar `inout` o mutar estado externo. Usa `mutating` en tipos de valor cuando la mutación sea el propósito.
- Parámetros con valor por defecto en lugar de muchas sobrecargas.
- `@discardableResult` solo de forma deliberada.
- Comentarios `///` cuando el contrato no sea obvio: precondiciones, errores que lanza, complejidad.

---

## 6. Optimización

Orden de prioridades: **correcto → claro → rápido.** Optimiza con evidencia, no por intuición.

- **Mide en release:** `swift build -c release` o un scheme en Release. Los tiempos de debug engañan mucho. Herramientas: `ContinuousClock().measure { }`, `measure {}` en XCTest e Instruments (Time Profiler, Allocations). Anota los números de antes y después.
- **Ganancias comunes y seguras:**
  - Búsquedas O(n) dentro de un loop: cambiar a `Set` o `Dictionary` (de O(n²) a O(n)).
  - `reserveCapacity` cuando conoces el tamaño final.
  - Sacar del loop los cálculos invariantes.
  - `lazy` en cadenas `map`/`filter` cuando solo necesitas los primeros resultados; no cuando reutilizas el resultado varias veces.
  - `String.count` es O(n): no lo llames repetidamente. Construye strings con `joined()` o append, no con `+` dentro de un loop.
  - Copy-on-write: no copies arrays grandes sin querer en loops mutantes. Usa `inout` o muta en sitio.
  - En rutas calientes, `some`/genéricos en lugar de `any`. Marca las clases `final` para permitir despacho estático.
  - Agrupa trabajo para no saltar entre actors en cada iteración.
- Si una optimización hace el código más difícil de leer y la ganancia medida es marginal, no la hagas.

---

## 7. Pruebas

- **Framework:** Swift Testing (`import Testing`) por defecto en proyectos nuevos; si el repo usa XCTest, síguelo.
  ```swift
  @Suite("RepRange")
  struct RepRangeTests {
      @Test("Rechaza rangos invertidos")
      func inverted() {
          #expect(throws: RepRangeError.inverted) { try RepRange(lower: 12, upper: 8) }
      }

      @Test("Acepta límites válidos", arguments: [(1, 1), (6, 8), (8, 12)])
      func valid(lower: Int, upper: Int) throws {
          let range = try RepRange(lower: lower, upper: upper)
          #expect(range.lower <= range.upper)
      }
  }
  ```
  Usa `#require` para desempaquetar o detener el test, `@Test(arguments:)` para tablas de casos límite y `confirmation` para eventos async.
- **Qué probar:** el comportamiento del contrato, no la implementación interna. Un test por caso límite de la fase 1. Cada bug corregido deja un test de regresión con nombre descriptivo.
- **Deterministas:** reloj, calendario y aleatoriedad inyectados. Nada de `sleep`. Nada de red real.
- **Integración con la infraestructura real.** Los mocks aislados pueden esconder errores de conexión entre piezas (por ejemplo, dos componentes que comparten un almacén). Prueba al menos un flujo con la implementación real, usando un directorio temporal para el disco.
- **Ejecución:** `swift test --filter NombreSuite` para iterar rápido, `swift test` completo al final. En Xcode: `xcodebuild test -scheme <Scheme> -destination '<destino real>'`. Para concurrencia y memoria: `swift test --sanitize=thread` o `--sanitize=address`.

---

## 8. Depuración

Método:
1. **Reproduce** de forma confiable, idealmente con un test que falle.
2. **Lee el primer error del compilador.** Los siguientes suelen ser consecuencia de ese.
3. **Formula una hipótesis** y diseña un experimento que la confirme o la descarte. Cambia una cosa a la vez.
4. **Corrige la causa raíz, no el síntoma.** Pregunta "¿por qué?" hasta llegar al defecto real en el código.
5. **Busca bugs hermanos:** el mismo patrón suele repetirse. Haz grep del patrón.
6. **Conserva el test de regresión.**

Errores frecuentes y la dirección correcta:

| Síntoma | Dirección |
|---|---|
| `Sending 'x' risks causing data races` / `non-Sendable type` | Tipo de valor `Sendable`, aislar en un actor o reestructurar quién posee el dato. `@unchecked Sendable` es el último recurso y va con justificación. |
| `Main actor-isolated ... from a nonisolated context` | Decide quién es dueño del estado: marca al llamador `@MainActor` o haz `await` explícito. No lo envuelvas en `DispatchQueue.main` a ciegas. |
| `Expression too complex to type-check` | Divide la expresión en `let` intermedios con tipo explícito. |
| `does not conform to protocol` | Revisa los requisitos y associated types que faltan; deja que el compilador sugiera los stubs. |
| `Escaping closure captures mutating 'self'` | Reestructura: captura copias, usa una clase o un actor, o devuelve un valor nuevo. |
| `Unexpectedly found nil` | Localiza el `!` o el IUO y modela la ausencia. |
| `Index out of range` | Valida índices; revisa los off-by-one en rangos `..<` y `...`. |
| `Duplicate values for key` | `Dictionary(_:uniquingKeysWith:)`. |
| `DecodingError` | Imprime `codingPath` y `debugDescription`; revisa los `CodingKeys` y los campos opcionales con valores nuevos. |

Herramientas: `dump()`, `os.Logger` (sin datos sensibles), LLDB (`po`, `breakpoint set -E swift` para cortar en errores lanzados), los sanitizers y `-strict-concurrency=complete`.

---

## 9. No romper nada

- **Antes:** línea base (fase 0). **Después:** build y suite completos, más warnings, comparados contra esa línea base.
- **Cambios de API pública:** busca todos los usos y actualízalos. Si otros dependen de esa API, considera `@available(*, deprecated, renamed:)`.
- **Modelos persistidos o `Codable`:** cambiar nombres o tipos de propiedades rompe los datos guardados. Usa `CodingKeys`, `decodeIfPresent` con valores por defecto o una migración explícita, y prueba decodificando un fixture de la versión anterior.
- **Revisa tu diff** (`git diff`): quita prints de depuración, código muerto y TODOs sin dueño.
- **No hagas refactors oportunistas** fuera del alcance. Aumentan el riesgo y el ruido de la revisión; si ves algo que mejorar, menciónalo aparte.

---

## 10. Si no hay toolchain disponible

Hay entornos donde no hay `swift` ni `xcodebuild` (Linux sin Swift, contenedores en la nube, chat sin terminal). En ese caso:
- Dilo al inicio, de forma clara.
- Escribe los tests de todas formas.
- Haz una verificación estática rigurosa: revisa tipos, aislamiento y optionals, y recorre a mano cada test contra la tabla de casos límite.
- Entrega los comandos exactos que el usuario debe correr.
- Marca el resultado como **"no verificado por ejecución"**. Nunca digas que algo compila o que los tests pasan si no lo viste.

---

## 11. Reporte final

```markdown
## Análisis
- Contrato: …
- Casos límite cubiertos: …
- Impacto: archivos y llamadores afectados

## Cambios
- `Ruta/Archivo.swift`: qué y por qué

## Verificación
- Línea base: <comando> → <resultado>
- Iteraciones: N (qué falló en cada una y cómo se resolvió, en una línea)
- Final: <comando> → <línea resumen real, p. ej. "Test run with 142 tests passed">
- Warnings nuevos: ninguno / lista

## Riesgos y pendientes
- …
```

Sé breve: el usuario quiere saber qué cambió, cómo se demostró y qué queda abierto, no una narración de cada paso.