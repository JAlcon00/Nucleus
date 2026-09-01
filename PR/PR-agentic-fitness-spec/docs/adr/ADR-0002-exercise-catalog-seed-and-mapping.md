# ADR-0002 — Seed del catálogo de ejercicios (fuente y mapeo)

- **Fecha:** 2026-09-01
- **Estado:** Aceptado
- **PR:** PR-0301 (Seed exercise catalog, EPIC-03)
- **Ámbito:** Exercise Knowledge (datos de catálogo)

---

## Contexto

PR-0301 requiere un catálogo mínimo de ejercicios versionado y un import/seed
idempotente, con atributos suficientes para order/substitution en el MVP. El
dominio `Exercise` (PR-0102) es mucho más rico que cualquier dataset público:
`movementPattern`, `EquipmentType`, `JointClass`, `DemandLevel`, `FatigueCost`,
`Loadability`, `ExerciseRole`, `RestrictionTag`, `MuscleContribution` y
`substitutionFamilyID`.

La pregunta "¿de dónde salen los datos de los ejercicios?" tenía dos vías
posibles: dataset externo o curado a mano. Se evaluaron datos crudos de
`free-exercise-db` para no duplicar la curación.

## Decisión

Usar el dataset público **free-exercise-db** (`exercises.json`, repo
`yuhonas/free-exercise-db`) como **datos crudos de origen**, con licencia
**Unlicense (public domain)** — segura para una app comercial. Se integra un
**subset curado** de **678 ejercicios** (categorías `strength`, `powerlifting`,
`olympic weightlifting` y `strongman`; se excluyen `stretching`, `cardio`,
`plyometrics` que no aportan valor al MVP de fuerza) como resource del paquete
PRCore (`Resources/exercises.json`).

El dataset crudo NO preserva la ontología completa de PRDomain. Por tanto se
define un **mapeo determinista y centralizado**:

| Campo PRDomain | Fuente en dataset | Regla |
|---|---|---|
| `id` (`ExerciseID`) | `id` (slug) | SHA-256(namespace+"exercise"+slug) → primer UUID, fijando bits v5/RFC-4122. Determinista e idempotente |
| `canonicalName` | `name` | 1:1 |
| `movementPattern` | — | Clasificador heurístico por keywords (ordre prioritario) + fallback por grupo muscular primario |
| `movementAngle` | — | Sólo press: inferido de keywords (incline/decline/overhead/upright), si no `.flat`; nil para el resto |
| `primaryMuscles` | `primaryMuscles` | Mapa de 17 músculos del dataset → `MuscleGroup` + activación 1.0 |
| `secondaryMuscles` | `secondaryMuscles` | Mismo mapa + activación 0.4 |
| `equipment` | `equipment` | Mapa de strings del dataset → `EquipmentType` (default `.other`) |
| `laterality` | — | `.bilateral` (el MVP usa variantes; el dataset no la distingue) |
| `jointClass` | `mechanic` | `compound`→`.multiJoint`, `isolation`→`.singleJoint`, nil→umbral por nº de grupos primarios |
| `stabilityDemand` / `skillDemand` | `level` | beginner→low, intermediate→moderate, expert→high |
| `systemicFatigueCost` | — | `.multiJoint`→0.5, `.singleJoint`→0.25 |
| `localFatigue` | — | Fatiga por grupo = contribución × 0.5 (derivada de primary+secondary) |
| `loadability` | `equipment` | machine/cable/plateLoaded/smith→`fixedStack`, barbell/dumbbell/kettlebell/sled→`discreteIncrements`, bodyweight→`bodyweight`, bands→`resisted`, resto→`discreteIncrements` |
| `defaultRoles` | — | Por patrón + compound: primaryCompound / secondaryCompound / accessoryIsolation / mobility / conditioning |
| `contraindicationTags` | — | Vacío (no hay datos en el dataset; no se inventa) |
| `aliases` | — | Vacío |
| `substitutionFamilyID` | — | **Una familia por patrón de movimiento**, con ID determinista SHA-256(namespace+"family"+patrón) |

Reglas de fatiga/activación son heurísticas documentadas iniciales, versionadas
en el código (`ExerciseInflector`) y ajustables sin cambiar el dataset.

## Alternativas consideradas

1. **Curar el catálogo a mano (0 de dataset).** Rechazado como fuente primaria por
   el costo de mantinimiento y el criterio de "*catálogo mínimo*"; el MVP no
   necesita miles de entradas curadas manualmente.
2. **Importar los ~876 ejercicios completos.** Rechazado: incluye stretching,
   cardio y plyometrics que hoy no aportan al MVP de fuerza y ensuciarían el
   catálogo con patrones no usados.
3. **Mapeo en runtime por heurísticas de nombres.** Rechazado para producción:
   el engine no debe depender de strings (Gate de plan.md); el mapeo ocurre **sólo
   en el seed** y el motor consume datos tipados.
4. **IDs aleatorios por import.** Rechazado: rompería la idempotencia exigida por
   PR-0301.

## Consecuencias

- **Positivas:**
  - Import **idempotente** por construcción (IDs y familias deterministas).
  - Un solo resource (178 KB) versionado con metadata de origen/licencia.
  - El motor sigue sin tocar strings: tras el seed consume `Exercise` tipados.
  - Cobertura demostrable: tests verifican los 18 patrones MVP con ≥1 ejercicio.
- **Negativas / a vigilar:**
  - `movementPattern` y campo derivados son **heurísticos**: un ejercicio con
    nombre ambiguo puede caer en fallback por músculo. Mitigación: reglas
    centralizadas y versionadas; revisión de calidad por ejercicio del MVP queda
    como trabajo futuro (plan.md §6 Revisión de calidad de datos).
  - `contraindicationTags` y `aliases` quedan vacíos: mejorables por curaduría
    posterior, no bloqueante para el MVP.
  - Una familia por patrón es una granularidad gruesa para substitution en un
    futuro; refinarla será un cambio delimitado a `ExerciseInflector` sin tocar
    datos ya persistidos (los IDs de familia derivan del patrón).

## Rollback

- Quitar el resource `Resources/exercises.json`, la referencia `.copy(...)` en
  `Package.swift`, `ExerciseCatalog.swift` y `ExerciseCatalogTests.swift`.
- El dominio `Exercise`/`ExerciseFamily` (PR-0102/PR-0103) no cambia; los datos
  ya persistidos con IDs deterministas siguen siendo válidos.