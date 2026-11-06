> **Archivo de noviembre de 2026.** Aquí van el detalle, los criterios y la `Evidencia:` de cada historia terminada desde el 2026-11-03. En el tablero activo, [`mvp-plan.md`](../../mvp-plan.md) §4, queda una línea por historia. Lo de octubre está congelado en [`mvp-plan-2026-10.md`](mvp-plan-2026-10.md).

# Historias terminadas en noviembre de 2026

## SCRUM-241 · PR-E009 Cambiar un ejercicio con IA no deshace su superset

- **Épica y prioridad:** Fase E (SCRUM-10) · Should · hito 1.0 · carril 🟢 verde.
- **Estado:** PR #35, 2026-11-03. Sin auto-merge porque el epic no está autorizado para el agente: lo fusiona Jesús.
- **Por qué se hizo antes de autorizar el epic:** Jesús pidió implementarla en la sesión el 2026-11-03, aunque la cola 👤 pasa de 5.
- **Decisión que aplica:** DE-5 (SCRUM-239), por analogía en el criterio 7.

**Qué cambió:**
- Si la IA cambia un ejercicio que va en superset, el par se queda con el sustituto cuando no comparte ningún músculo con su pareja (`SupersetPairing.areCompatible`).
- Si comparte músculo, la sustitución se rechaza con el motivo nuevo `breaksSuperset`.
- El hecho `superset` ("A + B") se reescribe desde el bloque final, también en la migración de un plan guardado.

**Criterios:**
- [x] Un sustituto compatible con la pareja se queda con el par (C + B) y la sesión ahorra el mismo descanso.
- [x] Uno que comparte músculo con la pareja se rechaza con `breaksSuperset`, queda en la bitácora y no se le ofrece a la IA.
- [x] Con el ejercicio en par en varias sesiones, el sustituto tiene que ser compatible con cada pareja.
- [x] Si la IA cambia los dos del par, el segundo se mide contra la pareja ya cambiada.
- [x] Los hechos `superset` (también los que recibe la IA) y la nota de Hoy nombran al sustituto; sin sustituciones aceptadas no cambian.
- [x] Al regenerar un plan guardado, el par se conserva con el sustituto o la sustitución se rechaza; nunca queda un par roto y los hechos nombran los pares reales.
- [x] Un plan guardado con un par roto se abre igual (los dos ejercicios solos, sin perder series) y no se reescribe el disco (DE-5).
- [x] Sin red: sin IA el plan es el del motor con sus pares, y la migración no usa red.
- [x] Prohibido por una restricción se rechaza con `rejectedByPolicy`; si además rompe el par, gana `breaksSuperset`.
- [x] Formato: `supersets` ya era opcional y `PersonalizationRejection` sólo gana un caso; las muestras de `Fixtures/Persistence/` no cambian.
- [x] Catálogo real, planes de 30 y 45 min: cualquier alternativa ofrecida conserva los pares de cada sesión.

**Verificación pendiente 👤:** con la IA real (SCRUM-201), un plan de 30 min con superset. Si la IA cambia un ejercicio del par, Hoy y "Por qué tu plan es así" deben nombrar al sustituto.

Evidencia: rama `SCRUM-241-superset-sustitucion-ia`, PR #35.
- **Pruebas:** `PlanPersonalizationSupersetTests` (9 pruebas, 10 casos) y `PlanPersistenceTests.migrationKeepsSupersetsWhole` y `savedBrokenPairIsLeftUntilRegeneration` (integración con `LocalPersistence` real en un directorio temporal).
- **Rojo antes del cambio:** 8 de las 9 pruebas de la suite nueva fallaron, también la del catálogo real con 30 y 45 min: el bug existía en `main` @ `d8961f2`.
- **`make ci`** (2026-11-03) → `✔ Test run with 597 tests in 87 suites passed` + `✔ Test run with 666 tests in 112 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK. Línea base: 597 + 655.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base d8961f2, 1412 → 1423 pruebas).`
- **E2E:** `make test-ui-smoke` → `testFirstWorkoutReachesProgressAndExport` y `testWorkoutSurvivesForceQuitAndKeepsPain` OK.
  - `testIntermediateQuestionnaireFromAboutYouToReopening` falló en el paso del consentimiento en Perfil: el toque en la pestaña "Perfil" calculó el punto `{-1, -1}` y Perfil no se abrió.
  - Con el mismo build, `make test-ui-journey RECORRIDO="IntermediateQuestionnaireJourney"` → `OK testIntermediateQuestionnaireFromAboutYouToReopening() (53 s)`. Es una falla intermitente del tab bar, ajena a esta historia; ningún recorrido usa la IA.
- **Medición** (plan de 3 días con brazos de prioridad):
  - 30 min: de las 18 alternativas que se ofrecían para los 6 ejercicios en par, 1 chocaba con su pareja;
  - 45 min: de 12 alternativas para 4 ejercicios, 1 chocaba;
  - la lista se rellena con la siguiente opción compatible: siguen 18 y 12, y ningún ejercicio se queda sin alternativas.

## SCRUM-232 · PR-E001 Sustituto equivalente de verdad (motor)

- **Épica y prioridad:** Fase E (SCRUM-10) · Should · hito 1.0 · carril 🟢 verde.
- **Estado:** PR #36, 2026-11-05. Sin auto-merge porque el epic no está autorizado para el agente: lo fusiona Jesús.
- **Por qué se hizo antes de autorizar el epic:** excepción de Jesús del 2026-11-05 para SCRUM-232 y SCRUM-240, que no agregan pantallas.
- **Decisiones que aplica:** DE-1 y DE-3 (SCRUM-231).

**Qué cambió:**
- `substitutes(for:)` ya no sólo ordena: aplica la regla de DE-3 por etapas y, si una deja la lista vacía, dice cuál (`NoEquivalentReason`).
- La disponibilidad es por ejercicio (`unavailableExerciseIDs`). `gymProfile` sólo matiza el puntaje.
- La regla `safety.substitutionScoring` sube a v2 con `minimumScore` y `maxOptions`.
- Cada opción trae sus componentes y la regla con versión. Hoy nadie llama al motor desde la app: lo conectan PR-E003, PR-E005 y PR-E008.

**Criterios:**
- [x] Sólo salen las candidatas con el mismo patrón, al menos un músculo principal en común y la misma clase articular, permitidas, disponibles, que no están en la sesión y con puntaje ≥ el mínimo.
- [x] Para el press de banca, las aperturas no salen y el press con mancuernas sí, también con el catálogo real.
- [x] Una candidata prohibida nunca sale, aunque tenga el mejor puntaje.
- [x] Si ninguna pasa, el resultado dice por qué: sin candidatas, todas prohibidas, todas no disponibles o todas bajo el mínimo.
- [x] Con los mismos datos el orden es idéntico: si empatan, por nombre y, con el mismo nombre, por ID.
- [x] Como máximo `maxOptions` opciones, cada una con los componentes del puntaje y la regla con versión.
- [x] La regla sube a v2 con `minimumScore = 0.60` y `maxOptions = 3`. El código no lleva números de política.

**Una prueba existente cambió:** `bestEquivalentRanksFirst` esperaba 3 resultados, incluido el press de hombro (otro patrón y otro músculo), que es lo que DE-3 prohíbe. Ahora exige exactamente el Smith y el inclinado, en ese orden. La prueba sigue y es más estricta.

Evidencia: rama `SCRUM-232-sustituto-equivalente`, PR #36.
- **Pruebas:** `EquivalentSubstituteTests` (16 pruebas) y, con el catálogo real, `RestrictionsNeverBypassedTests.benchPressSubstitutesInTheRealCatalog` y las aserciones nuevas de patrón y máximo en `crossedPermissionsSubstitutionsAgentAndDropset`.
- **Rojo antes del cambio:** 11 pruebas de `SubstitutionScoringTests` y 2 del catálogo real fallaron; con el catálogo real salían sustitutos de otro patrón.
- **`make ci`** (2026-11-05) → `✔ Test run with 613 tests in 88 suites passed` + `✔ Test run with 667 tests in 112 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK. Línea base: 597 + 666.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base 5afbb18, 1423 → 1440 pruebas).`
- **E2E:** `make test-ui-smoke` → `OK testFirstWorkoutReachesProgressAndExport() (1 min 11 s)`, `OK testIntermediateQuestionnaireFromAboutYouToReopening() (36 s)`, `OK testWorkoutSurvivesForceQuitAndKeepsPain() (7 min 49 s)`. Ningún recorrido llama al motor.
- **Medición** (ejercicios del plan con al menos un sustituto con el mínimo de 0.60, sin contar los que ya van en su sesión):

  | Plan | Con sustituto |
  |---|---|
  | 2 días, 60 min | 7 de 7 |
  | 3 días, 45 min | 8 de 8 |
  | 3 días, 60 min | 13 de 13 |
  | 4 días, 60 min | 18 de 18 |
  | 4 días, 75 min | 25 de 25 |
  | 6 días, 60 min | 26 de 26 |
  | Hombro y rodilla restringidos, 3 días, 60 min | 14 de 14 |
  | Hombro y rodilla restringidos, 4 días, 75 min | 25 de 25 |

## SCRUM-240 · PR-E008 La IA sólo propone sustitutos equivalentes de verdad

- **Épica y prioridad:** Fase E (SCRUM-10) · Should · hito 1.0 · carril 🟢 verde.
- **Estado:** PR #37, 2026-11-05. Sin auto-merge porque el epic no está autorizado para el agente: lo fusiona Jesús.
- **Por qué se hizo antes de autorizar el epic:** excepción de Jesús del 2026-11-05 para SCRUM-232 y SCRUM-240, que no agregan pantallas.
- **Decisiones que aplica:** DE-3 (SCRUM-231) y DE-5 (SCRUM-239).

**Qué cambió:**
- `PlanPersonalizationValidator` ya no tiene su propia regla. La definición de "mismo movimiento" y el puntaje salen del motor de PR-E001, que ahora también se usa para calcular lo que se le ofrece a la IA.
- Motivos nuevos: `differentPattern` y `belowMinimumScore`. Los rechazos de equivalencia llevan la versión de la regla en la bitácora.
- `PlanPersonalizationFlow.reapply` revisa las sustituciones al migrar un plan guardado y deja el registro y la explicación coherentes con el plan final.

**Criterios:**
- [x] La personalización usa la regla de PR-E001 para ofrecer y para aceptar, sin una segunda copia; con el catálogo real da lo mismo que el motor.
- [x] Otro patrón se rechaza con `differentPattern`, el plan queda igual y la bitácora guarda el motivo.
- [x] Bajo el mínimo se rechaza con `belowMinimumScore` y la bitácora lleva la versión de la regla.
- [x] A la IA se le ofrecen como máximo `maxAlternativesPerExercise` opciones, todas equivalentes, por puntaje y, si empatan, por nombre; sin equivalentes, el ejercicio no aparece.
- [x] Un equivalente prohibido nunca se ofrece y se rechaza con `rejectedByPolicy`, también con la revisión vencida.
- [x] El motivo es el primero que falla, en el orden fijo de la regla.
- [x] Un plan guardado con una sustitución que ya no pasa se abre igual y no se reescribe el disco (DE-5).
- [x] Al migrar, lo que no pasa vuelve al ejercicio del motor y queda rechazado con su motivo; la explicación ya no lo menciona y lo que pasa se conserva con su hecho `substitution`.
- [x] Sin red: la regla corre local y la migración no usa la IA.
- [x] Formato: `PersonalizationRejection` sólo gana casos; las muestras de `Fixtures/Persistence/` no cambian.

**Una prueba existente cambió:** en `crossedPermissionsSubstitutionsAgentAndDropset`, el caso "permitido sólo por la otra zona" se armaba sobre el plan restringido. Ahí ya no puede existir, porque el sustituto hace el mismo movimiento que el original. Ahora se arma sobre el plan del mismo perfil sin restricciones; el `#require` y la aserción no cambian.

**Verificación pendiente 👤:** con la IA real (SCRUM-201), que cada ejercicio que cambie en el plan haga el mismo movimiento que el original.

Evidencia: rama `SCRUM-240-ia-equivalencia-estricta`, PR #37.
- **Pruebas:** `PlanPersonalizationEquivalenceTests` (9 pruebas, 11 casos) y 3 de integración en `PlanPersistenceTests` con `LocalPersistence` real en un directorio temporal.
- **Rojo antes del cambio:** 10 de esas 12 pruebas fallaron.
- **`make ci`** (2026-11-05) → `✔ Test run with 613 tests in 88 suites passed` + `✔ Test run with 679 tests in 113 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK. Línea base: 613 + 667.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base 965f01a, 1440 → 1452 pruebas).`
- **E2E:** `make test-ui-smoke` → `OK testFirstWorkoutReachesProgressAndExport() (37 s)`, `OK testIntermediateQuestionnaireFromAboutYouToReopening() (38 s)`, `OK testWorkoutSurvivesForceQuitAndKeepsPain() (50 s)`. Ningún recorrido usa la IA.
- **Medición** (lo que se le ofrecía a la IA antes y después, sin restricciones):

  | Plan | Ejercicios con alternativas (antes y después) | Ofrecidas antes | De otro patrón antes | Ofrecidas después |
  |---|---|---|---|---|
  | 2 días, 60 min | 7 de 7 | 21 | 4 | 20 |
  | 3 días, 45 min | 8 de 8 | 24 | 4 | 23 |
  | 3 días, 60 min | 13 de 13 | 39 | 10 | 37 |
  | 4 días, 60 min | 18 de 18 | 54 | 17 | 48 |
  | 4 días, 75 min | 25 de 25 | 75 | 27 | 64 |
  | 6 días, 60 min | 26 de 26 | 78 | 27 | 67 |

  Ahora ninguna alternativa es de otro patrón y ningún ejercicio se queda sin opciones.

---

## Fase E en un solo PR (PR #38)

- **Épica:** Fase E (SCRUM-10) · hito 1.0 · carril 🟡 amarillo por `LocalPersistence.swift` y `CodableRepositories.swift`.
- **Estado:** PR #38, rama `SCRUM-10-fase-e`, 2026-11-05. Un commit por historia; lo fusiona Jesús con merge commit.
- **Por qué en un PR:** excepción de Jesús del 2026-11-05 para toda la fase, con la cola 👤 sobre el límite.
- **Decisiones que aplica:** DE-1 a DE-4 (SCRUM-231) y DE-5 (SCRUM-239).
- **También corrige:** el puntaje de sustitución de SCRUM-232 cambiaba en el último dígito según el orden de un diccionario, y eso hacía fallar de vez en cuando la prueba de paridad. Ahora suma con claves ordenadas (commit `4aabd25`, prueba `realCatalogScoresAreStable`).

### SCRUM-235 · PR-E004 Mi gimnasio

**Qué cambió:** `GymCoordinator` nuevo; colección `.gyms` por usuario; `FileGymRepository.save` guarda sin la ocupación; Perfil › Gimnasio; el export lleva los gimnasios.

**Criterios:**
- [x] Sin gimnasio guardado se crea "Mi gimnasio", sin pasos nuevos y con el mismo plan.
- [x] Perfil lo muestra y se renombra; el nombre vacío se rechaza y el nombre sobrevive a reabrir.
- [x] Dos cuentas en el mismo iPhone tienen cada una su gimnasio.
- [x] Lo guardado nunca lleva ocupación.
- [x] Un error al escribir avisa, no bloquea y no se traga.
- [x] El export incluye los gimnasios.
- [x] Los datos anteriores se ven igual.
- [x] El gimnasio vive en su propia colección, fuera del plan y del perfil.

### SCRUM-233 · PR-E002 Máquina ocupada

**Qué cambió:** `ExerciseQueueState` gana `order` y `occupied`, opcionales; `WorkoutQueue` y `ReorderBeforeReplaceController` trabajan sobre la cola real; "Máquina ocupada" (`workout.occupied`) reemplaza a "Para después" en la pantalla.

**Criterios:**
- [x] Con adelanto seguro, B pasa a ser el actual, A queda justo después y la pantalla lo dice.
- [x] Sin adelanto seguro, A va al final y lo dice. Desde SCRUM-234 primero se ofrece la hoja y "Esperar" lo manda al final.
- [x] Si A es lo único pendiente, nada cambia y se ofrece esperar o saltar.
- [x] Las series hechas no cambian, el descanso sigue y no se crea ninguna serie.
- [x] La ocupación no pasa a otra sesión.
- [x] En superset el par se separa y la pareja sigue sola.
- [x] Tras un cierre forzado sigue el mismo orden.
- [x] En pausa no está disponible.
- [ ] En el descanso la acción está sobre "Sigue: X". Está en la pantalla, pero sin prueba automática: va en la verificación 👤.
- [x] "Para después" desaparece de la pantalla. `deferCurrentExercise` sigue en el coordinador porque "Esperar" usa la misma cola.

### SCRUM-234 · PR-E003 Sustituto durante el entrenamiento

**Qué cambió:** `SessionSubstitution` y `WorkoutSessionRecord.substitutions`, opcional; `OccupiedChoiceSheet`; el resumen dice "A → B (máquina ocupada)". La plantilla de la sesión pasa a ser lo planeado para hoy, ya adaptado: el plan guardado no cambia.

**Criterios:**
- [x] Hasta 3 sustitutos con su razón, más esperar y saltar.
- [x] Lo pendiente pasa a B, lo hecho se queda como A y el total no cambia.
- [x] El peso de B nunca es el de A.
- [x] Con restricciones no aparece nada prohibido; sin sustitutos, la hoja lo dice.
- [x] Con dolor moderado o alto no se ofrecen sustitutos: sale la recomendación y saltar.
- [x] Tras un cierre forzado se sigue con B.
- [x] Otro día toca A.
- [x] El resumen y el export dicen A → B y las series de B salen como B.
- [x] Los récords de B sólo se comparan con B: la base es por ejercicio.
- [x] La sesión guarda objetivo, elegido, puntaje, regla y versión.

### SCRUM-237 · PR-E006 Mis cargas por máquina

**Qué cambió:** `EquipmentType.loadIsPerMachine`, `LastLoadIndex` e `ImplicitMachine.id(gym:exercise:)`; cada serie "por máquina" se guarda con su máquina; `workout.lastWeight` dice "Tu último peso en esta máquina".

**Criterios:**
- [x] La misma máquina en el mismo gimnasio trae el último peso y lo dice.
- [x] La segunda serie trae el peso de la anterior.
- [x] Sin historial en el gimnasio activo aparece vacío, aunque haya historial en otro.
- [x] Barra, mancuernas y kettlebell comparten el peso entre gimnasios.
- [x] Los calentamientos no cuentan.
- [x] Un sustituto trae su último peso, nunca el del original.
- [x] La serie se guarda con su máquina.
- [x] Las series viejas sin máquina no son historial de máquina; para barra sí cuentan.
- [x] Los récords se comparan por máquina.
- [x] Se precarga lo último hecho: no sube carga y después de dolor nunca propone más.

**Medición:** abrir el entrenamiento con 500 sesiones de 20 series tarda 117 ms en debug; armar el índice, 25 ms.

### SCRUM-236 · PR-E005 "No hay esta máquina aquí"

**Qué cambió:** `GymSessionAdapter` aplica el gimnasio encima del plan al armar el día, sin tocar el bloque guardado; `GymProfile.missingExercises`, opcional; notas en Hoy y Semana; Perfil › Máquinas que no hay.

**Criterios:**
- [x] Marcar sigue hoy con B y guarda la marca antes de cambiar la pantalla.
- [x] Una sesión futura trae B, con su nota.
- [x] Quitar devuelve A a la siguiente sesión.
- [x] Marcar y quitar no regeneran el plan guardado.
- [x] Una restricción nueva descarta a B y propone otro; sin ninguno, A se omite y se explica.
- [x] Si B ya está en la sesión se usa el siguiente equivalente.
- [x] Sin sustituto se guarda igual y nunca se programa la máquina.
- [x] Un error al guardar no marca el gimnasio y avisa.
- [x] Marcar sólo afecta al gimnasio activo.

**Diferencias con la tarjeta:**
- El paso E2E de quitar la marca está en `WorkoutRecoveryJourney`, no en `ProfileJourney`, porque necesita una marca hecha en ese mismo recorrido.
- La nota de Semana es un aviso general en la pestaña Plan, no una nota por día.

**Sin prueba propia:** "quitar la marca con un entrenamiento activo no cambia la sesión". Se cumple porque la sesión tiene su propia plantilla.

**Limitaciones conocidas:**
- `reorderSession` valida contra el bloque del motor: en una sesión con sustituto del gimnasio, reordenar falla sin dañar nada.
- `timeRoles` no trata al sustituto de un ancla como ancla, y la explicación no lo menciona (caso límite de la tarjeta, sin cubrir).

### SCRUM-238 · PR-E007 Varios gimnasios

**Qué cambió:** `GymCoordinator.addGym` y `select(_:duringWorkout:)`; `renameActive` también rechaza repetidos; lista "Mis gimnasios" en Perfil; "En: Oficina" en Hoy sólo con más de un gimnasio.

**Criterios:**
- [x] Agregar aparece en la lista; vacío o repetido, sin importar mayúsculas, se rechaza con mensaje.
- [x] Elegir cambia lo que dice Hoy y la sesión se arma con lo de ese gimnasio.
- [x] Con un entrenamiento activo la opción está desactivada y dice por qué.
- [x] Cambiar no toca el plan guardado ni el historial. La racha sale del historial.
- [x] El activo sobrevive a reabrir y es por usuario.
- [x] Una prensa sin historial en ese gimnasio aparece sin peso.
- [x] VoiceOver dice "Gimnasio activo: Oficina".
- [ ] Letra grande sin cortes y áreas de toque de 44 × 44 pt: sin prueba automática, van en la verificación 👤.

**Pruebas existentes que cambiaron:** en el commit de SCRUM-234, cinco casos de `OccupiedMachineTests` (escritos en SCRUM-233) se ajustaron porque sin adelanto seguro ahora primero se pregunta: `.movedToEnd` pasa a `needsChoice` más `waitForOccupiedExercise()`, y `.onlyExercise` pasa a `needsChoice` con `isOnlyExercise`. Ninguna prueba se borró ni se desactivó. Las muestras de `Fixtures/Persistence/` no cambian.

**Verificaciones pendientes 👤:** en `mvp-plan.md` §2.

Evidencia: rama `SCRUM-10-fase-e`, PR #38.
- **Pruebas nuevas:** `GymCoordinatorTests`, `OccupiedMachineTests`, `LiveSubstitutionTests`, `MachineLoadTests` y `GymAdaptationTests`, con `LocalPersistence` real en un directorio temporal.
- **`make ci`** (2026-11-05) → `✔ Test run with 613 tests in 88 suites passed` + `✔ Test run with 748 tests in 119 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK. Línea base: 613 + 679.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base 88d4db9, 1452 → 1521 pruebas).`
- **E2E:** `make test-ui` completa, 9 de 9 a la primera (incluye los 3 recorridos del smoke, así que `make test-ui-smoke` no se corrió aparte):
  - `OK testBeginnerAndAdvancedQuestionnaires() (1 min 16 s)`
  - `OK testFirstWorkoutReachesProgressAndExport() (47 s)`
  - `OK testIntermediateQuestionnaireFromAboutYouToReopening() (44 s)`
  - `OK testPendingPlanShowsLoadingThenExplainsTheWeek() (31 s)`
  - `OK testProfileRestrictionsSignOutAndRedo() (1 min 42 s)`
  - `OK testSundayIsRestDayWithoutStartButton() (10 s)`
  - `OK testSupersetFromTodayThroughTheRound() (24 s)`
  - `OK testTodayFromSleepCheckInToTheWeek() (1 min 11 s)`
  - `OK testWorkoutSurvivesForceQuitAndKeepsPain() (2 min 35 s)`

## SCRUM-245 · PR-F002 La energía del mismo entrenamiento se cuenta una vez (motor)

- **Épica y prioridad:** Fase F (SCRUM-11) · Should · hito 1.0 · carril 🟡 amarillo.
- **Estado:** PR #40, en `main` el 2026-11-06.
- **Por qué amarillo y no 🟢:** el criterio 5 necesita representar fuerza funcional y carrera, y `HealthWorkoutActivityType` vive en `HealthWorkout.swift`, que entra en `Health*.swift`. La tarjeta no lo preveía.
- **Decisión que aplica:** ninguna abierta. La tolerancia de 10 minutos la fija la regla v1 para cubrir la prueba 7 del gate (SCRUM-251) también en entrenamientos cortos.

**Qué cambió:**
- `WorkoutReconciliationEngine` mide el solapamiento sobre el más corto, no intersección sobre unión.
- También son el mismo los que comparten tiempo y tienen inicio y fin dentro de la tolerancia (§15.4). Sin un segundo en común, nunca.
- Los grupos son componentes conexas: el resultado ya no depende del orden de entrada.
- Umbral, tolerancia y confianza por fuente salen de la regla `health.workoutReconciliation` v1 (`ReconciliationRule.swift`).
- Un candidato sin duración o con el fin antes del inicio se ignora: no se une a nada ni aporta energía. Energía negativa, `NaN` o infinita no cuenta como energía real.
- `HealthWorkoutActivityType` gana `functionalStrengthTraining` y `running`. `WorkoutEnergyCandidate` gana `identifier`, que `ExternalWorkout.asCandidate` llena con su referencia.

**Criterios:**
- [x] A de 18:00 a 19:00 y B de 18:10 a 18:50 son el mismo.
- [x] A de 18:00 a 19:00 y B de 18:30 a 19:30 son distintos.
- [x] A de 18:00 a 19:00 y B de 19:00 a 20:00 son distintos.
- [x] Fuera del umbral, con inicio y fin dentro de la tolerancia, son el mismo.
- [x] Fuerza tradicional y funcional pueden ser el mismo; fuerza y carrera, nunca.
- [x] Gana la fuente de mayor prioridad con energía real, sin sumar. Sin energía, no hay energía.
- [x] A igual prioridad gana la mayor duración; si empatan, el menor identificador. Cualquier orden da lo mismo.
- [x] Umbral, tolerancia y confianza salen de una regla versionada.

Evidencia: rama `SCRUM-245-energia-una-vez`, PR #40.
- **Pruebas:** suite `WorkoutEnergyCountedOnceTests` (24 pruebas) en `ReconciliationTests.swift`, con una de 200 barajas de semilla fija. Las 8 pruebas de PR-1105 quedan sin cambios: ninguna afirmaba intersección sobre unión, sólo lo decía un comentario.
- **`make ci`** (2026-11-05) → `✔ Test run with 613 tests in 88 suites passed` + `✔ Test run with 772 tests in 120 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base b5b2d9d, 1521 → 1545 pruebas).`
- **E2E:** `make test-ui-smoke` → `testFirstWorkoutReachesProgressAndExport` (1 min 29 s), `testIntermediateQuestionnaireFromAboutYouToReopening` (54 s) y `testWorkoutSurvivesForceQuitAndKeepsPain` (2 min 16 s) OK. El motor no se llama desde la app: ningún recorrido cambia.

## Fase G en un solo PR

- **Épica y prioridad:** Fase G (SCRUM-12) · Could · hito 1.0 · carril 🟡 amarillo (`*.pbxproj`, `.github/`, `Health*.swift`, `PendingOperationStore.swift`). Lo fusiona Jesús.
- **Por qué así:** Jesús pidió toda la fase en una rama, varios commits y un PR, el 2026-11-05. Es una excepción a la cola 👤 y a esperar el gate de F (SCRUM-251).
- **Decisiones:** DG-1 a DG-5 (SCRUM-243).
- **Firma:** la cuenta gratuita firma iPhone y reloj con HealthKit, con perfiles de 7 días.

**Qué cambió:**
- **SCRUM-254:** `WorkoutSyncEngine` da lo mismo en cualquier orden de llegada. Una revocación gana aunque llegue antes y dos series en una ranura no pierden ninguna. Un error real, reproducido con una prueba antes de arreglarlo.
- **SCRUM-253:** `WatchSessionSnapshot` trae lo que falta en el orden de la cola del iPhone. El reloj no calcula el orden.
- **SCRUM-252:** `PR.app` embebe `PRWatch.app`, con entitlement, equipo, modo de segundo plano y textos propios.
- **SCRUM-255:** `PhoneWatchBridge` guarda cada serie en la cola antes de aplicarla, en pantalla o sobre lo guardado.
- **SCRUM-256:** `WatchSessionController` escribe en disco antes del háptico y conserva el buzón hasta que un estado lo confirme.
- **SCRUM-257:** la pantalla del reloj, con Corona, un botón grande, descanso por hora de fin y sin contador con la muñeca abajo.
- **SCRUM-260:** el dolor usa la misma escala y el mismo motor. El reporte no sale del buzón hasta que el iPhone lo guarde.
- **SCRUM-259:** pausar y terminar, también sin iPhone, con su hora real. El resumen deja elegir entre series en conflicto.
- **SCRUM-258 (abierta):** sesión de Salud en el reloj, apagada por `watch.health_session.enabled` hasta el gate. `make install-iphone` la enciende con `PR_DEVICE_TEST`.

**Criterios sin cerrar:**
- [ ] SCRUM-258 c3 y c4: que el iPhone respete `healthRecording.watchOwnsHealthWorkout`. El dato ya existe; falta PR-F003 (SCRUM-246).
- [ ] SCRUM-258 c9: mostrar la energía del reloj una vez. El dato ya llega; falta PR-F007 (SCRUM-250).
- [ ] 👤 Todo lo de dispositivo: instalar en el reloj (SCRUM-252 c6) y las 10 pruebas de SCRUM-261. Nada de WatchConnectivity ni HealthKit se ejecutó en un dispositivo.

**Hallazgos:**
- Las publicaciones al reloj corrían en tareas sueltas y podían llegar desordenadas. Ahora se encadenan.
- El identificador de la tarjeta de conflicto tapaba el de sus botones. Lo encontró el recorrido E2E.
- Medido: 60 series = 13 877 bytes por estado. El reloj en Debug pesa 30 MB con el catálogo de PRCore.

Evidencia: rama `SCRUM-12-fase-g`, PR #41.
- **`make ci`** (2026-11-06) → `✔ Test run with 648 tests in 91 suites passed` + `✔ Test run with 857 tests in 127 suites passed` + `Executed 151 tests, with 0 failures`; build de iOS y de watchOS OK.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base 58babf7, 1545 → 1666 pruebas).`
- **Firma real:** `xcodebuild` para iPhone con reloj embebido, cuenta gratuita, `BUILD SUCCEEDED`, sin instalar.
- **E2E:** `make test-ui-smoke` → `testFirstWorkoutReachesProgressAndExport`, `testIntermediateQuestionnaireFromAboutYouToReopening`, `testSetConflictIsResolvedInTheSummary` (nuevo) y `testWorkoutSurvivesForceQuitAndKeepsPain` OK. Dos corridas anteriores fallaron por carga de la Mac (carga promedio de 164, con otra sesión corriendo UI), no por el código; sí encontraron el error del identificador.
- **Sin prueba automática:** no hay target de UI del reloj ni runtime de watchOS en esta Mac. La pantalla se compila, y su lógica se prueba en PRCore.

## Fase F en un solo PR (PR #42)

- **Épica:** Fase F (SCRUM-11) · hito 1.0 · carril 🟡 amarillo. SCRUM-245 entró antes, por el PR #40.
- **Estado:** PR #42, rama `SCRUM-11-fase-f`, 2026-11-06. Un commit por historia; lo fusiona Jesús con merge commit.
- **Por qué en un PR:** Jesús lo pidió el 2026-11-05, igual que la Fase E.
- **Decisiones que aplica:** DF-1 a DF-5 (SCRUM-242).
- **También cierra:** los dos criterios de SCRUM-258 que dependían de esta fase.

### SCRUM-262 · PR-F009 Build de prueba para iPhone

**Qué cambió:** `make install-iphone` compila Debug, firma con `scripts/device/PR.device.entitlements` e instala con `devicectl`. `AuthLaunchMode.resolve` admite `isDeviceTestBuild`, que sale de `PR_DEVICE_TEST`.

**Criterios:**
- [x] Compila Debug, firma sólo con HealthKit. Verificado con la firma real, sin instalar.
- [x] Release es siempre `.appleID`, aunque traiga la condición o el argumento.
- [x] Debug sin la condición decide como antes.
- [x] `PR/PR.entitlements` no cambia.
- [x] Sin iPhone falla con mensaje y código distinto de 0.
- [x] Con varios iPhone se elige con `DEVICE=<nombre>`; ningún identificador queda en el repo.
- [x] El README explica el comando, los 7 días y que no sirve para TestFlight.
- [ ] 👤 Abrir desde el ícono en el iPhone sin inicio de sesión (en simulador limpio sí).
- [ ] 👤 Mismo usuario tras cierre forzado.
- [ ] 👤 Perfil vencido: renueva sin borrar datos.

### SCRUM-244 · PR-F001 Permisos de Salud reales

**Qué cambió:** `HealthAccessRequest.workouts`, `HealthSystemPermissionProvider`, `HealthWorkoutsAccess` y el estado `.notVisible`. El flag `health.workouts.enabled` viene apagado; lo enciende sólo el build de prueba, porque abre sin argumentos y es el que usa el gate.

**Prueba modificada:** `usageDescriptionsCorrect` ahora afirma `NSHealthUpdateUsageDescription` para `workout`, porque el criterio 7 lo pide.

**Criterios:**
- [x] Se piden exactamente escribir entrenamientos, leerlos y leer energía activa. Sin ritmo cardiaco. Visto también en la hoja real del simulador.
- [x] Negar escribir deja `workout` negado; conceder, concedido.
- [x] Un permiso de lectura es "no visible"; la energía se conserva con él y se quita con negado.
- [x] Sin Salud es un fallo recuperable.
- [x] `Info.plist` coincide con `HealthUsageDescription` y no dice que la app no escribe.
- [x] Con el flag apagado no se pide ni se lee nada.
- [x] "Usar datos de Salud" funciona igual.

### SCRUM-246 · PR-F003 Cola de escritura a Salud

**Qué cambió:** campo opcional `healthWriteStatus`, `HealthWorkoutWrite`, protocolo `HealthWorkoutWriting` y `HealthWriteCoordinator`, un actor por cuenta. Se engancha por `onPersisted`: `LocalPersistence.swift` sólo gana la colección de SCRUM-248.

**Criterios:**
- [x] Queda pendiente en disco antes de llamar a Salud; guardado después, con la referencia llena.
- [x] Si Salud falla queda pendiente y se reintenta al abrir y al volver a primer plano.
- [x] Cerrar entre escribir y marcar no duplica.
- [x] Abandonada, sin series o anterior a esta historia no se escribe.
- [x] Apagado o negado no deja nada pendiente; negado con algo pendiente no falla ni lo pierde.
- [x] Series, horas y resumen no cambian.
- [x] El resumen no espera a Salud.
- [x] Dos cuentas: sólo la activa.
- [x] A Salud sólo van inicio, fin, tipo e identificador.

### SCRUM-247 · PR-F004 Guardar en Salud de verdad

**Qué cambió:** `HealthKitWorkoutStore` con `HKWorkoutBuilder`, `HealthSaveDisplay` y la Salud falsa de las pruebas de UI (`-PRUITestFakeHealth`). Con Salud falsa el reloj fijo avanza, porque una sesión sin duración no va a Salud.

**Condición de paro revisada:** en simulador, tres escrituras con el mismo identificador y versión dejaron un entrenamiento. El `uuid` cambia en cada escritura: la última reemplaza a la anterior.

**Criterios:**
- [x] Fuerza tradicional, horas reales, en interiores, con Nucleus como fuente (simulador).
- [x] Identificador de la sesión, versión 1.
- [x] Sin energía ni ritmo cardiaco.
- [x] El resumen dice "Guardado en Salud" o "Se guardará en Salud"; apagado o negado, nada.
- [ ] 👤 Con letra grande y VoiceOver en el iPhone. Tiene previews por estado.

### SCRUM-248 · PR-F005 Pedir permiso en el momento correcto

**Qué cambió:** colección `health-preference`, `HealthPermissionOffer`, `HealthWriteSetting`, la tarjeta del resumen y el interruptor de Perfil. Nota de DF-2 en `promptMaster.md` §4.1.

**Criterios:**
- [x] La tarjeta sale tras un entrenamiento completado sin haber decidido, nunca al empezar ni durante.
- [x] "Guardar en Salud" abre la hoja real sobre el resumen y guarda ese entrenamiento (simulador, de punta a punta).
- [x] "Ahora no" no vuelve a salir y Perfil sigue ofreciéndolo.
- [x] El interruptor explica el caso negado; apagar no borra lo guardado.
- [x] Negar en la hoja no insiste.
- [x] La decisión es por usuario y sobrevive a reabrir.
- [ ] 👤 Letra grande, claro y oscuro, y VoiceOver en el iPhone.

### SCRUM-249 · PR-F006 Leer entrenamientos externos

**Qué cambió:** `HealthExternalWorkouts.swift` clasifica y filtra; `HealthKitWorkoutStore` lee de Salud. `HealthWorkoutActivityType` gana `other`.

**Criterios:**
- [x] Lo externo llega con inicio, fin, tipo, energía y fuente, de los últimos 14 días.
- [x] Lo propio se filtra por fuente y por identificador.
- [x] Apple Watch y otra app se distinguen con una función pura.
- [x] Un tipo desconocido llega como otro.
- [x] Sin permiso es vacío, sin error.
- [x] Sin series, reps ni peso, y sin duplicados.
- [x] Nada entra a la IA ni a los logs.
- [ ] 👤 Confirmar en el gate el identificador real de la fuente de Apple.

### SCRUM-250 · PR-F007 Ver la energía una sola vez

**Qué cambió:** `EnergySource` y `CanonicalWorkoutEnergy` pasan a PRDomain con las mismas claves; campo opcional `energy` en la sesión; `HealthEnergyCoordinator`; fila "Actividad de Salud" en Progreso; el export lleva `healthActivities`.

**Criterios:**
- [x] Con un entrenamiento de reloj que se solapa, la sesión muestra "Energía activa · Apple Watch" una vez.
- [x] Sin coincidencia no hay energía.
- [x] Nada suma dos fuentes; el total semanal lo prueba.
- [x] Si el reloj llega tarde, la energía aparece al abrir el historial.
- [x] Un externo sin sesión sale como "Actividad de Salud", sin series.
- [x] No cuenta en la racha ni en el historial.
- [x] El export lleva la energía con su fuente y las actividades aparte.
- [x] Con Salud apagada no entra energía nueva y lo guardado se queda.
- [x] Nada entra al contexto de la IA.

**Verificación pendiente 👤:** el gate SCRUM-251 completo, en iPhone y reloj, y las filas de SCRUM-262 y SCRUM-248 en `mvp-plan.md` §2.

Evidencia: rama `SCRUM-11-fase-f`, PR #42, sobre `main` @ `c011a98`.
- **`make ci`** (2026-11-06) → `✔ Test run with 648 tests in 91 suites passed` + `✔ Test run with 956 tests in 133 suites passed`; build de iOS y de watchOS OK.
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base c011a98, 1666 → 1770 pruebas).`
- **E2E:** `make test-ui` → 15 de 15 OK, entre ellas `testSummaryOffersHealthAndSavesTheWorkout`, `testRefusingTheSheetDoesNotInsist`, `testSummarySaysItWasSavedInHealth`, `testWatchEnergyShowsOnceAndActivityStaysApart` y `testHealthSwitchInProfile`.
- **Fallas que encontró la E2E, ya arregladas:** la tarjeta pisaba los identificadores de sus botones, y Progreso no recibía las actividades, así que la fila nunca salía.
- **Salud real en simulador:** la hoja pide lo correcto, con nuestros textos. Tarjeta, hoja y "Guardado en Salud" de punta a punta. iOS 27 agrega un segundo paso: cuántos datos históricos compartir.
- **Firma real:** `xcodebuild` para el iPhone con cuenta gratuita, `BUILD SUCCEEDED`, sin instalar. `codesign` muestra HealthKit y no `applesignin`. Esa corrida fue antes de integrar la Fase G.

