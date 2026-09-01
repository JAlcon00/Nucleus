# backlog.md — PR Agentic Fitness Coach

> Backlog ejecutable. Las historias están ordenadas por dependencia y valor. Un agente NO debe saltar a features P1/P2 si existe una dependencia P0 incompleta que invalide su implementación.

## Convenciones

### Prioridad

- **P0**: imprescindible para MVP o fundamento técnico.
- **P1**: importante para primera versión pública.
- **P2**: evolución/ventaja competitiva.
- **P3**: exploración futura.

### Tamaño

- **S**: slice pequeño.
- **M**: slice medio.
- **L**: requiere múltiples componentes.
- **XL**: debe dividirse antes de implementarse.

### Estados

`TODO | READY | IN_PROGRESS | BLOCKED | REVIEW | DONE`

### Definition of Done

Además de los criterios particulares, todas las historias heredan el DoD de `promptMaster.md`:

- implementación;
- tests;
- build;
- validación;
- accesibilidad cuando aplique;
- documentación;
- sin secretos ni warnings relevantes nuevos.

---

# EPIC-00 — Foundation & Engineering Quality

## PR-0001 — Bootstrap de proyecto y targets
**Priority:** P0  
**Size:** M  
**Dependencies:** none  
**Status:** IN_PROGRESS (iOS DONE; smoke build watchOS pendiente de runtime)  


### Historia
Como equipo de desarrollo, quiero una estructura estable de iOS/watchOS/core para que las features no crezcan dentro de un monolito de Views.

### Criterios de aceptación
- Existe target iOS principal.
- Existe target watchOS companion.
- Existe local Swift Package `PRCore` o estructura equivalente con dominio separado.
- Strict Concurrency está habilitado.
- iOS y watchOS compilan en Debug.
- No existe lógica de negocio dentro de `PRApp.swift`.
- Existe un `AppEnvironment` o composition root equivalente.
- `xcodebuild -list` documenta schemes disponibles.

### Tests
- Smoke build iOS.
- Smoke build watchOS.

---

## PR-0002 — CI local reproducible
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0001

### Criterios de aceptación
- Existe script/Makefile/justfile documentado para build + unit tests.
- El comando falla con exit code no cero ante fallo.
- No depende de ruta absoluta de un desarrollador.
- README documenta ejecución.

---

## PR-0003 — Logging seguro
**Priority:** P0  
**Size:** S  
**Dependencies:** PR-0001

### Criterios de aceptación
- Wrapper basado en `Logger`.
- Categorías: app, workout, health, sync, agent, persistence.
- Prohibido loggear notas de lesión, samples de salud, tokens o Apple identifiers.
- Tests verifican redaction donde exista formateo propio.

---

## PR-0004 — Feature flags y configuración
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-0001

### Criterios de aceptación
- Flags para agent backend, bodybuilding advanced y experimental features.
- Configuración no contiene secretos.
- Defaults seguros para producción.

---

# EPIC-01 — Domain Model

## PR-0101 — Core identifiers y value objects
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0001  
**Status:** DONE  


### Implementar
- ExerciseID
- TrainingBlockID
- WorkoutID
- SetRecordID
- GymID
- RestrictionID
- DecisionID
- LoadUnit
- TimeConstraint

### Criterios de aceptación
- `Codable`, `Hashable`, `Sendable` donde corresponda.
- No usar UUID/String raw sueltos en APIs de dominio críticas.
- Validación de kg/lb y valores no negativos.

### Notas de implementación
- Identificadores tipados en `Packages/PRCore/Sources/PRDomain/Identifiers.swift` (`ExerciseID`, `TrainingBlockID`, `WorkoutID`, `SetRecordID`, `GymID`, `RestrictionID`, `DecisionID`, `EvidenceRuleID`).
- Value objects en `LoadAndTime.swift`: `LoadUnit` (kg/lb), `Load` (rechaza negativos y NaN), `TimeConstraint` (rechaza minutos/tolerancia negativos vía `validated()` y decode).
- 15 tests Swift Testing verdes en `PRDomainTests/DomainTests.swift` (round trip Codable, equality/hash, invalid load/time boundaries).

### Tests
- round trip Codable;
- equality/hash;
- invalid load/time boundaries.

---

## PR-0102 — Exercise knowledge domain
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0101  
**Status:** DONE  


### Implementar
- Exercise
- ExerciseFamily
- MovementPattern
- MovementAngle
- EquipmentType
- MuscleGroup
- MuscleContribution
- ExerciseRole
- fatigue/skill/stability/loadability enums

### Criterios de aceptación
- Un ejercicio puede tener varios músculos secundarios.
- Cada ejercicio tiene `substitutionFamilyID`.
- No existe un único campo `muscle: String` como modelo principal.
- El dominio permite distinguir DB Bench, Smith Bench y machine press.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/Exercise.swift`: `Exercise`, `ExerciseFamily` (+`ID`/`ExerciseFamilyID`), `MovementPattern` (22), `ExerciseRole`, `EquipmentType` (distingue `dumbbell`/`smithMachine`/`machine`), `MovementAngle`, `Laterality`, `JointClass`, `DemandLevel`, `FatigueCost` (0...1 validado), `Loadability`, `RestrictionTag`, `MuscleGroup` (+`ID`), `MuscleContribution` (activación 0...1 validada).
- `Exercise` modela biomecánica + función (muscles estructurados, no `muscle: String`); `substitutionFamilyID` presente; variantes distinguibles por `equipment`/`id`.
- 23 tests Swift Testing verdes (fixtures press/pull/squat/isolation, encode/decode, family validation, validación de valores).

### Tests
- fixtures de press/pull/squat/isolations;
- encode/decode;
- family validation.

---

## PR-0103 — Training block/session/set domain
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0101, PR-0102  
**Status:** DONE  


### Criterios de aceptación
- Separación entre plan (`SessionTemplate`) y ejecución (`WorkoutSessionRecord`).
- SetPrescription y SetRecord son distintos.
- Workout lifecycle tiene transiciones validadas.
- No se pueden registrar reps negativas o weight negativo.
- Warmup sets distinguibles.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/Training.swift`: `SessionTemplate` (planeado) vs `WorkoutSessionRecord`/`SetRecord` (ejecución); `SetPrescription` vs `SetRecord` distintos; `PlannedSet`.
- Lifecycle validado: `WorkoutLifecycleState` (7 estados, transiciones rechazadas en dominio) y `SetLifecycleState` (5 estados).
- Validación: no reps negativas/cero, no weight negativo, rango de reps/descanso válido, RIR y target load no negativos. Warmup distinguible vía `isWarmup`.
- Feedback: `DifficultyFeedback`, `PainFeedback` (severidad 1...5 validada).
- 37 tests Swift Testing verdes (lifecycle transitions, invalid sets, planned vs performed integrity).

### Tests
- lifecycle transitions;
- invalid sets;
- planned vs performed integrity.

---

## PR-0104 — User training profile
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0101  
**Status:** DONE  


### Implementar
- ExperienceLevel
- TrainingGoal
- BodyCompositionPhase
- VarietyPreference
- CoachingDetailLevel
- MusclePriority
- schedule/time preferences

### Criterios de aceptación
- Goal y phase independientes.
- Usuario puede modificar goal sin perder historial.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/UserProfile.swift`: enums existentes + `MusclePriority` (spec §3.4) y preferencias schedule/time: `WeekDay`, `PreferredDayTime` (ventana validada), `SchedulePreference` (días 2...7, minutos 20...240).
- Goal y phase son campos independientes; modificar goal no afecta phase ni el historial de `SetRecord`/`WorkoutSessionRecord`.
- 45 tests Swift Testing verdes (MusclePriority, SchedulePreference, perfil independiente del historial).

---

## PR-0105 — Gym, machine y equipment domain
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0102  
**Status:** DONE  


### Criterios de aceptación
- GymProfile con availability.
- `occupied`, `missing`, `available`, `unknown` diferenciados.
- MachineProfile permite historial por instancia.
- Estado occupied es session-scoped.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/Gym.swift`: `GymProfile` (spec §6.4) con `equipmentAvailability`, `machineInstances`, `learnedBusyPatterns`; `MachineProfile` (spec §6.5) con `MachineProfileID` y `loadHistoryKey` (exercise + instancia).
- Estados de availability: `EquipmentAvailabilityState` con `doesNotExist`, `occupied`, `unknown`, `available` (spec §6.4). `BusyPattern`/`BusyLevel`.
- `occupied` es session-scoped: se rastrea en `occupiedDuringSession` y se limpia en `endingSession()`; no se persiste como hecho del gym.
- 51 tests Swift Testing verdes (estados diferenciados, historial por instancia, occupied session-scoped).

---

## PR-0106 — Restrictions domain
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0102  
**Status:** DONE  


### Criterios de aceptación
- body region, side, source, reviewDate, forbidden patterns/exercises.
- restricción no se autoelimina al llegar reviewDate.
- estado active/reviewNeeded/resolved.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/Restriction.swift`: `TrainingRestriction` (spec §16.1) con `BodyRegion`, `BodySide`, `RestrictionSource` (userReported/professionalGuidance), `reviewDate`, `forbiddenPatterns`, `forbiddenExerciseIDs`, `allowedExerciseIDs`, `restrictionTags`.
- `RestrictionStatus` (active/reviewNeeded/resolved) con transiciones validadas; `refreshed(asOf:)` pasa a `reviewNeeded` cuando pasa el `reviewDate` (nunca autoelimina); resolución solo por acción explícita.
- 58 tests Swift Testing verdes.

---

# EPIC-02 — Persistence & Offline-first

## PR-0201 — Repository protocols
**Priority:** P0  
**Size:** M  
**Dependencies:** EPIC-01  
**Status:** DONE

### Implementar contratos
- ExerciseRepository
- TrainingBlockRepository
- WorkoutRepository
- GymRepository
- RestrictionRepository
- DecisionRepository
- UserProfileRepository

### Criterios de aceptación
- PRCore no importa SwiftData.
- APIs async donde exista IO.
- tests usan in-memory fakes.

---

## PR-0202 — SwiftData persistence adapters
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0201

### Criterios de aceptación
- Persistencia de profile, blocks, workouts, sets, gyms, restrictions, decisions.
- Mapping aislado del dominio.
- Save de SetRecord ocurre inmediatamente al confirmar set.
- Error de sync remoto no revierte local save.

### Tests
- round-trip integration con in-memory ModelContainer;
- relaciones;
- delete policies;
- migration baseline.

---

## PR-0203 — Pending operation queue
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0202

### Criterios de aceptación
- Operaciones críticas tienen idempotency ID.
- Queue persiste entre launches.
- retry no duplica SetRecord.
- app funciona aunque backend esté apagado.

---

## PR-0204 — Export de datos
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0202

### Criterios de aceptación
- Export JSON completo de training data.
- CSV mínimo para workout sets.
- No exportar secrets.
- user-controlled share/export flow.

---

# EPIC-03 — Exercise Library & Evidence Registry

## PR-0301 — Seed exercise catalog
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0102, PR-0202

### Criterios de aceptación
- Catálogo mínimo cubre todos los patrones del MVP.
- Cada ejercicio tiene atributos suficientes para order/substitution.
- Dataset incluye versión.
- Import es idempotente.
- Licencias/source metadata documentadas si se importa dataset externo.

---

## PR-0302 — Exercise search
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0301

### Criterios de aceptación
- Buscar por canonical name y aliases.
- Filtrar por equipment, pattern y muscles.
- búsqueda offline.
- respuesta <100 ms para catálogo MVP en hardware representativo.

---

## PR-0303 — Evidence Registry
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0101

### Criterios de aceptación
- EvidenceRule versionada.
- DecisionRecord puede guardar rule ID/version.
- parámetros centralizados.
- cambios de reglas son testeables.

---

# EPIC-04 — Authentication & Onboarding

## PR-0401 — Sign in with Apple
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0001

### Criterios de aceptación
- Usa AuthenticationServices real.
- Maneja cancel/failure/success.
- No persiste credential token inseguramente.
- Primer login crea perfil local.
- Login no requiere HealthKit.

### Tests
- auth coordinator unit con fake provider abstraction;
- UI state tests.

---

## PR-0402 — Onboarding profile flow
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0104, PR-0401

### Criterios de aceptación
- goal;
- phase;
- experience;
- days/week;
- time/session;
- gym/equipment;
- variety;
- optional restrictions.
- usuario puede volver atrás sin perder respuestas.
- validaciones 2...7 días, 20...240 min.

---

## PR-0403 — Coaching detail initial mapping
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-0402

### Criterios de aceptación
- novice/beginner default guided.
- intermediate balanced.
- advanced/competitive advanced.
- usuario puede cambiar manualmente.

---

# EPIC-05 — Block Planner

## PR-0501 — Split selector
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0104, PR-0301

### Criterios de aceptación
- 2–3 días considera full body.
- 4 días soporta upper/lower.
- 3–6 días permite PPL cuando tenga sentido.
- selección es determinista y explicable.
- split no depende de LLM.

---

## PR-0502 — Volume allocator
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0501, PR-0303

### Criterios de aceptación
- distribuye targets por músculo/semana.
- respeta maintain/normal/emphasize/specialize.
- no genera volumen negativo.
- respeta time budget aproximado.
- límites vienen de configuración/evidence rules versionadas.

---

## PR-0503 — Exercise assignment
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0502, PR-0301

### Criterios de aceptación
- asigna anchors y rotatables.
- sólo usa equipment disponible/conocido o pregunta si unknown.
- prioriza variedad según profile sin romper anchors.
- no programa ejercicios bloqueados por restrictions.

---

## PR-0504 — 4–8 week block generation
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0503

### Criterios de aceptación
- genera bloque completo persistible.
- semanas dentro de 4...8.
- se puede explicar estructura.
- rebuild no borra historial anterior.

---

## PR-0505 — Block transition
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0504

### Criterios de aceptación
- nuevo goal/phase puede cerrar/transition current block.
- historical records permanecen intactos.
- exercise continuity se conserva cuando conviene.

---

# EPIC-06 — Today & Workout Logging

## PR-0601 — Today screen
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0504

### Criterios de aceptación
- muestra sesión, duración estimada y CTA empezar.
- máximo dos acciones para iniciar.
- funciona offline.
- estado de descanso/no workout claro.

---

## PR-0602 — Active workout state machine
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0103, PR-0202

### Criterios de aceptación
- start/pause/resume/finish/abandon.
- state transitions validadas.
- app kill/relaunch puede restaurar workout activo.

---

## PR-0603 — One-tap set completion
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0602

### Criterios de aceptación
- target weight/reps precargados.
- si coinciden, un tap registra.
- edición de peso/reps accesible.
- set persiste antes de transición UI final.

---

## PR-0604 — Rest timer
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603

### Criterios de aceptación
- inicia automáticamente tras working set cuando corresponde.
- puede skip/extend.
- no bloquea navegación.
- sobrevive background razonablemente según plataforma.

---

## PR-0605 — Workout completion summary
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603

### Criterios de aceptación
- duration;
- working sets;
- volume;
- PRs;
- energy cuando disponible y reconciliada;
- next action.

---

# EPIC-07 — Exercise Order Engine

## PR-0701 — Base ordering rules
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0301, PR-0503

### Criterios de aceptación
- prioridad > role > fatigue/skill según reglas.
- default compounds normalmente antes de accessories.
- priority isolation puede ir antes si bloque lo requiere.
- determinista.

### Tests
- strength bench priority;
- bodybuilding side-delt priority;
- novice full body;
- conflicting accessory fatigue.

---

## PR-0702 — Fatigue interference model
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0701

### Criterios de aceptación
- penaliza pre-fatiga de musculatura necesaria para movimiento prioritario.
- no impide supersets compatibles.
- configuración versionada.

---

## PR-0703 — Order explanation facts
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-0701

### Criterios de aceptación
- “por qué está primero” se explica con facts concretos.

---

# EPIC-08 — Time-aware Session Composer

## PR-0801 — Duration estimator
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603

### Criterios de aceptación
- default estimates por exercise/set/rest.
- actualiza perfil personal con completed workouts.
- confidence aumenta con muestras.

---

## PR-0802 — Hard time optimizer
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0801, PR-0502, PR-0701

### Criterios de aceptación
- session estimated duration <= hard limit con tolerancia documentada.
- preserva prioridades.
- elimina/reduce opcionales primero.
- no agrega supersets incompatibles.

---

## PR-0803 — Flexible time optimizer
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0802

### Criterios de aceptación
- session cae dentro de target ± tolerance cuando sea factible.
- explica cuando no es factible.

---

## PR-0804 — Extra time behavior
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0802

### Criterios de aceptación
- 180 min disponibles no multiplican volumen automáticamente.
- opcionales separados visualmente.
- cardio/mobility/posing sólo si corresponden.

---

# EPIC-09 — Gym Intelligence & Substitution

## PR-0901 — Gym profile UI
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0105, PR-0202

### Criterios de aceptación
- create/rename/select gym.
- equipment can be unknown/available/missing.
- no formulario inicial obligatorio de 100 máquinas.

---

## PR-0902 — Mark occupied
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0602, PR-0901

### Criterios de aceptación
- action disponible durante active workout.
- estado sólo sesión actual.
- dispara reorder evaluation.

---

## PR-0903 — Mark missing
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0901

### Criterios de aceptación
- persiste missing en gym profile.
- futuras sessions no programan esa máquina salvo usuario revierta.

---

## PR-0904 — Substitution scoring engine
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0301, PR-0106

### Criterios de aceptación
- safety gate.
- pattern/muscle/role/angle/fatigue/history/preference.
- ranking reproducible.
- devuelve “no safe substitute” si corresponde.

---

## PR-0905 — Reorder-before-replace
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0702, PR-0902, PR-0904

### Criterios de aceptación
- occupied intenta siguiente ejercicio compatible.
- no mueve triceps antes de priority bench si la interferencia excede threshold.
- si no hay reorder seguro, ofrece sustitución.

---

## PR-0906 — Per-machine history
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0105, PR-0603

### Criterios de aceptación
- historial de load por machine instance.
- sustitución recupera historial del sustituto, no transfiere carga del original.

---

## PR-0907 — Learned busy patterns
**Priority:** P2  
**Size:** L  
**Dependencies:** PR-0902

### Criterios de aceptación
- aprendizaje sólo con acciones del usuario.
- pattern confidence visible/interno.
- no afirmar disponibilidad en tiempo real.

---

# EPIC-10 — Progression & Personal Records

## PR-1001 — Double progression
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0603, PR-0303

### Criterios de aceptación
- carga aumenta sólo bajo reglas.
- respeta incrementos de machine/profile.
- pain moderate/high cancela progression.
- DecisionRecord creado.

---

## PR-1002 — Strength progression strategies
**Priority:** P1  
**Size:** L  
**Dependencies:** PR-1001

### Criterios de aceptación
- linearLoad/repGoal/topSetBackoff modelados.
- strategy explícita por block/exercise.
- no usar una única fórmula para todos.

---

## PR-1003 — PR detector
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603

### Criterios de aceptación
- load PR;
- rep PR;
- e1RM PR con fórmula versionada;
- no contar warmup como PR si policy lo excluye.

---

## PR-1004 — PR celebration
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-1003

### Criterios de aceptación
- celebración breve, accesible y no obstructiva.
- reduce motion respetado.

---

# EPIC-11 — HealthKit

## PR-1101 — Health authorization abstraction
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0001

### Criterios de aceptación
- HealthKit detrás de protocol.
- permisos granulares.
- denegar permiso no bloquea app.
- usage descriptions correctas.

---

## PR-1102 — Start/finish strength workout
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1101, PR-0602

### Criterios de aceptación
- workout configuration correcta.
- start/finish lifecycle manejado.
- errores no pierden sets locales.
- reference asociada a WorkoutSessionRecord.

---

## PR-1103 — Health workout summary
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-1102

### Criterios de aceptación
- duration;
- active energy si disponible;
- HR summary si permitido/disponible;
- datos marcados como measured vs estimated.

---

## PR-1104 — External workouts query
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1101

### Criterios de aceptación
- importa metadata autorizada.
- no inventa set data.
- puede vincular workout del día al plan manualmente/por sugerencia.

---

## PR-1105 — Workout reconciliation
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1103, PR-1104

### Criterios de aceptación
- overlap matcher.
- canonical energy source.
- same workout no suma energía dos veces.
- tests con overlapping/non-overlapping fixtures.

---

# EPIC-12 — Apple Watch

## PR-1201 — Watch workout UI shell
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0001, PR-0602

### Criterios de aceptación
- current exercise;
- weight;
- reps;
- set index;
- complete set;
- rest timer.
- touch targets adecuados.

---

## PR-1202 — Watch HealthKit live workout
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1102, PR-1201

### Criterios de aceptación
- usa HKWorkoutSession/HKLiveWorkoutBuilder según APIs reales.
- start/pause/resume/end.
- errores manejados.

---

## PR-1203 — Multidevice workout coordination
**Priority:** P0  
**Size:** XL  
**Dependencies:** PR-1202

### Antes de implementar
Dividir en subtareas según API real disponible.

### Criterios generales
- iPhone y Watch muestran el mismo workout lógico.
- comandos son idempotentes.
- conflicto no duplica sets.
- uno puede continuar si el otro se desconecta temporalmente.

---

## PR-1204 — Digital Crown editing
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1201

### Criterios de aceptación
- ajuste de weight/reps usable.
- no produce valores inválidos.
- haptics opcionales/no excesivos.

---

# EPIC-13 — Recovery & Deload

## PR-1301 — Pre-workout fatigue check-in
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-0601

### Criterios de aceptación
- excellent/normal/tired/veryTired/somethingHurts.
- no obligatorio todos los días si policy no lo requiere.

---

## PR-1302 — RecoveryDecisionEngine v1
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1001, PR-1301

### Criterios de aceptación
- usa performance + subjective feedback.
- Health context opcional.
- outcomes: normal/adjust/recovery/rest.
- sin score falso de 0–100.
- DecisionRecord.

---

## PR-1303 — Deload engine
**Priority:** P1  
**Size:** L  
**Dependencies:** PR-1302

### Criterios de aceptación
- planned y triggered deload.
- reduce variable(s) según policy.
- deload counts toward adherence.

---

## PR-1304 — Auto-reschedule after rest
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1302

### Criterios de aceptación
- descanso recomendado puede mover sesión.
- evita conflictos de sesiones consecutivas incompatibles.
- usuario confirma cambios importantes de calendario.

---

# EPIC-14 — Restrictions & Safety

## PR-1401 — Restrictions management UI
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0106

### Criterios de aceptación
- crear/edit/review/resolve.
- user-reported vs professional-guidance.
- reviewDate no auto-resolve.

---

## PR-1402 — RestrictionPolicyEngine
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1401, PR-0904

### Criterios de aceptación
- forbidden movement excludes exercise.
- allowed explicit list can refine.
- substitution never bypasses restriction.
- safety tests exhaustivos.

---

## PR-1403 — Pain feedback during workout
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603, PR-1402

### Criterios de aceptación
- none/mild/moderate/high.
- moderate/high suspende load progression.
- UI recomienda detener/modificar sin diagnosticar.

---

## PR-1404 — Parse professional restriction text via agent
**Priority:** P2  
**Size:** L  
**Dependencies:** EPIC-16

### Criterios de aceptación
- LLM propone structured draft.
- usuario confirma antes de guardar.
- no añade restricciones no presentes en texto.

---

# EPIC-15 — Education & Expertise Progression

## PR-1501 — Contextual coaching cards
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0403

### Criterios de aceptación
- education tied to current context.
- dismissible.
- advanced mode reduce explanations.

---

## PR-1502 — RIR progressive disclosure
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0603

### Criterios de aceptación
- guided UI usa lenguaje simple.
- advanced UI puede usar RIR técnico.
- misma semántica de dominio.

---

## PR-1503 — Advanced controls
**Priority:** P2  
**Size:** L  
**Dependencies:** PR-0504, PR-1002

### Criterios de aceptación
- volume targets;
- RIR targets;
- progression strategy;
- exercise priorities;
- block length;
- rest intervals.
- overrides registrados.

---

## PR-1504 — Personal response insights
**Priority:** P2  
**Size:** XL  
**Dependencies:** suficiente historial

### Antes de implementar
Dividir por insight: rest, volume, adherence, exercise preference.

### Regla
Etiquetar correlaciones como observadas, no causales.

---

# EPIC-16 — Agentic Layer

## PR-1601 — AgentIntent schema
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0104, PR-0106

### Criterios de aceptación
- intents definidos en dominio.
- Codable wire representation independiente si backend.
- unknown intent seguro.

---

## PR-1602 — ActionPolicyValidator
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1601, TrainingEngine components

### Criterios de aceptación
- LLM action cannot bypass restrictions.
- no direct repository writes.
- no load progression when pain gate active.
- logs DecisionRecord.

---

## PR-1603 — Agent gateway protocol
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-1601

### Criterios de aceptación
- `interpret(text, context)`.
- `explain(decisionFacts)`.
- timeout/retry bounded.
- backend failure has local fallback.

---

## PR-1604 — Natural language: time constraint
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1603, PR-0802

### Ejemplos
- “Hoy sólo tengo 30 minutos.”
- “No tengo prisa.”

### Criterios
- intent estructurado correcto.
- engine, no LLM, recompone sesión.

---

## PR-1605 — Natural language: gym/equipment
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1603, PR-0905

### Ejemplos
- “No tienen hack squat aquí.”
- “El bench está ocupado.”

---

## PR-1606 — Why explanations
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-1603, DecisionRecord

### Criterios de aceptación
- explanation sólo usa facts suministrados.
- fallback template funciona offline.
- 1–4 razones concretas.

---

## PR-1607 — Agent audit trail
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1602

### Criterios
- intent/action/result traceable.
- datos sensibles minimizados.

---

# EPIC-17 — Consistency & Gamification

## PR-1701 — Weekly adherence engine
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0605

### Criterios de aceptación
- planned sessions vs completed/adjusted/rest.
- planned rest no rompe consistency.
- rescheduled workout se cuenta correctamente.

---

## PR-1702 — Consistency streak
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-1701

### Criterios de aceptación
- streak por semanas de cumplimiento.
- no streak de entrenar todos los días como métrica principal.

---

## PR-1703 — Achievement framework
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1003, PR-1701

### Achievements iniciales
- first workout;
- first PR;
- 4-week consistency;
- 8-week consistency;
- block complete;
- deload complete;
- first smart substitution;
- 100/500/1000 working sets.

---

# EPIC-18 — Bodybuilding Mode

## PR-1801 — Bodybuilding phase domain
**Priority:** P1  
**Size:** S  
**Dependencies:** PR-0104

### Criterios
- offSeason/cut/contestPrep/recovery.
- TrainingGoal bodybuilding remains separate from phase.

---

## PR-1802 — Specialization blocks
**Priority:** P2  
**Size:** L  
**Dependencies:** PR-0502, PR-1801

### Criterios
- selected muscles emphasize/specialize.
- maintain targets for non-priorities.
- time budget respected.

---

## PR-1803 — Body measurements
**Priority:** P2  
**Size:** M  
**Dependencies:** PR-0202

### Criterios
- measurements versioned over time.
- local privacy.
- no inferred body fat precision from photo.

---

## PR-1804 — Progress photos
**Priority:** P2  
**Size:** L  
**Dependencies:** privacy review

### Criterios
- explicit opt-in.
- secure local storage strategy documented.
- delete/export.
- no automatic medical/body-fat diagnosis.

---

## PR-1805 — Posing sessions
**Priority:** P2  
**Size:** M  
**Dependencies:** PR-1801

### Criterios
- schedulable posing sessions.
- duration/tracking.
- no unsafe contest-prep advice.

---

# EPIC-19 — Analytics & Self-Knowledge

## PR-1901 — Exercise progress charts
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0605

### Criterios
- weight/reps/e1RM trends.
- machine-specific context.
- no misleading aggregation.

---

## PR-1902 — Weekly actionable summary
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-1701, PR-1003

### Criterios
- adherence;
- PRs;
- what changes next week;
- no vanity metrics without action.

---

## PR-1903 — Exercise preference learning
**Priority:** P2  
**Size:** M  
**Dependencies:** PR-0904

### Criterios
- repeated swaps reduce ranking.
- explicit like/dislike overrides learned preference.
- user can reset.

---

## PR-1904 — Duration learning
**Priority:** P1  
**Size:** M  
**Dependencies:** PR-0801

### Criterios
- personal session/exercise timing visible to optimizer.

---

# EPIC-20 — Privacy, Security & Quality Gates

## PR-2001 — Health privacy audit
**Priority:** P0 before release  
**Size:** M

### Criterios
- cada HealthKit type tiene razón documentada.
- unused permissions eliminados.
- permission-denied flow probado.

---

## PR-2002 — Secrets audit
**Priority:** P0 before release  
**Size:** S

### Criterios
- no API keys en repo/bundle.
- git history workflow documentado para incident response.

---

## PR-2003 — Accessibility critical flow audit
**Priority:** P0 before release  
**Size:** M

### Flujos
- onboarding;
- Today;
- active workout;
- set logging;
- occupied/substitute;
- restriction;
- finish.

---

## PR-2004 — Performance profiling
**Priority:** P1 before GA  
**Size:** M

### Criterios
- launch profiling;
- set completion latency;
- exercise search;
- SwiftData query hot paths;
- watch battery sanity.

---

## PR-2005 — Data migration test suite
**Priority:** P0 before first schema change  
**Size:** M

---

# Release slices

## MVP-0 — Engineering skeleton
PR-0001..0003, EPIC-01 core, PR-0201/0202.

## MVP-1 — Offline trainer
Onboarding local, exercise library, block planner, Today, workout logging, progression, order, time-aware.

## MVP-2 — Real gym adaptation
Gyms, occupied/missing, substitution, per-machine history.

## MVP-3 — Apple integration
Sign in with Apple, HealthKit, watchOS, reconciliation.

## MVP-4 — Elite coach behavior
Recovery, restrictions, explainability, agent intent/explanation, weekly adherence.

## V1
Achievements, richer analytics, advanced controls, sync/backend hardening, accessibility/performance release gates.

## V2
Bodybuilding specialization, body measurements, progress photos, posing, personal response insights.

---

# Backlog execution rule

La siguiente historia a implementar debe ser la primera `READY` de mayor prioridad cuyas dependencias estén `DONE`. Una IA agente NO debe seleccionar sólo la feature más llamativa.

