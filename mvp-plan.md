# mvp-plan.md — Plan activo: MVP / POC de Nucleus

> **Fuente:** Jira `creadevs.atlassian.net`, proyecto **SCRUM** (épica POC: SCRUM-180).
> **Actualizado:** 2026-10-26 (tablero sincronizado con Jira y con el código).
> **Ejecuta:** el agente de IA de Xcode. Hace todo el trabajo asignado en Jira a Gael Durán y Joss Amador, en el orden de este archivo.
> **Regla:** mientras quede un `[ ]` en las secciones 2 y 3, **no se trabaja ninguna historia P1/P2 de `backlog.md`**.

---

## 0. Cómo usar este archivo

1. **Qué tomar:** el primer bloque de la sección 3 que no esté en `[x]` y tenga sus dependencias en `[x]`.
2. **Cómo trabajar:** cada bloque se trabaja como una historia completa (AGENTS.md: modo lógica primero, después UI).
3. **Cuándo marcar `[x]`:** un criterio se marca solo cuando su test pasó en `make ci`. Una prueba manual se marca solo cuando Jesús la confirmó.
4. **Evidencia al cerrar:** al cerrar un bloque, agregar debajo de él una línea `Evidencia:` con el commit y la línea real de `make ci`.
5. **Commits y ramas:** la clave de Jira va al inicio del mensaje, por ejemplo `SCRUM-23 (P0): ...`. Así aparecen en Jira cuando se conecte GitHub for Jira (S-04). En las ramas igual: `scrum-23-export-historial`.
6. **IDs de Jira vs. `backlog.md`:** los IDs `PR-01xx` de Jira **no son** los `PR-01xx` de `backlog.md`; son historias distintas. En este plan y en los commits se usa siempre `SCRUM-XX`.
7. **Partes humanas:** lo marcado 👤 lo hace una persona. El agente prepara todo lo demás y deja indicado qué falta.

---

## 1. Ya hecho (base existente en el repo)

- [x] Dominio y motores de entrenamiento (74 de 93 historias de `backlog.md` en DONE).
- [x] Unos 810 tests en verde: 662 de Swift Testing y ~150 de XCTest (`.ci/test-core.log`, 2026-10-20).
- [x] CI local endurecido: guards, SwiftPM, tests, build iOS y build watchOS (`make ci`, commit 0fe7bb6).
- [x] Proyecto en Xcode 27.1; la spec salió del target de la app.
- [x] AGENTS.md y skills de estilo (`swift-logic-engineer`, `swiftui-design-expert`).
- [x] UI existente:
  - Sign in with Apple.
  - Cuestionario de onboarding.
  - Pantalla Hoy, con estado de descanso y botón de empezar.
  - Workout con completar serie de un toque.
  - Temporizador de descanso.
  - Resumen.
  - Export JSON/CSV.

---

## 2. Tablero del POC (SCRUM-180)

Cada funcionalidad se cierra cuando todas sus casillas están en `[x]`.

### F-01 · Iniciar sesión y cuestionario — SCRUM-181 (era de Gael)
- [x] Inicio sesión con Apple y respondo el cuestionario.
- [x] El cuestionario se responde **una sola vez**; al cerrar y reabrir entro directo a Hoy con el mismo plan → SCRUM-26 (`PlanPersistenceTests`, UI `testReopeningTheAppGoesStraightToToday`).
- [x] Funciona sin internet después del primer inicio → SCRUM-26 (`PlanPersistenceTests`: credencial `.unavailable` entra a Hoy).

### F-02 · Plan semanal correcto — SCRUM-182 (era de Joss)
- [x] La semana tiene exactamente los días elegidos (2 a 7) → SCRUM-27.
- [x] Cada día tiene su propia sesión con series realistas → SCRUM-28.
- [x] Más tiempo no agrega series → SCRUM-28.

### F-03 · Pantalla Hoy — SCRUM-183 (era de Joss)
- [x] Hoy muestra la sesión correcta del día o "Día de descanso" → SCRUM-27. La UI existe; el cálculo quedó corregido.
- [x] Ejercicios en orden lógico, de grandes a pequeños → SCRUM-29.
- [x] Puedo empezar el entrenamiento con un toque.

### F-04 · Registrar series sin internet — SCRUM-184 (era de Gael)
- [x] Una serie cumplida se registra con un toque.
- [x] Cada serie queda guardada al instante en disco → SCRUM-24 (`WorkoutRecoveryTests`: en disco antes de que la UI avance, < 100 ms).
- [ ] Todo funciona en modo avión → SCRUM-24 (el registro no usa red, sólo disco local; sin prueba automática de modo avión: 👤 Jesús lo marca en dispositivo).

### F-05 · Retomar el entrenamiento tras cerrar la app — SCRUM-185 (era de Gael)
- [x] Al reabrir aparece "Tienes un entrenamiento en curso" → SCRUM-24 (UI `testForceQuitMidWorkoutOffersToContinue`).
- [x] Las series hechas siguen ahí y sigue la siguiente → SCRUM-24 (`WorkoutRecoveryTests`: 5 series → sigue la 6).
- [x] El descanso muestra el tiempo que realmente queda → SCRUM-24 (`WorkoutRecoveryTests`: descanso guardado como hora de fin).

### F-06 · Resumen y exportar historial — SCRUM-186 (era de Gael)
- [x] Al completar la última serie aparece un resumen.
- [x] El resumen muestra duración, series, volumen y récords calculados desde los datos guardados → SCRUM-25 (`WorkoutClosingTests`).
- [x] El entrenamiento queda guardado una sola vez como completado → SCRUM-25 (`WorkoutClosingTests`: Export lo cuenta una vez).
- [x] Progreso muestra el registro desde el primer entrenamiento → SCRUM-186 (`ProgressHistoryTests` (9), UI `testProgressLogsTheFirstWorkout`; `make ci` PRDomain 484, PRCore 387, XCTest 151; `make test-ui` 20/20).
- [x] Exportar muestra el número real de entrenamientos y todas sus series → SCRUM-23.

### F-07 · Ajustar la sesión a mi tiempo (opcional) — SCRUM-187 (era de Joss)
Entra al demo solo si F-01 a F-06 están completos.
- [x] Hoy muestra la duración real de la sesión → SCRUM-30.
- [x] Con 30 minutos se conservan los ejercicios principales y la app dice qué quitó → SCRUM-30.
- [x] Con más tiempo no se agregan series → SCRUM-30.

### Soporte
- [ ] S-01 · Ambiente demo y deploy — SCRUM-188 (era de Gael). Ver bloque 11. Criterios del agente [x]; falta 👤 firma, iPhone y video.
- [ ] S-02 · CI en GitHub — SCRUM-189 (era de Joss). Ver bloque 3. CI verde en `main` (`bb3c472`); falta 👤 proteger `main`.
- [ ] S-03 · Pruebas de los flujos — SCRUM-190 (era de Joss). Ver bloque 10. Criterios del agente [x]; falta 👤 pruebas manuales.
- [ ] S-04 · Integración GitHub–Jira — SCRUM-191 (era de Joss). Ver bloque 12. Criterio del agente [x]; falta 👤 instalar "GitHub for Jira".
- [ ] S-05 · Presentación con demo — SCRUM-192 (era de Gael). Ver bloque 13. Criterios del agente [x]; falta 👤 ensayo.

---

## 3. Orden de ejecución del agente

Diagnóstico verificado en el código el 2026-10-20: todos los bugs descritos abajo siguen presentes.

| # | Jira | Qué | Prioridad | Depende de | Estado |
|---|---|---|---|---|---|
| 1 | SCRUM-23 | Historial y export correctos (colecciones separadas) | P0 | — | [ ] criterios [x]; falta 👤 manual |
| 2 | SCRUM-27 | Días correctos de la semana | P0 | — (su test de integración final espera al #6) | [ ] criterios [x]; integración con plan persistido [x] (`WeekEndToEndTests`); falta 👤 manual |
| 3 | SCRUM-189 | CI en GitHub | P0 soporte | — | [ ] criterios del agente [x]; falta 👤 proteger `main` |
| 4 | SCRUM-24 | No perder el workout si la app se cierra | P0 | 1 | [ ] criterios [x]; falta 👤 manual |
| 5 | SCRUM-25 | Cerrar bien la sesión al terminar | P0 | 4 | [x] |
| 6 | SCRUM-26 | Recordar perfil y plan | P0 | 1 | [ ] criterios [x]; falta 👤 manual |
| 7 | SCRUM-28 | Volumen real y una sesión distinta por día | P0 | 2, 6 | [ ] criterios [x]; falta 👤 manual |
| 8 | SCRUM-29 | Ejercicios en orden correcto | P0 | 7 | [x] |
| 9 | SCRUM-30 | Duración real y ajuste de tiempo (F-07) | P1 | 7 | [ ] criterios [x]; falta 👤 sesión larga en dispositivo |
| 10 | SCRUM-190 | Pruebas de los flujos | soporte | 1–8 | [ ] criterios del agente [x]; falta 👤 manual |
| 11 | SCRUM-188 | Ambiente demo | soporte | 1–8 | [ ] criterios del agente [x]; falta 👤 firma, iPhone y video |
| 12 | SCRUM-191 | Integración GitHub–Jira | soporte | 3 | [ ] criterio del agente [x]; falta 👤 instalar "GitHub for Jira" |
| 13 | SCRUM-192 | Guion de presentación | soporte | 10, 11 | [ ] criterios del agente [x]; falta 👤 ensayo |

Definition of Done para todos los bloques:
- Cumple los criterios.
- Tests unitarios.
- Test de integración con `AppEnvironment` y la infraestructura real compartida, sobre un directorio temporal.
- `make ci` en verde.
- Validado en simulador.
- Funciona sin internet.
- No viola invariantes.
- Actualizados este archivo y `requirements-traceability.md`.

---

### Bloque 0 — Pruebas de UI y bugs de la primera prueba manual (antes del bloque 3)

Origen: la primera prueba manual de Jesús (2026-10-21). Herramienta: target `PRUITests` (XCUIAutomation, equivalente a Cypress), `make test-ui`. Modos de arranque solo en Debug: `-PRFakeSignIn`, `-PRUITestReset` (datos temporales aparte), `-PRFixedDate yyyy-MM-dd`.

- [x] Pantalla negra al tocar Empezar (la cubierta se presentaba con el workout `nil`) → `fullScreenCover(item:)`. Prueba: `testStartShowsTheFirstSetNotABlackScreen`.
- [x] Cuestionario en español (no "Generalhealth"/"Hypertrophy"). Prueba: `testOnboardingOptionsAreInSpanish`.
- [x] La opción elegida se ve marcada (icono + borde + trait). Prueba: `testSelectedOptionIsMarked`.
- [x] Días y minutos por defecto se registran sin mover el selector. Prueba: `testDefaultDaysAndMinutesCanAdvance...`.
- [x] Hoy lista los ejercicios de la sesión. Prueba: `testTodayListsTheExercisesOfTheSession`.
- [x] Lunes con sesión, domingo "Día de descanso"; Export vacío explícito; llegar a Hoy desde el cuestionario.
- [x] Sesión de 60 min con volumen realista → SCRUM-28. Prueba: `testTodaySessionHasRealisticVolume` (ya verde; `make test-ui` sigue aparte de `make ci` por tardar ~4 min).
- [x] Nombres de ejercicios en español: los 678 nombres se tradujeron (`exercise-names-es.json`); el inglés queda como alias de búsqueda. 👤 Jesús: revisar la calidad de los nombres en la app.
- [x] Mínimos de entrenamiento: 2 días y 30 minutos por sesión (antes 20), en una sola constante (`TrainingWeek.allowedSessionMinutes`).

Evidencia: `make ci` → `✔ Test run with 439 tests in 69 suites passed` + `✔ Test run with 274 tests in 54 suites passed` (2026-10-21); `xcodebuild test` de `PRUITests` en simulador iOS: 9 de 10 pasan, falla solo la de volumen.

---

### Bloque 1 — SCRUM-23 · Ver y exportar todo mi historial (P0, READY)

**Bug actual:**
- `AppEnvironment` crea **un solo** `AtomicFileRepositoryStore` en `PR/persistence`. La cola (`PendingOperationQueueStore`) y los workouts escriben ahí.
- `readAll` intenta decodificar todo como `WorkoutSession`, falla con la cola y el error se traga. Resultado: Export muestra 0 sesiones.

**Criterios:**
- [x] Cada colección (workouts, cola de pendientes, perfil, bloque y demás) vive en su propio subdirectorio, y al leer una colección solo se leen sus archivos.
- [x] Con 2 sesiones completadas y al menos 1 operación en cola, Export muestra "2 sesiones".
- [x] El JSON exportado contiene las 2 sesiones con todas sus series, y el CSV tiene exactamente una fila por serie.
- [x] Sin sesiones, Export muestra un estado vacío explícito ("Aún no tienes entrenamientos"), no "0 sesiones".
- [x] Con 1 archivo corrupto entre 3 válidos:
  - se devuelven las 3 válidas;
  - el error se registra sin datos personales;
  - Export avisa que 1 registro no se pudo leer;
  - nunca devuelve 0 en silencio.
- [x] Hay una migración única desde el directorio compartido:
  - cada archivo se mueve a su colección, clasificado por contenido decodificable y no por nombre;
  - no se borra nada antes de haberlo escrito en su destino;
  - si se ejecuta dos veces, la segunda no hace nada.
- [x] El export no incluye tokens, identificadores de Apple ni claves.

Evidencia: commit `7b68b38`; `make ci` → `✔ Test run with 427 tests in 68 suites passed` + `✔ Test run with 250 tests in 49 suites passed` (2026-10-20). Tests en `Packages/PRCore/Tests/PRCoreTests/CollectionPersistenceTests.swift` (15, incluida la integración workout → disco → otra instancia → Export = 1). UI validada con previews en simulador iOS 27.1 (2 sesiones, 1 sesión + ilegible en oscuro, vacío con aviso, error con `.accessibility3`). Decisión: Export cuenta y exporta todas las sesiones guardadas (completadas y abandonadas, con su estado). **Pendiente:** 👤 prueba manual de Jesús con la app corriendo.

**Tests:**
- Unitarios: lectura por colección, lectura tolerante a un archivo corrupto, migración idempotente.
- Integración con `AppEnvironment` real en un directorio temporal: iniciar un workout, completar series y terminar; después `allSessions().count == 1` y el conteo de Export es 1.

**Archivos:** `AppEnvironment.swift`, `RepositoryStore.swift` (`AtomicFileRepositoryStore`), `CodableRepositories.swift`, `PendingOperationStore.swift`, `DataExport*.swift`, `ExportView.swift`.

**👤 Manual (Jesús):** en simulador, hacer 2 entrenamientos e ir a Export para contar sesiones y filas del CSV.

---

### Bloque 2 — SCRUM-27 · Entrenar los días correctos de la semana (P0)

**Bug actual:** en `TodayPlanCoordinator.weekdayIndex`, el lunes da 1 y el índice 0 nunca ocurre. Con 3 días elegidos solo propone 2, y con 7 días sábado y domingo repiten sesión.

**Corrección:** `(weekday + 5) % 7` sobre el `weekday` gregoriano (domingo = 1 … sábado = 7), que da lunes = 0 … domingo = 6. Centralizar este cálculo en **un solo lugar del dominio** (PRDomain).

**Criterios:**
- [x] Para cualquier opción de 2 a 7 días, en los 7 días de la semana exactamente ese número de días propone entrenar.
- [x] En un día libre, Hoy muestra "Día de descanso" y no hay botón de empezar.
- [x] Ningún día repite por error la sesión de otro.
- [x] Lunes da índice 0 y domingo da 6.
- [x] El resultado no cambia con la zona horaria ni con el `firstWeekday` del sistema.

Evidencia: commit `64c95d9`; `make ci` → `✔ Test run with 439 tests in 69 suites passed` + `✔ Test run with 251 tests in 50 suites passed` (2026-10-20). Cálculo único en `PRDomain/TrainingWeek.swift`; tests en `PRDomainTests/TrainingWeekTests.swift` (12) y `PRCoreTests/TodayWeekIntegrationTests.swift` (coordinador real recorriendo 19–25 oct 2026 para N = 2…7). "Zona horaria" se interpreta como día **local** del usuario: el mismo día local da el mismo índice en 5 zonas; cerca de medianoche cuenta el día local, no el de UTC. En día libre el estado es `.restDay` y `TodayView` no tiene botón en ese caso. Regla de días conservada: los primeros N días desde el lunes. **Pendiente:** integración con `AppEnvironment` y plan persistido (espera al bloque 6); 👤 prueba manual de Jesús.

**Actualización (2026-10-22):** integración con plan persistido cubierta por `PRCoreTests/WeekEndToEndTests.swift` (cuestionario real con L/Mi/V, `LocalPersistence` real en directorio temporal, app reabierta cada día con reloj inyectado: entrena L/Mi/V con sesiones distintas y descansa el resto). Queda sólo 👤.

**Tests:**
- Unitarios:
  - tabla de `weekday` 1…7 contra el índice esperado;
  - conteo de días de entrenamiento para cada opción de 2 a 7 días;
  - calendario con un `firstWeekday` distinto.
- Integración con `AppEnvironment` real y reloj inyectado: recorrer los 7 días. Esta parte se completa cuando el bloque 6 persista el plan.

**👤 Manual (Jesús):** cambiar la fecha del simulador a lunes y a domingo y revisar Hoy.

---

### Bloque 3 — SCRUM-189 · CI en GitHub (soporte)

**Criterios:**
- [x] `.github/workflows/ci.yml` corre `make ci` en cada pull request y en cada push a `main`, sobre un runner macOS. El workflow fija la versión de Xcode con una lista explícita (el runner sólo trae 26.5).
- [x] Los logs de `.ci/` se suben como artifact cuando el job falla.
- [x] El resultado se ve en el PR.

**👤 Humano (Jesús):** en GitHub › Settings › Branches, proteger `main` y exigir el check de CI, para que un PR en rojo no se pueda fusionar.

**Estado (2026-10-22):** verde. PR #2 (SCRUM-189) dejó `make ci` en verde con el Xcode 26.5 del runner: el build system `native` de SwiftPM no compilaba el String Catalog (se fija `swiftbuild`), un test dependía del día real y el artifact de `.ci/` salía vacío (carpeta oculta). Corrida verde en `main`: `bb3c472`, run 39731930158. Queda sólo lo 👤: proteger `main`.

**Estado (2026-10-21):** `.github/workflows/ci.yml` corre `make ci` en `macos-26`. **Primera corrida real: falló porque el runner no trae Xcode 27.1** (el riesgo previsto). Se cambió a una lista explícita `XCODE_CANDIDATES: "27.1 27.0 26.5"` (usa la primera instalada, la imprime y falla con la lista de versiones si no hay ninguna). Piso 26.5 = deployment target; el código no usa APIs de iOS 27, así que 26.5 debería compilar. Ningún gate se desactivó. Los criterios siguen en `[ ]` hasta ver una corrida en verde; si vuelve a fallar, pegar el paso "Versiones disponibles" del log. Las pruebas de UI (`make test-ui`) quedan fuera del CI.

**Riesgo:** que el runner de GitHub no tenga todavía Xcode 27.1 o un simulador iOS 27. El agente debe documentarlo y no desactivar gates para ponerlo en verde.

---

### Bloque 4 — SCRUM-24 · No perder el entrenamiento si la app se cierra (P0)

**Bug actual:**
- `WorkoutSessionCoordinator` solo guarda en `onSessionFinished`, con `try? await workoutRepository?.save`.
- `drainSetOperations` nunca se llama.
- No hay restauración del workout activo.

**Criterios:**
- [x] Al iniciar un entrenamiento, la sesión ya está guardada en disco con estado `active`.
- [x] Al completar una serie, queda persistida **antes** de que la UI avance, en menos de 100 ms medidos en el test.
- [x] Con 5 series hechas, tras un cierre forzado y reabrir:
  - aparece "Tienes un entrenamiento en curso";
  - al continuar están las 5 series y sigue la 6.
- [x] El descanso se guarda como **hora de fin**, no como contador. Ejemplo: descanso de 120 s, cierre a los 30 s, reabrir 40 s después: quedan unos 50 s. Si ya terminó, muestra 0 y la siguiente serie lista.
- [x] Al arrancar, la cola de pendientes se drena y queda vacía. Si el drenado corre dos veces, no se duplica ninguna serie.
- [x] En modo avión el resultado es idéntico.
- [x] "Terminar sin completar" con confirmación deja la sesión `abandoned` y conserva las series hechas.
- [x] Si hay 2 sesiones activas por error:
  - se restaura la más reciente;
  - la otra queda `abandoned` con sus series intactas;
  - el evento se registra.
- [x] Ninguna escritura de datos del workout usa `try?`.

**Tests:**
- Unitarios: guardado al iniciar y en cada serie, drenado idempotente, descanso restante calculado desde la hora de fin.
- Integración:
  - `AppEnvironment` sobre un directorio: registrar 5 series y descartar la instancia;
  - crear otra instancia sobre el mismo directorio y verificar que la restauración es exacta;
  - repetir con la cola llena.

Evidencia: `make ci` → `✔ Test run with 451 tests in 71 suites passed` + `✔ Test run with 332 tests in 62 suites passed` (2026-10-21); `PRCoreTests/WorkoutRecoveryTests.swift` (14), `PRDomainTests/WorkoutRecoveryPlannerTests.swift` (7); UI en Xcode, simulador: `testForceQuitMidWorkoutOffersToContinue` (cierre forzado real tras 3 series ⇒ "Tienes un entrenamiento en curso" ⇒ continúa en la serie 4). Diseño: `persistSession` síncrono en `WorkoutSessionCoordinator`, descanso como `RestSnapshot` (hora de fin) dentro del `WorkoutSessionRecord`, `WorkoutRecoveryPlanner` (puro) + `LocalPersistence.recoverWorkout`. "Modo avión idéntico": todo es disco local, sin red (la cobertura es la misma suite; 👤 lo confirma en dispositivo). Los `try?` que quedaban sobre datos de workout se reemplazaron por manejo explícito (`persistenceFailed` + aviso en pantalla).

**👤 Manual (Jesús):** cierre forzado desde el selector de apps, en simulador y en iPhone, también en modo avión.

---

### Bloque 5 — SCRUM-25 · Cerrar bien la sesión al terminar (P0)

**Bug actual:**
- Al completar la última serie el lifecycle no pasa a `completed`.
- `tick()` llama a `currentPhase()`, que llama a `closeAsFinished()`, que lanza `Task { await onSessionFinished(live) }` **en cada tick**: guardados repetidos y concurrentes.

**Criterios:**
- [x] Al completar la última serie, la sesión pasa a `completed` con hora de fin y se muestra el resumen.
- [x] Durante 60 s en el resumen no hay ninguna escritura adicional (verificado con un store espía).
- [x] `tick()` nunca escribe en disco. Solo persisten los cambios de estado: serie, pausa, reanudación, fin y abandono.
- [x] Si faltan series, "Terminar" ofrece "Completar" (`completed`) o "Abandonar" (`abandoned`), y ambas conservan las series hechas.
- [x] Desde un estado final, cualquier otra transición se rechaza.
- [x] En Export el entrenamiento aparece una sola vez y como completado.
- [x] El resumen muestra duración, series de trabajo, volumen y récords, calculados desde los datos guardados.

**Tests:**
- Unitarios: transiciones válidas e inválidas del lifecycle, y `tick()` sin efectos de persistencia.
- Integración: flujo completo como la UI, con un store espía que cuente las escrituras.

Evidencia: misma corrida de `make ci` que el bloque 4; `PRCoreTests/WorkoutClosingTests.swift` (10, con `SpyStore` que cuenta escrituras). Hallazgo: `completeCurrentSet()` aceptaba series en una sesión abandonada; ahora rechaza todo lo que no sea `active`. `complete()` sobre una sesión ya completada es idempotente (no vuelve a escribir).

**Antes de cambiar:** buscar con grep todos los lectores de `lifecycle`.

---

### Bloque 6 — SCRUM-26 · Recordar mi perfil y mi plan (P0)

**Bug actual:** `FileUserProfileRepository` y `FileTrainingBlockRepository` existen, pero `AppEnvironment` no los usa. Cada arranque repite login y cuestionario y genera un bloque con IDs nuevos.

**Criterios:**
- [x] En el primer arranque, al terminar el cuestionario se guardan el perfil y el bloque.
- [x] Al reabrir (al día siguiente y sin internet), se entra directo a Hoy con el mismo bloque y los mismos IDs.
- [x] De la sesión de Apple solo se persiste el identificador del usuario, sin tokens ni correo.
- [x] Al cambiar objetivo, fase o días se genera un bloque nuevo, y el anterior queda cerrado y conservado con su historial.
- [x] "Rehacer cuestionario", temporalmente desde Hoy, ejecuta ese mismo flujo de cambio de plan.
- [x] Si Apple revocó la credencial, la app vuelve al login sin borrar datos locales.
- [x] Si el perfil está corrupto, se ofrece rehacer el cuestionario sin tocar el historial.
- [x] Los datos quedan asociados al identificador del usuario, para que no se mezclen dos cuentas.

**Tests:**
- Unitarios: guardar y leer perfil y bloque, cambio de plan, perfil corrupto.
- Integración: onboarding con `AppEnvironment` real; una segunda instancia sobre el mismo directorio llega a Hoy con el mismo `blockID`.

Evidencia: `make ci` → `✔ Test run with 444 tests in 70 suites passed` + `✔ Test run with 304 tests in 59 suites passed` (2026-10-21); `PRCoreTests/PlanPersistenceTests.swift` (plan, migración, dos cuentas, perfil corrupto, revocación, rehacer) sobre `LocalPersistence` real; UI (Xcode, simulador): 12 de 12, incluidas `testReopeningTheAppGoesStraightToToday` y `testRedoQuestionnaireFromTodayOpensTheQuestionnaire`. Diseño: `StoredPlan`/`StoredSession` (PRDomain), `PlanStore`, `AppSessionCoordinator` (PRCore); la sesión guarda sólo `userID` + versión de formato, las claves de archivo se derivan del ID. Historial y cola de pendientes ahora son por usuario (`users/<clave>/…`, `UserScopedHistoryTests`); el historial anterior a las cuentas lo adopta el primer usuario una sola vez. **Límite:** la revocación se comprueba al arrancar y al volver a primer plano, no en tiempo real. **Pendiente:** 👤 Jesús (instalar, reabrir, modo avión, cuenta revocada real).

**👤 Manual (Jesús):** instalar, completar onboarding, cerrar y reabrir, también en modo avión.

---

### Bloque 7 — SCRUM-28 · Volumen real y una sesión distinta por día (P0)

**Bug actual:** `BlockPlanner.buildSessions` asigna `weeklySets / days` series a **cada ejercicio** y repite la misma plantilla todos los días. Salen sesiones de más de 100 series.

**Criterios:**
- [x] Un músculo con objetivo de 8 series por semana suma 8 en la semana, no 8 por ejercicio.
- [x] Las series se reparten entre los ejercicios y los días de ese músculo.
- [x] Cada día tiene su propia plantilla, y los ejercicios ancla se conservan entre semanas.
- [x] Una sesión pensada para 60 minutos cabe en 60 minutos según el estimador.
- [x] Con 180 minutos no hay más series de trabajo que con 90.
- [x] Un bloque guardado con volumen inflado se regenera o migra al arrancar, conserva IDs de bloque y anclas, y se muestra un aviso breve. Prueba: `PlanPersistenceTests.inflatedPlanIsMigrated`.
- [x] Rangos de series por semana según la prioridad del músculo:
  - mantener: 4–6;
  - normal: 8–12;
  - enfatizar: 12–16;
  - especializar: 16–20.

**Tests:**
- Unitarios: suma semanal contra el objetivo (plan de 3 días de cuerpo completo), plantilla distinta por día, anclas estables, regeneración de un bloque inflado.
- Integración: onboarding real → bloque guardado → recorrer la semana en Hoy sumando series.

Evidencia: `make ci` → `✔ Test run with 443 tests in 70 suites passed` + `✔ Test run with 283 tests in 55 suites passed` (2026-10-21); `PRCoreTests/BlockPlannerRealCatalogTests.swift` (catálogo real, N = 2…7) y rangos por prioridad en `VolumeAllocatorTests`; `make test-ui` → 10 de 10. **Pendiente:** regenerar/migrar bloques guardados con volumen inflado (criterio abierto; depende del bloque 6, que es quien persiste el bloque) y 👤 prueba manual de Jesús.

**👤 Manual (Jesús):** generar planes de 2, 3, 4 y 6 días y revisar las series por sesión.

---

### Mejora de calidad de la asignación de ejercicios (fuera del plan original, 2026-10-21)

**Problema (hallado en la prueba manual):** con el catálogo real, espalda recibía encogimientos, pecho "Vueltas al mundo" y "Press guillotina", y piernas sólo aductores y peso muerto en polea: sin sentadilla, sin curl femoral, sin remo ni jalón.
**Cambio:** lista curada por músculo (`exercise-staples.json`, 63 ejercicios, orden de preferencia; sentadilla → prensa → extensión, press de banca → inclinado → cruce, remo → jalón…). `ExerciseAssigner` elige el primero permitido como ancla y los siguientes como rotatables; sin ejercicios de referencia disponibles usa la selección genérica, ahora prefiriendo los que trabajan el músculo como principal. Un plan guardado con generador anterior se regenera (`currentGeneratorVersion = 3`, mismo ID de bloque) y avisa.
Evidencia: `make ci` → `✔ Test run with 451 tests in 71 suites passed` + `✔ Test run with 338 tests in 63 suites passed` (2026-10-21); `ExerciseSelectionQualityTests` (básicos presentes en 3/4/6 días, nada de guillotina/vueltas al mundo/encogimientos/aductores, cada referencia trabaja el músculo como principal); UI en Xcode: 5 de 5 relacionadas. **Límite:** la lista es una curación del equipo (revisable por Jesús); no cubre equipo fuera de barra/mancuernas/máquina/polea/peso corporal. 👤 Jesús: revisar que las rutinas generadas le parezcan razonables.

### Bloque 8 — SCRUM-29 · Ejercicios en el orden correcto (P0)

**Bug actual:** `BlockPlanner` recibe `orderEngine` y `fatigueEngine` pero nunca los llama. Puede salir tríceps antes del press de banca.

**Criterios:**
- [x] Primero los compuestos principales, luego los secundarios y al final los aislamientos y accesorios.
- [x] Un músculo prioritario puede adelantarse frente a otros del mismo rol.
- [x] Ningún aislamiento va antes de un compuesto que necesita ese músculo fresco: tríceps/press, bíceps/remo.
- [x] La misma entrada produce el mismo orden (determinismo).
- [x] "¿Por qué este orden?" muestra una razón sencilla desde el `DecisionRecord`: rol, prioridad o fatiga.
- [x] La precedencia entre prioridad muscular y fatiga queda documentada en el `DecisionRecord`.

**Tests:**
- Unitarios: `BlockPlanner` invoca ambos motores; casos tríceps/press, bíceps/remo y prioridad; determinismo.
- Integración: orden de cada sesión en Hoy desde el onboarding real.

Evidencia: `make ci` (mismas líneas que el bloque 7, 2026-10-21); `PRDomainTests/BlockPlannerOrderTests.swift` (tríceps/press, bíceps/remo, prioridad, determinismo, explicación + precedencia), `PRCoreTests/BlockPlannerRealCatalogTests.swift` (aislamiento nunca antes de su compuesto, N = 2…7) y `TodayExerciseListTests.orderExplanationMatchesSession`. La hoja "¿Por qué este orden?" (`today.whyOrder`) se verificó por compilación y tests de datos; **pendiente** revisarla en dispositivo/preview y 👤 Jesús. Precedencia: restricciones > rol funcional > prioridad muscular > demanda técnica > interferencia por fatiga.

---

### Bloque 9 — SCRUM-30 · Duración real y ajuste a mi tiempo (P1, F-07 opcional)

Solo se empieza si los bloques 1 a 8 están en `[x]`.

**Criterios:**
- [x] Hoy muestra la duración calculada de la sesión real (series, descansos y transiciones), no la del cuestionario.
- [x] Al elegir 30, 45, 60 o 90 minutos, la sesión se ajusta:
  - primero se quita lo opcional;
  - después se reducen los accesorios;
  - se conservan los ejercicios ancla y los prioritarios.
- [x] La app dice en una frase qué quitó y por qué.
- [x] Con 90 o 180 minutos no se agregan series; como mucho se sugiere movilidad o cardio.
- [x] Si la sesión no cabe ni recortada, la app lo dice claramente en lugar de quitar anclas en silencio.

**Tests:**
- Unitarios: 30, 45, 60, 90 y 180 minutos sobre la misma sesión, y el mensaje de "no cabe".
- Integración: ajuste de tiempo desde el coordinador de Hoy hasta iniciar el workout recortado.

Evidencia: commit `1c50415`; `make ci` → `✔ Test run with 513 tests in 77 suites passed` + `✔ Test run with 478 tests in 86 suites passed` (2026-10-23). Tests en `Packages/PRCore/Tests/PRDomainTests/SessionTimeFitTests.swift` (30/45/60/90/180 sobre la misma sesión, no cabe, opcional primero, prioritario, calentamiento, día) y `Packages/PRCore/Tests/PRCoreTests/SessionTimeBudgetTests.swift` (plan real del motor; integración con `LocalPersistence` en directorio temporal: ajuste guardado → workout recortado → cierre forzado → se retoma igual; sin cambio con workout en curso; al día siguiente no aplica). Validado en simulador iPad: Hoy muestra ~17 min reales (antes ~60), "Tengo 30 min" con la frase de tiempo de sobra, sobrevive a reabrir y "Sesión completa" lo quita. **Pendiente:** 👤 Jesús, probar cada opción con una sesión larga (que sí recorte) en dispositivo.

---

### Bloque 10 — SCRUM-190 · Pruebas de los flujos (soporte)

**Agente:**
- [x] Crear `docs/poc/pruebas-flujos.md` con una lista de pruebas por flujo, cada una con pasos y resultado esperado:
  1. Primer uso.
  2. Entrenar.
  3. Recuperación (cierre forzado y modo avión).
  4. Exportar.
- [x] Ejecutar las pruebas automatizables y anotar resultado y fecha.

Evidencia: commits `fd7074c` (lista de pruebas y `testExportCountsTheFirstWorkout`) y `e3de2e7` (resultados), rama al día con `main` (`787144e`).
- `make test-ui` → `Executed 30 tests, with 0 failures (0 unexpected) in 1306.026 seconds` (2026-10-26, simulador "PR UI Tests").
- `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `Test run with 496 tests in 90 suites passed … with 5 known issues` (2026-10-26). Los 5 *known issues* son los de la caracterización de SCRUM-214.
- Unidad e integración por flujo: 91, 74, 18 y 7 en verde (2026-10-23).
- UI por flujo: 9, 6, 1 y 2 en verde (2026-10-26).

**👤 Humano (Jesús):** ejecutar las pruebas manuales (cierre forzado, modo avión, iPhone real) y anotar pasó/falló con fecha. En `pruebas-flujos.md` son P1.8, P3.1, P3.7 y P4.7.

---

### Bloque 11 — SCRUM-188 · Ambiente demo (soporte)

**Agente:**
- [x] Datos demo: un perfil de ejemplo y 2 semanas de historial.
  - Se cargan **solo** con un launch argument, por ejemplo `-PRDemoData`.
  - Usan un directorio de persistencia **separado**.
  - **Nunca** se mezclan con datos reales ni se activan en Release.
  - Tienen un test que lo verifica.
- [x] Scheme o instrucciones para correr el demo en el simulador.

Evidencia: commit `7ecb106`; `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `✔ Test run with 494 tests in 89 suites passed` (2026-10-25; línea base 520 + 488).
- **Tests:** `Packages/PRCore/Tests/PRCoreTests/DemoDataTests.swift` (6). Cubren:
  - el argumento solo en Debug, nunca en Release;
  - el inicio de sesión simulado solo en Debug;
  - directorio aparte, sin estar uno dentro del otro;
  - siembra con `LocalPersistence` en directorio temporal:
    - 8 entrenamientos en los días elegidos;
    - cada serie planeada registrada;
    - nada que la rodilla prohíba;
    - avance de la semana 1 a la 2;
    - récords del bloque;
  - determinista e idempotente;
  - un plan ilegible no se sobrescribe.
- **Instrucciones:** `docs/poc/ambiente-demo.md`.
- **Simulador (iPad A16):** con `-PRDemoData` entra solo hasta "Personaliza tu plan con IA". Después:
  - Hoy muestra L, M, J y V completados;
  - Progreso muestra "4 de 4", 64 series, racha de 2 semanas, 48 récords del bloque, la gráfica de 2 semanas y "Registro · 8".
- **Corrección incluida:** un bloque nuevo empieza con el reloj de la app. Antes `TrainingBlock` tomaba `Date()` y "Récords del bloque" quedaba en 0 con el demo o con `-PRFixedDate`.

**👤 Humano (Jesús):**
- Firma de desarrollo o TestFlight (requiere cuenta de Apple Developer).
- Instalar en el iPhone.
- Grabar el video de respaldo en el simulador.

---

### Bloque 12 — SCRUM-191 · Integración GitHub–Jira (soporte)

**Agente:**
- [x] Todos los commits y ramas desde ahora llevan la clave `SCRUM-XX` (regla en AGENTS.md).

Evidencia (2026-10-26, `main` @ `e32fe97`):
- **Commits:** desde que entró la regla (`08f5930`, 2026-10-20) hay 80 commits en `main` sin contar merges, y 78 empiezan con `SCRUM-XX`.
  - Excepciones: `51df8c2` y `8716e7e` (2026-10-21), dos commits de documentación (`docs(ux)`, `docs(mvp-plan)`).
  - Desde entonces, 53 de 53 llevan la clave.
- **Ramas:** las de los PR #2, #4 y #5 llevan la clave (`SCRUM-189-ci-xcode-26-5`, `scrum-193-198-cierre-huecos`, `SCRUM-186-progreso-historial`), y también todas las ramas de trabajo desde el 25 de octubre.
  - Excepción: la del PR #1 (`claude/swiftui-auditoria-ui-design-063bc9`, 2026-10-21).
- **Comprobación:** `git log --no-merges --invert-grep --grep="^SCRUM-" 08f5930..origin/main`.

**👤 Humano (Jesús):**
- Instalar la app "GitHub for Jira" en `creadevs` y conectarla al repo `JAlcon00/Nucleus`.
  - Al instalarla, verificar que enlaza la rama en minúsculas `scrum-193-198-cierre-huecos`. Si no la enlaza, las ramas nuevas van en mayúsculas, como `SCRUM-23-...`.
- Opcional: automatización que mueva la historia a **TEST** al fusionar el PR.

---

### Bloque 13 — SCRUM-192 · Presentación con demo (soporte)

**Agente:**
- [x] Borrador del guion en `docs/poc/guion-demo.md`, sin tecnicismos y de 10 minutos o menos, en este orden:
  1. El problema.
  2. Qué es Nucleus.
  3. Demo en vivo: primer uso, entrenar, cerrar y retomar.
  4. Cómo sabemos que funciona.
  5. Qué sigue.

Evidencia: commit `da984cf` (solo documento; `make guards` en verde).
- El guion recorre F-01 a F-07 en 10:00. Usa una Pantalla A sin datos para el primer uso y una Pantalla B con `-PRDemoData` para el historial.
- **Textos de la app:** salen del código. Hoy con datos demo se revisó en el simulador el 2026-10-26: "Hola, Alex · Torso A · 20 series · ~40 min", "Ajustar a mi tiempo" con 30/45/60/90 min, etiquetas RIR y dropset, "Última vez", "¿Por qué este orden?", "Ordenar" y "Empezar Torso A".
- **Sin recorrer en simulador:** entrenar, retomar y el resumen, por la entrada lenta del simulador (SCRUM-217). Esos flujos los cubren las pruebas de UI de F-05 y F-06.

**👤 Humano (Jesús):** ensayar al menos una vez con el demo real.

---

## 3.1 Bloques UX del POC (agregados el 2026-10-22)

- **Fuente:** `docs/ux/auditoria-ui-2026-10-22.md`. Es la auditoría y la spec completa: tokens, contrastes medidos, referencias de Hevy/Alpha/Fitbod y la maqueta de "Tu semana".
- **Excepción a la congelación de P1:** estas historias **sí entran**. Son el pulido del demo (F-02, F-03, S-05), y los bloques P0 1 a 8 ya tienen sus criterios cumplidos.
- **Orden:** empiezan después del bloque 8 y antes de los bloques de soporte 10 a 13.
- **Forma de trabajo:** cada bloque se trabaja como historia completa, con la DoD de la sección 3 y el modo de AGENTS.md (U3 y U5 van primero en modo lógica).

| # | Jira | Qué | Prioridad | Depende de | Estado |
|---|---|---|---|---|---|
| U2 | SCRUM-193 | Estados de carga reales; Hoy nunca muestra "Descanso" mientras carga | P1 (primero) | — | [x] |
| U1 | SCRUM-194 | Paleta Iron Energy, tema oscuro, `EnergyButtonStyle` (texto negro sobre el acento) | P1 | U2 | [x] |
| U6 | SCRUM-195 | Pestañas en español, Sign in with Apple oficial, acciones terciarias a Perfil | P1 | U1 | [x] |
| U3 | SCRUM-196 | Elegir días (L/Mi/V…) con descanso intercalado + migración del plan | P1 | — | [x] |
| U4 | SCRUM-197 | "Tu semana": Lunes · Pull, Miércoles · Push…, tira semanal en Hoy | P1 | U3 | [x] |
| U5 | SCRUM-198 | "Sobre ti": nombre, edad, sexo, estatura y peso (local, con migración) | P1 | U1 + 👤 decisión de edad mínima (2026-10-21: **18 años**) | [x] |

- **Decisiones de producto (2026-10-21):** edad mínima 18 años; nombres de sesión Push · Pull · Pierna (Torso/Pierna en Upper/Lower, Cuerpo completo en Full Body).
- Evidencia: `make ci` → "Test run with 482 tests in 73 suites passed" (PRDomain), "Test run with 373 tests in 68 suites passed" (PRCore), XCTest 151 sin fallos, build iOS y watchOS OK, sin warnings nuevos. Tests por bloque: U2 `TodayLoadingStateTests` (8); U6 `TrainingVocabularyPresenterTests` (8); U3 `TrainingDaysTests` (20, con fixture del perfil anterior) y `PlanDaysMigrationTests` (2, plan real reescrito como la versión anterior); U4 `WeekOverviewTests` (12); U5 `AboutYouTests` (11, con fixture del perfil anterior) y `AboutYouFlowTests` (5).
- Evidencia UI: `make test-ui` (iPad A16, iOS 27.1) → 18 de 18 pruebas de `PRUITests` en verde, con las nuevas de pestañas en español, chips de días, "Tu semana", tira semanal y "Sobre ti" con el mínimo de 18.
- 👤 Pendiente en dispositivo (Jesús): VoiceOver real, sol directo, Liquid Glass del tab bar sobre carbón con Reduce Transparency e Increase Contrast y la transparencia de iOS 27 en ambos extremos; layout en iPhone pequeño (las pruebas de UI corren en iPad).
- **Cierre de huecos frente a los criterios de Jira (2026-10-22, rama `scrum-193-198-cierre-huecos`):**
  - U2: prueba de UI `testPendingPlanNeverShowsRestDay` (plan demorado a propósito con `-PRUITestPlanDelay`, sólo Debug: se ve la carga y nunca "Día de descanso"). El skeleton de Hoy sólo aparece al reintentar tras un error; al arrancar, el plan pendiente se muestra con "Armando tu semana".
  - U1: guard de colores en `make ci` (`scripts/check_color_tokens.sh`) y previews de Onboarding con `.accessibility3`.
  - U3: cambiar qué días se entrena crea bloque nuevo (como pide el criterio); chips con palomita además del color; integración de punta a punta L/Mi/V → Hoy correcto los 7 días (`WeekEndToEndTests`).
  - U4: músculos como chips (`MuscleChips`, bajan de línea con Dynamic Type); integración plan real de 3 días → "Tu semana" = Hoy los 7 días.
  - U5: cada dato inválido se explica junto a su campo (`AboutYouAnswer.issues`); estatura en cm o ft/in (se guarda en cm); el nombre de Apple prellena "Sobre ti"; el export incluye "Sobre ti" sólo si la persona lo activa; guard de logs en `make ci` (`scripts/check_privacy_logs.sh`).
  - Evidencia: `make ci` → "Test run with 484 tests in 73 suites passed" (PRDomain), "Test run with 378 tests in 70 suites passed" (PRCore), XCTest 151 sin fallos, build iOS y watchOS OK, guards de documentación, colores y privacidad OK, sin warnings nuevos (sólo el aviso de metadatos de AppIntents de Xcode, que ya existía).
  - Evidencia UI: `make test-ui` (iPad A16, iOS 27.1) → 19 de 19 pruebas de `PRUITests` en verde, incluida la nueva `testPendingPlanNeverShowsRestDay`.

**Reglas que no se negocian en estos bloques:**
- **Contraste:** nunca texto blanco sobre `#FF3D2E` (3.22:1) ni sobre `#FF7A1A` (2.39:1). Sobre el acento se usa `onAccent` (negro carbón).
- **Colores en un solo lugar:** ningún color fuera de `DesignTokens.swift`.
- **Copy del plan:** el plan lo arma el motor, no la IA. Nunca "La IA está creando tu rutina".
- **Personalización con IA (SCRUM-205):** el motor arma el bloque con todo el perfil. Con consentimiento y conexión, la IA sólo propone énfasis (máx. 2 músculos de las prioridades) y sustituciones (máx. 3, elegidas de alternativas que el motor ya filtró: mismo músculo, misma clase, equipo y restricciones). Todo pasa por `PlanPersonalizationValidator` + `ActionPolicyValidator`, queda en `AgentAuditRecord` y se guarda con el plan. "Por qué tu plan es así" sólo se acepta de la IA si cada número viene de los hechos del motor; si no, texto local. La IA caída deja el plan del motor igual.
- **Migraciones con fixture:** las del plan (U3) y del perfil (U5) llevan test con fixture de la versión anterior. Son integridad de datos P0.
- **Datos personales de U5:** no van a logs ni a analytics. Al LLM sólo con consentimiento explícito (SCRUM-202, decisión de Jesús 2026-10-22): edad, sexo, estatura, peso, objetivo, fase, experiencia, restricciones activas (sin notas), días, minutos, variedad y check-in de sueño; nunca el nombre ni IDs. Se puede retirar en Perfil y aplica al instante.
- **Llave de la IA (SCRUM-204):** sólo en Debug y sólo en la Mac del desarrollador (`NVIDIA_API_KEY` o `.env` ignorado; scheme local no compartido para iPhone). Release no la busca y usa el motor local. Toda falla de la IA es "no disponible", nunca bloquea el plan. `check_secrets.sh` en `make guards`. Antes de TestFlight la llave va a un backend.

### Excepción P2 · SCRUM-199 · Identidad visual v2 (2026-10-22)

- Aprobada por Jesús: se ejecuta aunque este plan tiene casillas abiertas, porque es sólo de assets y configuración (no toca PRDomain ni PRCore).
- Fuente: paquete `NucleusIdentidad.zip` (ícono claro/oscuro/tintado, AccentColor, `Brand Colors`, `Brand Logos`, `LaunchLogo`).
- [x] Catálogos de iOS y Watch con ícono, acento, colores y logos; símbolos generados (`ironRed`, `logoHorizontal`…).
- [x] Pantalla de arranque en `PR/Info.plist` (`LaunchBackground` + `LaunchLogo`), sin tocar `project.pbxproj`.
- [x] Los 6 colores de marca de `DesignTokens.swift` salen del catálogo; ningún hex de la paleta en código Swift.
- [x] Logo horizontal en el inicio de sesión e isotipo en "Conectando con Apple…".
- [ ] 👤 Jesús: ícono oscuro y tintado (estilo de íconos de la pantalla de inicio), arranque en frío en iPhone SE y Pro Max, ícono del Watch.

## 3.2 IA personalizada · SCRUM-201 (2026-10-22) — terminada

| # | Jira | Qué | Estado |
|---|---|---|---|
| IA-1 | SCRUM-202 | Consentimiento y contexto del perfil para la IA | [x] |
| IA-2 | SCRUM-203 | Check-in diario de sueño que aligera el día | [x] |
| IA-3 | SCRUM-204 | Conexión con la IA sólo en Debug con llave local + guard de secretos | [x] |
| IA-4 | SCRUM-205 | Plan personalizado por IA tras el formulario y "Por qué tu plan es así" | [x] |
| IA-5 | SCRUM-206 | Apple Salud opcional para prellenar "Sobre ti" | [x] |

- Evidencia: commits `cc16bcc`, `0b0a1f6`, `335d7d3`, `32cbc57` y `413a326` en main; `make ci` en verde en cada uno. La evidencia detallada está en el comentario de cada historia en Jira.
- [ ] 👤 Jesús: probar la IA real con la llave en `.env` (simulador) y Salud en un iPhone físico con datos reales.
- Antes de TestFlight: mover la llave de la IA a un backend (historia por crear).

## 3.3 Feedback del stakeholder · SCRUM-207 (2026-10-22) — terminada

- **Decisiones de Jesús (2026-10-22):**
  - formulario con 3 flujos según la experiencia;
  - restricciones con zona del cuerpo + texto opcional;
  - se quita el paso "Gimnasio".
- **Orden:** FB-1 → FB-2 → FB-3 → FB-4 → FB-5 → FB-6. Cada una se sube a main con `make ci` y `make test-ui` en verde.

| # | Jira | Qué | Estado |
|---|---|---|---|
| FB-1 | SCRUM-208 | Perfil: modo claro (Sistema/Claro/Oscuro) y cerrar sesión | [x] `13df62f` |
| FB-2 | SCRUM-209 | Formulario: quitar "Gimnasio" y restricciones con zona + texto | [x] |
| FB-3 | SCRUM-210 | Formulario adaptado al nivel de experiencia (3 flujos) | [x] |
| FB-4 | SCRUM-211 | Reordenar los ejercicios del día | [x] |
| FB-5 | SCRUM-212 | Saltar o dejar en espera ejercicios durante el entrenamiento | [x] |
| FB-6 | SCRUM-213 | Progreso: 4 KPIs y gráfica | [x] |

## 3.4 Repriorización 2026-10-25 (RICE + MoSCoW)

- **Decisión de Jesús (2026-10-25):** SCRUM-31 va antes del soporte del demo, por la regla P0 de AGENTS §5 (un bug que salta una restricción bloquea lo demás).
- **Orden del agente para el demo:** SCRUM-31 → SCRUM-216 (Perfil › Restricciones, solo lectura) → SCRUM-188 → SCRUM-192 → cierre de SCRUM-190 → SCRUM-214.
- El detalle y los puntajes RICE están en Jira, en el comentario "Priorización 2026-10-25" de cada issue.

### SCRUM-31 · Mis restricciones nunca se saltan (P0, Fase C)

**Criterios:**
- [x] Con restricciones en vigor, ni el plan, ni las sustituciones, ni lo que se le ofrece a la IA traen un ejercicio prohibido.
- [x] El permiso (allow-list) de una restricción solo refina esa restricción; nunca anula la prohibición de otra.
- [x] Con varias restricciones, un ejercicio vale solo si ninguna lo prohíbe, en cualquier orden. Prohibir por ID gana incluso al permiso de la misma restricción.
- [x] Una restricción resuelta ya no limita.
- [x] Con la fecha de revisión vencida, la restricción sigue aplicando hasta que se confirme que se resolvió (RN-004).
- [ ] La app pregunta "¿cómo sigues?" al vencer la fecha de revisión: es de UI, va con SCRUM-216 y SCRUM-36 (hoy Perfil › Restricciones no recibe datos).
- [x] Si no queda ningún ejercicio seguro para un músculo, se omite y la explicación lo dice; nunca se fuerza uno.
- [x] Una sola implementación: `RestrictionPolicyEngine.verdict(for:under:scope:)`. La usan el plan (`ExerciseAssigner`), las sustituciones, la IA (`PlanPersonalizationValidator`) y el dropset (`IntensityAdvisor`).

Evidencia: commit `285a4ff`; `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `✔ Test run with 482 tests in 87 suites passed` (2026-10-25; línea base 513 + 478).
- **Tests de dominio:** `Packages/PRCore/Tests/PRDomainTests/RestrictionPermissionTests.swift`. Cubren plan, sustitución y dropset con:
  - permisos cruzados hombro + rodilla;
  - prohibir por ID contra el permiso de la misma restricción;
  - todas las permutaciones de 3 restricciones;
  - restricción resuelta;
  - fecha de revisión vencida;
  - regla por defecto igual a la versionada.
- **Tests con el catálogo real:** `Packages/PRCore/Tests/PRCoreTests/RestrictionsNeverBypassedTests.swift`. Cubren:
  - plan guardado con `LocalPersistence` en directorio temporal y reabierto;
  - sustituciones con todo el catálogo;
  - alternativas para la IA y rechazo de una propuesta prohibida;
  - dropset;
  - músculo sin ejercicio seguro;
  - 100 planes con semilla fija. Antes del arreglo 28 de 100 traían algo prohibido; ahora 0.
- **Por qué no hay prueba en simulador:** hoy ninguna pantalla crea permisos ni resuelve restricciones. La regresión de las zonas del formulario la cubre `RestrictionZonesTests`.
- **La integración no usa `AppEnvironment`:** vive en el target de la app. Se usan `TodayPlanCoordinator` y `LocalPersistence` reales.

### SCRUM-216 · Perfil › Restricciones muestra las que declaré (solo lectura, demo)

**Criterios:**
- [x] Cada restricción del perfil se ve con su zona, su lado, su nota y su origen ("La declaraste tú" o "Indicación de un profesional"), en palabras simples. También se ve si el plan la sigue cuidando; con la fecha de revisión vencida sigue cuidándose (RN-004).
- [x] Sin restricciones hay un estado vacío que explica cómo agregarlas (rehacer el cuestionario). La nota del paso "Restricciones" se muestra aparte y dice que no cambia el plan.
- [x] No hay botones que no hagan nada: "Nueva", "Marcar como revisado" y "Resolver" se quitaron hasta SCRUM-36.
- [x] Una sola fuente: la lista sale de `completedProfile`, que es el perfil que restaura `TodayPlanCoordinator.restore` y con el que se arma el plan. La traducción vive en `RestrictionListPresenter` (PRCore); la vista no decide nada.
- [x] Accesible:
  - VoiceOver lee cada restricción en una frase (zona, lado, origen, estado y nota).
  - El texto escala, y con letra muy grande el lado baja a su propia línea.
  - El estado lleva texto además de icono y color.
  - Contraste medido (5.22:1 a 10.75:1 en claro y oscuro).

Evidencia: commit `f55256f`; `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `✔ Test run with 488 tests in 88 suites passed` (2026-10-25; línea base 520 + 482).
- **Tests:** `Packages/PRCore/Tests/PRCoreTests/RestrictionListPresenterTests.swift` (6). Cubren:
  - codo del cuestionario con nota;
  - indicación profesional con lado, nota y revisión vencida;
  - orden;
  - estados vacíos;
  - inglés;
  - integración con `LocalPersistence` en directorio temporal (perfil guardado y reabierto llega a la pantalla, y el plan restaurado respeta esa misma restricción).
- **Previews:** con restricciones en claro, oscuro y `.accessibility3`; vacío; vacío con nota en oscuro.
- **Simulador (iPad A16):** con un perfil real hecho en el cuestionario (codo + nota), Perfil › Restricciones muestra "Codo · La declaraste tú · Tu plan la cuida." y "Tu nota", sin botones.
- **Pendiente en simulador:** no se vio la fila profesional con revisión vencida ni el estado vacío. Los toques del simulador fallan (mismo problema de entorno que SCRUM-217); los cubren los tests y las previews.

### SCRUM-214 · PR-B001 Test de caracterización del motor de rutinas (Should, demo)

**Criterios:**
- [x] Con el catálogo real, una muestra determinista de 200 perfiles de la matriz reporta las rutinas distintas en total y por número de días. La matriz es {días 2–7} × {variedad} × {objetivo} × {experiencia} × {fase} × {30, 45, 60, 90, 120 min}.
- [x] El gate de la Fase B queda escrito en el test. Cada comprobación que hoy falla va en su propio `withKnownIssue`, que apunta a la historia que la arregla:
  - el objetivo cambia los ejercicios → SCRUM-219;
  - la experiencia cambia los ejercicios → SCRUM-215 y SCRUM-219;
  - ningún ejercicio con 1 serie → SCRUM-218;
  - pantorrilla y core en el plan → SCRUM-215.
- [x] Mismo perfil y mismo bloque ⇒ la misma rutina.
- [x] No exige más series con más minutos (PR-B003 espera la decisión D1, SCRUM-220).
- [x] No rompe `make ci` y tarda menos de 10 s (~1.2 s).

**Línea base del 2026-10-26** (`main` @ `237c831`; el log de `make ci` la imprime con el prefijo `[PR-B001]`):

| Medida | Hoy | Meta de la Fase B |
|---|---|---|
| Conjuntos de ejercicios distintos en 200 perfiles | **2** (56 variantes de orden y series) | Que cambien con objetivo y experiencia |
| Conjuntos por número de días (2 a 7) | 2 en cada uno | — |
| Conjuntos por variedad | 1 por variedad; dos variedades comparten el mismo | — |
| Pares fuerza/hipertrofia con ejercicios distintos | **0/40** (0 %) | ≥ 80 % |
| Pares novato/avanzado con ejercicios distintos | **0/40** (0 %) | ≥ 80 % |
| Ejercicios con menos de 2 series de trabajo | **1,394 de 5,943** (23 %) | 0 |
| Planes con pantorrilla / con core | **0/200** / **0/200** | 200/200 |

**Conclusión:** hoy el conjunto de ejercicios solo depende de la variedad. Objetivo, fase, experiencia, minutos y días cambian el reparto de series y el orden, pero no qué ejercicios salen. Es más drástico que la simulación de la auditoría (16 conjuntos en 8,100 perfiles, sobre `0b0a1f6`).

Evidencia: commit `a4aacd4`; `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `Test run with 496 tests in 90 suites passed … with 5 known issues` (2026-10-26; línea base 520 + 494). Test en `Packages/PRCore/Tests/PRCoreTests/RoutineCharacterizationTests.swift`.

### SCRUM-217 · Entorno de pruebas de UI estable (Should, demo)

**Criterios:**
- [x] Con el simulador recién arrancado, `make test-ui` corre todas las pruebas de UI de principio a fin dos veces seguidas, sin colgarse, y deja el resultado por prueba. Hoy son 28 en `main`; la 29.ª, `testExportCountsTheFirstWorkout`, llega con SCRUM-190.
- [x] El README documenta cómo preparar el simulador (teclado físico, destino, cómo recuperarlo si se cuelga).
- [x] Los cambios a las pruebas dicen por qué, y el bug real encontrado se reporta (ver abajo).

**Causas:**
1. **El cuelgue:** cuando fallaba una prueba, `xcodebuild` se quedaba esperando a `simctl diagnose`. Ahora corre con `-collect-test-diagnostics never`.
2. **"Sobre ti":** el iPad de pruebas quedó con "teclado físico visto" (`HardwareKeyboardLastSeen`). El teclado en pantalla se minimiza y el peso que escribe la prueba no llega. Ahora las pruebas corren en un simulador propio, "PR UI Tests" (iPhone), que se borra y arranca limpio en cada corrida.

**Bug real encontrado (se arregla aparte):** en iPhone, con "¿Cómo dormiste?" en Hoy, la lista de ejercicios queda de **24 pt** de alto y apenas se ve media fila.

Evidencia: commit `024cc33`.
- `make test-ui` ×2 seguidas el 2026-10-26: `Executed 28 tests, with 0 failures` (1,199 s) y `Executed 28 tests, with 0 failures` (1,211 s), `make exit=0` las dos.
- `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `Test run with 496 tests in 90 suites passed … with 5 known issues` (las de SCRUM-214).

### SCRUM-222 · Hoy en iPhone: los ejercicios se ven con "¿Cómo dormiste?" (Must, demo)

**Criterios:**
- [x] En iPhone, con "¿Cómo dormiste?", toda la pantalla se desplaza y los ejercicios quedan a un deslizamiento. Antes la lista medía 24 pt.
- [x] "Empezar", "Ordenar" y "¿Por qué este orden?" quedan fijos abajo, siempre a la vista.
- [x] Lo que se desplaza pasa por debajo de la tira de la semana sin mezclarse. La tarjeta de sueño entra y sale con animación que respeta Reducir movimiento.
- [x] Previews en iPhone chico y grande, en claro y oscuro, y `.accessibility3`. Sin lógica nueva en la vista.
- [ ] 👤 Revisarlo en un iPhone real, chico y grande.

Evidencia: commit `42ffa7b`.
- `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `Test run with 496 tests in 90 suites passed … with 5 known issues`.
- `make test-ui` (simulador "PR UI Tests", iPhone 18 Pro) → `Executed 29 tests, with 0 failures`. Incluye la nueva `testTodayExercisesStayReachableWithSleepCheckIn`, y `testReorderTodayExercisesAndReset` ya no esquiva el bug (2026-10-26).
- Capturas en simulador: Hoy con la tarjeta y tras deslizar, con la tira de la semana limpia.

## 4. Después del POC (no empezar todavía)

En orden: Fase C (restricciones ~~SCRUM-31~~ hecha el 2026-10-25, 32, 36) → Fase D (agente SCRUM-33, 34) → deuda (SCRUM-35, 37–40) → HealthKit, Watch, pestañas.

### SCRUM-40 · PR-0118 Migraciones seguras de datos guardados (Must 1.0, adelantada en rama)

- **Decisión de Jesús (2026-10-26):** se trabaja en paralelo con las pruebas manuales del POC.
- Va en la rama `SCRUM-40-migraciones` y **no se sube a `main` hasta después del demo**, porque toca la persistencia.
- Criterios aprobados en Jira el 2026-10-26.

**Criterios:**
- [x] Versión por colección: cada carpeta guarda la suya (`.schema-version`); sin marca es la 1.
- [x] Migra en orden y una sola vez, también las colecciones de cada usuario. Un corte a la mitad se termina al siguiente arranque sin perder ni duplicar.
- [x] Nunca se pierde el original:
  - se escribe aparte y se verifica antes de cambiar las carpetas;
  - queda un respaldo de la versión anterior;
  - un registro que no migra va intacto a cuarentena y el resto sí migra.
- [x] Aviso: lo que está en cuarentena cuenta en el "no pude leer N" de Exportar y Progreso. Un plan en cuarentena da "plan ilegible".
- [x] Con una versión más nueva, una marca ilegible o un paso faltante no se toca nada, y se registra.
- [x] Detector en CI: muestras v1 reales de las 7 colecciones que la app escribe. Probado: renombrar un campo de `SleepCheckIn` hace fallar `PersistenceFormatTests`.
- [x] Regla escrita: ADR-0003 y `AGENTS.md` §3.1.

Evidencia: commit `cf58811` (rama `SCRUM-40-migraciones`).
- `make ci` → `✔ Test run with 520 tests in 78 suites passed` + `Test run with 521 tests in 92 suites passed … with 5 known issues` (2026-10-26; línea base 520 + 496). Los 5 *known issues* son los de SCRUM-214. El build de iOS y el de watchOS pasaron.
- **Tests:**
  - `Packages/PRCore/Tests/PRCoreTests/SchemaMigrationTests.swift` (18): cubren todo lo de arriba más la integración con el historial demo real. Pasan del layout antiguo a carpetas y a versiones, Exportar cuenta lo mismo, y con un paso nuevo que rechaza un entrenamiento, Exportar avisa 1 ilegible y el respaldo conserva los 8.
  - `PersistenceFormatTests.swift` (7): el generador de muestras solo corre con `PR_WRITE_PERSISTENCE_FIXTURES=1`.
- **Pendiente:** 👤 Jesús, actualizar la app en un iPhone con datos reales. El historial, el plan y Progreso deben verse igual, y la marca se escribe sola.
