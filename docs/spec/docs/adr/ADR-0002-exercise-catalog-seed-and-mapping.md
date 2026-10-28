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
## Actualización 2026-10-28 · SCRUM-37 (P0): clasificación revisada y contraindicaciones

La consecuencia negativa "nombre ambiguo" se volvió un bug de seguridad. Las restricciones
filtraban solo por patrón, y con restricción de codo el plan asignaba extensiones y jalones
de tríceps con cuerda (las clasificaba como cardio). Cambios en `ExerciseInflector`:

- **Orden de las reglas:**
  - lo aislado y específico va antes que lo genérico;
  - curls y extensiones van antes que press, remos y jalones;
  - la zancada va antes que la sentadilla ("split squat" es zancada);
  - el press inclinado o declinado es de pecho.
- **Coincidencias por palabra:**
  - "row" solo cuenta como palabra, así que "narrow" ya no es remo;
  - "rope" ya no significa cardio; solo "battling ropes", "rope climb" y saltar la cuerda lo son;
  - "kickback" con glúteo como principal es cadera.
- **`contraindicationTags`** deja de estar vacío. Es la red de seguridad: `RestrictionPolicyEngine` ya cruzaba estas etiquetas.
  - **Codo:** tríceps, bíceps o antebrazo como principal.
  - **Hombro y cuello:** la carga termina sobre o detrás de la cabeza (vertical de manos, arrancada, envión, push press, sentadilla con barra arriba).
  - **Hombro:** remo al mentón o al cuello.
  - **Cuello:** todo lo que nombra el cuello.
- **Otras correcciones:**
  - un músculo cuenta una sola vez;
  - el press vertical lleva ángulo `overhead`;
  - las aperturas y todo lo de una articulación son aislamiento (`accessoryIsolation`).
- **Pruebas** (`PRCoreTests/CatalogClassificationTests.swift`):
  - cada zona del formulario se prueba contra el catálogo real con un criterio que no usa la clasificación (el nombre del dataset y el músculo principal);
  - los 63 staples tienen su patrón fijado;
  - lo que no cuadra con su músculo principal queda en una lista con su razón;
  - un caso nuevo hace fallar la prueba.
- Los planes guardados se regeneran con `currentGeneratorVersion` 6.

## Actualización 2026-10-28 · SCRUM-219: equipo guiado, fatiga y más staples

La selección por objetivo, experiencia y fase (`ExerciseSelectionRule`, `pr-b005-v1`) necesitó
tres cambios en el mapeo:

- **Smith como equipo propio.** El dataset la marca "machine" (o "barbell"); si el nombre dice
  "smith", el equipo es `smithMachine`. Guía la barra como una máquina, pero el gesto es el de
  la barra: es el ancla del novato con objetivo de fuerza. El equipo por defecto de la app la
  incluye.
- **Fatiga sistémica por patrón y equipo.** Antes era fija por clase articular (0.5 compuesto,
  0.25 aislamiento), así que el déficit no podía elegir algo que cansara menos. Ahora
  (`ExerciseInflector.systemicFatigue`):
  - compuesto: 0.5, más la bisagra (+0.2), la sentadilla (+0.15) y la zancada o la cargada (+0.1);
  - aislamiento: 0.25;
  - equipo: barra +0.15, mancuerna o kettlebell +0.05, polea, Smith o bandas −0.1, máquina −0.15;
    en un aislamiento cuenta un tercio.
  Ejemplos: sentadilla con barra 0.8, prensa 0.5, peso muerto rumano 0.85, press de banca con
  barra 0.65, en máquina 0.35.
- **15 staples más** (63 → 78), para que cada slot tenga variantes guiadas e inclinadas entre
  las cuales elegir y rotar: press de banca e inclinado en Smith, press inclinado con barra y en
  máquina de palanca, mariposa, remo isolateral y remo en Smith, press de hombro en Smith,
  aperturas inversas en máquina, curl y extensión de tríceps en máquina, fondos en máquina,
  sentadilla y sentadilla dividida en Smith, y peso muerto con piernas rígidas en Smith. Van al
  final de cada lista, así que el orden curado de los anteriores no cambia. Su patrón queda
  fijado en `CatalogClassificationTests`.
- Los planes guardados se regeneran con `currentGeneratorVersion` 7.
