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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

> **Nota tecnológica (ver `ADR-0001`):** los `@Model` de SwiftData no pueden vivir
> en una librería SPM compartida (crash SIGTRAP). PR-0202 se implementa con un
> almacén Codable/JSON de escritura atómica dentro de PRCore; SwiftData queda
> reservado para la capa de app.

### Criterios de aceptación
- Persistencia de profile, blocks, workouts, sets, gyms, restrictions, decisions.
- Mapping aislado del dominio.
- Save de SetRecord ocurre inmediatamente al confirmar set.
- Error de sync remoto no revierte local save.

### Tests
- round-trip integration con in-memory `RepositoryStore`;
- relaciones (sets dentro de una sesión);
- delete policies;
- persistencia atómica a disco (escritura temp + rename).

---

## PR-0203 — Pending operation queue
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0202  
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- Export JSON completo de training data.
- CSV mínimo para workout sets.
- No exportar secrets.
- user-controlled share/export flow.

### Estado
Implementado con un motor determinista de dominio (`ExportEngine`).
- **JSON completo**: `ExportBundle` versionado (bloques, sesiones+sets, ejercicios, gyms,
  restricciones y perfil), serialización determinista (`sortedKeys` + ISO-8601).
- **CSV mínimo de workout sets**: una fila por set (cabecera + 10 columnas), orden
  determinista y quoting RFC-4180.
- **No exporta secrets**: el bundle sólo contiene agregados de dominio de entrenamiento;
  además `containsForbiddenSecretFields` niega el export si detecta campos con nombres
  de secretos (`DataExportError.secretDetected`).
- **user-controlled flow**: `DataExportCoordinator` (caso de uso en PRCore) + `ExportView`
  con `ShareLink` del archivo.
- Cobertura: 7 tests en `PRDomainTests/DataExportTests.swift`.

---

# EPIC-03 — Exercise Library & Evidence Registry

## PR-0301 — Seed exercise catalog
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0102, PR-0202  
**Status:** DONE

### Criterios de aceptación
- Catálogo mínimo cubre todos los patrones del MVP.
- Cada ejercicio tiene atributos suficientes para order/substitution.
- Dataset incluye versión.
- Import es idempotente.
- Licencias/source metadata documentadas si se importa dataset externo.

**Nota técnica:** dataset público *free-exercise-db* (Unlicense) curado a 678
ejercicios (strength/powerlifting/olympic/strongman) como resource del paquete;
mapeo determinista a la ontología `Exercise` de PRDomain documentado en
`ADR-0002`; IDs/familias derivadas por SHA-256 del slug (idempotente).

---

## PR-0302 — Exercise search
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0301  
**Status:** DONE

### Criterios de aceptación
- Buscar por canonical name y aliases.
- Filtrar por equipment, pattern y muscles.
- búsqueda offline.
- respuesta <100 ms para catálogo MVP en hardware representativo.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/ExerciseSearch.swift`: `ExerciseSearchEngine`
  (índice value-type determinista y sin IO), `ExerciseSearchQuery` (filtros AND),
  `ExerciseSearchHit` (relevancia) con normalización case/diacritic-insensitive.
- Tests de comportamiento en `PRDomainTests/ExerciseSearchTests.swift` y test de
  rendimiento <100 ms sobre el catálogo real en
  `PRCoreTests/ExerciseSearchPerfTests.swift`.
- Suite **125 tests / 45 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0303 — Evidence Registry
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0101  
**Status:** DONE

### Criterios de aceptación
- EvidenceRule versionada.
- DecisionRecord puede guardar rule ID/version.
- parámetros centralizados.
- cambios de reglas son testeables.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/Evidence.swift`: `EvidenceRule` versionada +
  `EvidenceRegistry` (registro centralizado; cambiar una regla exige bump de
  versión) + `EvidenceRuleReference` (id + versión) que `DecisionRecord` persiste
  para auditar qué versión de regla se usó (§22.2). Validación de versión,
  non-finite parameters, títulos de referencia y duplicados.
- `DecisionRecord.ruleReferences` reemplaza al campo `ruleIDs` (que queda como
  view derivada); los registros persisten la referencia versionada.
- 16 tests nuevos en `PRDomainTests/EvidenceTests.swift`; suite **109 tests /
  41 suites** verdes (`swift test`); iOS Debug build verde.

---

# EPIC-04 — Authentication & Onboarding

## PR-0401 — Sign in with Apple
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0001  
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- novice/beginner default guided.
- intermediate balanced.
- advanced/competitive advanced.
- usuario puede cambiar manualmente.

### Estado
DONE. `Packages/PRCore/Sources/PRDomain/CoachingDetail.swift`: `CoachingDetailMapper`
(mapeo determinista novice/beginner→guided, intermediate→balanced,
advanced/competitive→advanced) + `CoachingDetailPrefs` (nivel efectivo + origen
`defaultByExperience`/`manualOverride`, override manual manda sobre el default y
`resetting` limpia el override). El usuario SIEMPRE puede cambiar manualmente.
Cobertura: 10 tests en `PRDomainTests/CoachingDetailTests.swift`.

---

# EPIC-05 — Block Planner

## PR-0501 — Split selector
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0104, PR-0301  
**Status:** DONE

### Criterios de aceptación
- 2–3 días considera full body.
- 4 días soporta upper/lower.
- 3–6 días permite PPL cuando tenga sentido.
- selección es determinista y explicable.
- split no depende de LLM.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/SplitSelector.swift`: `SplitSelector` +
  `TrainingSplit` (fullBody/upperLower/pushPullLegs) + `SplitSelection` con
  facts explicables. 2–3 días fullBody; 4 días upperLower (salvo bodybuilding
  avanzado surplus → PPL); 5+ días PPL por adherencia. Determinista.
- 10 tests nuevos en `PRDomainTests/SplitSelectorTests.swift`; suite **135 tests /
  47 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0502 — Volume allocator
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0501, PR-0303  
**Status:** DONE

### Criterios de aceptación
- distribuye targets por músculo/semana.
- respeta maintain/normal/emphasize/specialize.
- no genera volumen negativo.
- respeta time budget aproximado.
- límites vienen de configuración/evidence rules versionadas.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/VolumeAllocator.swift`: `VolumeAllocator` +
  `VolumeConfig` (regla `EvidenceRule` con rangos por tier) + `VolumeAllocation`
  (`MuscleVolumeAssignment` con priority y ruleReference). Determinista, sin
  volumen negativo, sin inventar músculos, límites versionados.
- 9 tests nuevos en `PRDomainTests/VolumeAllocatorTests.swift`; suite **144 tests /
  49 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0503 — Exercise assignment
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0502, PR-0301  
**Status:** DONE

### Criterios de aceptación
- asigna anchors y rotatables.
- sólo usa equipment disponible/conocido o pregunta si unknown.
- prioriza variedad según profile sin romper anchors.
- no programa ejercicios bloqueados por restrictions.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/ExerciseAssignment.swift`: `ExerciseAssigner` +
  `ExerciseAssignmentInput` + `MuscleExerciseAssignment`/`AssignedExercise`
  (`assignmentRole` anchor/rotatable). Asigna el candidato más estable de la familia
  como anchor y el resto como rotatables según variedad (stable 1, balanced 2,
  varied 3, configurable). Equipment: sólo usa disponibles si son conocidos, o deja
  sugerencias si `unknown` (la UI pregunta). Restricciones: excluye patrones/ID
  prohibidos y respeta la lista explícitamente permitida.
- 10 tests nuevos en `PRDomainTests/ExerciseAssignmentTests.swift`; suite **154 tests /
  50 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0504 — 4–8 week block generation
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0503  
**Status:** DONE

### Criterios de aceptación
- genera bloque completo persistible.
- semanas dentro de 4...8.
- se puede explicar estructura.
- rebuild no borra historial anterior.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/BlockPlanner.swift`: `BlockPlanner` (
  `BlockPlanningInput`/`BlockPlanningResult`/`BlockExplanation`) orquesta de forma
  determinista SplitSelector → VolumeAllocator → ExerciseAssigner →
  ExerciseOrderEngine → FatigueInterferenceEngine para producir un `TrainingBlock`
  persistible 4–8 semanas. `block.status == .planned`, `sessions`, `muscleTargets` y
  `priorities` poblados; estructura explicable vía facts + referencias versionadas.
  Siempre genera un bloque NUEVO (ID distinto): rebuild NO muta ni borra historial.
  Valida semanas 4...8 y prioridades no vacías (no inventa músculos).
- `ExerciseAssignmentDefaults.makeRule()` añadido en `ExerciseAssignment.swift`.
- 7 tests nuevos en `PRDomainTests/BlockPlannerTests.swift`; suite **177 tests /
  53 suites** verdes (`swift test`); iOS Debug build verde.

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- start/pause/resume/finish/abandon.
- state transitions validadas.
- app kill/relaunch puede restaurar workout activo.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/ActiveWorkout.swift`: `ActiveWorkoutController`
  (con `ActiveWorkoutState`/`ActiveWorkoutSnapshot`/`ActiveWorkoutError`) gestiona el
  ciclo de vida de un entrenamiento activo. `start(from:)` abre un workout nuevo y
  rechaza sobrescribir uno activo; `pause`/`resume`/`finish`/`complete`/`abandon`
  validan cada transición contra la tabla de `WorkoutLifecycleState` y lanzan
  `ActiveWorkoutError.invalidTransition` ante movimientos inválidos. `finish` pasa a
  `.finishing` y `complete` a `.completed`. Abandonar no borra los sets ya realizados
  (no se muta el historial).
- Restauración tras kill/relaunch: `snapshot()` devuelve un `ActiveWorkoutSnapshot`
  persistible (Codable) y `ActiveWorkoutController.restore(from:)` lo recupera;
  los snapshots en estado terminal (`.completed`/`.abandoned`) no son restaurables.
- 10 tests nuevos en `PRDomainTests/ActiveWorkoutTests.swift`; suite **187 tests /
  54 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0603 — One-tap set completion
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0602  
**Status:** DONE

### Criterios de aceptación
- target weight/reps precargados.
- si coinciden, un tap registra.
- edición de peso/reps accesible.
- set persiste antes de transición UI final.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/SetCompleter.swift`: `SetCompleter` (con
  `SetCompletionDraft`/`SetCompletionInput`/`SetCompletionError`) precarga el target
  de peso/reps desde la prescripción (`targetLoad`) o, si no hay targetLoad, desde el
  último peso realizado del ejercicio (progresión), con reps del rango inferior.
- `oneTap(...)` registra el set sólo si el input coincide exactamente con el target
  (mismo peso+unidad+reps); si difiere devuelve `nil` para que la UI abra la edición
  sin forzar un registro erróneo. `recordSet(...)` permite editar peso/reps de forma
  accesible y registra un working set `.completed`. Ambos persisten el set en la
  sesión activa (`WorkoutSessionRecord.performedSet`) ANTES de cualquier transición
  UI, de forma append-only (no mutan sets previos ni el plan).
- 9 tests nuevos en `PRDomainTests/SetCompleterTests.swift`; suite **196 tests /
  55 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0604 — Rest timer
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603  
**Status:** DONE

### Criterios de aceptación
- inicia automáticamente tras working set cuando corresponde.
- puede skip/extend.
- no bloquea navegación.
- sobrevive background razonablemente según plataforma.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/RestTimer.swift`: `RestTimer` (con
  `RestTimerState`) inicia automáticamente el descanso tras un working set con la
  duración recomendada desde `SetPrescription.restSeconds`; los warmups NO inician
  descanso (`autoStart(afterCompletedWarmup:prescription:)`).
- `extend(by:)` prolonga el `endDate` (no-op si el timer está inactivo o con duración
  no positiva); `skip` cancela el descanso.
- No bloquea navegación: el timer es un valor con `endDate` anclado en wall-clock;
  `remaining(at:)`/`hasElapsed(at:)` se computan contra `Date()` en lectura, por lo
  que sobrevive background/relaunch sin depender de ticks en memoria.
- 8 tests nuevos en `PRDomainTests/RestTimerTests.swift`; suite **204 tests /
  56 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0605 — Workout completion summary
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0603  
**Status:** DONE

### Criterios de aceptación
- duration;
- working sets;
- volume;
- PRs;
- energy cuando disponible y reconciliada;
- next action.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/WorkoutSummary.swift`: `WorkoutSummaryBuilder`
  (con `WorkoutSummary`/`PersonalRecord`/`SummaryNextAction`/`PersonalRecordDetector`)
  agrega una sesión de forma determinista:
  - **duration**: `endedAt - startedAt` (`now` si no terminó);
  - **working sets**: sets `.completed`; **volume**: Σ weight×reps de los completados
    (skipped/planned no cuentan);
  - **PRs**: `PersonalRecordDetector` compara cada set completado contra un baseline
    histórico de peso por ejercicio; NO inventa récords sin referencia previa;
  - **energy**: sólo se propaga si llega reconciliada de una fuente externa y es
    finita/≥0; nunca se computa aquí (RN-008, no doble contabilización);
  - **next action**: `.inProgress` / `.readyToFinish` / `.completed` según lifecycle.
- 8 tests nuevos en `PRDomainTests/WorkoutSummaryTests.swift`; suite **212 tests /
  57 suites** verdes (`swift test`); iOS Debug build verde.

---

# EPIC-07 — Exercise Order Engine

## PR-0701 — Base ordering rules
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0301, PR-0503  
**Status:** DONE

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

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/ExerciseOrder.swift`: `ExerciseOrderEngine` +
  `ExerciseOrderInput` + `OrderedExercise` (exercise + orderScore + rank).
  Orden base determinista siguiendo §9: rol funcional (`primaryCompound` >
  `secondaryCompound` > `priorityIsolation` > `accessoryIsolation` > warmup/mobility
  > conditioning/posing), bonus de prioridad muscular (specialize 60 / emphasize 45 /
  normal 20 / maintain 0) y bonus de demanda técnica (`skillDemand` high 30 /
  moderate 15). Empates resueltos por nombre canónico. `ExerciseOrderEngine.order`
  devuelve `[OrderedExercise]` rankeado 1...N.
- 7 tests nuevos en `PRDomainTests/ExerciseOrderTests.swift`; suite **161 tests /
  51 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0702 — Fatigue interference model
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0701  
**Status:** DONE

### Criterios de aceptación
- penaliza pre-fatiga de musculatura necesaria para movimiento prioritario.
- no impide supersets compatibles.
- configuración versionada.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/FatigueInterference.swift`: `FatigueInterferenceEngine` +
  `FatigueInterferenceConfig` (regla `EvidenceRule` categoría `.ordering` con
  `penaltyWeight`, `minOverlap`, `compatibleThreshold`) + `InterferenceAssessment`/
  `InterferencePenalty`. Acumula la fatiga local de todos los ejercicios previos y
  penaliza cuando pre-fatigan musculatura de un movimiento prioritario posterior
  (compound/anchor/priorityIsolation); supersets compatibles (solapamiento bajo) no
  se penalizan. `reorder` minimiza interferencia preservando prioridad base (nunca
  mueve un movimiento prioritario después de uno menor). Sin constantes dispersas:
  parámetros versionados vía regla de evidencia.
- 9 tests nuevos en `PRDomainTests/FatigueInterferenceTests.swift`; suite **170 tests /
  52 suites** verdes (`swift test`); iOS Debug build verde.

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
**Status:** DONE

### Criterios de aceptación
- default estimates por exercise/set/rest.
- actualiza perfil personal con completed workouts.
- confidence aumenta con muestras.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/DurationEstimator.swift`: `DurationEstimator` (con
  `DurationDefaults`/`ExerciseDurationProfile`) estima la duración de una sesión de
  forma determinista a partir de defaults por set/rest/transición y opcionalmente por
  ejercicio (`perExerciseSeconds`), aplicando un multiplicador de calentamiento a los
  warmups y sumando descanso (`restSeconds`) + transición entre sets.
- **Perfil personal**: `ExerciseDurationProfile` mantiene una media EWMA
  (`averageSeconds`) + `sampleCount` + `confidence` (logística `n/(n+k)`). `record`
  aprende con workouts completados; el motor favorece el tiempo personal sobre el
  default cuando `confidence >= personalThreshold` (`shouldPreferPersonal`).
- 8 tests nuevos en `PRDomainTests/DurationEstimatorTests.swift`; suite **220 tests /
  58 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0802 — Hard time optimizer
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0801, PR-0502, PR-0701  
**Status:** DONE

### Criterios de aceptación
- session estimated duration <= hard limit con tolerancia documentada.
- preserva prioridades.
- elimina/reduce opcionales primero.
- no agrega supersets incompatibles.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/HardTimeOptimizer.swift`: `HardTimeOptimizer` (con
  `SessionItem`/`CompatibleSuperset`/`TimeOptimizerResult`) recorta una sesión a un
  límite duro de forma determinista:
  - **preserva anchors y prioridades**: `role == .anchor` o `isPriorityMuscle` nunca
    se recortan;
  - **opcionales primero**: elimina `role == .optional` antes de tocar accesorios;
  - **reduce accesorios**: reduce set-count a la mitad antes de descartar, y sólo
    descarta si aun así no cabe;
  - **supersets compatibles**: `CompatibleSuperset` sólo existe si los grupos
    musculares son disjuntos; nunca agrega supersets incompatibles;
  - **tolerancia documentada**: `withinLimit` = `estimated <= limit + tolerance`, con
    `notes` explicando lo eliminado/reducido.
- 8 tests nuevos en `PRDomainTests/HardTimeOptimizerTests.swift`; suite **228 tests /
  59 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0803 — Flexible time optimizer
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0802  
**Status:** DONE

### Criterios de aceptación
- session cae dentro de target ± tolerance cuando sea factible.
- explica cuando no es factible.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/FlexibleTimeOptimizer.swift`: `FlexibleTimeOptimizer`
  (con `FlexibleTimeResult`/`FlexibleStatus`) ajusta una sesión a una ventana
  `target ± tolerance`:
  - `inWindow`: si la sesión ya cae dentro de la ventana, no recorta nada;
  - sobre el límite: reusa `HardTimeOptimizer` para recortar SÓLO lo necesario y entrar
    por el borde superior (no recorta de más);
  - `under`: por debajo del umbral, NO añade volumen (invariante; extra-time en
    PR-0804) y lo explica;
  - `notFeasible`: explica cuando no es factible — sobre el límite aun conservando
    todos los anchors/prioridades, o ventana demasiado estrecha para la granularidad
    de los sets.
- 6 tests nuevos en `PRDomainTests/FlexibleTimeOptimizerTests.swift`; suite
  **234 tests / 60 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0804 — Extra time behavior
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0802  
**Status:** DONE

### Criterios de aceptación
- 180 min disponibles no multiplican volumen automáticamente.
- opcionales separados visualmente.
- cardio/mobility/posing sólo si corresponden.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/ExtraTimeBehavior.swift`: `ExtraTimeBehavior` (con
  `ExtraTimePlan`/`ExtraTimeActivity`) decide el uso del tiempo extra:
  - **no multiplica volumen**: nunca añade working sets; a lo sumo rellena con
    actividades de extensión dentro del tiempo disponible (plan §388);
  - **opcionales separados**: `optionalsAreSeparate = true` (se muestran fuera del
    plan núcleo);
  - **sólo si corresponden**: `mobility` siempre aplica; `cardio` según objetivo/fase
    (`cardioApplies`: generalHealth/recomposition/powerbuilding, o déficit); `posing`
    sólo para `bodybuilding`. Nunca se excede el tiempo extra y se explica el sobrante
    sin más volumen.
- 7 tests nuevos en `PRDomainTests/ExtraTimeBehaviorTests.swift`; suite **241 tests /
  61 suites** verdes (`swift test`); iOS Debug build verde.

---

# EPIC-09 — Gym Intelligence & Substitution

## PR-0901 — Gym profile UI
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0105, PR-0202  
**Status:** DONE

### Criterios de aceptación
- create/rename/select gym.
- equipment can be unknown/available/missing.
- no formulario inicial obligatorio de 100 máquinas.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/GymProfileManager.swift`: `GymProfileManager` (con
  `GymProfileManagerError`/`persistentAvailabilityStates`) gestiona el perfil del gym
  de forma determinista:
  - **create/rename/select**: crea un gym vacío, lo renombra (nombre no vacío) y lo
    selecciona como activo (`activeGymID`);
  - **equipment unknown/available/missing**: `setAvailability(type, to:, on:)` fija
    disponibilidad persistente sólo entre `.unknown`/`.available`/`.doesNotExist`;
    `.occupied` es session-scoped y se rechaza (se marca vía `GymProfile.markingOccupied`);
  - **sin onboarding obligatorio**: el equipamiento no confirmado queda `.unknown`
    (progressive disclosure); `knownEquipmentTypes` reporta sólo lo confirmado.
- 7 tests nuevos en `PRDomainTests/GymProfileManagerTests.swift`; suite **248 tests /
  62 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0902 — Mark occupied
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0602, PR-0901  
**Status:** DONE

### Criterios de aceptación
- action disponible durante active workout.
- estado sólo sesión actual.
- dispara reorder evaluation.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/OccupancyController.swift`: `OccupancyController`
  (con `OccupancyChange`/`OrderedEquipmentUse`) marca un equipo como ocupado en la
  sesión activa:
  - **sólo sesión actual**: `occupiedDuringSession` (session-scoped); al finalizar la
    sesión (`endingSession`) vuelve al estado persistente del gym;
  - **dispara reorder**: `shouldReorder == true` si algún ítem ordenado del plan usa
    el equipo ocupado (`OrderedEquipmentUse`), señalando que el orden debe reevaluarse
    ANTES de sustituir (RF-010).
- 5 tests nuevos en `PRDomainTests/OccupancyControllerTests.swift`; suite **253 tests /
  63 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0903 — Mark missing
**Priority:** P0  
**Size:** M  
**Dependencies:** PR-0901  
**Status:** DONE

### Criterios de aceptación
- persiste missing en gym profile.
- futuras sessions no programan esa máquina salvo usuario revierta.

### Notas de implementación
- `Packages/PRCore/Sources/PRDomain/MissingEquipment.swift`: `MissingEquipmentGuard`
  (con `MissingEquipmentFilter`/`EquipmentRequiringItem`) garantiza que las futuras
  sesiones no programen máquinas marcadas inexistentes:
  - **persiste missing**: usa `GymProfile` estado `.doesNotExist` (`setAvailability`);
  - **filtra programación futura**: `filter(_:in:)` devuelve sólo los ítems cuya
    maquinaria existe (`allowed`) y bloquea los que requieren equipo inexistente
    (`blocked` + `missingTypes`); available/unknown no bloquean;
  - **revertir**: `revert(_:in:)` vuelve el equipo a `.unknown` para que el usuario
    pueda volver a programar esa máquina.
- 5 tests nuevos en `PRDomainTests/MissingEquipmentTests.swift`; suite **258 tests /
  64 suites** verdes (`swift test`); iOS Debug build verde.

---

## PR-0904 — Substitution scoring engine
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-0301, PR-0106  
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- linearLoad/repGoal/topSetBackoff modelados.
- strategy explícita por block/exercise.
- no usar una única fórmula para todos.

---

## PR-1003 — PR detector
**Priority:** P0  
**Size:** S  
**Dependencies:** PR-0603  
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- usa HKWorkoutSession/HKLiveWorkoutBuilder según APIs reales.
- start/pause/resume/end.
- errores manejados.

---

## PR-1203 — Multidevice workout coordination
**Priority:** P0  
**Size:** XL  
**Dependencies:** PR-1202
**Status:** DONE

### Antes de implementar
Dividir en subtareas según API real disponible.

### Criterios generales
- iPhone y Watch muestran el mismo workout lógico.
- comandos son idempotentes.
- conflicto no duplica sets.
- uno puede continuar si el otro se desconecta temporalmente.

### Estado
Implementado con un motor determinista e idempotente de coordinación en el dominio
(`WorkoutSyncEngine` + `SetEvent` + `WorkoutSyncLedger`, RNF-014):
- **Idempotencia**: cada comando es idempotente por su clave estable (`event.dedupKey` / `SetRecordID`);
  reenviar o reintentar es un no-op y nunca duplica sets.
- **Conflicto sin duplicar**: dos eventos que nombran el mismo `SetSlot` representan el mismo
  set lógico; gana el más reciente (`performedAt`, empate ⇒ mayor `device`) y queda exactamente uno.
- **Mismo workout lógico**: el merge es commutativo; los dispositivos convergen al mismo contenido
  de sets en cualquier orden de llegada.
- **Desconexión tolerante**: local-first/offline-first; cada dispositivo aplica sus eventos en
  solitario y el merge converge al reconectar.
- Cobertura: 6 tests en `PRDomainTests/WorkoutSyncTests.swift`.

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- crear/edit/review/resolve.
- user-reported vs professional-guidance.
- reviewDate no auto-resolve.

---

## PR-1402 — RestrictionPolicyEngine
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1401, PR-0904  
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

### Criterios de aceptación
- intents definidos en dominio.
- Codable wire representation independiente si backend.
- unknown intent seguro.

---

## PR-1602 — ActionPolicyValidator
**Priority:** P0  
**Size:** L  
**Dependencies:** PR-1601, TrainingEngine components  
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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
**Status:** DONE

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

