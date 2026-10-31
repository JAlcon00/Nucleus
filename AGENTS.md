# AGENTS.md

Reglas para cualquier agente de IA que trabaje en este repositorio (Xcode coding assistant, Claude Code, Codex u otro).
Este archivo es la autoridad máxima del repo: si una skill o una guía general contradice algo de aquí, gana este archivo.

## 1. Start here

Antes de cualquier cambio, leer en este orden:

1. `promptMaster.md`: visión e invariantes del producto.
2. **`mvp-plan.md`: plan activo (MVP/POC, fuente Jira SCRUM). Manda sobre `backlog.md` mientras tenga casillas abiertas.**
3. `.agents/skills/swift-elite-coach/SKILL.md`: reglas de ingeniería propias de PR (dominio, HealthKit, watchOS, agente, seguridad).
4. La skill de estilo que corresponda a la tarea (sección 3).
5. `backlog.md`: historias de dominio ya implementadas y futuras.
6. `plan.md` y `README.md`: arquitectura y fases.

## 2. Invariantes

**Producto.** PR es un entrenador experto digital, no un chatbot fitness ni un simple tracker.

**Ingeniería.**

```text
Develop → Test → Prove
```

Ninguna historia está DONE sin tests, build y validación aplicables realmente ejecutados.

**Arquitectura.**

```text
LLM interprets/explains
Training Engine decides
Policy Validator protects
Local persistence protects workout data
```

**Prioridad cuando hay conflicto:** integridad de datos > seguridad del usuario > corrección del plan > flujo principal usable > todo lo demás.

## 3. Estilos de programación: qué skill usar

El repo trae dos skills de estilo además de `swift-elite-coach`. Lee el `SKILL.md` completo de la que aplique **antes** de escribir código y sigue su flujo de trabajo.

| Tipo de tarea | Skill | Dónde vive el código |
|---|---|---|
| Dominio, motores, cálculos, persistencia, repositorios, coordinators, view models, concurrencia, Codable, tests, bugs, "no compila" | `.agents/skills/swift-logic-engineer/SKILL.md` | `Packages/PRCore/Sources/PRDomain`, `Packages/PRCore/Sources/PRCore` |
| Pantallas, componentes, tokens, layout, color, estados visuales, animación, hápticos, accesibilidad, Apple Watch UI | `.agents/skills/swiftui-design-expert/SKILL.md` (+ su `references/` según la tabla interna) | `PR/App`, `PRWatch/App` |
| Historia vertical (dominio + pantalla) | Ambas, en este orden: **primero lógica** (tipos, motor, tests en verde), **después UI** que consume esa lógica | Ambos |

Regla de frontera: si al hacer UI aparece una regla de negocio, un cálculo o una decisión, **no** va en la View. Se cambia de modo a `swift-logic-engineer`, se implementa en PRCore con tests y la View solo la consume.

### 3.1 Modo lógica (`swift-logic-engineer`)

Ciclo obligatorio: Reconocer → Analizar → Diseñar tipos → Implementar → Probar → Depurar → Optimizar (solo con razón) → Verificar sin regresión.

Resumen de lo que se espera (detalle en la skill):

- **Línea base primero:** correr `make test` antes de tocar nada y anotar qué fallaba de antes.
- **Contrato en 3–6 líneas** y lista de casos límite antes de programar. Bugs: reproducir con un test que falle.
- **Estados inválidos irrepresentables:** enums en vez de Bool/String sueltos, tipos envoltorio para IDs y unidades, invariantes validadas en el `init`.
- **Sin** `!`, `try!`, `as!`, `Any`, `[String: Any]`, estado global mutable ni números mágicos de política (van a `EngineConfiguration` / reglas versionadas).
- **Funciones puras para decidir;** reloj, `Calendar`, `TimeZone`, UUID y aleatoriedad inyectados.
- **Fechas:** `weekday` siempre es 1 = domingo; para lunes = 0 usar `(weekday + 5) % 7`. Nunca sumar 86 400 s para "un día".
- **`switch` exhaustivo sin `default`** en enums propios.
- **No tragar errores de escritura** (`try?` sobre guardado está prohibido en datos de workout).
- **Operaciones reintentables idempotentes** (cola de pendientes, guardado de series, sync).
- **Persistencia compartida:** cada repositorio en su propia colección o prefijo; probar con el `RepositoryStore` real en directorio temporal.
- **Cambio de modelo persistido = versión + migración + muestra + test** (ADR-0003). Agregar un campo opcional no lo requiere. Renombrar, quitar o cambiar el tipo o el significado de un campo sí: subir `current` en `PersistenceSchemas`, agregar el `SchemaMigrationStep`, guardar la muestra nueva y que `PersistenceFormatTests` pase en `make ci`.
- **Límite de atasco:** 3 intentos sin avance sobre la misma falla → detenerse, replantear y, si sigue, reportar el bloqueo con evidencia.
- **Nunca** borrar, desactivar ni debilitar un test para ponerlo en verde.

### 3.2 Modo UI (`swiftui-design-expert`)

Flujo: Contexto → Jerarquía → Tokens → Layout → Color → Estados → Iconografía/performance → Revisión con `references/checklist-revision.md`.

Contexto fijo de PR (no hace falta preguntarlo):

- **Usuario en el gimnasio:** una mano, sudor, entre series, prisa, a veces con sol o poca luz. Áreas de toque ≥ 44×44 pt; la acción "completar serie" más grande que eso. Números con `.monospacedDigit()`.
- **Modo entrenamiento = simplicidad.** Una acción principal por pantalla. No meter análisis ni gráficas en el workout activo.
- **Versión vigente vs. versión mínima.** La vigente es **iOS 27 / watchOS 27** (Xcode 27). La mínima (deployment target) sigue siendo **iOS 26.5** y **watchOS 11**. Confirmar el SDK instalado con `xcodebuild -version` antes de usar APIs nuevas.
  - **iOS:** APIs de iOS 26 sin `#available`. APIs de **iOS 27** (p. ej. `reorderable()`, `swipeActionsContainer()`, `visibilityPriority`, `topBarPinnedTrailing`, `toolbarMinimizeBehavior`, `asyncImageURLSession()`) van detrás de `if #available(iOS 27, *)` con fallback.
  - **Watch:** cualquier API de watchOS 26 o 27, incluido Liquid Glass, va detrás de `#available` con fallback.
  - No subir los deployment targets sin una nota de decisión (ADR) aprobada.
- **Cambios de Xcode 27 que afectan el código:**
  - `@State` ahora es macro y evalúa su valor inicial de forma perezosa: no depender de efectos secundarios en ese inicializador.
  - Los result builders se unifican en `ContentBuilder`: si aparecen ambigüedades nuevas en `overlay` o `background`, resolverlas con tipos explícitos, no con `AnyView`.
  - Xcode 27 avisa cuando un default de `@Entry` crea una instancia de clase: corregir el aviso, no silenciarlo.
  - Las apps de iPhone ahora pueden mostrarse redimensionables: nada de layouts que asuman ancho fijo ni checks de idiom o de modelo de dispositivo.
  - El usuario controla la transparencia de Liquid Glass (de ultra transparente a totalmente tintado): probar legibilidad en ambos extremos y con Reduce Transparency e Increase Contrast.
- **Watch:** leer `references/watchos.md`. Respetar `isLuminanceReduced`, hápticos como confirmación principal y nada de timers por segundo innecesarios.

Reglas de código UI:

- **Views solo muestran estado y envían intenciones.** Nada de progresión, volumen, sustituciones, restricciones ni reconciliación de HealthKit en una View.
- **Un enum de estado por pantalla** (`loading`, `empty`, `loaded`, `failed`…). Cada caso se diseña; los que no aplican se declaran "no aplica" con razón.
- **Previews por estado:** claro, oscuro, `.dynamicTypeSize(.accessibility3)` y cada caso del enum.
- **Texto sin tamaño fijo;** `@ScaledMetric` para métricas que escalan. Sin `AnyView`. `ForEach` con ids estables.
- **Strings localizables** (`String(localized:)`).
- **Color nunca como único portador de significado.** Contraste medido con `python3 .agents/skills/swiftui-design-expert/scripts/contrast_check.py`.
- **Nunca inventar APIs:** si no se puede confirmar firma o disponibilidad, se marca "verificar" y se dice.

### 3.3 Adaptaciones del repo (mandan sobre las skills)

| La skill genérica dice | En PR se hace así |
|---|---|
| Tokens tipo `Spacing.m`, `Radius.card` | Usar los existentes en `PR/App/DesignTokens.swift`: `DSpace.xs…xl`, `DRadius.small/medium/large`, `Color.primaryAction/secondaryAction/success/warning`. Si falta un token, **agregarlo ahí**, no crear otro sistema paralelo. |
| Swift Testing o XCTest | Tests nuevos en **Swift Testing** (`import Testing`). Los archivos existentes en XCTest se quedan en XCTest. |
| Comandos genéricos de build | `make test` (iterar, todas las unitarias), `make ci` + smoke + recorridos que toca (cierre). Ver §4.1. Scheme iOS: `PR`; confirmar con `xcodebuild -list`. |
| Estructura libre de módulos | `PRDomain` no importa SwiftUI, HealthKit, SwiftData ni networking. Infraestructura implementa contratos de `PRCore`. |
| Reporte final de la skill | Usar el formato unificado de la sección 7. |

## 4. Before coding

```bash
git status
xcodebuild -list
make test
```

Inspeccionar el repo real antes de asumir paths o schemes. No pisar cambios sin commitear de otra persona.

### 4.1 Qué pruebas correr y cuándo (decisión de Jesús, 2026-10-30; SCRUM-228)

| Momento | Qué se corre |
|---|---|
| **Mientras se programa** | `make test`: **todas** las unitarias y de integración (unos 13 s). No se filtran: atrapan regresiones en suites "no relacionadas". |
| **Al cerrar cada historia** | `make ci` completo, `make test-ui-smoke` y los recorridos E2E que la historia toca: `make test-ui-journey RECORRIDO="TodayJourney ProfileJourney"` (corre sin recompilar, con lo que compiló el smoke). |
| **Al cerrar una fase o antes de una entrega** | La E2E completa: `make test-ui`. |

- Los recorridos son las clases de `PRUITests/Journeys/` (una por recorrido). Una historia que cambia un flujo agrega o ajusta su paso en el recorrido que corresponde, y lo dice en el reporte.
- Una sola corrida de pruebas de UI a la vez, nunca en paralelo: con 16 GB, un solo simulador ya llena la memoria. Cómo cuidarla: README › "Cuidar la memoria al correr pruebas".

## 5. Backlog selection

- **Primero `mvp-plan.md`:** tomar el primer bloque de su sección 3 que no esté en `[x]` y tenga sus dependencias en `[x]`. Trabajar ahí todo lo asignado en Jira a Gael y Joss.
- **Congelado:** mientras `mvp-plan.md` tenga casillas abiertas, no se trabaja ninguna historia P1/P2 de `backlog.md`.
- **IDs:** usar siempre la clave de Jira (`SCRUM-XX`) en commits y ramas, por ejemplo `SCRUM-23 (P0): ...`. Los `PR-01xx` de Jira **no** son los `PR-01xx` de `backlog.md`.
- **Al cerrar un bloque:** marcar `[x]` solo los criterios cuyo test pasó en `make ci` y agregar la línea `Evidencia:`. Las pruebas 👤 las marca Jesús.
- Fuera del plan MVP: elegir la primera historia `READY` de mayor prioridad con dependencias `DONE`.
- No empezar una P2 si hay una dependencia P0 incompleta.
- Un bug que pierde datos, duplica energía, ignora una restricción o recomienda una carga inválida es P0 y bloquea lo demás.
- Sin refactors oportunistas fuera del alcance de la historia: se mencionan aparte.

## 6. Uso de la terminal (autonomía en Xcode)

- **Un comando por llamada.** No encadenar con `;`, `&&` ni `|` salvo que sea indispensable; así coinciden con los comandos permitidos y no se piden permisos de más.
- **Pedir confirmación antes de:** `git push`, `git reset --hard`, `rm`, `curl`/`wget`, `sudo`, cambios en `project.pbxproj` fuera de lo que pide la historia.
- No leer ni imprimir `.env` ni claves (NVIDIA u otras).

## 7. Reporte de trabajo

Al inicio:

```markdown
## Task
- Historia: PR-XXXX
- Modo: lógica / UI / vertical
- Contrato y casos límite: …
- Archivos probables: …
- Invariantes que toca: …
- Tests a agregar: …
```

Al final:

```markdown
## Result
- Cambios: `Ruta/Archivo.swift` → qué y por qué
- Línea base: <comando> → <resultado>
- Iteraciones: N (qué falló y cómo se resolvió, una línea c/u)
- Final: `make ci` → <línea resumen real, p. ej. "Test run with 412 tests passed">
- E2E: `make test-ui-smoke` y los recorridos que toca → <resultado por recorrido> (la completa sólo al cerrar fase)
- Warnings nuevos: ninguno / lista
- UI (si aplica): estados cubiertos, accesibilidad verificada, pendientes en dispositivo, APIs sin confirmar
- Riesgos y pendientes: …
```

Si no hubo toolchain para ejecutar, marcarlo como **"no verificado por ejecución"**.

## 8. Never

- invent Apple APIs;
- store secrets in client;
- put business rules in Views;
- rely on LLM for deterministic calculations (cargas, volumen, calorías, equivalencias);
- lose or duplicate workout data because of network, retries or navigation;
- double-count HealthKit energy;
- bypass restrictions (tampoco vía sustitución, agente o progresión);
- raise load with moderate or high pain;
- diagnose injuries or promise recovery;
- add random exercise variation;
- break the state of an active workout;
- weaken, skip or delete a test to make it pass;
- claim tests ran when they did not.
