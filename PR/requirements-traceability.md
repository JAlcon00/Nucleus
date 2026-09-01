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

## Persistencia local (EPIC-02)

Implementada en PR-0202 detrás de los protocolos `Repository` con un almacén
Codable/JSON de escritura atómica (no SwiftData; ver `PR-agentic-fitness-spec/docs/adr/ADR-0001`). Cobertura en
`Packages/PRCore/Tests/PRCoreTests/CodableRepositoriesTests.swift`: round-trip por entidad, relaciones,
delete policies, perfil único y persistencia atómica a disco. El save local es
inmediato y autoritativo para proteger los datos de workout (RF-028/RF-029).

## Catálogo de ejercicios (EPIC-03)

Implementado en PR-0301 con el dataset público *free-exercise-db* (Unlicense)
curado a 678 ejercicios y mapeado de forma determinista a la ontología `Exercise`
de PRDomain (ver `PR-agentic-fitness-spec/docs/adr/ADR-0002`). Cobertura en
`Packages/PRCore/Tests/PRCoreTests/ExerciseCatalogTests.swift`: carga del bundle,
determinismo de IDs, patrones MVP e idempotencia del seed (RF-034).

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

## Safety-critical traceability

| Rule | Components that MUST enforce it |
|---|---|
| RN-003 no progression with moderate/high pain | RestrictionPolicyEngine + ProgressionEngine + ActionPolicyValidator |
| RN-004 restriction not auto-resolved | RestrictionRepository + Restrictions feature |
| RN-008 no calorie double count | WorkoutReconciliationEngine + summary aggregation |
| RN-009 no invented external sets | Health import mapping |
| RN-015 no diagnosis | Agent policy + copy review |
| RN-017 agent actions validated | AgentCore/ActionPolicyValidator |
| RN-018 measured vs estimated | Domain metadata + UI formatting |

