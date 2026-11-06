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
