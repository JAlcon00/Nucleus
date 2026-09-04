# plan.md — Plan de implementación PR

> Este plan convierte la visión de `promptMaster.md` y el backlog en una secuencia de implementación verificable. Las fases son gates técnicos: no se avanza sólo por calendario.

---

# 1. Estrategia general

## Principio

Construir de adentro hacia afuera:

```text
Domain
  ↓
Deterministic Training Engine
  ↓
Local Persistence / Offline Workout
  ↓
Simple UX
  ↓
Gym Adaptation
  ↓
HealthKit / watchOS
  ↓
Agentic Language Layer
  ↓
Advanced Learning / Bodybuilding
```

No invertir el orden.

## Desarrollo obligatorio

Cada slice sigue:

```text
DESARROLLAR
    ↓
TESTEAR
    ↓
PROBAR
    ↓
INTEGRAR
```

“Probar” significa ejecutar el comportamiento en una app/simulator/device apropiado, no sólo leer el código.

---

# 2. Milestones

| Milestone | Resultado |
|---|---|
| M0 | Repo compilable, arquitectura y tests base |
| M1 | Entrenador offline completo sin IA |
| M2 | Adaptación real al gym y tiempo |
| M3 | HealthKit + Apple Watch coherentes |
| M4 | Agente conversacional seguro sobre engine determinista |
| M5 | Recovery, lesiones, educación, gamificación |
| M6 | Release candidate V1 |
| M7 | Bodybuilding / self-knowledge V2 |

---

# 3. Fase 0 — Repository discovery y baseline

## Objetivo
No modificar arquitectura a ciegas.

## Acciones

1. `git status`.
2. inventariar archivos/targets/schemes.
3. `xcodebuild -list`.
4. compilar baseline.
5. ejecutar tests existentes.
6. registrar errores preexistentes.
7. verificar bundle IDs/entitlements existentes sin cambiarlos innecesariamente.
8. decidir si `PRCore` será local package o targets existentes.

## Gate de salida

- baseline documentado;
- build reproducible;
- tests baseline conocidos;
- ningún trabajo previo sobrescrito.

---

# 4. Fase 1 — Core Domain

## Objetivo
Construir el vocabulario estable del producto antes de UI.

## Implementar

- typed IDs;
- user profile;
- goals/phases;
- Exercise ontology;
- ExerciseFamily;
- TrainingBlock;
- SessionTemplate;
- WorkoutSessionRecord;
- SetPrescription/SetRecord;
- GymProfile/MachineProfile;
- TrainingRestriction;
- DecisionRecord;
- EvidenceRule.

## Decisiones técnicas

- Domain no depende de SwiftUI, HealthKit, SwiftData o networking.
- Todos los modelos adecuados son `Sendable`.
- Evitar protocol proliferation para value objects simples.
- Validación en initializers/factories/domain services.

## Pruebas

- Codable roundtrip;
- value bounds;
- lifecycle transitions;
- goal + phase combinations;
- gym state semantics;
- restriction lifecycle.

## Gate

- PRCore Domain compila independientemente;
- tests de dominio pasan;
- ninguna View contiene business rule.

---

# 5. Fase 2 — Persistence y offline-first

## Objetivo
Garantizar que una sesión jamás dependa de internet.

## Implementar

- repository protocols;
- SwiftData adapters;
- in-memory fakes;
- atomic local set save;
- pending operation queue;
- schema/version baseline.

## Flujo crítico

```text
Tap ✓ Set
  ↓
validate SetRecord
  ↓
write local transaction
  ↓ SUCCESS
update UI
  ↓
enqueue remote sync (optional)
```

Nunca:

```text
Tap ✓ → API → wait → save
```

## Pruebas

- simulate network unavailable;
- app restart with active workout;
- duplicate retry;
- persistence mapping;
- transactional failure.

## Gate

Se puede crear y recuperar un workout completo sin red.

---

# 6. Fase 3 — Exercise Knowledge + Evidence Registry

## Objetivo
Dar al engine información suficiente para decidir.

## Implementar

- catálogo inicial versionado;
- import/seed idempotente;
- search;
- aliases;
- movement patterns;
- muscle contributions;
- substitution families;
- fatigue/skill/stability/loadability;
- evidence rules versionadas.

## Revisión de calidad de datos

Para cada ejercicio del MVP verificar:

- nombre canonical;
- equipment;
- movement pattern;
- primary muscles;
- secondary muscles;
- role candidates;
- family;
- restriction tags.

## Gate

Ninguna feature de substitution/order depende de strings o heurísticas de nombre.

---

# 7. Fase 4 — Training Engine v1

## Objetivo
Ser capaz de generar una sesión sensata sin LLM.

## Subfases

### 4A SplitSelector
Entrada:

```text
goal
experience
days/week
usual time
```

Salida: split.

### 4B VolumeAllocator
Entrada:

```text
goal
phase
priorities
experience
time
EvidenceRules
```

Salida: weekly muscle targets.

### 4C ExerciseAssignment
Respeta:

- equipment;
- restrictions;
- priorities;
- anchor/rotatable policy.

### 4D ExerciseOrderEngine
Ordena por:

- priority;
- role;
- skill;
- fatigue interference.

### 4E ProgressionEngine
Implementar primero double progression.

## Testing matrix

| Fixture | Goal | Phase | Experience | Expected |
|---|---|---|---|---|
| A | hypertrophy | surplus | novice | simple full body |
| B | hypertrophy | deficit | intermediate | preserved anchors, conservative volume |
| C | strength | maintenance | advanced | priority lifts first |
| D | bodybuilding | surplus | advanced | muscle priorities influence order/volume |
| E | generalHealth | maintenance | beginner | manageable frequency/time |

## Gate

Given fixture → block/session reproducible + explainable.

---

# 8. Fase 5 — First-user experience

## Objetivo
Pasar de cero a workout real rápidamente.

## Implementar

- Sign in with Apple boundary/flow;
- onboarding;
- local profile;
- block generation;
- Today.

## UX constraints

- no giant dashboard;
- first plan visible inmediatamente después de onboarding;
- HealthKit puede skip;
- lenguaje según coaching detail.

## Gate

Un usuario nuevo puede llegar a `Start Workout` sin configurar parámetros avanzados.

---

# 9. Fase 6 — Workout tracker v1

## Objetivo
Crear una UX de logging más simple que la complejidad interna.

## Pantalla principal

```text
Exercise
Suggested Weight × Reps
Set X / Y
[✓]
```

## Implementar

- active workout state machine;
- edit weight;
- edit reps;
- complete set;
- skip;
- rest timer;
- resume after relaunch;
- finish summary.

## Performance target

Set completion local <100 ms perceptual target.

## Manual test obligatorio

Simular una sesión de 20+ sets completa en simulator/device.

## Gate

Workout de principio a fin sin red y sin pérdida de datos.

---

# 10. Fase 7 — Time-aware engine

## Objetivo
Resolver el caso “normalmente 1 h, hoy 30 min, mañana 3 h”.

## Implementar

### DurationEstimator v1
Defaults por:

- sets;
- rest;
- transition;
- exercise category.

### Personal timing
Actualizar EWMA con historial.

### Hard optimizer
Ejemplo:

```text
plan = 65 min
available = 35 min
```

Debe:

1. preservar priority anchor;
2. eliminar optional;
3. reducir accessory;
4. compatible supersets;
5. redistribuir si aplica.

### Extra time
No añadir volumen sin límites.

## Tests

- 30, 45, 60, 90, 180 min;
- priority muscle;
- strength anchor;
- restrictions;
- no feasible plan.

## Gate

Todos los outputs respetan time constraint y no violan safety/priority invariants.

---

# 11. Fase 8 — Gym intelligence

## Objetivo
Resolver la fricción principal del gimnasio real.

## Implementar

- gym profiles;
- machine profiles;
- select current gym;
- occupied;
- missing;
- substitution;
- reorder-before-replace;
- per-machine history.

## Flujo ocupado

```text
User taps OCCUPIED
  ↓
mark temporary state
  ↓
OrderEngine evaluates remaining session
  ↓
if safe reorder exists → suggest/perform reorder
else → SubstitutionEngine ranks candidates
```

## Flujo missing

```text
User taps DOESN'T EXIST
  ↓
persist gym equipment missing
  ↓
recompute current session
  ↓
future block generation excludes equipment
```

## Gate

Un usuario puede entrenar en un gym incompleto sin entrar manualmente a un catálogo de ejercicios.

---

# 12. Fase 9 — Progression, PR y consistency

## Objetivo
Hacer progreso visible y accionable.

## Implementar

- double progression;
- PR detector;
- e1RM versioned formula;
- weekly adherence;
- block completion;
- consistency streak.

## Regla

No daily streak pressure.

## Gate

Descanso programado no rompe consistency; pain blocks progression.

---

# 13. Fase 10 — HealthKit iPhone layer

## Objetivo
Usar Apple Health como contexto y workout source sin duplicar datos.

## Implementar

- HealthWorkoutStore protocol;
- authorization coordinator;
- requested types mínimos;
- workout lifecycle;
- summary;
- external workout read;
- reconciliation engine.

## Reconciliation algorithm v1

Inputs:

```text
start
end
duration
activityType
source/device
energy
```

Candidate duplicate if:

```text
overlap >= 0.80
AND compatible activity type
AND temporal tolerance satisfied
```

Decision uses canonical priority.

## Tests

- exact duplicate;
- 90% overlap;
- adjacent workouts;
- two legitimate separate strength workouts same day;
- missing energy;
- denied permissions.

## Gate

No scenario de fixture suma dos veces el mismo workout.

---

# 14. Fase 11 — watchOS

## Objetivo
Poder completar el workout sin usar constantemente el iPhone.

## Implementar en orden

1. Watch workout UI con fake data.
2. HealthKit workout lifecycle real.
3. set logging local/watch coordination.
4. phone/watch synchronization.
5. failure handling.
6. Digital Crown refinements.

## Reglas

- verificar APIs reales en Xcode/Apple docs;
- no asumir network constante entre phone/watch;
- commands idempotentes;
- duplicate set prevention.

## Device testing

HealthKit workout behavior debe probarse en hardware físico antes de release.

## Gate

Workout completo desde Watch, con sets reflejados correctamente y HealthKit workout finalizado.

---

# 15. Fase 12 — Recovery & restrictions

## Objetivo
Que el coach también sepa frenar.

## Implementar

- check-in;
- RecoveryDecisionEngine;
- rest/adjust/recovery session;
- restrictions CRUD;
- RestrictionPolicyEngine;
- pain feedback;
- progression gate;
- review date.

## Safety tests obligatorios

- overhead forbidden → no overhead substitutions;
- pain high → no load increase;
- resolved restriction only after explicit action;
- restriction conflict → safe no-plan response.

## Gate

No fixture de restriction puede ser bypassed por substitution, agent o progression.

---

# 16. Fase 13 — Agentic layer

## Objetivo
Agregar lenguaje natural SIN ceder el control del Training Engine.

## Implementar primero sin proveedor real

- AgentIntent;
- AgentAction;
- ActionPolicyValidator;
- fake AgentGateway;
- templated explainability.

Después integrar backend.

## Agent pipeline

```text
User text
  ↓
AgentGateway.interpret
  ↓
AgentIntent
  ↓
ActionPolicyValidator
  ↓
Training Engine
  ↓
DecisionRecord
  ↓
AgentGateway.explain OR local template
```

## Primeras intents

1. time constraint;
2. equipment occupied/missing;
3. request swap;
4. fatigue;
5. ask why;
6. goal/phase change.

No comenzar por un “general purpose chat”.

## Security

- no provider key in client;
- minimize context;
- validate schema;
- timeout;
- bounded retries;
- malformed output = no mutation.

## Gate

Desconectar backend y verificar que workout core sigue funcionando.

---

# 17. Fase 14 — Education

## Objetivo
Que la app cambie según experiencia.

## Implementar

- CoachingDetailLevel;
- contextual cards;
- progressive RIR disclosure;
- “Why?”;
- advanced mode.

## Regla

No usar expertise gamificado como autoridad. Usuario controla detail level.

---

# 18. Fase 15 — V1 release hardening

## Checklist

### Functional
- onboarding;
- block;
- Today;
- time adjustment;
- offline tracking;
- occupied/missing;
- substitution;
- progression;
- PR;
- recovery;
- restriction;
- HealthKit;
- Watch;
- agent explanation.

### Security/privacy
- HealthKit permission audit;
- no secrets;
- log audit;
- delete/export paths;
- privacy copy reviewed.

### Accessibility
- VoiceOver;
- Dynamic Type;
- Reduce Motion;
- contrast;
- Watch touch targets.

### Reliability
- force quit active workout;
- airplane mode;
- Watch disconnect;
- Health authorization denied;
- agent backend timeout;
- SwiftData migration test.

### Performance
- launch;
- exercise search;
- set completion;
- Today load;
- Watch workout battery sanity.

## Release gate

No P0 bug conocido que pueda:

- perder workout data;
- duplicar workout/energy;
- ignorar restriction;
- recomendar invalid load;
- romper active workout state.

---

# 19. Fase 16 — Bodybuilding V2

## Orden

1. BodybuildingPhase.
2. muscle specialization.
3. volume redistribution.
4. body measurements.
5. posing.
6. progress photos.
7. competition timeline.
8. self-knowledge insights.

## Mantener fuera

- medical contest prep;
- drug protocols;
- dangerous dehydration/electrolyte advice.

---

# 20. Arquitectura de testing

## Pirámide

```text
          UI / Device E2E
             few
        ─────────────
       Integration tests
          targeted
    ───────────────────
      Domain/Engine tests
          extensive
```

## Domain tests
Swift Testing, deterministic fixtures.

## Persistence
In-memory SwiftData integration.

## HealthKit
Protocol fakes para automation + physical-device smoke validation.

## Agent
Recorded JSON fixtures; ningún unit test depende de una API LLM real.

## UI
XCUITest sólo flujos críticos, no cada detalle visual.

---

# 21. Branch/commit strategy recomendada

Branches cortas:

```text
feat/PR-0802-hard-time-optimizer
fix/PR-1105-energy-reconciliation
```

Commits enfocados:

```text
feat(training): add hard time session optimizer

test(training): cover priority preservation under 30m constraint
```

No mezclar refactor masivo con feature salvo necesidad demostrable.

---

# 22. ADRs requeridos

Crear Architecture Decision Record cuando cambie:

- persistence technology;
- module boundaries;
- deployment target;
- HealthKit strategy;
- sync conflict policy;
- LLM provider/backend contract;
- analytics/telemetry;
- photo storage/privacy.

ADR mínimo:

```text
Context
Decision
Alternatives
Consequences
Rollback
```

### ADRs registrados

- **`ADR-0001`** (PR-0202): SwiftData y la capa de persistencia local → almacén
  Codable/JSON de escritura atómica en PRCore. Los `@Model` de SwiftData no pueden
  vivir en una librería SPM compartida (SIGTRAP); SwiftData queda reservado a la
  capa de app. Ubicación: `PR-agentic-fitness-spec/docs/adr/ADR-0001-*.md`.
- **`ADR-0002`** (PR-0301): seed del catálogo de ejercicios — dataset
  *free-exercise-db* (Unlicense) + mapeo determinista a la ontología `Exercise`
  de PRDomain. Ubicación: `PR-agentic-fitness-spec/docs/adr/ADR-0002-*.md`.

---

# 23. Riesgos principales y mitigaciones

## Riesgo A — IA impredecible
Mitigación: LLM interpret/explain only + validator + deterministic engine.

## Riesgo B — Science-based se vuelve hardcode frágil
Mitigación: Evidence Registry versionado.

## Riesgo C — Demasiada complejidad UX
Mitigación: progressive disclosure + Today minimal + advanced controls opt-in.

## Riesgo D — HealthKit doble conteo
Mitigación: canonical workout + reconciliation tests.

## Riesgo E — Watch state conflicts
Mitigación: idempotent IDs, clear ownership, recovery tests.

## Riesgo F — Substitution mala
Mitigación: rich ontology + safety gate + role/pattern scoring.

## Riesgo G — “recovery score” falso
Mitigación: categorical decisions + explainable facts.

## Riesgo H — lesiones convierten app en producto médico
Mitigación: restrictions not diagnosis; conservative messaging; professional guidance capture only.

## Riesgo I — overengineering
Mitigación: one PRCore package first; split only with measured reason.

## Riesgo J — no data for personalization
Mitigación: defaults science-based; confidence attached to learned insights.

---

# 24. Secuencia recomendada de los primeros 20 PRs

1. PR-0001 project structure.
2. PR-0101 identifiers/value objects.
3. PR-0102 exercise domain.
4. PR-0103 training domain.
5. PR-0104 user profile.
6. PR-0105 gym domain.
7. PR-0106 restrictions domain.
8. PR-0201 repositories.
9. PR-0202 SwiftData.
10. PR-0301 exercise seed.
11. PR-0303 evidence registry.
12. PR-0501 split selector.
13. PR-0502 volume allocator.
14. PR-0503 exercise assignment.
15. PR-0701 ordering.
16. PR-0504 block generation.
17. PR-0401 Sign in with Apple.
18. PR-0402 onboarding.
19. PR-0601 Today.
20. PR-0602 active workout state machine.

Después seguir backlog por dependencies.

### Estado PR-0001 (Bootstrap)

Implementado y verificado:

- **Targets:** `PR` (iOS) y `PRWatch` (watchOS companion) en `PR.xcodeproj` (filesystem-synchronized groups).
- **Core local:** paquete Swift `Packages/PRCore` con productos `PRCore` y `PRDomain` (platforms iOS 18 / watchOS 11 / macOS 15), Swift tools 6.0.
- **Dominio inicial en `PRDomain`:** identificadores tipados (`ExerciseID`, `TrainingBlockID`, `WorkoutID`, `SetRecordID`, `GymID`, `RestrictionID`, `DecisionID`, `EvidenceRuleID`), `LoadAndTime` (`Load`, `LoadUnit`, `TimeConstraint`, `DomainValidationError`) y `UserProfile` (`ExperienceLevel`, `TrainingGoal`, `BodyCompositionPhase`, `VarietyPreference`, `CoachingDetailLevel`, `PriorityTier`, `UserTrainingProfile`).
- **Strict Concurrency:** `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Composition root:** `AppEnvironment` (`@MainActor`, `@Observable`) inyectado al entorno de contenido. `PRApp.swift` y `PRWatchApp.swift` sin lógica de negocio.
- **Compilación:** iOS Debug `BUILD SUCCEEDED`. watchOS definido pero **no compilable en este entorno** por ausencia del runtime watchOS (solo iOS 26.5 instalado).
- **Tests `PRCore`:** 12 tests Swift Testing, todos verdes (`swift test`).
- **Schemes:** `xcodebuild -list` documenta `PR`, `PRWatch`, `PRCore`, `PRDomain`.

**Fix de build:** los `.md`/spec dentro de la carpeta sincronizada `PR/` se excluyen del target vía `PBXFileSystemSynchronizedBuildFileExceptionSet` para evitar el error "Multiple commands produce".

### Estado PR-0002 (CI local reproducible)

DONE. `scripts/ci.sh` + `Makefile` (root). Pipeline reproducible de build + unit tests:
resuelve el root relativo al script (sin rutas absolutas de dev), con `set -euo pipefail`
y fallo fail-fast (exit != 0 ante cualquier gate roto). Gates: (1) guard del pbxproj
(`scripts/check_pbxproj_exception.sh`), (2) `swift build` de PRCore, (3) `swift test`
de PRCore, (4) build del scheme `PR` con el primer destination de iOS Simulator
detectado (si no hay destination se omite, el core ya quedó validado). La salida de
cada fase se vierte a `.ci/<fase>.log` (ignorado vía `.gitignore`) para que el exit
code del gate sea fiable (issue: `swift test` a `/dev/null` devuelve no-cero falsamente).
`Makefile`: `make ci` (todo), `make test`, `make test-ios`, `make guards`. README
documenta ejecución (§CI local reproducible). Verificado: `make ci` → exit 0 con los 4
gates verdes (584 tests / 103 suites, iOS scheme build OK) y gate fallido → exit 1.

### Estado PR-0003 (Logging seguro)

DONE. `Packages/PRCore/Sources/PRCore/SafeLogging.swift` + `SafeLoggingTests.swift`: wrapper
`Sendable` sobre `os.Logger` (`PRLogger`) con categorías tipadas `LogCategory`
(app, workout, health, sync, agent, persistence) y `subsystem` por defecto; `LogLevel`
(debug/info/notice/error/fault) mapeado a los métodos de `Logger`. La redacción es un
`LogRedactor` puro (formateo propio, testeable sin el unified logging system): NUNCA
loguea notas de lesión/dolor, ids de sample de salud (UUID), tokens (`Bearer`/`sk-`/`tok_`/
JWT sensibles) ni Apple identifiers (`userIdentifier`); los valores se interpolan con
privacidad por defecto del sistema (nunca `.public`). Tests (10) en `SafeLoggingTests.swift`
(PRCore): seis categorías, logger por categoría, nota de lesión redactada, entrada de
dolor/lesión oculta por clave, sample de salud redactado, tokens por prefijo, JWT explícito
reemplazado, Apple identifier redactado, clave token/secret oculta entera, y datos no
sensibles conservados. Verificado con `swift test --filter SafeLoggingTests`: 10/10 verdes.

### Estado PR-0101 (Core identifiers y value objects)

DONE. Implementado en `Packages/PRCore/Sources/PRDomain/`:

- `Identifiers.swift`: `ExerciseID`, `TrainingBlockID`, `WorkoutID`, `SetRecordID`, `GymID`, `RestrictionID`, `DecisionID`, `EvidenceRuleID` — tipados, `Codable`/`Hashable`/`Sendable`/`Identifiable`.
- `LoadAndTime.swift`: `LoadUnit` (kg/lb), `Load` (rechaza negativos y NaN), `TimeConstraint` (rechaza minutos/tolerancia negativos).
- 15 tests Swift Testing verdes (`swift test`): round trip Codable, equality/hash, invalid load/time boundaries.
- iOS Debug build sigue verde con el paquete vinculado.

### Estado PR-0102 (Exercise knowledge domain)

DONE. Implementado en `Packages/PRCore/Sources/PRDomain/Exercise.swift`:

- `Exercise` (biomecánica + función programática), `ExerciseFamily` (+`substitutionFamilyID`), `MovementPattern` (22 casos del spec), `ExerciseRole`, `EquipmentType` (distingue DB/Smith/machine), `MovementAngle`, `Laterality`, `JointClass`, `DemandLevel`, `FatigueCost`, `Loadability`, `RestrictionTag`, `MuscleGroup`, `MuscleContribution`.
- Musculatura modelada vía `primaryMuscles`/`secondaryMuscles` estructurados (sin `muscle: String`); un ejercicio admite varios músculos secundarios.
- 23 tests Swift Testing verdes (`swift test`): fixtures press/pull/squat/isolation, encode/decode, family validation, validación de valores.
- iOS Debug build verde con el paquete vinculado.

### Estado PR-0103 (Training block/session/set domain)

DONE. Implementado en `Packages/PRCore/Sources/PRDomain/Training.swift`:

- Separación plan/ejecución: `SessionTemplate` vs `WorkoutSessionRecord`; `SetPrescription` vs `SetRecord` distintos; `PlannedSet`.
- Lifecycle validado: `WorkoutLifecycleState` (7 estados) y `SetLifecycleState` (5 estados) con transiciones rechazadas en dominio.
- Validación: no reps negativas/cero, no weight negativo, rangos de reps/descanso válidos, RIR/target load no negativos. Warmup vía `isWarmup`.
- Feedback: `DifficultyFeedback`, `PainFeedback` (severidad 1...5).
- 37 tests Swift Testing verdes (`swift test`): lifecycle transitions, invalid sets, planned vs performed integrity.
- iOS Debug build verde con el paquete vinculado.

### Estado PR-0104 (User training profile)

DONE. En `Packages/PRCore/Sources/PRDomain/UserProfile.swift`:

- Enums existentes (`ExperienceLevel`, `TrainingGoal`, `BodyCompositionPhase`, `VarietyPreference`, `CoachingDetailLevel`, `PriorityTier`) + `MusclePriority` (spec §3.4) + schedule/time preferences: `WeekDay`, `PreferredDayTime` (ventana validada 0...1439 / duración > 0), `SchedulePreference` (días 2...7, minutos 20...240).
- Goal y phase independientes; cambiar goal no afecta phase ni borra historial.
- 45 tests Swift Testing verdes (`swift test`).
- iOS Debug build verde con el paquete vinculado.

### Estado PR-0105 (Gym, machine y equipment domain)

DONE. `Packages/PRCore/Sources/PRDomain/Gym.swift`:

- `GymProfile` (spec §6.4), `MachineProfile` (spec §6.5) + `MachineProfileID`/`loadHistoryKey` (exercise + instancia).
- `EquipmentAvailabilityState`: `doesNotExist`/`occupied`/`unknown`/`available` (spec §6.4); `EquipmentAvailability`; `BusyPattern`/`BusyLevel`.
- `occupied` session-scoped: `occupiedDuringSession` + `endingSession()`; no se persiste.
- 51 tests Swift Testing verdes (`swift test`).
- iOS Debug build verde con el paquete vinculado.

### Estado PR-0106 (Restrictions domain)

DONE. `Packages/PRCore/Sources/PRDomain/Restriction.swift`:

- `TrainingRestriction` (spec §16.1) con `BodyRegion`, `BodySide`, `RestrictionSource`, `reviewDate`, `forbiddenPatterns`, `forbiddenExerciseIDs`, `allowedExerciseIDs`, `restrictionTags`.
- `RestrictionStatus` (active/reviewNeeded/resolved) con transiciones validadas; `refreshed(asOf:)` pasa a `reviewNeeded` al pasar el `reviewDate` (no autoelimina); resolución por acción explícita.
- 58 tests Swift Testing verdes (`swift test`).
- iOS Debug build verde con el paquete vinculado.

### Estado PR-0201 (Repository protocols)

DONE. `Packages/PRCore/Sources/PRCore/PersistenceContracts.swift`:

- `ExerciseRepository`, `TrainingBlockRepository`, `WorkoutRepository`, `GymRepository`, `RestrictionRepository`, `DecisionRepository`, `UserProfileRepository` — async, `Sendable`.
- `PRCore` no importa SwiftData; los contratos son la frontera de persistencia.
- Tests con fakes in-memory (`Tests/PRCoreTests/InMemoryRepositories.swift`).

### Estado PR-0202 (Local persistence adapters)

DONE. Persistencia local offline-first detrás de los protocolos `Repository`.

> **Decisión tecnológica (ver `ADR-0001`):** los `@Model` de SwiftData **no pueden
> vivir en un target de librería SPM compartido** — el runtime de SwiftData aborta
> con SIGTRAP al ejercitar el modelo (reproducido y documentado). PRCore es un
> paquete compartido por iOS + watchOS y se valida vía `swift test`; por tanto PR-0202
> se implementa con un **almacén Codable/JSON de escritura atómica** en lugar de
> SwiftData. SwiftData queda reservado para la capa de app si un día se desea (con
> sus `@Model` en el target ejecutable de la app).

- `Sources/PRCore/RepositoryStore.swift`: protocolo `RepositoryStore` + `MemoryRepositoryStore` (tests) + `AtomicFileRepositoryStore` (archivos JSON, escritura temp + rename).
- `Sources/PRCore/CodableRepositories.swift`: `FileExerciseRepository`, `FileTrainingBlockRepository`, `FileWorkoutRepository`, `FileGymRepository`, `FileRestrictionRepository`, `FileDecisionRepository`, `FileUserProfileRepository`.
- Cada agregado se persiste como blob JSON tras su clave tipada (`id.rawValue.persistenceKey`); el save local es inmediato y autoritativo (un fallo de sync jamás lo revierte). Al confirmar un set se persiste la sesión completa (incluye sus sets) de forma atómica.
- Perfil único bajo clave fija: el save reemplaza, nunca duplica.
- Tests de integración (`Tests/PRCoreTests/CodableRepositoriesTests.swift`): round-trip por entidad, relaciones (sets dentro de sesión), delete policies, perfil único, persistencia atómica a disco.
- Suite global verde: **82 tests / 33 suites** (`swift test`); iOS Debug build verde; watchOS no compilable en este entorno (runtime no instalado, como en PR-0001).

### Estado PR-0203 (Pending operation queue)

DONE. Cola de operaciones pendientes offline-first con idempotencia.

- `Sources/PRDomain/PendingOperations.swift`: `PendingOperation` (idempotencyKey, kind, payload, createdAt) + `PendingOperationQueue` (dedup por key e id, orden por createdAt, filtro por kind, Codable). El dedupe lo decide el **dominio** (arquitectura determinista), no el LLM.
- `Sources/PRCore/PendingOperationStore.swift`: `PendingOperationQueueStore` (persistencia atómica sobre `RepositoryStore`) + `SetPersistenceGuard` — `enqueueSetSave` (idempotencyKey = `set.id.rawValue.persistenceKey`) y `drainSetOperations` (re-aplica sets pendientes de forma idempotente y los retira de la cola; si la sesión aún no existe, conserva la operación para reintentar).
- Garantiza el invariante *"retry no duplica SetRecord"* y que la app siga funcionando aunque el backend esté apagado (PR-0203 AC).
- Tests: `Tests/PRDomainTests/PendingOperationTests.swift` + `Tests/PRCoreTests/PendingOperationStoreTests.swift` (14 tests: dedup por key e id, orden, Codable round-trip, drain idempotente, no pérdida cuando falta la sesión).
- Suite global verde: **551 tests / 101 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0204 (Data export)

DONE. Export de datos portable y determinista (RF-030, RNEG-006).

- `Sources/PRDomain/DataExport.swift`: `ExportEngine` + `ExportBundle` (JSON completo:
  bloques, sesiones+sets, ejercicios, gyms, restricciones, perfil; versionado, orden
  determinista, ISO-8601) + `workoutSetsCSV` (CSV mínimo, una fila por set, 10 columnas,
  quoting RFC-4180). Política de secrets explícita (`ForbiddenExportFields`) y guardia
  `containsForbiddenSecretFields` que impide exportar campos con nombres de secrets.
- `Sources/PRCore/DataExportCoordinator.swift`: caso de uso que compone los artefactos
  y lanza `DataExportError.secretDetected` ante cualquier campo sospechoso.
- `PR/App/ExportView.swift`: pantalla user-controlled con `ShareLink` (JSON completo /
  CSV de sets), alimentada vía `AppRootView`.
- Tests: `Tests/PRDomainTests/DataExportTests.swift` (7 tests: JSON completo+determinista,
  sin secrets, guardia detecta field inyectado, CSV cabecera+filas+orden, columnas estables,
  vacío, rir/pain).
- Suite global verde: **597 tests / 105 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0301 (Exercise catalog seed)

DONE. Catálogo inicial versionado con import idempotente.

- **Fuente:** dataset público *free-exercise-db* (`exercises.json`, repo `yuhonas/free-exercise-db`), licencia **Unlicense (public domain)**.
- **Subset curado:** 678 ejercicios (categorías `strength`, `powerlifting`, `olympic weightlifting`, `strongman`), incrustado como resource del paquete (`Packages/PRCore/Sources/PRCore/Resources/exercises.json`).
- `Sources/PRCore/ExerciseCatalog.swift`: DTO del dataset + `ExerciseCatalogLoader` (bundle y JSON crudo) + `ExerciseInflector` (reglas deterministas de mapeo a la ontología `Exercise`) + `ExerciseCatalogSeeder` (import idempotente a `ExerciseRepository`).
- **IDs deterministas:** hash SHA-256(namespace+slug) → UUID estable; **una familia por patrón de movimiento** con ID también determinista. Re-importar no duplica (criterio PR-0301).
- Decisiones de mapeo (equipment, músculos, jointClass, fatiga, loadability, roles, ángulo, laterality) centralizadas y versionadas; ver `ADR-0002`.
- Tests (`Tests/PRCoreTests/ExerciseCatalogTests.swift`): carga del bundle, determinismo (mismo dataset → mismos IDs), cobertura de los 18 patrones MVP con ≥1 ejercicio, well-formedness, idempotencia del seeder.
- Suite global verde: **93 tests / 37 suites** (`swift test`); iOS Debug build verde (resource incluido).

### Estado PR-0303 (Evidence Registry)

DONE. `Packages/PRCore/Sources/PRDomain/Evidence.swift` (promptMaster §22):

- **`EvidenceRule` versionada**: id, name, `EvidenceCategory`, `EvidenceConfidence`, `version` (≥1), `parameters: [String: Double]` (rechaza non-finite), `references` y `active`.
- **`EvidenceRegistry`**: registro centralizado de reglas — source única de parámetros ajustables (sin constantes dispersas). Registrar un cambio exige incrementar versión (`ruleVersionNotAdvanced`); `deactivate` excluye reglas de parámetros/referencias; listado en orden estable de id.
- **`EvidenceRuleReference`** (id + versión): `DecisionRecord` guarda la referencia de la regla usada, de modo que un cambio de regla no re escribe el pasado (auditable, §22.2). Sin cambios se mantiene `ruleIDs` como view conveniente.
- Tipos de apoyo: `EvidenceCategory` (volume/progression/recovery/ordering/rest/safety), `EvidenceConfidence` (established/emerging/expertConsensus/anecdotal), `EvidenceReference` (título + fuente/año/URL).
- Tests (`Tests/PRDomainTests/EvidenceTests.swift`): codable round-trip, validación de versión/parámetros, centralización de parámetros, rechazo de cambio sin bump, bump aceptado, deactivate, orden estable, y referencia versionada persistida en `DecisionRecord`.
- Suite global verde: **109 tests / 41 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0302 (Exercise search)

DONE. Búsqueda offline del catálogo (`Packages/PRCore/Sources/PRDomain/ExerciseSearch.swift`):

- **`ExerciseSearchEngine`**: índice value-type puro y determinista (sin IO). Normaliza nombre/aliases (minúsculas + diacríticos, locale fijo) y tokeniza; mismas entradas → mismo orden de resultados.
- **`ExerciseSearchQuery`**: filtros AND por `text`, `equipment`, `movementPatterns` y `muscleGroups`; sin filtros se listan todos ordenados por nombre.
- **Relevancia de texto** (score): nombre canónico exacto > prefijo > subconjunto de tokens > subcadena; aliases similares con menor peso. Con texto, sólo entran matches con score > 0; sin texto los filtros devuelven todos los que cumplen.
- **`ExerciseSearchHit`** (exercise + textScore): resultados ordenados por score descendente y luego nombre.
- Tests de comportamiento (`Tests/PRDomainTests/ExerciseSearchTests.swift`): matching por nombre/alias, tokens desordenados, case/diacritic insensitivo, filtros por equipment/patrón/músculos, combinación AND, determinismo y orden por relevancia.
- Test de rendimiento sobre el catálogo real (`Tests/PRCoreTests/ExerciseSearchPerfTests.swift`): **<100 ms** sobre los 678 ejercicios del bundle (cumple criterio PR-0302).
- Suite global verde: **125 tests / 45 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0401 (Sign in with Apple)

DONE. `Packages/PRCore/Sources/PRCore/AuthTypes.swift` + `AppleIDAuthCoordinator.swift` y la
implementación de producción `PR/App/Auth/SignInWithAppleProvider.swift`. AuthenticationServices
queda detrás de `AppleIDAuthProviding` (protocolo): el coordinador (`AppleIDAuthCoordinator`,
`@Observable`) es testeable con fake y no importa HealthKit ni AuthenticationServices (RF-001). El
provider real (capa app) usa `ASAuthorizationController` y sólo conserva el `user` opaco; el
credential token/email NO se persisten (RF-0401). Maneja success/cancel/failure: cancel vuelve a
`idle` sin alerta; primer login crea `LocalUserProfile` con `isFirstLogin`. Tests
(`Packages/PRCore/Tests/PRCoreTests/AuthCoordinatorTests.swift`, 8): success crea perfil, transición
UI a `signedIn`, cancel→idle, failure expone mensaje sin perfil, identificador vacío→error, no se
persiste token sensible, reset conserva perfil, signOut descarta perfil. Verificado con `swift test
--filter AuthCoordinatorTests`: 8/8 verdes.

### Estado PR-0402 (Onboarding profile flow)

DONE. `Packages/PRCore/Sources/PRDomain/Onboarding.swift` (dominio) +
`Packages/PRCore/Sources/PRCore/OnboardingCoordinator.swift` (app-core wiring) + vistas
`PR/App/Onboarding/*.swift`. Todas las reglas viven en el dominio:
`OnboardingProfileBuilder.build` valida **2...7 días/semana y 20...240 min/sesión**
(Onboarding.swift:162-163) y construye `OnboardingProfile` con goal, phase, experience,
daysPerWeek, sessionMinutes, variety, gym opcional (defaultGymID) y restrictions
opcionales. `OnboardingFlowController` conserva el borrador al `goBack()` (respuestas
no se pierden). `OnboardingCoordinator` es app-core sin reglas: delega en los engines y
expone `phase` observable; las vistas son renderizadores puros sin lógica de validación.
Tests (22): 11 en `OnboardingTests.swift` (PRDomain) — perfil completo, días/minutos
fuera de rango lanzan, boundaries aceptados (2/7, 20/240), paso requerido faltante,
gym/restricciones opcionales propagan, back preserva respuestas, avance bloqueado sin
respuesta, pasos opcionales avanzan sin responder, faltan pasos ⇒ error, límites
respetados; 11 en `OnboardingCoordinatorTests.swift` (PRCore) — auth-gate, navegación,
goBack preserva, complete construye, complete no inventa respuestas, no requiere
HealthKit. Verificado con `swift test --filter Onboarding`: 22 tests verdes en 2 suites.

### Estado PR-0403 (Coaching detail initial mapping)

DONE. `Packages/PRCore/Sources/PRDomain/CoachingDetail.swift` + `CoachingDetailTests.swift`:
`CoachingDetailMapper` (novice/beginner → guided, intermediate → balanced,
advanced/competitive → advanced, determinista) y `CoachingDetailPrefs` (nivel efectivo +
origen `defaultByExperience`/`manualOverride`; el override manual manda sobre el default
aunque coincida, y `resetting` vuelve al default). El usuario siempre puede cambiar
manualmente (PR-0403 AC). 10 tests verdes.

### Estado PR-0501 (Split selector)

DONE. `Packages/PRCore/Sources/PRDomain/SplitSelector.swift` (promptMaster §8.2):

- **`TrainingSplit`**: `fullBody` / `upperLower` / `pushPullLegs` (estructuras MVP del spec).
- **`SplitSelector`** determinista y explicable (nunca LLM):
  - 2–3 días → `fullBody`;
  - 4 días → `upperLower` (salvo bodybuilding avanzado en surplus → `pushPullLegs`);
  - 5 días → `pushPullLegs`;
  - 6–7 días → `pushPullLegs` por adherencia.
- **`SplitSelection`** (split + días + goal + experiencia + `SplitReason`) con `explanationFacts` (DecisionFact) para el "por qué". Valida días 2...7.
- Tests (`Tests/PRDomainTests/SplitSelectorTests.swift`): meses por días, caso especializado, matriz del plan (fixture A full body), determinismo y explicabilidad.
- Suite global verde: **135 tests / 47 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0502 (Volume allocator)

DONE. `Packages/PRCore/Sources/PRDomain/VolumeAllocator.swift` (plan §4B):

- **`VolumeConfig`**: regla de evidencia versionada (`EvidenceRule`) con rangos de
  sets semanales por tier (`maintain` 4–6, `normal` 8–12, `emphasize` 12–16,
  `specialize` 16–20). Centraliza constantes científicas (SKILL.md: no magic numbers).
- **`VolumeAllocator`** determinista: distribuye targets por músculo según
  `PriorityTier`; nunca genera volumen negativo; sin prioridades no inventa músculos.
- **`VolumeAllocation`** (`MuscleVolumeAssignment` por grupo con `priority` +
  `ruleReference`): reporta presupuesto global [min, max] y total.
- Tests (`Tests/PRDomainTests/VolumeAllocatorTests.swift`): orden de tiers,
  presupuesto agregado, determinismo, ausencia de negativo, referencia versionada
  y validación de `VolumeConfig` (params obligatorios).
- Suite global verde: **144 tests / 49 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0503 (Exercise assignment)

DONE. `Packages/PRCore/Sources/PRDomain/ExerciseAssignment.swift` (plan §4C):

- **`ExerciseAssigner`** determinista: asigna **anchors** (candidato más estable de
  la familia, para medir progreso) y **rotatables** (resto de la familia según
  variedad: stable 1, balanced 2, varied 3 — límite configurable; los anchors no
  rotan sólo por variedad).
- **Equipment**: con disponibilidad conocida excluye ejercicios no disponibles; si
  es `unknown` no descarta nada y la UI pregunta, no programa a ciegas.
- **Restricciones** (`TrainingRestriction`): excluye ejercicios con patrón o ID
  prohibido y respeta la lista explícitamente permitida; nunca programa ejercicios
  bloqueados.
- **`MuscleExerciseAssignment`** por grupo (`muscleGroupID` + `familyID` +
  `[AssignedExercise]` con `assignmentRole`).
- Tests (`Tests/PRDomainTests/ExerciseAssignmentTests.swift`): anchor/rotatable,
  exclusión por equipment conocido, política unknown, restricciones por patrón e ID,
  precedencia de lista permitida, número de rotatables por variedad, determinismo y
  error explícito sin candidatos.
- Suite global verde: **154 tests / 50 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0701 (Base ordering rules)

DONE. `Packages/PRCore/Sources/PRDomain/ExerciseOrder.swift` (plan §4D):

- **`ExerciseOrderEngine`** determinista: ordena los ejercicios de una sesión por
  score §9.3 — rol funcional (`primaryCompound` 100 > `secondaryCompound` 80 >
  `priorityIsolation` 70 > `accessoryIsolation` 50 > warmup/mobility > optional/
  conditioning/posing), bonus de prioridad muscular (specialize 60 / emphasize 45 /
  normal 20 / maintain 0) y bonus de demanda técnica (`skillDemand` high 30 /
  moderate 15). Determinista: empates resueltos por `canonicalName`.
- **`OrderedExercise`** (exercise + `orderScore` + `rank` 1...N); `order` lanza
  `ExerciseOrderError.emptyInput` con lista vacía.
- Tests (`Tests/PRDomainTests/ExerciseOrderTests.swift`): compuestos antes de
  aislados, técnica alta antes, priority isolation de músculo specialized antes que
  accessories, conditioning/posing al final, determinismo, ranks contiguos y error
  sin entrada.
- Suite global verde: **161 tests / 51 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0702 (Fatigue interference model)

DONE. `Packages/PRCore/Sources/PRDomain/FatigueInterference.swift` (plan §4D,
promptMaster §9.2):

- **`FatigueInterferenceEngine`** determinista: acumula la fatiga local de todos los
  ejercicios previos y penaliza cuando pre-fatigan musculatura que necesita un
  movimiento prioritario posterior (compound/anchor/priorityIsolation). Un superset
  compatible (solapamiento bajo) NO se penaliza. `reorder` minimiza la interferencia
  preservando la prioridad base: nunca mueve un movimiento prioritario después de uno
  menos prioritario.
- **`FatigueInterferenceConfig`**: regla de evidencia versionada (categoría
  `.ordering`) con `penaltyWeight`, `minOverlap` y `compatibleThreshold`; sin
  constantes dispersas, con `ruleReference()` auditable.
- **`InterferenceAssessment`** (`orderedExercises` + `penalties` + `totalPenalty` +
  `ruleReference`) y `InterferencePenalty` (`overFatiguedMuscles` + `penalty`).
- Tests (`Tests/PRDomainTests/FatigueInterferenceTests.swift`): penaliza pre-fatiga a
  prioridad, orden inverso sin penalización, superset compatible sin penalización,
  reorder preserva prioridad, configuración versionada/auditable, validación de
  parámetros y error con <2 ejercicios.
- Suite global verde: **170 tests / 52 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0504 (4–8 week block generation)

DONE. `Packages/PRCore/Sources/PRDomain/BlockPlanner.swift` (plan §4F):

- **`BlockPlanner`** orquesta de forma determinista el pipeline completo:
  `SplitSelector` (estructura por días/objetivo) → `VolumeAllocator` (sets
  semanales/músculo) → `ExerciseAssigner` (anchor/rotatables) →
  `ExerciseOrderEngine` + `FatigueInterferenceEngine` (orden de sesión) → produce
  un **`TrainingBlock`** persistible 4–8 semanas.
- **Determinista y explicable**: `BlockExplanation` con `[DecisionFact]` (goal,
  phase, weeks, split, days, músculos, volumen total) + referencias versionadas
  (`VolumeDefaults`, `ExerciseAssignmentDefaults`).
- **Rebuild sin borrar historial**: cada `plan` genera un bloque NUEVO (ID distinto);
  el planificador no muta ni borra bloques previos.
- **Validación**: semanas fuera de 4...8 y prioridades vacías (no inventa músculos)
  lanzan `BlockPlanningError`.
- Tests (`Tests/PRDomainTests/BlockPlannerTests.swift`): bloque completo persistible
  (Codable round-trip), rechazo de semanas/prioridades inválidas, explicabilidad,
  rebuild → ID nuevo sin borrar, determinismo y exclusión por restricciones.
- Suite global verde: **177 tests / 53 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0505 (Block transition)

DONE. `Packages/PRCore/Sources/PRDomain/BlockTransition.swift` + `BlockTransitionTests.swift`
(RF-033). `BlockTransitionEngine.transition(current:toGoal:phase:priorityMuscles:...)`:
cierra el bloque actual como copia inmutable (`closedBlock`, mismo ID, sessions e historial
intactos) y abre un `newBlock` con ID nuevo y goal/fase destino. Continuidad de ejercicio
"cuando conviene": `CatalogExercisePrimaryResolver` resuelve el músculo primario de cada
ejercicio; se conserva (carryover a las plantillas del nuevo bloque) si ese músculo sigue
siendo prioritario, y se descarta si deja de priorizarse. Números de weeks válidos 4...8;
bloque terminal ⇒ `BlockTransitionError.notTransitionable`. 6 tests verdes.
- Suite global verde: **603 tests / 106 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0601 (Today screen)

DONE. `Packages/PRCore/Sources/PRDomain/TodayScreen.swift` (driver determinista puro) +
`Packages/PRCore/Sources/PRCore/TodayPlanCoordinator.swift` (cablea un plan REAL generado:
`BlockPlanner` → block → rotación semanal determinista a la template de hoy → duración
estimada) + vista `PR/App/TodayView.swift` (un CTA principal por estado, ≤2 acciones
"Empezar/Continuar"). Muestra sesión, duración estimada y CTA; funciona offline (sin red)
y distingue estado de descanso/sin-entrenamiento (`restDay` / `readyToStart` / `activeWorkout`).
Nunca inventa duración. Tests (14): `TodayScreenTests.swift` (10) —
`restDayWithoutTemplate`, `trainingDayYieldsReadyToStart`, `restDayYieldsRestDay`,
`activeWorkoutShowsResume`, `emptyTemplateIsRestDay`, determinismo/offline; y
`TodayPlanCoordinatorTests.swift` (4) — plan real generado. Verificado con `swift test
--filter Today`: 14/14 verdes.

### Estado PR-0602 (Active workout state machine)

DONE. `Packages/PRCore/Sources/PRDomain/ActiveWorkout.swift` (plan §8):

- **`ActiveWorkoutController`** gestiona el ciclo de vida de un entrenamiento activo:
  `start(from:)` abre un workout nuevo y rechaza sobrescribir uno activo;
  `pause`/`resume`/`finish`/`complete`/`abandon` validan cada transición contra la
  tabla de `WorkoutLifecycleState`, lanzando `ActiveWorkoutError.invalidTransition`
  ante movimientos inválidos (`finish` → `.finishing`, `complete` → `.completed`).
- **Sin mutar historial**: abandonar no borra los sets ya realizados; el registro de
  lo realizado permanece intacto.
- **Kill/relaunch**: `snapshot()` produce un `ActiveWorkoutSnapshot` persistible
  (Codable) y `restore(from:)` lo recupera; los snapshots en estado terminal
  (`.completed`/`.abandoned`) no son restaurables (`ActiveWorkoutError.notRestorable`).
- Tests (`Tests/PRDomainTests/ActiveWorkoutTests.swift`): start/start-duplicado,
  pause+resume, finish→complete, abandon preserva sets, snapshot sin activo, restore,
  no-restaurable de terminal, Codable round-trip.
- Suite global verde: **187 tests / 54 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0603 (One-tap set completion)

DONE. `Packages/PRCore/Sources/PRDomain/SetCompleter.swift` (plan §8):

- **`SetCompleter`** con `SetCompletionDraft`/`SetCompletionInput`: precarga target
  weight/reps desde la prescripción (`targetLoad`) o, si no hay, desde el último peso
  realizado del ejercicio; reps desde el rango inferior.
- **Un tap si coincide**: `oneTap` registra el set sólo si el input coincide
  exactamente (`SetCompletionDraft.matches`); si difiere devuelve `nil` para ofrecer
  edición sin forzar registro erróneo.
- **Edición accesible**: `recordSet` valida peso≥0 y reps≥1 y registra un working set
  `.completed`. Ambas persisten el set (`session.performedSet`) ANTES de cualquier
  transición UI, append-only sin mutar historial ni plan.
- Tests (`Tests/PRDomainTests/SetCompleterTests.swift`): preload desde targetLoad/
  último realizado/placeholder, one-tap match, one-tap mismatch → nil, matching exacto
  de unidad/reps, recordSet editable, validación de peso/reps, append-only.
- Suite global verde: **196 tests / 55 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0604 (Rest timer)

DONE. `Packages/PRCore/Sources/PRDomain/RestTimer.swift` (plan §8, RF-008):

- **`RestTimer`/`RestTimerState`**: inicia automáticamente el descanso tras completar
  un working set con la duración recomendada desde `SetPrescription.restSeconds`
  (`autoStart(afterCompletedWarmup:prescription:)`); los warmups NO inician descanso.
- **Skip/extend**: `skip` cancela el descanso; `extend(by:)` prolonga `endDate` (no-op
  si está inactivo o duración no positiva).
- **No bloquea**: el timer es un valor con `endDate` anclado en wall-clock; la UI
  consulta `remaining(at:)`/`hasElapsed(at:)` contra `Date()`, por lo que sobrevive
  background/relaunch sin ticks en memoria.
- Tests (`Tests/PRDomainTests/RestTimerTests.swift`): auto-start tras working set, no
  tras warmup, remaining wall-clock tras relaunch, elapsed flag, skip, extend activo/
  idle, extend no-positiva, inactivo → 0.
- Suite global verde: **204 tests / 56 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0605 (Workout completion summary)

DONE. `Packages/PRCore/Sources/PRDomain/WorkoutSummary.swift` (plan §8):

- **`WorkoutSummaryBuilder`** (con `WorkoutSummary`/`PersonalRecord`/
  `SummaryNextAction`/`PersonalRecordDetector`) agrega una sesión determinista:
  duration (`endedAt - startedAt`), working sets (`.completed`), volume (Σ weight×reps
  de completados; skipped/planned no cuentan), PRs y next action (.inProgress/
  .readyToFinish/.completed según lifecycle).
- **PR detector**: `PersonalRecordDetector` compara cada set completado contra un
  baseline histórico de peso por ejercicio; nunca inventa un récord sin referencia.
- **Energy (RN-008)**: sólo se propaga si llega reconciliada de una fuente externa y
  es finita/≥0; nunca se computa ni se inventa aquí → no doble contabilización.
- Tests (`Tests/PRDomainTests/WorkoutSummaryTests.swift`): basics (duration/working
  sets/volume), ignores skipped, inProgress/readyToFinish action, PR con baseline,
  no inventa PR sin baseline, energy reconciliada/sin inventar, Codable.
- Suite global verde: **212 tests / 57 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0801 (Duration estimator)

DONE. `Packages/PRCore/Sources/PRDomain/DurationEstimator.swift` (plan §8, RF-006):

- **`DurationEstimator`** (con `DurationDefaults`/`ExerciseDurationProfile`) estima la
  duración de una sesión determinista desde defaults por set/rest/transición, con
  override por ejercicio (`perExerciseSeconds`) y multiplicador de calentamiento.
- **Perfil personal EWMA**: `averageSeconds` + `sampleCount` + `confidence`
  (logística `n/(n+k)`). `record(observation:current:)` se actualiza con workouts
  completados; `shouldPreferPersonal` favorece el tiempo personal sobre el default
  cuando la confianza es suficiente (`>= personalThreshold`).
- Tests (`Tests/PRDomainTests/DurationEstimatorTests.swift`): suma de componentes
  (set+rest+transición), warmup más rápido, preferencia personal con confianza,
  defaults con poca confianza, override por ejercicio, crecimiento de confianza,
  EWMA/record, convergencia a la media.
- Suite global verde: **220 tests / 58 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0802 (Hard time optimizer)

DONE. `Packages/PRCore/Sources/PRDomain/HardTimeOptimizer.swift` (plan §8, RF-006):

- **`HardTimeOptimizer`** (con `SessionItem`/`CompatibleSuperset`/`TimeOptimizerResult`)
  recorta una sesión a un límite duro determinista: preserva anchors (`role == .anchor`)
  y prioridades (`isPriorityMuscle`), elimina opcionales primero, reduce accesorios
  (set-count a la mitad antes de descartar) y ofrece supersets sólo si los grupos
  musculares son disjuntos (`CompatibleSuperset` devuelve nil ante solape) → nunca
  agrega supersets incompatibles.
- **Tolerancia documentada**: `withinLimit = estimated <= limit + tolerance`; `notes`
  explica lo eliminado/reducido y cuándo el límite no es alcanzable aun conservando
  todos los anchors/prioridades.
- Tests (`Tests/PRDomainTests/HardTimeOptimizerTests.swift`): dentro del límite sin
  cambios, preserva anchors/prioridades, elimina opcionales primero, reduce antes de
  descartar, nunca superset incompatible, sólo compatibles, best-effort cuando es
  imposible, tolerancia documentada.
- Suite global verde: **228 tests / 59 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0803 (Flexible time optimizer)

DONE. `Packages/PRCore/Sources/PRDomain/FlexibleTimeOptimizer.swift` (plan §8, RF-006):

- **`FlexibleTimeOptimizer`** (con `FlexibleTimeResult`/`FlexibleStatus`) ajusta una
  sesión a una ventana `target ± tolerance`: si ya cabe (`inWindow`) no recorta; si la
  excede, reusa `HardTimeOptimizer` para recortar SÓLO lo necesario y entrar por el
  borde superior (nunca recorta de más).
- **under**: por debajo del umbral NO añade volumen (invariante; extra-time en
  PR-0804) y lo explica.
- **Explica no-factible**: `notFeasible` cuando sobrepasa el límite aun conservando
  todos los anchors/prioridades, o cuando la ventana es demasiado estrecha para la
  granularidad de los sets.
- Tests (`Tests/PRDomainTests/FlexibleTimeOptimizerTests.swift`): ya-en-ventana,
  recorte justo para entrar, under sin añadir volumen, no-factible sobre el límite,
  ventana estrecha, preserva anchors al recortar.
- Suite global verde: **234 tests / 60 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0804 (Extra time behavior)

DONE. `Packages/PRCore/Sources/PRDomain/ExtraTimeBehavior.swift` (plan §8):

- **`ExtraTimeBehavior`** (con `ExtraTimePlan`/`ExtraTimeActivity`) decide el uso del
  tiempo extra: NUNCA multiplica el volumen de trabajo automáticamente (plan §388: no
  añadir volumen sin límites) — a lo sumo rellena con actividades de extensión dentro
  del tiempo disponible, sin excederlo.
- **Opcionales separados**: `optionalsAreSeparate = true` (se presentan fuera del plan
  núcleo).
- **Sólo si corresponden**: `mobility` siempre; `cardio` vía `cardioApplies(goal:
 phase:)` (generalHealth/recomposition/powerbuilding, o déficit); `posing` sólo para
  `bodybuilding`. Explica el sobrante sin añadir más volumen cuando no corresponde
  ninguna actividad.
- Tests (`Tests/PRDomainTests/ExtraTimeBehaviorTests.swift`): no multiplica volumen con
  180 min, opcionales separados, mobility siempre, cardioApplies por objetivo/fase,
  cardio/posing gated en bodybuilding, nunca excede el tiempo, explica sobrante.
- Suite global verde: **241 tests / 61 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0901 (Gym profile)

DONE. `Packages/PRCore/Sources/PRDomain/GymProfileManager.swift` (plan §9, RF-011):

- **`GymProfileManager`** (con `GymProfileManagerError`/`persistentAvailabilityStates`):
  - **create/rename/select**: crea un gym vacío, lo renombra (nombre no vacío) y lo
    selecciona como activo (`activeGymID`);
  - **equipment unknown/available/missing**: `setAvailability(type,to:on:)` persiste
    sólo `.unknown`/`.available`/`.doesNotExist`; `.occupied` es session-scoped y se
    rechaza (se marca con `GymProfile.markingOccupied`);
  - **sin onboarding obligatorio**: el equipamiento no confirmado queda `.unknown`
    (progressive disclosure); `knownEquipmentTypes` sólo reporta lo confirmado.
- Tests (`Tests/PRDomainTests/GymProfileManagerTests.swift`): create vacío sin forzar
  equipo, rechazo de nombre vacío, rename, select activo, set available/doesNotExist/
  unknown, occupied rechazado + session-scoped, transiciones de disponibilidad.
- Suite global verde: **248 tests / 62 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0902 (Mark occupied)

DONE. `Packages/PRCore/Sources/PRDomain/OccupancyController.swift` (plan §9, RF-010):

- **`OccupancyController`** (con `OccupancyChange`/`OrderedEquipmentUse`) marca un
  equipo como ocupado durante la sesión activa:
  - **sólo sesión actual**: `GymProfile.occupiedDuringSession` (session-scoped); al
    finalizar (`endingSession`) vuelve al estado persistente del gym;
  - **dispara reorder**: `shouldReorder == true` si algún `OrderedEquipmentUse` del
    plan usa el equipo ocupado → el orden se reevalúa ANTES de sustituir (RF-010).
- Tests (`Tests/PRDomainTests/OccupancyControllerTests.swift`): marca ocupado, reorder
  cuando el plan usa el equipo, no-reorder si irrelevante, session-scoped + limpieza al
  finalizar, acumula varias ocupaciones.
- Suite global verde: **253 tests / 63 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0903 (Mark missing)

DONE. `Packages/PRCore/Sources/PRDomain/MissingEquipment.swift` (plan §9, RF-011):

- **`MissingEquipmentGuard`** (con `MissingEquipmentFilter`/`EquipmentRequiringItem`):
  - **persiste missing**: estado `.doesNotExist` del `GymProfile` (`setAvailability`);
  - **filtra futuras sesiones**: `filter(_:in:)` permite sólo ítems cuya maquinaria
    existe; bloquea los que requieren equipo inexistente; available/unknown no
    bloquean;
  - **revertir**: `revert(_:in:)` vuelve a `.unknown` para volver a programar esa
    máquina.
- Tests (`Tests/PRDomainTests/MissingEquipmentTests.swift`): persiste missing, bloquea
  ítems que lo requieren, sólo bloquea su propio equipo, revert permite programar de
  nuevo, available/unknown no bloquean.
- Suite global verde: **258 tests / 64 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0904 (Substitution scoring engine)

DONE. `Packages/PRCore/Sources/PRDomain/SubstitutionScoring.swift` (promptMaster §10.3):

- **Pesos versionados** via `EvidenceRule` (`safety.substitutionScoring`, versión rule
  en el EvidenceRegistry, no constantes dispersas): muscle 0.30, movement pattern 0.20,
  training role 0.15, angle 0.10, fatigue profile 0.08, stability 0.05, user history
  0.05, preference 0.04, equipment confidence 0.03 (suman 1.00).
  `SubstitutionScoringConfig` valida categoría `.safety`, claves presentes y suma 1.00.
- **Safety gate** obligatorio: reutiliza `RestrictionPolicyEngine.safeSubstitutes`
  (PR-1402). Un candidato prohibido por la política NUNCA se adopta (§16.2).
- **`SubstitutionScoringEngine.substitutes(for:)`** → `SubstitutionVerdict`
  (`.safe([ScoredSubstitute])` / `.noSafeSubstitute`). Ranking reproducible:
  mayor score primero, empate → nombre canónico. Dimensiones desde `Exercise`
  (músculo primario Jaccard, patrón, rol, ángulo, perfil de fatiga coseno,
  estabilidad, historial/preferencia del usuario, confianza de equipamiento vía
  `GymProfile`).
- Tests (`Tests/PRDomainTests/SubstitutionScoringTests.swift`): pesos suman 1.00,
  rechazo de pesos no unitarios, ranking reproducible, mejor equivalente lidera,
  historial/preferencia elevan score, gate excluye prohibidos, no-safe-substitute
  con todas prohibidas / sin candidatas, máquina ocupada baja el score.
- Suite global verde: **554 tests / 101 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0905 (Reorder-before-replace)

DONE. `Packages/PRCore/Sources/PRDomain/ReorderController.swift` (plan §9, RF-010):

- **`ReorderBeforeReplaceController`**: cuando un equipo está ocupado, localiza el
  primer ejercicio de la sesión restante que usa ese equipo (el "bloqueado") e intenta
  adelantar el siguiente ejercicio **compatible y libre**.
- **GATE de interferencia por fatiga** (reusa `FatigueInterferenceEngine`): el candidato
  sólo se adopta si el reorder NO aumenta la interferencia respecto al orden base. Así
  NUNCA mueve un ejercicio de prioridad baja (p.ej. triceps) antes de un movimiento
  prioritario (p.ej. priority bench) si la interferencia lo excede.
- **`.substitute(blocked:)`** si no hay reorder seguro (deja sitio a la sustitución
  PR-0904); `.unchanged` sin ocupación relevante. Salida auditable con `DecisionFact`.
- Tests (`Tests/PRDomainTests/ReorderControllerTests.swift`, 5): adelanta compatible
  libre, no triceps antes de priority bench (interferencia excede threshold),
  sin reorder seguro ofrece sustitución, unchanged sin ocupación, un solo ejercicio
  ocupado → sustitución.
- Suite global verde: **554 tests / 101 suites** (`swift test`); iOS Debug build verde.

### Estado PR-1001 (Double progression)

DONE. `Packages/PRCore/Sources/PRDomain/ProgressionEngine.swift` (plan §4E, RF-014):
pesos versionados via `EvidenceRule` (`progression.double`). Sube carga SÓLO si: todas
las working sets alcanzan el rango superior, sin fallo excesivo, sin dolor ≥ moderate
(pain cancela progresión), sin caída reciente, y respetando el incremento disponible de
la máquina (`availableIncrement`; desconocido ⇒ conservador). Emite `DecisionRecord`
(loadChange, rule reference). Tests: `ProgressionEngineTests.swift` (9): rango superior,
fallo excesivo, dolor moderate/high cancela, dolor leve/no bloquea, caída, incremento de
máquina, desconocido, primera vez, DecisionRecord.

### Estado PR-1002 (Strength progression strategies)

DONE. `Packages/PRCore/Sources/PRDomain/StrengthProgression.swift` + `StrengthProgressionTests.swift`:
enum `ProgressionStrategy` (doubleProgression, linearLoad, repGoal, rirAutoregulated,
strengthTopSetBackoff, maintain; spec §12.2). La estrategia es explícita por
block/exercise — cada una usa su propia regla, no una fórmula única (§12.1): linearLoad
sube un incremento fijo cuando todas las working sets alcanzan el rango superior;
repGoal avanza el objetivo de reps dentro del rango sin tocar peso y, al completarlo,
sube carga y reinicia al tramo inferior; topSetBackoff sube el top set al cumplir su
objetivo y modela back-off a la fracción configurada (0.85); rirAutoregulated reacciona
al RIR (bajo⇒sube, alto⇒hold); doubleProgression delega en el engine PR-1001; maintain
conserva. Peso versionado via `EvidenceRule` (`progression.strength`), gate conservador
común (dolor ≥ moderate cancela; fallo excesivo y caída mantienen; primera vez sin carga base mantiene) y emisión de `DecisionRecord`. Tests (20): casos del enum, estrategia
explícita y no fórmula única, subida/mantenimiento en las tres estrategias, respeto del
incremento de equipo, back-off configurado, RIR, maintain, delegación doubleProgression,
gate de dolor y primera vez.

### Estado PR-1003 (PR detector)

DONE. `Packages/PRCore/Sources/PRDomain/PRDetector.swift` + `PRDetectorTests.swift`:
detección determinista de PR por carga/reps/1RM estimado, con política de exclusión de
warmup y formula versionada. DecisionRecord auditable.

### Estado PR-1101 (Health authorization abstraction)

DONE. `Packages/PRCore/Sources/PRCore/HealthAuthorization.swift` (PRCore, no HealthKit
directo en el paquete compartido): autorización detrás de protocolo, permisos granulares
por tipo de dato, permiso denegado no bloquea (app sigue). Tests: `HealthAuthorizationTests.swift`.

### Estado PR-1102 (Start/finish strength workout)

DONE. `Packages/PRCore/Sources/PRCore/HealthWorkout.swift` + `HealthWorkoutTests.swift`:
lifecycle start/finish; los errores del sistema de salud NUNCA pierden los sets locales
(offline-first); el summary referencia la sesión de entrenamiento.

### Estado PR-1103 (Health workout summary)

DONE. `Packages/PRCore/Sources/PRCore/HealthWorkout.swift` (`HealthWorkoutSummary`) +
`HealthWorkoutSummaryTests.swift` (PR-1103): duration derivada de start/end, active
energy sólo si disponible, HR summary sólo si permitido/disponible, cada dato marcado
`measured`/`estimated`/`unavailable` (energyOrigin, HR origin).

### Estado PR-1105 (Workout reconciliation)

DONE. `Packages/PRCore/Sources/PRCore/Reconciliation.swift` + `ReconciliationTests.swift`:
matcher de solape; fuente energética canónica; no hay doble conteo de energía HealthKit.

### Estado PR-1201 (Watch workout UI shell)

DONE. `Packages/PRCore/Sources/PRDomain/WatchWorkout.swift` + `WatchWorkoutTests.swift`:
estado del workout en watch (ejercicio actual, peso/reps/índice de set, completar set,
rest timer). El shell de UI usa este estado determinista.

### Estado PR-1202 (Watch HealthKit live workout)

DONE. `Packages/PRCore/Sources/PRCore/HealthLiveWorkout.swift` + `HealthLiveWorkoutTests.swift`:
máquina de estados start/pause/resume/end del `HKLiveWorkoutBuilder` (via protocolo en PRCore).

### Estado PR-1203 (Multidevice workout coordination)

DONE. `Packages/PRCore/Sources/PRDomain/WorkoutSync.swift` + `WorkoutSyncTests.swift`:
motor determinista e idempotente de coordinación del workout compartido (RNF-014).
`WorkoutSyncEngine` aplica `SetEvent` (idempotentes por clave estable) sobre un
`WorkoutSyncLedger`:
- reintentar/reenviar ⇒ no-op (nunca duplica sets);
- conflicto sobre el mismo `SetSlot` ⇒ supersede por `performedAt` (empate ⇒ mayor device),
  queda exactamente un set;
- merge commutativo ⇒ mismo workout lógico en cualquier orden de llegada;
- local-first/offline-first ⇒ un dispositivo continúa y converge al reconectar.
6 tests.

### Estado PR-1302 (RecoveryDecisionEngine v1)

DONE. `Packages/PRCore/Sources/PRDomain/RecoveryDecisionEngine.swift` +
`RecoveryDecisionEngineTests.swift`: combina rendimiento + subjetivo (check-in PR-1301),
veredicto normal/adjust/recovery/rest; NO inventa una puntuación 0-100 falsa; sin diagnóstico.

### Estado PR-1401 (Restrictions management UI)

DONE. `Packages/PRCore/Sources/PRDomain/RestrictionManager.swift` + `RestrictionManagerTests.swift`:
crear/editar/revisar/resolver restricciones; user vs professional; reviewDate NO auto-resuelve.

### Estado PR-1402 (RestrictionPolicyEngine)

DONE. `Packages/PRCore/Sources/PRDomain/RestrictionPolicyEngine.swift` + tests:
patrón prohibido excluye, lista explícita `allowed` refina, un sustituto prohibido NUNCA
se adopta (gate de sustitución §16.2); veredicto auditable con `DecisionRecord`.

### Estado PR-1403 (Pain feedback during workout)

DONE. `Packages/PRCore/Sources/PRDomain/PainFeedbackEngine.swift` + `PainFeedbackEngineTests.swift`:
none/mild/moderate/high; moderate/high suspende progresión (integra PR-1001); nunca diagnostica.

### Estado PR-1601 (AgentIntent schema)

DONE. `Packages/PRCore/Sources/PRDomain/AgentIntent.swift` + `AgentIntentTests.swift`:
intents en dominio, Codable para wire, intent desconocido seguro (fallback determinista).
La arquitectura se respeta: el LLM interpreta a `AgentIntent`, el engine decide.

### Estado PR-1602 (ActionPolicyValidator)

DONE. `Packages/PRCore/Sources/PRDomain/ActionPolicyValidator.swift` + tests:
no puede evadir restricciones; no escribe repos directamente; gate de dolor; genera
`DecisionRecord`. Protege el invariant "Policy Validator protects".

### Estado PR-1603 (Agent gateway protocol)

DONE. `Packages/PRCore/Sources/PRDomain/AgentGateway.swift` + `AgentGatewayTests.swift`:
interpreta/explica con timeout y retry acotados; fallback local si el backend no responde.

### Estado PR-1606 (Why explanations)

DONE. Explicación del "por qué" que usa SÓLO los `DecisionFact` suministrados
(`Packages/PRCore/Sources/PRDomain/AgentGateway.swift` → `LocalFallbackExplainer.explain`,
`PRCore/LLMBackendTransport.swift.explain`, `PRDomain/AgentActionWriter.swift`
`askWhy(DecisionID)`). Fallback de plantilla determinista funciona offline (1–4 razones
concretas, `prefix(4)`); backend retry acotado y si vacío/no parseable ⇒ fallback local.
Cada engine emite `DecisionFact`/`explanationFacts` que alimentan al explicador. Tests
verdes: `AgentGatewayTests` (12, offline fallback, límite a 4 razones, backend/fallback local,
no guarda key), `AgentActionWriterTests` (10, preview read-only), `LLMBackendTransportTests`
(15, explain desde facts, strips bullets, límite a 4, unparseable⇒empty), `AgentIntentTests`
(14, `askWhy(DecisionID)`). 51 tests en 4 suites.

### Estado PR-1701 (Weekly adherence engine)

DONE. `Packages/PRCore/Sources/PRDomain/WeeklyAdherence.swift` + `WeeklyAdherenceTests.swift`:
completo vs ajustado/rest planificado; descanso planificado no rompe la constancia.

Todas las historias P0 del EPIC-09→17 de dominio/persistencia quedan marcadas DONE con
este sync: suite global verde **554 tests / 101 suites** (`swift test`); iOS Debug build verde.

### Estado PR-0004 (Feature flags)

DONE. `Packages/PRCore/Sources/PRCore/FeatureFlags.swift` + `FeatureFlagsTests.swift`
(PR-core). `FeatureFlags` con claves estables de Appendix E (`agent.nvidia.*`,
`agent.tools.write.enabled`, `agent.health_context.enabled`,
`agent.recovery_adjustment.enabled`, `agent.exercise_substitution.enabled`) con DEFAULTS
SEGUROS (todo DESHABILITADO en producción), override auditable (source default/override),
write independiente de read-only, Codable que rechaza claves desconocidas.
`AppConfiguration` sólo expone `environmentTag`, nunca secretos (PR-2002). 6 tests.

### Estado PR-0703 (Order explanation facts)

DONE. `ExerciseOrderEngine.orderWithExplanation` (+`OrderExplanation`/`OrderedExerciseExplanation`)
en `ExerciseOrder.swift` + `OrderExplanationTests.swift` (PR-domain). Explica de forma
determinista "por qué va primero" con facts por ejercicio (rol funcional, bonus de
prioridad muscular, bonus de demanda técnica) reusando `DecisionFact` para PR-1606;
alineado rank-por-rank con el orden; Codable. 6 tests.

### Estado PR-1605 (NL gym/equipment)

DONE. `LocalFallbackInterpreter` en `AgentGateway.swift` + `AgentGatewayTests.swift`
(PR-domain). Reconoce de forma determinista ocupado/inexistente de equipo →
`.equipmentUnavailable(ref, .occupied|.doesNotExist)` con mapeo nombre→`EquipmentType`
("el bench está ocupado", "no tienen hack squat aquí", "no hay mancuernas"); nunca inventa
instancias de máquina ni transfiere carga. 6 tests.

### Estado PR-0906/1303/1304/1604/1607/1702/1703/1801/1904

Backfill: estas P1 de dominio ya estaban implementadas con tests. Marcadas DONE en backlog:
per-machine history (`LoadHistory.swift`), deload (`DeloadEngine.swift`), auto-reschedule
(`AutoRescheduleEngine.swift`), NL time constraint (`AgentIntent`+`LocalFallbackInterpreter`),
agent audit trail (`AgentAuditTrail.swift`), consistency streak (`ConsistencyStreak.swift`),
achievements (`Achievements.swift`), bodybuilding phase (`BodybuildingPhase.swift`), duration
learning (`DurationEstimator`).

Suite global verde: **615 tests / 108 suites** (`swift test`); iOS Debug build verde.

---

# 25. Definition of milestone completion

Un milestone se cierra sólo cuando:

- historias relevantes `DONE`;
- suite verde;
- build iOS verde;
- build watchOS verde si aplica;
- manual scenario ejecutado;
- bugs P0/P1 bloqueantes resueltos;
- documentación actualizada.

