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
Codable/JSON de escritura atómica (no SwiftData; ver `adr/ADR-0001`). Cobertura en
`PRCoreTests/CodableRepositoriesTests.swift`: round-trip por entidad, relaciones,
delete policies, perfil único y persistencia atómica a disco. El save local es
inmediato y autoritativo para proteger los datos de workout (RF-028/RF-029).

## Catálogo de ejercicios (EPIC-03)

Implementado en PR-0301 con el dataset público *free-exercise-db* (Unlicense)
curado a 678 ejercicios y mapeado de forma determinista a la ontología `Exercise`
de PRDomain (ver `adr/ADR-0002`). Cobertura en `PRCoreTests/ExerciseCatalogTests.swift`:
carga del bundle, determinismo de IDs, cobertura de patrones MVP e idempotencia
del seed (RF-034).

## Evidence Registry (EPIC-03)

Implementado en PR-0303 en `PRDomain/Evidence.swift` (promptMaster §22): `EvidenceRule`
versionada + `EvidenceRegistry` centralizado (el cambio de una regla exige bump de
versión) + `EvidenceRuleReference` (id + versión). `DecisionRecord` persiste la
referencia versionada de la regla usada, haciendo auditable qué versión de regla
soportó cada decisión (RF-025). Cobertura en `PRDomainTests/EvidenceTests.swift`.

## Búsqueda de ejercicios (EPIC-03)

Implementado en PR-0302 en `PRDomain/ExerciseSearch.swift`: `ExerciseSearchEngine`
offline determinista (nombre/aliases normalizados, filtros por equipment/patrón/
músculos) con objetivo <100 ms sobre el catálogo MVP. Cobertura en
`PRDomainTests/ExerciseSearchTests.swift` + `PRCoreTests/ExerciseSearchPerfTests.swift`.

## Split selector (EPIC-05)

Implementado en PR-0501 en `PRDomain/SplitSelector.swift` (promptMaster §8.2):
selección determinista y explicable de la estructura de bloques por días/objetivo/
experiencia (fullBody 2–3, upperLower 4, pushPullLegs 5+), sin depender de LLM.
Cobertura en `PRDomainTests/SplitSelectorTests.swift` (RF-004).

## Volume allocator (EPIC-05)

Implementado en PR-0502 en `PRDomain/VolumeAllocator.swift` (plan §4B): distribución
determinista de sets semanales por músculo según `PriorityTier`, con límites
versionados vía `EvidenceRule` (`VolumeConfig`), sin volumen negativo y sin inventar
músculos. Cobertura en `PRDomainTests/VolumeAllocatorTests.swift` (RF-004).

## Exercise assignment (EPIC-05)

Implementado en PR-0503 en `PRDomain/ExerciseAssignment.swift` (plan §4C): asignación
de `anchors` (estables para medir progreso) y `rotatables` (rotación dentro de la
familia según `varietyPreference`), usando sólo equipment disponible/conocido o
dejando candidatos para pregunta si `unknown`, sin programar ejercicios bloqueados
por `TrainingRestriction` (excluye patrones/IDs prohibidos y respeta la lista
permitida). Cobertura en `PRDomainTests/ExerciseAssignmentTests.swift` (RF-004).

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

