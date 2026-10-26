# Pruebas de los flujos del POC (SCRUM-190)

Lista de pruebas de los 4 flujos del demo, con su resultado esperado y cómo se comprueba cada una. El resultado se anota con fecha:

- ✅ pasó
- ❌ falló
- ⛔ no se pudo correr (bloqueo del entorno, explicado abajo)
- 👤 pendiente: prueba manual de Jesús

## Cómo correrlas

| Tipo | Comando | Dónde |
|---|---|---|
| Unidad e integración | `make ci` (todo) o `swift test --build-system swiftbuild --filter "<suites>"` dentro de `Packages/PRCore` | Mac, sin simulador |
| UI (XCUIAutomation) | `make test-ui` | Simulador iPad (A16); fuera de `make ci` |
| Manual 👤 | Pasos de cada fila | iPhone real |

Suites por flujo (para `--filter`):

- **Flujo 1:** `AuthLaunchModeTests|AppSessionTests|OnboardingCoordinatorTests|OnboardingChoicesTests|AboutYouFlowTests|PlanPersistenceTests|PlanDaysMigrationTests|BlockPlannerRealCatalogTests|TodayPlanCoordinatorTests|TodayExerciseListTests|ExperienceFlowTests|RestrictionZonesTests`
- **Flujo 2:** `WorkoutSessionCoordinatorTests|WorkoutQueueTests|WorkoutClosingTests|SessionOrderTests|SessionTimeBudgetTests|IntensityFlowTests|ProgressHistoryTests|ProgressInsightsTests|SleepCheckInTests|ReadinessEngineTests|SessionTimeFitTests`
- **Flujo 3:** `WorkoutRecoveryTests|UserScopedHistoryTests`
- **Flujo 4:** `ExportHistoryTests|WorkoutHistoryIntegrationTests|AboutYouExportTests`

## Resumen de la última corrida (2026-10-23)

| Flujo | Unidad e integración | UI en simulador | Manual 👤 |
|---|---|---|---|
| 1 · Primer uso | ✅ 91 de 91 | ⛔ bloqueada | 👤 sin internet |
| 2 · Entrenar | ✅ 74 de 74 (61 PRCore + 13 PRDomain) | ⛔ bloqueada | — |
| 3 · Recuperación | ✅ 18 de 18 | ⛔ bloqueada | 👤 cierre forzado y modo avión |
| 4 · Exportar | ✅ 7 de 7 | ⛔ bloqueada | 👤 abrir los archivos |

`make ci` completo en verde el mismo día: `✔ Test run with 513 tests in 77 suites passed` + `✔ Test run with 478 tests in 86 suites passed`.

## Bloqueo de las pruebas de UI (2026-10-23)

**Síntoma.** Todas las pruebas de UI pasan por "Sobre ti", y todas fallan en el mismo paso: tras escribir el peso, el toque en "Continuar" no avanza (`No aparece 'onboarding.option.intermediate'`). Se repitió 3 veces, también con un test que no cambió (`testOnboardingReachesToday`). En un 4º intento, con el teclado en pantalla oculto, el runner se quedó en la pantalla de inicio y se canceló.

**Evidencia.**
- El video y la jerarquía que guarda XCTest muestran el formulario completo (30 años, Hombre, 72 kg) y "Continuar" habilitado, con el teclado en pantalla abierto. El toque no hace nada.
- Las mismas pruebas pasaban en corridas anteriores, por ejemplo `make test-ui` 20 de 20 en SCRUM-186.

**No es un bug de la app.** A mano, con el teclado en pantalla abierto, escribir 72 con sus teclas y tocar "Continuar" sí avanza a "Paso 1 de 7 · Experiencia" (simulador iPad, 2026-10-23 15:32). Quien use el iPad con el teclado en pantalla no se queda atorado.

**Causa probable: el entorno.** Tras reiniciar el simulador con `simctl boot`, durante las pruebas aparece el teclado en pantalla. Con él abierto, el toque que simula XCUITest en "Continuar" no llega.

**Para desbloquear:**
1. Abrir el simulador desde Simulator.app con *I/O → Keyboard → Connect Hardware Keyboard* activo, o reiniciarlo desde Xcode.
2. Correr `make test-ui` y anotar aquí el resultado de cada prueba de UI.
3. Si se quiere que las pruebas no dependan del teclado, cambiar el ayudante para cerrar el teclado antes de "Continuar". Es una decisión pendiente: no lo hice para no esconder un posible problema real.

## Flujo 1 · Primer uso

| ID | Prueba (pasos) | Resultado esperado | Cómo se comprueba | Resultado |
|---|---|---|---|---|
| P1.1 | Abrir la app por primera vez | Se queda en el inicio de sesión | `PlanPersistenceTests` · "Primer arranque: sin sesión se queda en el login" | ✅ 2026-10-23 |
| P1.2 | Iniciar sesión → "Sobre ti" | "Sobre ti" va primero y exige 18 años o más | `AboutYouFlowTests`; UI `testAboutYouComesFirstAndNeedsAnAdult` | ✅ unidad · ⛔ UI |
| P1.3 | Elegir Novato o Avanzado en Experiencia | Novato: menos pasos y RIR explicado en palabras. Avanzado: pide músculos prioritarios | `ExperienceFlowTests`; UI `testBeginnerFlowIsSimplerAndExplainsRIR`, `testAdvancedFlowAsksPriorityMuscles` | ✅ unidad · ⛔ UI |
| P1.4 | Marcar una zona con molestia y escribir una nota | El plan evita esa zona y "Tu semana" lo explica | `RestrictionZonesTests`; UI `testRestrictionZoneIsExplainedInYourWeek` | ✅ unidad · ⛔ UI |
| P1.5 | Terminar el cuestionario | "Armando tu semana" sin mostrar nunca "Día de descanso"; luego "Tu semana" con "Por qué tu plan es así" | UI `testPendingPlanNeverShowsRestDay` | ⛔ UI |
| P1.6 | Ir a Hoy un lunes y un domingo | Lunes: la sesión del día con su lista y su duración real. Domingo: descanso, sin botón de empezar | `TodayPlanCoordinatorTests`, `TodayExerciseListTests`, `SessionTimeBudgetTests`; UI `testOnboardingReachesToday`, `testTodayListsTheExercisesOfTheSession`, `testSundayIsRestDayWithoutStartButton` | ✅ unidad · ⛔ UI |
| P1.7 | Cerrar y volver a abrir la app | Entra directo a Hoy con el mismo plan; no repite el cuestionario | `PlanPersistenceTests` · "Al terminar el cuestionario se guardan perfil y bloque…"; UI `testReopeningTheAppGoesStraightToToday` | ✅ unidad · ⛔ UI |
| P1.8 | Abrir la app sin internet después del primer inicio | Conserva la sesión y entra a Hoy | `PlanPersistenceTests` · "Sin internet (credencial no verificable)…" | ✅ unidad · 👤 iPhone en modo avión |

## Flujo 2 · Entrenar

| ID | Prueba (pasos) | Resultado esperado | Cómo se comprueba | Resultado |
|---|---|---|---|---|
| P2.1 | Tocar "Empezar" en Hoy | Se ve la primera serie (nunca pantalla negra) | `WorkoutSessionCoordinatorTests`; UI `testStartShowsTheFirstSetNotABlackScreen` | ✅ unidad · ⛔ UI |
| P2.2 | Completar una serie con un toque | La serie queda en disco antes de que la pantalla avance, en menos de 100 ms | `WorkoutRecoveryTests` · "Cada serie queda en disco antes de que la UI avance…" | ✅ 2026-10-23 |
| P2.3 | "Para después", "Saltar ejercicio" y "Retomar" | El ejercicio vuelve al final o se salta con confirmación; el resumen dice qué se saltó; no se inventan series | `WorkoutQueueTests`; UI `testDeferSkipAndResumeInWorkout` | ✅ unidad · ⛔ UI |
| P2.4 | "Ordenar" antes de empezar y luego restablecer | El orden propio se guarda y se puede restablecer; la prescripción no cambia | `SessionOrderTests`; UI `testReorderTodayExercisesAndReset` | ✅ unidad · ⛔ UI |
| P2.5 | "Ajustar a mi tiempo" con 30, 45, 60 y 90 min | Conserva lo principal, dice qué quitó, no agrega series y el entrenamiento empieza recortado | `SessionTimeBudgetTests`, `SessionTimeFitTests` | ✅ 2026-10-23 |
| P2.6 | Responder "dormí poco" en el check-in | El día va más ligero y Hoy lo dice | `SleepCheckInTests`, `ReadinessEngineTests`; UI `testSleepCheckInMakesTheDayLighter` | ✅ unidad · ⛔ UI |
| P2.7 | Terminar la sesión | Resumen con duración, series, volumen y récords calculados de lo guardado; queda completada una sola vez | `WorkoutClosingTests` | ✅ 2026-10-23 |
| P2.8 | Abrir Progreso después del primer entrenamiento | Aparece en el registro, con 4 KPIs y la gráfica | `ProgressHistoryTests`, `ProgressInsightsTests`; UI `testProgressLogsTheFirstWorkout` | ✅ unidad · ⛔ UI |

## Flujo 3 · Recuperación (cierre forzado y modo avión)

| ID | Prueba (pasos) | Resultado esperado | Cómo se comprueba | Resultado |
|---|---|---|---|---|
| P3.1 | Hacer 3 series, cerrar la app a la fuerza y reabrir | "Tienes un entrenamiento en curso"; al continuar sigue la serie 4 con las 3 anteriores guardadas | `WorkoutRecoveryTests` · "Con 5 series hechas, tras un cierre forzado…"; UI `testForceQuitMidWorkoutOffersToContinue` | ✅ unidad · ⛔ UI · 👤 iPhone |
| P3.2 | Cerrar a mitad de un descanso y reabrir | El descanso muestra el tiempo que de verdad queda (o 0 si ya terminó) | `WorkoutRecoveryTests` · "El descanso se guarda como hora de fin…" | ✅ 2026-10-23 |
| P3.3 | Cerrar justo después de la última serie | Al reabrir queda completada, no "en curso" | `WorkoutRecoveryTests` · "Cierre forzado justo después de la última serie…" | ✅ 2026-10-23 |
| P3.4 | Reabrir con operaciones pendientes en la cola | La cola se vacía sin duplicar series | `WorkoutRecoveryTests` · "La cola se drena al arrancar…" | ✅ 2026-10-23 |
| P3.5 | Falla el disco durante el entrenamiento | El entrenamiento sigue en memoria y la app avisa | `WorkoutRecoveryTests` · "Si el disco falla…" | ✅ 2026-10-23 |
| P3.6 | Cerrar a la fuerza con ejercicios en espera o con la sesión ajustada a 30 min | Se retoma igual: esperas, saltos y sesión recortada | `WorkoutQueueTests` · "Esperas y saltos sobreviven a un cierre forzado…"; `SessionTimeBudgetTests` | ✅ 2026-10-23 |
| P3.7 | Modo avión: abrir, entrenar, terminar y exportar | Todo funciona sin red | El único código de red es el cliente de IA (NVIDIA), apagado en Release y en las pruebas; registro, plan y export usan sólo el disco. Sin prueba automática de modo avión | 👤 iPhone en modo avión |
| P3.8 | Dos cuentas en el mismo dispositivo | No comparten historial ni cola de pendientes | `UserScopedHistoryTests` | ✅ 2026-10-23 |

## Flujo 4 · Exportar

| ID | Prueba (pasos) | Resultado esperado | Cómo se comprueba | Resultado |
|---|---|---|---|---|
| P4.1 | Perfil → Exportar sin entrenamientos | Estado vacío explícito ("Aún no tienes entrenamientos") | `ExportHistoryTests` · "Sin sesiones ⇒ estado vacío explícito…"; UI `testExportShowsEmptyStateBeforeAnyWorkout` | ✅ unidad · ⛔ UI |
| P4.2 | Entrenar una vez y abrir Exportar | "1 sesión" y los botones "JSON completo" y "Series (CSV)" | `WorkoutHistoryIntegrationTests` · "Entrenar y terminar ⇒ 1 sesión en disco y Export cuenta 1…"; UI `testExportCountsTheFirstWorkout` (nueva, aún sin correr) | ✅ unidad · ⛔ UI |
| P4.3 | Exportar con una serie todavía en la cola | Export ve todas las series | `ExportHistoryTests` · "2 sesiones completadas + 1 operación en cola…" | ✅ 2026-10-23 |
| P4.4 | Exportar con un archivo dañado | Export muestra los válidos y avisa cuántos no pudo leer | `ExportHistoryTests` · "Con un archivo corrupto entre 3 válidos…" | ✅ 2026-10-23 |
| P4.5 | Revisar el contenido exportado | Sin tokens, identificadores de Apple ni claves | `ExportHistoryTests` · "El export no incluye tokens…" | ✅ 2026-10-23 |
| P4.6 | Activar o no "Incluir Sobre ti" | "Sobre ti" sólo aparece si la persona lo elige | `AboutYouExportTests` | ✅ 2026-10-23 |
| P4.7 | Compartir el CSV y el JSON y abrirlos en el iPhone (Archivos o Numbers) | Se abren y traen las series del entrenamiento | Manual | 👤 iPhone |

## Pruebas manuales para Jesús (👤)

Anotar pasó/falló y la fecha en la fila correspondiente:

1. **P1.8 y P3.7, modo avión:** con la app ya configurada, activar modo avión, abrirla, entrenar una sesión completa, terminarla y exportar.
2. **P3.1, cierre forzado:** en un entrenamiento, hacer 3 series, cerrar la app desde el selector de apps y reabrirla: debe ofrecer continuar en la serie 4.
3. **P4.7, abrir los archivos:** compartir el CSV y el JSON y abrirlos en el iPhone.
