# Requirements Traceability Matrix

Esta matriz vincula requisitos maestros con épicas principales. Debe actualizarse cuando un requisito cambie de alcance.

| Requirement | Primary backlog area | Verification |
|---|---|---|
| RF-001 Sign in with Apple | EPIC-04 | Auth integration + UI test |
| RF-002 Use without HealthKit | EPIC-11 | denied permission test |
| RF-003 Onboarding | EPIC-04 | UI flow |
| RF-004 Training Block | EPIC-05 | engine tests |
| RF-005 Today | EPIC-06 | UI test |
| RF-006 Time adaptation | EPIC-08 | optimizer matrix |
| RF-007 Logging | EPIC-06 | unit + UI |
| RF-008 Rest timer | EPIC-06 | timer tests/UI |
| RF-009 Exercise order | EPIC-07 | ordering fixtures |
| RF-010 Occupied | EPIC-09 | integration scenario |
| RF-011 Missing | EPIC-09 | persistence test |
| RF-012 Substitution | EPIC-09 | scoring fixtures |
| RF-013 Machine history | EPIC-09 | repository tests |
| RF-014 Progression | EPIC-10 | progression fixtures |
| RF-015 PRs | EPIC-10 | PR detector tests |
| RF-016 Consistency | EPIC-17 | adherence tests |
| RF-017 HealthKit workout | EPIC-11 | fake + physical device |
| RF-018 Watch | EPIC-12 | watch UI/device test |
| RF-019 Calories reconciliation | EPIC-11 | reconciliation matrix |
| RF-020 External workout | EPIC-11 | import tests |
| RF-021 Recovery | EPIC-13 | decision fixtures |
| RF-022 Deload | EPIC-13 | deload policy tests |
| RF-023 Restrictions | EPIC-14 | CRUD + policy tests |
| RF-024 Pain | EPIC-14 | progression safety test |
| RF-025 Explainability | EPIC-16 | DecisionRecord/explanation tests |
| RF-026 Coaching detail | EPIC-15 | UI/model tests |
| RF-027 Agent input | EPIC-16 | schema/validator tests |
| RF-028 Offline workout | EPIC-02/06 | airplane-mode scenario |
| RF-029 Sync | EPIC-02 | idempotency tests |
| RF-030 Export | EPIC-02 | exported schema tests |
| RF-031 Bodybuilding domain | EPIC-18 | domain tests |
| RF-032 Gym switching | EPIC-09 | integration tests |
| RF-033 Goal change | EPIC-05 | block transition tests |
| RF-034 Exercise catalog | EPIC-03 | catalog seed + MVP coverage tests (PR-0301) |
| RF-025 Explainability (versioned) | EPIC-03/16 | EvidenceRegistry + versioned rule references in DecisionRecord (PR-0303) |

## Historial y export por colecciones (SCRUM-23, RF-028/RF-030)

`Packages/PRCore/Sources/PRCore/LocalPersistence.swift`: una colección por
subdirectorio (`PersistenceCollection`) bajo `Application Support/PR/persistence`;
lectura tolerante (`RepositoryReadResult` con `unreadableCount`, registrada sin datos
personales vía `PersistenceLog`). `PersistenceMigration.swift`: migración única e
idempotente del layout compartido, clasificada por contenido. `DataExportCoordinator`
expone `ExportHistory` (vacío / cargado + ilegibles) para que Export nunca muestre un 0
silencioso. Cobertura en `Packages/PRCore/Tests/PRCoreTests/CollectionPersistenceTests.swift`.

## Días de la semana (SCRUM-27, RF-005)

`Packages/PRCore/Sources/PRDomain/TrainingWeek.swift`: único cálculo de "qué día es"
(lunes = 0 … domingo = 6 vía `(weekday + 5) % 7`, zona horaria inyectada, sin
depender de `firstWeekday`) y de qué días se entrena (primeros N desde el lunes, slot
propio por día). `TodayPlanBuilder` lo usa. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/TrainingWeekTests.swift` y
`Packages/PRCore/Tests/PRCoreTests/TodayWeekIntegrationTests.swift`.

## Volumen, orden y límites del plan (SCRUM-28 / SCRUM-29, RF-005, RF-034)

`BlockPlanner` reparte el objetivo semanal de cada músculo entre sus días y ejercicios
(una plantilla por día, recorte al tiempo de la sesión con `DurationEstimator`) y ordena
con `ExerciseOrderEngine` + `FatigueInterferenceEngine`; la explicación y la precedencia
(restricciones > rol funcional > prioridad muscular > demanda técnica > fatiga) viajan en
`BlockExplanation.sessionOrder` y se muestran en "¿Por qué este orden?". Límites únicos en
`TrainingWeek.allowedTrainingDays` (2...7) y `allowedSessionMinutes` (30...240). Nombres de
ejercicio en español desde `Resources/exercise-names-es.json` (el inglés queda como alias; los
IDs no cambian). Cobertura: `PRDomainTests/BlockPlannerOrderTests.swift`,
`PRCoreTests/BlockPlannerRealCatalogTests.swift`, `PRDomainTests/OnboardingTests.swift`.

## Recordar perfil y plan (SCRUM-26, RF-001/RF-005)

`PRDomain/StoredPlan.swift` (`StoredPlan`, `StoredSession`, `PlanChangeDecider`),
`PRCore/PlanStore.swift` (colecciones `plans`, `session` y `blocks`) y
`PRCore/AppSessionCoordinator.swift` (arranque: sesión → credencial de Apple → plan →
Hoy / cuestionario / login / perfil ilegible). Cambiar objetivo, fase o días cierra el bloque
anterior (`completed`) y crea uno nuevo; otros cambios regeneran el mismo bloque; un plan de
generador anterior se migra conservando el ID. Cobertura:
`PRCoreTests/PlanPersistenceTests.swift` y `PRUITests`: reabrir en `IntermediateQuestionnaireJourney` y
rehacer en `ProfileJourney`.

## Calidad de la asignación de ejercicios (RF-034, mejora sobre SCRUM-28/29)

`Resources/exercise-staples.json` (ejercicios de referencia por músculo) → `Exercise.staple` →
`ExerciseAssigner` (ancla y rotatables por orden de preferencia; genérico si no hay). Cobertura:
`PRCoreTests/BlockPlannerRealCatalogTests.swift` (`ExerciseSelectionQualityTests`).

## Entrenamiento que sobrevive al cierre y cierre de sesión (SCRUM-24 / SCRUM-25, RF-007)

`WorkoutSessionCoordinator` guarda la sesión de forma síncrona al iniciar y en cada cambio de
estado (nunca desde `tick()`); el descanso va como hora de fin (`RestSnapshot`).
`WorkoutRecoveryPlanner` (PRDomain) decide qué retomar/abandonar/completar y
`LocalPersistence.recoverWorkout` drena la cola de pendientes (idempotente) y restaura.
Una sesión en estado final rechaza otras transiciones y fija `endedAt`. Cobertura:
`PRCoreTests/WorkoutRecoveryTests.swift`, `WorkoutClosingTests.swift`,
`PRDomainTests/WorkoutRecoveryPlannerTests.swift` y la prueba de UI de cierre forzado (`WorkoutRecoveryJourney`).

## Persistencia local (EPIC-02)

Implementada en PR-0202 detrás de los protocolos `Repository` con un almacén
Codable/JSON de escritura atómica (no SwiftData; ver `docs/spec/docs/adr/ADR-0001`). Cobertura en
`Packages/PRCore/Tests/PRCoreTests/CodableRepositoriesTests.swift`: round-trip por entidad, relaciones,
delete policies, perfil único y persistencia atómica a disco. El save local es
inmediato y autoritativo para proteger los datos de workout (RF-028/RF-029).

## Migraciones seguras de datos guardados (SCRUM-40, RNF-028)

Cada colección guarda su versión de formato (`.schema-version`; sin marca = 1) y
`LocalPersistence.migrateSchemas()` la lleva a la vigente al arrancar. Las de cada usuario
migran en `scoped(toUser:)`. La migración escribe aparte y cambia las carpetas al final; la
original queda como respaldo. Un registro que no migra va a cuarentena y cuenta como
ilegible en Exportar y Progreso. Ver `docs/spec/docs/adr/ADR-0003`. Cobertura:
- `PRCoreTests/SchemaMigrationTests.swift`: orden, una sola vez, cortes, cuarentena,
  versión más nueva, paso faltante, por usuario, plan en cuarentena, y layout antiguo →
  versiones con Exportar.
- `PRCoreTests/PersistenceFormatTests.swift`: muestras reales por colección y versión,
  como detector en CI de cambios incompatibles.

## Composición de sesión (SCRUM-218, PR-B004, RF-006)

`SessionCompositionRule` (versión `pr-b004-v1`) fija el rango de ejercicios por duración
(30 → 3–4, 45 → 4–5, 60 → 5–7, 90+ → 7–9) y el mínimo de 2 series (3 en un ancla compuesta
con objetivo fuerza). `BlockPlanner` reparte las series de modo que nunca queda 1 serie y el
ancla sale al menos 2 veces por semana. Al componer cada sesión, primero aplica el tope y
luego el tiempo, y nunca quita las anclas compuestas ni los músculos prioritarios; si eso
no cabe, lo dice en la explicación. Cobertura:
- `PRDomainTests/SessionCompositionTests.swift`;
- `PRCoreTests/BlockPlannerRealCatalogTests.swift` (rango, fuerza y explicación);
- `PRCoreTests/RoutineCharacterizationTests.swift` (gates "nunca 1 serie" y "tope de ejercicios").

## "Ajustar a mi tiempo" sin series sueltas (SCRUM-225, RF-006)

El ajuste del día (`SessionTimeFitter` → `HardTimeOptimizer`) reduce un accesorio solo hasta
su calentamiento más `minimumWorkSets` (2, de `SessionCompositionRule`). Si ni así cabe, lo
quita. Cobertura:
- `PRDomainTests/HardTimeOptimizerTests.swift` (2 series se quita; 6 baja a 3 y luego a 2; el calentamiento no cuenta);
- `PRDomainTests/SessionTimeFitTests.swift`;
- `PRCoreTests/SessionTimeBudgetTests.swift` (plan real, 16 perfiles, cada sesión ajustada a 30 y 45 min, nunca 1 serie).

## Un plan ilegible no se sobrescribe (SCRUM-223, RNF-028)

Con un plan ilegible, "Rehacer cuestionario" primero guarda el registro intacto en
`plans/.quarantine/damaged/` (`PlanStore.preserveUnreadablePlan`) y solo después escribe el
plan nuevo. Si la copia falla, no se escribe nada. Si solo fallaba el bloque activo, el
historial de bloques se conserva. Cobertura: `PRCoreTests/UnreadablePlanTests.swift`.

## Una sola escala de dolor (SCRUM-32, RF-024, RN-003, RN-015)

`PainFeedback` guarda solo el nivel (`PainLevel`: ninguno, leve, moderado, alto) y, si se
indicó, el músculo. Moderado o alto bloquea la progresión (`PainFeedback.blocksProgression`)
igual en `PainFeedbackEngine`, `ProgressionEngine` y `StrengthProgressionEngine`, y el
umbral ya no se puede cambiar. La forma anterior (severidad 1–5 y molestia/punzante) se lee
con `LegacyPainScale`: 1 → leve; 2 y 3 → moderado; 4 y 5 → alto; punzante nunca por debajo
de moderado. `workouts` y `pending-operations` migran de v1 a v2 (ADR-0003).
`WorkoutSessionCoordinator.reportPain` guarda el dolor en la última serie antes de responder,
y `PainRecommendationPresenter` dice la recomendación sin diagnosticar. Cobertura:
- `PRDomainTests/PainScaleTests.swift`: la tabla, lectura y guardado, y los tres motores de
  acuerdo en cada nivel;
- `PRCoreTests/PainReportTests.swift`: reportar con `LocalPersistence` real, reabrir sin
  perder el dolor, textos sin diagnóstico, y migración de entrenamientos y series pendientes;
- `PRCoreTests/PersistenceFormatTests.swift`: muestras v1 (escala anterior) y v2.

## Prioridades en todos los niveles, pantorrilla y core (SCRUM-215, PR-B002, RF-004)

`OnboardingFlowPolicy` muestra el paso "Músculos prioritarios" (opcional, hasta 2) en todos
los niveles; a Novato y Principiante, con `OnboardingCopy` en palabras simples, y su
formulario sigue siendo el más corto. `TodayPlanBuilder.defaultPriorities()` agrega
pantorrilla y core en `.maintain`. El core va en el día con más espacio (pierna en
torso/pierna, jalón en empuje/jalón/pierna). Gana el tiempo: `BlockPlanner.compose` quita
primero los demás aislamientos y baja series; solo después pantorrilla y core. Si no caben
en la semana, el hecho `maintenanceLeftOut` y "Por qué tu plan" lo dicen; si los dejó fuera
una restricción, se explica como restricción. `StoredPlan.currentGeneratorVersion` = 5.
Cobertura:
- `PRDomainTests/MaintenanceCompositionTests.swift`: orden de recorte con catálogo sintético
  y aviso cuando no caben;
- `PRCoreTests/MuscleCoverageTests.swift`: catálogo real, presencia con tiempo, día de cada
  músculo por split, gana el tiempo, restricción y énfasis en cualquier nivel;
- `PRCoreTests/RoutineCharacterizationTests.swift`: gate "ningún plan sin pantorrilla o core
  sin decirlo";
- `PRCoreTests/PlanPersistenceTests.swift`: un plan del generador 4 se regenera con el mismo
  bloque y avisa;
- `ExperienceFlowTests`, `OnboardingTests` y la prueba de UI del principiante (`BeginnerQuestionnaireJourney`).

## Reportar el dolor en el entrenamiento (SCRUM-226, RF-024, RN-003, RN-015)

En el descanso, "Reportar dolor" abre la hoja "¿Te dolió esta serie?" (`PainReportSheet`),
que solo presenta `WorkoutSessionCoordinator.painReport`:
- el ejercicio de la última serie y el nivel ya guardado (gana el último);
- los músculos del ejercicio (`PainMuscleOptions`, del catálogo) para decir dónde, opcional;
- la recomendación de `PainFeedbackEngine`;
- si ese ejercicio todavía se puede saltar.

La escala usa siempre texto (`PainRecommendationPresenter.levelName`). Según el nivel:
- "Sin dolor" se guarda sin músculo y cierra la hoja;
- leve se confirma con un háptico;
- moderado y alto muestran la recomendación de SCRUM-32;
- alto ofrece saltar el ejercicio que dolió (`skipPainfulExercise`, mismas reglas que
  SCRUM-212) aunque no sea el que sigue.

Cobertura:
- `PRCoreTests/PainReportFlowTests.swift`: la hoja describe la última serie; gana el último
  nivel sin duplicar series; sin dolor no lleva músculo; la recomendación es la del motor;
  saltar el que dolió y retomarlo; no se ofrece si ya terminó; reabrir conserva el reporte;
  aviso si falla el guardado; músculos del catálogo real; textos sin diagnóstico;
- `PRUITests/WorkoutRecoveryJourney` (antes `testPainIsReportedDuringRestAndKeptAfterReopening`): moderado, músculo,
  reabrir y alto con saltar, en el simulador.

## Restricciones editables desde Perfil (SCRUM-36, RF-023, RN-004, RN-020)

Perfil › Restricciones deja de ser de solo lectura. Las piezas:
- **`RestrictionEditor`** (PRDomain): agregar una zona (patrones de SCRUM-209, sin duplicar
  una en vigor), editar, evitar un ejercicio, permitirlo (sólo con origen profesional),
  quitarlo y resolver.
- **`AppSessionCoordinator.updateRestrictions`**: regenera el mismo bloque y lo guarda.
- **`RestrictionScreenModel`**: decide cuándo confirmar, cuándo abrir la existente y qué aviso
  mostrar.
- **`RestrictionListPresenter`**: las en vigor y el historial.

Las reglas:
- Una activa se resuelve por acción explícita, con su fecha, y queda en el historial.
- Una fecha de revisión vencida nunca la resuelve (RN-004).
- Cualquier cambio a una profesional pide confirmación (RN-020).
- En el cuestionario, una zona resuelta marcada otra vez vuelve a proteger; desmarcar resuelve
  y no borra; sólo salen marcadas las zonas en vigor.
- El registro de un entrenamiento guarda su plantilla: si el plan se regenera a la mitad, se
  retoma igual.
- El guard de logs también cubre las notas de las restricciones.

Cobertura:
- `PRDomainTests/RestrictionEditorTests.swift` (11):
  - agregar, no duplicar, confirmación profesional, editar, nota larga;
  - evitar y permitir; un permiso sólo refina su restricción;
  - resolver; la fecha de revisión no cura;
  - el cuestionario con las resueltas.
- `PRDomainTests/RestrictionManagerTests.swift`: dos pruebas cambiadas a propósito por la
  decisión 1.
- `PRCoreTests/RestrictionEditingFlowTests.swift` (12, con `LocalPersistence` real):
  - agregar y reabrir; resolver;
  - cambio inválido; plan imposible; disco que falla;
  - entrenamiento en curso;
  - rehacer el cuestionario; la nota no llega a la IA;
  - lo que decide la pantalla.
- `PRCoreTests/RestrictionListPresenterTests.swift`: en vigor e historial, revisión en VoiceOver.
- `PRUITests/ProfileJourney` (antes `testRestrictionIsAddedAndResolvedFromProfile`): agregar codo desde Perfil → "Por
  qué tu plan" lo cuida y Hoy sin curls ni tríceps → resolver con confirmación → historial y
  el plan deja de cuidarlo.

## Pruebas E2E por recorrido (SCRUM-228, PR-T001)

Las 32 pruebas de UI quedaron en 8 recorridos, una clase cada uno en `PRUITests/Journeys/` (SCRUM-224 agregó el noveno);
ninguna comprobación se quitó ni se debilitó (tabla en `mvp-plan.md` › SCRUM-228). Qué cubre
cada recorrido:

| Recorrido | Requisitos e historias |
|---|---|
| `IntermediateQuestionnaireJourney` (smoke) | RF-003, SCRUM-198 (mayor de edad), 195, 196, 202 (consentimiento), 210, 215, 26 (reabrir) |
| `BeginnerQuestionnaireJourney` | SCRUM-210 (principiante y avanzado), 215 |
| `PendingPlanJourney` | SCRUM-193 (plan pendiente), 205 (por qué tu plan), 209 (zona en "Tu semana") |
| `WorkoutRecoveryJourney` (smoke) | RF-007, SCRUM-24 (cierre forzado), 226 (dolor), 212 (saltar y retomar) |
| `FirstWorkoutJourney` (smoke) | SCRUM-186 y 213 (Progreso), 23 y 190 (Exportar una sola vez) |
| `ProfileJourney` | SCRUM-36 (restricciones editables), 208 (cerrar sesión), 26 (rehacer) |
| `TodayJourney` | RF-005, SCRUM-195, 197, 203, 211, 222, 28 (volumen realista) |
| `SundayJourney` | SCRUM-27 (descanso el domingo) |
| `SupersetJourney` | SCRUM-224 (superset en Hoy, en "Por qué tu plan" y en el entrenamiento) |

Los recorridos que no son del cuestionario arrancan con `-PRUITestProfile intermedio-lmv`
(sólo Debug y con datos temporales): `UITestProfileSeeder` contesta el cuestionario con el
mismo `OnboardingCoordinator` que la pantalla y el plan lo arma `planCompleted`, como al
terminarlo. Cobertura en `make ci`:
- `PRCoreTests/UITestProfileSeederTests.swift`: el perfil sembrado y el cuestionario contestado
  como en las pruebas de UI dan el mismo perfil y el mismo plan (lunes y domingo), con
  `LocalPersistence` real y el catálogo real; con un plan guardado no contesta nada; sin
  sesión, tampoco;
- `PRCoreTests/UITestLaunchOptionsTests.swift`: la opción sólo vale en Debug, sólo con
  `-PRUITestReset`, y un perfil desconocido se ignora.

## Supersets compatibles (SCRUM-224, RF-006, PR-B004b)

Dos ejercicios sin músculos en común se hacen alternados (A1 → A2 → descanso) para caber en
el tiempo sin bajar series ni recortar lo básico. Las piezas:
- `PRDomain/Training.swift`: `SupersetPair` y `SessionTemplate.supersets` (opcional, ADR-0003:
  sin subir versión); `supersetPairs` ignora pares inválidos.
- `PRDomain/SupersetPairing.swift`: compatibles = sin músculos en común, ni secundarios.
- `PRDomain/BlockPlanner.swift` (`compose`): paso 2b del recorte de SCRUM-218, antes de bajar
  series; nunca un ancla compuesta; un par que al final no hace falta se deshace. Generador 9.
- `PRDomain/DurationEstimator.swift`: un descanso por ronda.
- `PRDomain/WorkoutQueue.swift` y `PRCore/WorkoutSessionCoordinator.swift`: alternar, descanso
  tras la ronda; dejar para después o saltar uno separa el par (la pareja sigue sola).
- `PRDomain/HardTimeOptimizer.swift` y `SessionTimeFit.swift`: "Ajustar a mi tiempo" junta
  pares antes de bajar series con los músculos del catálogo.
- Textos: `PlanRationalePresenter` (hecho `superset`, también para la IA), `SessionTimePresenter`
  y `SupersetPresenter` (Hoy).

Cobertura:
- `PRDomainTests/SupersetTests.swift`: modelo, lectura sin el campo, estimador, compatibilidad,
  cola (alternar, calentamiento, separados, para después, saltar), optimizador y ajuste;
- `PRCoreTests/SupersetCompositionTests.swift`: catálogo real (compatibles, nunca ancla
  compuesta, nunca 1 serie, sólo cuando hace falta, nada con tiempo de sobra);
- `PRCoreTests/SupersetWorkoutTests.swift`: coordinador con `LocalPersistence` real (alternar,
  para después, saltar, cierre forzado a mitad de la ronda, Exportar y Progreso iguales);
- `PRCoreTests/SupersetPresentationTests.swift`: textos en español e inglés y el ajuste con el
  plan real;
- `PRCoreTests/PlanPersistenceTests.swift`: un plan del generador 8 se regenera con supersets;
- `PRUITests/SupersetJourney`: Hoy, "Por qué tu plan" y una ronda A1 → A2 → descanso.

## Catálogo de ejercicios (EPIC-03)

Implementado en PR-0301 con el dataset público *free-exercise-db* (Unlicense)
curado a 678 ejercicios y mapeado de forma determinista a la ontología `Exercise`
de PRDomain (ver `docs/spec/docs/adr/ADR-0002`). Cobertura en
`Packages/PRCore/Tests/PRCoreTests/ExerciseCatalogTests.swift`: carga del bundle,
determinismo de IDs, patrones MVP e idempotencia del seed (RF-034).

**Clasificación revisada (SCRUM-37, P0, RF-034, RF-023).** Con restricción de codo, el
plan asignaba tríceps y bíceps con cuerda, porque los clasificaba como cardio. Ahora:
- las reglas por nombre de `ExerciseInflector` van en orden;
- `contraindicationTags` cubre codo, hombro y cuello, así que la restricción ya no depende
  solo del patrón (ver la actualización de ADR-0002).

Cobertura en `PRCoreTests/CatalogClassificationTests.swift`:
- cada zona del formulario contra el catálogo real (asignación por músculo y variedad, y
  plan completo), con un criterio que no usa la clasificación;
- los 63 staples con su patrón esperado;
- todo el catálogo: campos válidos, sin músculos repetidos, ángulos y aperturas;
- la lista con razón de lo que no cuadra con su músculo principal y de lo que queda como
  cardio;
- la búsqueda en menos de 100 ms.

`PlanPersistenceTests.planWithElbowLoadingExerciseIsRegenerated`: un plan del generador 5
se regenera sin el ejercicio que carga el codo.

**Selección por slots, objetivo, experiencia y fase (SCRUM-219, PR-B005, RF-023).** Antes
el ancla era siempre el primer staple: objetivo, experiencia y fase no cambiaban los
ejercicios. Ahora `ExerciseSelectionRule` (`pr-b005-v1`) reparte los staples por slot
funcional de cada músculo. Dentro de cada slot:
- el ancla sale por objetivo y experiencia: el novato recibe lo guiado y el avanzado con
  objetivo de fuerza, la barra en los básicos;
- los rotables salen por experiencia y fase: en déficit, menos fatiga;
- los rotables giran con el lugar del bloque en el historial (`blockSequence`), sin azar.

Cobertura:
- `PRDomainTests/ExerciseAssignmentTests.swift`, suite "Slots y scoring por eje" (6): slots,
  objetivo, experiencia, fase, rotación entre bloques y slot sin equipo;
- `PRCoreTests/ExerciseSelectionTests.swift` (5, catálogo real): tabla de anclas,
  novato/avanzado, déficit, bloques consecutivos y restricción o equipo limitado por zona;
- `BlockPlannerRealCatalogTests.slotsCoveredBeforeRepeating`: cobertura de slots en la
  asignación y en la semana;
- `PlanPersistenceTests.secondBlockRotatesAndKeepsItsPlace`: el segundo bloque rota y al
  regenerarse conserva su lugar;
- SCRUM-214: "cambia por objetivo" y "cambia por experiencia" salen de `withKnownIssue`.

**Volumen por experiencia; el tiempo pone el techo (SCRUM-227, PR-B003, RF-005, RN-002, ADR-0004).**
- `VolumeDefaults` v2 elige el punto del rango por experiencia.
- `VolumeAllocator` lo acota al rango y, con `maxWeeklySets` (lo que cabe en la semana), lo baja hacia el mínimo; nunca por debajo.
- `BlockPlanner` pasa la experiencia y el techo.

Cobertura:
- `PRDomainTests/VolumeAllocatorTests.swift`, suite "Volumen por experiencia" (6): posición por experiencia, siempre dentro del rango, el énfasis sigue arriba, posición acotada, techo hacia el mínimo y regla v2;
- `BlockPlannerRealCatalogTests`:
  - `moreTimeNeverExceedsTierMax` (reemplaza a `moreTimeDoesNotAddSets`), `ninetyNeverGivesLessThanSixty` y `noviceUnchangedOthersMore`;
  - las dos pruebas de recorte de SCRUM-218 fijan el volumen para comparar planes con el mismo volumen;
- `PlanPersistenceTests.planFromGenerator7GetsVolumeByExperience`.

## Evidence Registry (EPIC-03)

Implementado en PR-0303 en `Packages/PRCore/Sources/PRDomain/Evidence.swift`
(promptMaster §22): `EvidenceRule` versionada + `EvidenceRegistry` centralizado
(el cambio de una regla exige bump de versión) + `EvidenceRuleReference`
(id + versión). `DecisionRecord` persiste la referencia versionada de la regla
usada, haciendo auditable qué versión de regla soportó cada decisión (RF-025).
Cobertura en `Packages/PRCore/Tests/PRDomainTests/EvidenceTests.swift`.

## Búsqueda de ejercicios (EPIC-03)

Implementado en PR-0302 en `Packages/PRCore/Sources/PRDomain/ExerciseSearch.swift`:
`ExerciseSearchEngine` offline determinista (nombre/aliases normalizados, filtros por
equipment/patrón/músculos) con objetivo <100 ms sobre el catálogo MVP. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/ExerciseSearchTests.swift` +
`Packages/PRCore/Tests/PRCoreTests/ExerciseSearchPerfTests.swift`.

## Split selector (EPIC-05)

Implementado en PR-0501 en `Packages/PRCore/Sources/PRDomain/SplitSelector.swift`
(promptMaster §8.2): selección determinista y explicable de la estructura de bloques
por días/objetivo/experiencia (fullBody 2–3, upperLower 4, pushPullLegs 5+), sin
depender de LLM. Cobertura en `Packages/PRCore/Tests/PRDomainTests/SplitSelectorTests.swift`
(RF-004).

## Volume allocator (EPIC-05)

Implementado en PR-0502 en `Packages/PRCore/Sources/PRDomain/VolumeAllocator.swift`
(plan §4B): distribución determinista de sets semanales por músculo según
`PriorityTier`, con límites versionados vía `EvidenceRule` (`VolumeConfig`), sin
volumen negativo y sin inventar músculos. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/VolumeAllocatorTests.swift` (RF-004).

## Exercise assignment (EPIC-05)

Implementado en PR-0503 en `Packages/PRCore/Sources/PRDomain/ExerciseAssignment.swift`
(plan §4C): asignación de `anchors` (estables para medir progreso) y `rotatables`
(rotación dentro de la familia según `varietyPreference`), usando sólo equipment
disponible/conocido o dejando candidatos para pregunta si `unknown`, sin programas
ejercicios bloqueados por `TrainingRestriction` (excluye patrones/IDs prohibidos y
respeta la lista permitida). Cobertura en
`Packages/PRCore/Tests/PRDomainTests/ExerciseAssignmentTests.swift` (RF-004).

## Exercise order (EPIC-07)

Implementado en PR-0701 en `Packages/PRCore/Sources/PRDomain/ExerciseOrder.swift`
(plan §4D, promptMaster §9): orden base determinista de una sesión por prioridad
muscular, rol funcional y demanda técnica (`orderScore` §9.3), con compuestos antes
de accesorios y priority isolation adelantable según prioridad del bloque. Cobertura
en `Packages/PRCore/Tests/PRDomainTests/ExerciseOrderTests.swift` (RF-009).

## Fatigue interference (EPIC-07)

Implementado en PR-0702 en `Packages/PRCore/Sources/PRDomain/FatigueInterference.swift`
(plan §4D, promptMaster §9.2): penaliza la pre-fatiga de musculatura necesaria para un
movimiento prioritario posterior (acumulando fatiga previa), sin penalizar supersets
compatibles, con configuración versionada vía `EvidenceRule` (`FatigueInterferenceConfig`)
y reorder determinista que no mueve un movimiento prioritario después de uno menor.
Cobertura en `Packages/PRCore/Tests/PRDomainTests/FatigueInterferenceTests.swift` (RF-009).

## Block generation (EPIC-05)

Implementado en PR-0504 en `Packages/PRCore/Sources/PRDomain/BlockPlanner.swift`
(plan §4F): orquesta de forma determinista SplitSelector → VolumeAllocator →
ExerciseAssigner → ExerciseOrderEngine → FatigueInterferenceEngine para producir un
`TrainingBlock` persistible de 4–8 semanas, explicable (`BlockExplanation` con facts y
referencias versionadas) y reproducible; cada `plan` genera un bloque NUEVO sin mutar
ni borrar historial previo. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/BlockPlannerTests.swift` (RF-004, RF-009).

## Active workout state machine (EPIC-06)

Implementado en PR-0602 en `Packages/PRCore/Sources/PRDomain/ActiveWorkout.swift`
(plan §8, promptMaster §6.7): `ActiveWorkoutController` gestiona el ciclo de vida de
un entrenamiento activo (start/pause/resume/finish/complete/abandon) validando cada
transición contra `WorkoutLifecycleState` y rechazando movimientos inválidos; no muta
el historial de lo realizado. Persiste/restaura el workout activo tras kill/relaunch
vía `ActiveWorkoutSnapshot` Codable, sin restaurar estados terminales. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/ActiveWorkoutTests.swift` (RF-005).

## One-tap set completion (EPIC-06)

Implementado en PR-0603 en `Packages/PRCore/Sources/PRDomain/SetCompleter.swift`
(plan §8): precarga target weight/reps desde la prescripción (`targetLoad`) o desde el
último peso realizado (`weightFromHistory`); registra con un tap si el input coincide
exactamente, y ofrece edición accesible vía `recordSet`. Ambos persisten el set en la
sesión activa ANTES de cualquier transición UI, de forma append-only sin mutar el
plan ni el historial. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/SetCompleterTests.swift` (RF-005).

## Rest timer (EPIC-06, RF-008)

Implementado en PR-0604 en `Packages/PRCore/Sources/PRDomain/RestTimer.swift`
(plan §8): inicia automáticamente el descanso tras un working set (no warmup) con la
duración recomendada desde `SetPrescription.restSeconds`; permite `skip`/`extend(by:)`
y no bloquea la navegación (estado puro). El `endDate` anclado en wall-clock hace que
`remaining(at:)`/`hasElapsed(at:)` perduren tras background/relaunch. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/RestTimerTests.swift` (RF-008).

## Workout completion summary (EPIC-06)

Implementado en PR-0605 en `Packages/PRCore/Sources/PRDomain/WorkoutSummary.swift`
(plan §8): agrega una sesión en duration, working sets (`.completed`), volume
(Σ weight×reps de los completados) y next action según lifecycle. Detecta PRs vía
`PersonalRecordDetector` contra un baseline histórico (nunca inventa récords) y sólo
propaga energía cuando llega reconciliada de una fuente externa (RN-008, sin doble
contabilización). Cobertura en
`Packages/PRCore/Tests/PRDomainTests/WorkoutSummaryTests.swift` (RF-005, RF-006).

## Duration estimator (EPIC-08, RF-006)

Implementado en PR-0801 en `Packages/PRCore/Sources/PRDomain/DurationEstimator.swift`
(plan §8): estima la duración de una sesión desde defaults por set/rest/transición con
override por ejercicio y multiplicador de calentamiento; mantiene un perfil personal
EWMA (`averageSeconds`+`sampleCount`+`confidence`) que se actualiza con workouts
completados y favorece los tiempos personales frente a los defaults cuando la confianza
es suficiente. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/DurationEstimatorTests.swift` (RF-006).

## Hard time optimizer (EPIC-08, RF-006)

Implementado en PR-0802 en `Packages/PRCore/Sources/PRDomain/HardTimeOptimizer.swift`
(plan §8): recorta una sesión a un límite duro determinista preservando anchors y
prioridades, eliminando opcionales primero, reduciendo accesorios (mitad del set-count
antes de descartar) y nunca agregando supersets incompatibles (sólo los disjuntos). La
tolerancia queda documentada en `withinLimit` y `notes`. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/HardTimeOptimizerTests.swift` (RF-006).

## Flexible time optimizer (EPIC-08, RF-006)

Implementado en PR-0803 en `Packages/PRCore/Sources/PRDomain/FlexibleTimeOptimizer.swift`
(plan §8): ajusta una sesión a `target ± tolerance`, recortando SÓLO lo necesario
(reusando `HardTimeOptimizer`) para entrar por el borde superior; por debajo del umbral
no añade volumen (invariante) y explica la no-factibilidad cuando sobrepasa aun con
anchors/prioridades o la ventana es demasiado estrecha. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/FlexibleTimeOptimizerTests.swift` (RF-006).

## Extra time behavior (EPIC-08, RF-006)

Implementado en PR-0804 en `Packages/PRCore/Sources/PRDomain/ExtraTimeBehavior.swift`
(plan §8): con tiempo extra no multiplica el volumen de trabajo automáticamente
(plan §388), mantiene los opcionales separados del plan núcleo y sólo ofrece
cardio/mobility/posing cuando corresponden al objetivo/fase (`mobility` siempre;
`cardio` por objetivo o déficit; `posing` sólo `bodybuilding`), sin exceder el tiempo
disponible. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/ExtraTimeBehaviorTests.swift` (RF-006).

## Gym profile (EPIC-09, RF-011)

Implementado en PR-0901 en `Packages/PRCore/Sources/PRDomain/GymProfileManager.swift`
(plan §9): crea/renombra/selecciona el perfil de gym y gestiona la disponibilidad del
equipamiento (`.unknown`/`.available`/`.doesNotExist`) de forma persistente, dejando
`.occupied` como session-scoped; no obliga a un formulario inicial de todas las
máquinas (sin confirmar → `.unknown`, progressive disclosure). Cobertura en
`Packages/PRCore/Tests/PRDomainTests/GymProfileManagerTests.swift` (RF-010, RF-011).

## Mark occupied (EPIC-09, RF-010)

Implementado en PR-0902 en `Packages/PRCore/Sources/PRDomain/OccupancyController.swift`
(plan §9): marca un equipo como ocupado durante la sesión activa (session-scoped, no
persistido como hecho del gym) y dispara una señal de reevaluación del orden
(`shouldReorder`) cuando un ítem ordenado del plan usa el equipo ocupado, para reordenar
ANTES de sustituir. Cobertura en
`Packages/PRCore/Tests/PRDomainTests/OccupancyControllerTests.swift` (RF-010).

## Mark missing (EPIC-09, RF-011)

Implementado en PR-0903 en `Packages/PRCore/Sources/PRDomain/MissingEquipment.swift`
(plan §9): persiste el equipamiento inexistente en el perfil del gym (`.doesNotExist`)
y filtra las sesiones futuras para que no programen máquinas marcadas inexistentes,
salvo que el usuario revierta (`revert` → `.unknown`). Cobertura en
`Packages/PRCore/Tests/PRDomainTests/MissingEquipmentTests.swift` (RF-011).

## PR celebration (EPIC-10, RF-015)

Implementado en PR-1004: `Packages/PRCore/Sources/PRDomain/PRCelebration.swift` decide
la celebración (una por ejercicio, unidad real, explicación por nivel de coaching),
`Packages/PRCore/Sources/PRCore/PRCelebrationPresenter.swift` la convierte en textos
localizados (RNF-013, `Localizable.xcstrings`) con anuncio VoiceOver, y
`PersonalRecordBaselineBuilder` (`WorkoutSummary.swift`) deriva baselines
del historial comparables por unidad + máquina (RN-007), de modo que no se celebra un
récord inventado. Cobertura en `Packages/PRCore/Tests/PRDomainTests/PRCelebrationTests.swift`,
`Packages/PRCore/Tests/PRCoreTests/PRCelebrationPresenterTests.swift` y
`Packages/PRCore/Tests/PRCoreTests/WorkoutCelebrationWiringTests.swift`.

## Safety-critical traceability

| Rule | Components that MUST enforce it |
|---|---|
| RN-003 no progression with moderate/high pain | RestrictionPolicyEngine + `PainFeedback.blocksProgression` (PainFeedbackEngine, ProgressionEngine, StrengthProgressionEngine) + ActionPolicyValidator |
| RN-004 restriction not auto-resolved | RestrictionRepository + Restrictions feature |
| RN-008 no calorie double count | WorkoutReconciliationEngine + summary aggregation |
| RN-009 no invented external sets | Health import mapping |
| RN-015 no diagnosis | Agent policy + copy review + PainRecommendationPresenter (test de palabras de diagnóstico) |
| RN-017 agent actions validated | AgentCore/ActionPolicyValidator |
| RN-018 measured vs estimated | Domain metadata + UI formatting |

