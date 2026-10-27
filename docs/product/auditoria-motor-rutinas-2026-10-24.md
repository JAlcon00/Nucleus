# Auditoría del motor de rutinas de Nucleus

**Fecha:** 2026-10-24 · **Rama auditada:** `main` @ `0b0a1f6` (SCRUM-203) · **Autor:** PM/PO Nucleus con Claude (skills: science-based-strength-coach, swift-logic-engineer, swiftui-design-expert)

## 1. Resumen ejecutivo

La queja del usuario es correcta y tiene causa raíz identificable: **el generador de bloques no es un sistema de decisión, es una tabla fija con tres entradas efectivas (días, variedad y —sólo a 3 días— experiencia)**. Objetivo, fase, experiencia, minutos disponibles, equipo y prioridades musculares **no influyen en qué ejercicios salen**; sólo cambian repeticiones, descansos y cuántas series se recortan.

Evidencia reproducible (sección 3): de **8 100 perfiles distintos** (6 días × 3 variedades × 6 objetivos × 5 experiencias × 3 fases × 5 duraciones) salen **16 conjuntos de ejercicios distintos**, y para un número de días dado, entre 2 y 4. Un novato de 30 min en déficit y un avanzado de 120 min en superávit reciben los mismos ejercicios.

Causas raíz, en orden de impacto:

| # | Causa | Dónde |
|---|---|---|
| 1 | Las prioridades musculares están cableadas: 8 músculos a tier `.normal`; el usuario no las elige y pantorrilla, core y antebrazo nunca se programan | `TodayPlanCoordinator.swift:310-321, 339` |
| 2 | El volumen semanal es siempre el **mínimo** del tier (8 series/músculo) sin importar experiencia, días ni tiempo; con más tiempo nunca sube (y un test lo cementa) | `VolumeAllocator.swift:233-235`; test `moreTimeDoesNotAddSets` |
| 3 | La selección de ejercicios es un ranking fijo (`exercise-staples.json`): el primero permitido es ancla para todos los usuarios; variedad sólo cambia cuántos rotables hay, y sólo se nota si el músculo se entrena ≥2 veces por semana | `ExerciseAssignment.swift:141-161` |
| 4 | El recorte por tiempo baja series de los últimos ejercicios hasta 1 en lugar de quitar ejercicios: produce sesiones de 8 ejercicios × 1 serie (volumen basura) | `BlockPlanner.swift:trimToFit` |
| 5 | El nº de ejercicios por sesión sale de `(series+2)/3` sin cota: 2 días ⇒ 16 ejercicios/día; 5–6 días ⇒ día de tirón con 4 ejercicios y ~19 min aunque el usuario tenga 60 | `BlockPlanner.swift:distribute` |
| 6 | "Formas de llegar al fallo" = RIR por clase + aviso de dropset en la última serie. No existe el concepto de técnica de intensidad en `PlannedSet`; los motores de tiempo, progresión, sustitución y deload existen pero **ninguno está conectado** a la app | `IntensityAdvisor.swift`; 0 referencias en PRCore/App a `FlexibleTimeOptimizer`, `HardTimeOptimizer`, `ExtraTimeBehavior`, `ProgressionEngine`, `SubstitutionScoring`, `OccupancyController`, `DeloadEngine` |

Recomendación: tratar esto como **Fase B — Plan correcto (P0)** del roadmap, con un test de caracterización que hoy falle (sección 7, PR-B001) como gate de entrada, y entregarlo en las rebanadas verticales de la sección 7. No añadir motores nuevos: casi todo lo que falta ya existe en `PRDomain` y sólo hay que conectarlo y parametrizarlo.

---

## 2. Alcance y método

**Revisado (código real en `main`):** `BlockPlanner`, `SplitSelector`, `VolumeAllocator`, `ExerciseAssigner`, `IntensityAdvisor`, `DurationEstimator`, `TodayPlanBuilder`/`TodayPlanCoordinator`, `ExerciseCatalog` (+ `exercises.json`, `exercise-staples.json`), `OnboardingProfile`, `BlockPlannerRealCatalogTests`, y las vistas `TodayView`, `WeekComponents`, `WorkoutModeView`.

**Cómo se verificó:** la sesión no tiene toolchain de Swift (el shell del Mac vinculado es una VM Linux), así que **no se ejecutaron `swift test` ni `make ci`**. La lógica de selección (`ExerciseAssigner` por staples, `distribute`, reparto por días, `trimToFit`, `DurationEstimator`) se portó a un script de Python (`docs/product/sim-motor-rutinas.py`) que lee el catálogo y los staples reales del repo y reproduce el conjunto de ejercicios por sesión. La simulación no reproduce el orden (`ExerciseOrderEngine`/fatiga) porque el orden no cambia *qué* ejercicios salen. Todo lo marcado como "evidencia" abajo viene de esa simulación y de lectura del código; la historia PR-B001 pide convertirlo en un test Swift que lo confirme con el motor real.

**Criterio del entrenador aplicado:** mínima complejidad para máximo progreso sostenible; volumen recuperable y progresable (no el máximo tolerable); series efectivas (≥2–3 por ejercicio, cerca del fallo donde es seguro); selección por función y cobertura de ángulos, no por fama; adaptar al tiempo conservando movimientos prioritarios y calidad, no diluyendo; técnicas de intensidad con coste de fatiga contabilizado y sólo donde aportan.

---

## 3. Evidencia reproducible

### 3.1 La matriz

```
combinaciones de perfil evaluadas: 8100
rutinas distintas por conjunto de ejercicios: 16
distintas por nº de días: {2: 2, 3: 4, 4: 4, 5: 2, 6: 2, 7: 2}
```

Para 3 días hay 4 variantes: full body con 1, 2 o 3 rotables (variedad) y PPL (avanzado/competitivo o bodybuilding). **Nada más mueve la selección.**

### 3.2 Ejemplos (hipertrofia, intermedio, 60 min salvo que se indique)

**3 días, variedad "estable"** — día 2 y día 3 son el mismo ejercicio por músculo; el ancla sólo aparece el día 1:

```
Día 1 (8 ej / 24 series / ~59 min): Press banca barra ×3, Remo barra ×3, Press hombro manc. ×3, Curl barra ×3, Pushdown ×3, Sentadilla ×3, RDL ×3, Hip thrust ×3
Día 2 (8 ej / 24 series / ~59 min): Press incl. manc. ×3, Jalón ancho ×3, Laterales ×3, Curl incl. ×3, Rompecráneos ×3, Prensa ×3, Curl femoral sentado ×3, Puente glúteo ×3
Día 3 (8 ej / 16 series / ~39 min): (los mismos 8 del día 2) ×2
```

**3 días, 30 min** — mismo nº de ejercicios, series diluidas a 1:

```
Día 1 (8 ej / 12 series): Press banca ×3, Remo ×3, Press hombro ×1, Curl ×1, Pushdown ×1, Sentadilla ×1, RDL ×1, Hip thrust ×1
```

**3 días, 90 o 120 min** — idéntico al de 60 min (el test `moreTimeDoesNotAddSets` lo exige).

**3 días, objetivo fuerza** — descansos de 150 s hacen que el recorte deje **1 serie de sentadilla y 3 de curl de bíceps**:

```
Día 1 (8 ej / 15 series): Press banca ×3, Remo ×3, Press hombro ×3, Curl ×2, Pushdown ×1, Sentadilla ×1, RDL ×1, Hip thrust ×1
```

**5 días PPL** — tirón A y B tienen 4 ejercicios y ~19 min; pierna un solo día con 24 series:

```
Día 2 Pull (4 ej / 8 series / ~19 min): Remo barra ×2, Jalón ×2, Curl barra ×2, Curl incl. ×2
Día 3 Legs (9 ej / 24 series / ~59 min)
```

**2 días full body** — 16 ejercicios por sesión, la mitad con 1 serie.

**4 días U/L "estable"** — Upper A = Upper B y Lower A = Lower B exactamente (1 rotable, ocurrencia 0 y 1 caen en el mismo índice).

### 3.3 Lo que hace cada entrada hoy

| Entrada del perfil | Afecta a qué ejercicios | Afecta a volumen | Afecta a reps/descanso | Afecta a técnica |
|---|---|---|---|---|
| Días por semana | sí (split) | no (8/músculo fijo) | no | no |
| Variedad | sólo si el músculo se entrena ≥2×/sem | no | no | no |
| Objetivo | no | no (indirecto vía recorte) | sí | no |
| Experiencia | sólo a 3 días (PPL vs FB) | no | no | dropset sí/no |
| Fase (déficit/superávit) | no | no | no | no |
| Minutos | no | sólo recorta hacia abajo | no | no |
| Prioridades musculares | **no se piden** | — | — | — |
| Equipo real del gym | no (seed fijo) | — | — | — |

---

## 4. Hallazgos por severidad

### Bloqueantes (P0 — invalidan "plan correcto")

**H1 · Prioridades cableadas y músculos huérfanos.** `TodayPlanBuilder.defaultPriorities()` devuelve 8 músculos a `.normal`. El onboarding no pregunta prioridades (`OnboardingProfile` no tiene el campo) y pantorrilla, core y antebrazo no están en la lista, así que aparecen en la clasificación del split (`classification(for:)` incluye `.calves` y `.forearms`) pero `buildSessions` los salta por `guard let weeklySets = allocation.target(for:)`. Impacto: imposible especializar, ningún plan entrena pantorrilla ni core. Arreglo: pedir 0–3 prioridades en onboarding (tier `.emphasize`), poner el resto en `.normal` y pantorrilla/core en `.maintain`; ver PR-B002.

**H2 · Volumen = mínimo del tier, siempre.** `VolumeAllocator.representativeSets` devuelve `range.lowerBound`; el comentario dice "el block planner puede subirlo dentro del máximo según experiencia/tiempo", pero `BlockPlanner` nunca lo hace. Resultado: 8 series/músculo/semana para todos, y `trimToFit` sólo resta. Un avanzado con 6 días y 90 min recibe sesiones de 19–29 min. Arreglo: presupuesto de series por sesión derivado de minutos y experiencia, y asignación dentro de `[min,max]` del tier (prioritarios primero); ver PR-B003. El test `moreTimeDoesNotAddSets` debe reescribirse: "más tiempo no es más volumen" es un invariante contra **inflar sin límite**, no contra subir dentro del rango de evidencia.

**H3 · Selección por ranking fijo.** Con equipo de gym estándar, los staples de cada músculo son permitidos y `ExerciseAssigner` toma siempre `staples[0]` como ancla y `staples[1...n]` como rotables. No hay scoring por objetivo (fuerza quiere barra/estable; definición en déficit tolera más máquina/menos fatiga sistémica), por experiencia (novato: estabilidad externa; avanzado: más libertad), por cobertura de ángulos (pecho horizontal + inclinado + aislamiento) ni por equipo real. La variación entre bloques no existe: el bloque 2 es el bloque 1. Arreglo: PR-B005 (selección por cobertura funcional + scoring + variación intencional derivada del `blockID`, nunca aleatoria dentro del bloque).

**H4 · Recorte por tiempo que diluye.** `trimToFit` resta series al último ejercicio con >1 serie hasta que cabe, sin cota inferior. Produce 8 ejercicios × 1 serie (30 min) y 1 serie de sentadilla en fuerza. Criterio del entrenador: con poco tiempo se conservan los movimientos prioritarios y el volumen de calidad; se **quitan ejercicios** (aislamientos no prioritarios primero), se usan superseries antagonistas y máquinas, y ningún ejercicio queda con <2 series efectivas. Arreglo: PR-B004. Nota: `HardTimeOptimizer` ya implementa "quitar opcionales → reducir accesorios → superseries compatibles" y no está conectado.

### Importantes (P1)

**H5 · Nº de ejercicios por sesión sin cota.** `distribute` usa `count = min(asignados, (series+2)/3)`. A 2 días da 16 ejercicios/sesión; a 5–6 días da 4. No hay un rango objetivo por duración (p. ej. 30 min → 3–4, 45 → 4–5, 60 → 5–7, 90 → 7–9) ni un mínimo de series por ejercicio. Arreglo dentro de PR-B004.

**H6 · Técnicas de intensidad inexistentes en el modelo.** `SetPrescription` sólo tiene rango de reps, RIR, unidad y descanso. "Llegar al fallo de más formas" exige un tipo `IntensityTechnique` en la serie (`straight`, `topSetBackoff`, `dropSet`, `restPause`, `myoReps`, `antagonistSuperset(pairID)`, `lengthenedPartials`) con reglas por clase de ejercicio, experiencia, fase y tiempo, y con su coste de fatiga contabilizado en `FatigueInterference`. Hoy el dropset es un aviso de UI, no parte del plan ni del registro. Arreglo: PR-B006.

**H7 · El ancla no se entrena todos los días y el día 3 siempre es "ligero".** El reparto 8/3 = 3+3+2 deja el tercer día con 2 series por ejercicio, y en full body el ancla sólo sale el primer día (`count == 1, occurrence > 0 → rotable`), lo que contradice la razón de ser del ancla (medir progreso con frecuencia). Arreglo: cuando un músculo se entrena ≥2×, ancla en al menos 2 sesiones; el reparto debe seguir prioridad, no el índice del día.

**H8 · Sustitución y tiempo real en sesión no están conectados.** `agentExerciseSubstitutionEnabled` está en `false`, no hay acción "cambiar ejercicio" en `WorkoutModeView`, y `OccupancyController`, `SubstitutionScorer`, `FlexibleTimeOptimizer`, `ExtraTimeBehavior` tienen 0 referencias fuera de `PRDomain`. "Adaptar a tus tiempos" en el gym real es hoy imposible. Esto es Fase "Adaptación al gimnasio real" (prioridad 5) y se deja fuera de este paquete salvo el recorte por tiempo (H4), pero hay que saberlo.

**H9 · Estimador de duración sesgado.** `DurationEstimator` = 60 s/serie + descanso mínimo + 30 s de transición, sin calentamiento general ni series de aproximación (un `PlannedSet.isWarmup` existe pero el planner no las genera). "Cabe en 60 min" es optimista para fuerza (sin aproximaciones) y pesimista para aislamientos cortos. Arreglo: PR-B007 (series de aproximación en compuestos y calentamiento como bloque fijo de 5–8 min).

### Mejoras (P2)

**H10 · Split.** 4 días siempre U/L (salvo bodybuilding avanzado en superávit); 5 días PPL deja pierna a 1×/sem con 24 series en un día y 2 días de empuje/tirón de 19 min. Opciones más equilibradas: 4 días U/L o PPL+Upper; 5 días U/L/P/P/L o PPL+U/L. Decisión de producto, no bug.

**H11 · UI de "Hoy" / "Tu semana".** Muestra nombre, tipo (compuesto/aislado), series × reps, RIR y nota de dropset: correcto y legible. Falta: (a) el "por qué" de cada ejercicio ya existe en `SessionOrderExplanation` y no se muestra; (b) no hay affordance de "ver alternativas"; (c) cuando el motor adapte por tiempo, la UI debe decir qué se quitó y por qué (estado "sesión recortada"). Diseñar esto junto con PR-B004/B006, no antes.

### Lo que está bien y hay que conservar

- Determinismo y explicabilidad (facts, `EvidenceRuleReference`, precedencia de orden documentada).
- Anclas + rotables como concepto; orden por rol → prioridad → demanda → fatiga; "ningún aislamiento antes de su compuesto" está probado sobre el catálogo real.
- RIR por clase de ejercicio (barra pesada 2, compuesto 1–2, aislado 0–1) y bloqueadores de dropset: coinciden con el criterio del entrenador.
- Catálogo de 678 ejercicios con ontología (patrón, ángulo, familia, fatiga, estabilidad, loadability) ya rica para hacer scoring: no falta información, falta usarla.
- 904 tests; `BlockPlannerRealCatalogTests` es la base ideal para el test de caracterización.

---

## 5. Diseño objetivo del motor (qué debe decidir y con qué)

Entrada efectiva del planificador (todas deben mover el resultado):

1. **Prioridades musculares** (0–3 énfasis del usuario) → tier por músculo. Sin énfasis: todo `.normal`, pantorrilla/core `.maintain`.
2. **Presupuesto de series por sesión** = f(minutos, objetivo): minutos útiles ≈ minutos − calentamiento(6) ; series ≈ minutos útiles / coste medio de serie (descanso del objetivo + 60 s + transición). 60 min hipertrofia ≈ 20–24 series; fuerza ≈ 14–16.
3. **Volumen semanal por músculo** dentro de `[min,max]` del tier, escalado por experiencia (novato → min; intermedio → medio; avanzado → hacia max) y **capado por el presupuesto semanal** (series por sesión × días). Si el presupuesto no alcanza el mínimo del tier: bajar tiers no prioritarios a `.maintain` antes que diluir.
4. **Composición de la sesión**: rango de ejercicios por duración (30 → 3–4, 45 → 4–5, 60 → 5–7, 90 → 7–9, ≥120 → 8–10) y **≥2 series efectivas por ejercicio** (ideal 3–4). Si no cabe: quitar aislamientos no prioritarios → fusionar en superserie antagonista → luego recortar series.
5. **Selección por cobertura funcional**: para cada músculo, cubrir en la semana los "slots" funcionales (p. ej. pecho: press horizontal, press inclinado, aislamiento/aducción; espalda: tirón vertical, remo horizontal, aislamiento; cuádriceps: sentadilla/prensa, unilateral, extensión). Dentro de cada slot, scoring determinista: equipo disponible > restricciones > rol (ancla = estable + progresable: barra/máquina según experiencia) > objetivo (fuerza: barra; déficit: menos fatiga sistémica) > preferencia del usuario (likes/dislikes) > ranking de staples como desempate.
6. **Variación intencional**: anclas estables dentro del bloque y en bloques consecutivos; rotables elegidos con una semilla derivada del `blockID` + índice de bloque del usuario para que el bloque 2 no repita el bloque 1. Nunca aleatorio dentro del bloque.
7. **Técnicas de intensidad** como parte de la prescripción (ver H6), con reglas: fuerza → top set + back-off en el ancla; hipertrofia intermedio+ → dropset o rest-pause en el último aislado de la sesión, myo-reps en máquinas cuando falta tiempo, superseries antagonistas cuando el presupuesto no alcanza; parciales en posición alargada sólo en aislados estables y experiencia ≥ intermedio; nunca dos técnicas sobre el mismo ejercicio; nunca en barra libre pesada, con restricción activa ni en deload.
8. **Progresión conectada**: doble progresión del ancla alimentada por `lastPerformance` (ya se muestra "última vez"; `ProgressionEngine` existe y no se usa).

Invariantes que esto no toca y debe respetar: más tiempo no infla sin límite (cap por `[min,max]`), variación intencional nunca aleatoria, restricciones por encima de todo, el LLM no calcula nada.

---

## 6. Riesgos

- **Datos persistidos:** cambiar `SetPrescription`/`PlannedSet` (técnica) y `OnboardingProfile` (prioridades) rompe planes guardados si no hay `decodeIfPresent` con defaults y un fixture de versión anterior en tests. P0 dentro de cada historia.
- **Regenerar bloques existentes:** al desplegar un generador nuevo, el aviso `planUpdated` ya existe; conservar `blockID` y no tocar historial (`BlockPlanner` ya lo garantiza).
- **Seguridad:** las técnicas de intensidad deben pasar por `IntensityAdvisor` con los mismos bloqueadores que el dropset; una técnica nunca puede saltarse una restricción ni aplicarse con dolor moderado/alto (`PainFeedbackEngine`).
- **Sobre-ingeniería:** no añadir motores; conectar `HardTimeOptimizer`, `ProgressionEngine` y la ontología que ya existen. Medir el avance por rutinas distintas y usables, no por reglas nuevas.

---

## 7. Backlog propuesto (Fase B — Plan correcto)

Orden de ejecución: B001 → B002 → B003 → B004 → B005 → B006 → B007. B001 es el gate de entrada y de salida. Numeración `PR-B00x` provisional; al crearlas en Jira (proyecto SCRUM) se reemplaza por la clave real.

---

**PR-B001 — Test de caracterización: la rutina cambia con el perfil**
EPIC: EPIC-04 Planificación de bloque · Prioridad: P0 · Estado: READY · Dependencias: ninguna
Como PO, quiero un test que mida cuántas rutinas distintas genera el motor para una matriz de perfiles, para que el gate de Fase B sea verificable y no opinable.
Contexto: hoy 8 100 perfiles ⇒ 16 rutinas (simulación); el test debe fallar en `main` y pasar al cerrar B002–B005.
Criterios de aceptación:
- Dado el catálogo real y la matriz {días 2–7} × {variedad} × {objetivo} × {experiencia} × {fase} × {30, 45, 60, 90, 120 min}, cuando se genera el bloque para cada perfil, entonces el conjunto de ejercicios por sesión difiere entre: dos objetivos distintos con todo lo demás igual (fuerza vs hipertrofia), dos experiencias (novato vs avanzado), y dos duraciones (30 vs 90 min) en al menos el 80 % de los casos.
- Dado cualquier perfil, cuando se genera el bloque, entonces ningún ejercicio tiene menos de 2 series efectivas y el nº de ejercicios por sesión está en el rango de su duración (sección 5.4).
- Dado un perfil con 90 min, cuando se genera, entonces el total de series de la sesión es ≥ al de 60 min y ≤ al máximo del tier.
Invariantes afectados: variación intencional, más tiempo ≠ más volumen sin límite.
Tests requeridos: suite en `PRCoreTests` sobre `ExerciseCatalogLoader.loadBundled()`; el script `docs/product/sim-motor-rutinas.py` deja de ser necesario.
Fuera de alcance: cambiar el motor.
Riesgos: el test es lento (8 100 generaciones); limitar a una muestra determinista de ~200 perfiles.

---

**PR-B002 — Prioridades musculares del usuario y músculos completos**
EPIC: EPIC-03 Onboarding · Prioridad: P0 · Estado: READY · Dependencias: PR-B001
Como usuario, quiero elegir hasta 3 músculos a enfatizar para que el plan les dé más volumen y mejores posiciones.
Criterios de aceptación:
- Dado el onboarding, cuando llego al paso "Prioridades", entonces puedo elegir 0–3 músculos y el perfil persiste `priorities: [MusclePriority]`.
- Dado un perfil sin énfasis, cuando se genera el bloque, entonces los 8 grupos principales van a `.normal` y pantorrilla y core a `.maintain` (ambos aparecen en el plan).
- Dado un perfil con énfasis en hombros, cuando se genera, entonces hombros recibe tier `.emphasize`, más series semanales que el resto y su primer ejercicio va antes que cualquier no prioritario del mismo rol.
- Dado un perfil guardado sin el campo, cuando se decodifica, entonces carga con prioridades por defecto (fixture de versión anterior).
Invariantes afectados: ninguno nuevo.
Tests: `OnboardingTests`, `PlanPersistenceTests` (fixture antiguo), `BlockPlannerRealCatalogTests` (pantorrilla presente).
Fuera de alcance: `.specialize` (bodybuilding, fase posterior).
Riesgos: pantalla nueva de onboarding (UI); volumen total sube ~8 series/semana por pantorrilla+core y debe caber en el presupuesto de B003.

---

**PR-B003 — Presupuesto de volumen por tiempo y experiencia**
EPIC: EPIC-04 · Prioridad: P0 · Estado: READY · Dependencias: PR-B002
Como usuario, quiero que mis minutos y mi experiencia definan cuánto entreno para que 90 min no sea la misma sesión que 60 ni 30 min sea 8 ejercicios de 1 serie.
Criterios de aceptación:
- Dado minutos y objetivo, cuando se calcula el presupuesto, entonces `seriesPorSesión = floor((minutos − calentamiento) / costeMedioSerie(objetivo))` con constantes en una `EvidenceRule` versionada, nunca en el código.
- Dado un tier y experiencia, cuando se asigna volumen, entonces el valor está en `[min,max]` del tier, con novato en el mínimo, intermedio en el punto medio y avanzado/competitivo hacia el máximo, y capado por `presupuesto × días` repartido con prioridad a los tiers altos.
- Dado 3 días × 60 min hipertrofia intermedio, cuando se genera, entonces la sesión tiene 20–24 series; con 90 min, 26–30; con 30 min, 10–12 — y en ningún caso un ejercicio con <2 series.
- Dado 3 días × 180 min, cuando se genera, entonces las series no superan el máximo del tier (invariante "más tiempo no es más volumen").
Invariantes afectados: más tiempo no es más volumen (reinterpretado como cap, no como congelación).
Tests: `VolumeAllocatorTests` nuevos; reescribir `moreTimeDoesNotAddSets` como `moreTimeNeverExceedsTierMax`; `sessionFitsTheTime` se mantiene.
Fuera de alcance: aprendizaje de duración personal (ya existe EWMA, se conecta en B007).
Riesgos: cambia el volumen de todos los planes activos → aviso `planUpdated` y regeneración con mismo `blockID`.

---

**PR-B004 — Composición de sesión: rango de ejercicios y recorte por ejercicio**
EPIC: EPIC-04 · Prioridad: P0 · Estado: READY · Dependencias: PR-B003
Como usuario, quiero sesiones con un número sostenible de ejercicios y series útiles por ejercicio, para que ni 2 días signifique 16 ejercicios ni 6 días signifique 4.
Criterios de aceptación:
- Dado minutos, cuando se compone la sesión, entonces el nº de ejercicios está en el rango de la tabla (30 → 3–4, 45 → 4–5, 60 → 5–7, 90 → 7–9, ≥120 → 8–10) y cada ejercicio tiene ≥2 series (ideal 3–4).
- Dado que no cabe, cuando se recorta, entonces el orden es: quitar aislamientos de músculos `.maintain`/`.normal` → fusionar pares antagonistas compatibles en superserie (`CompatibleSuperset` de `HardTimeOptimizer`) → bajar series hasta 2 → sólo entonces quitar un ejercicio no prioritario más. Nunca 1 serie.
- Dado objetivo fuerza con 60 min, cuando se genera, entonces el ancla conserva ≥3 series y se recortan accesorios, no el ancla.
- Dado un músculo entrenado ≥2×/semana, cuando se reparten sus series, entonces el ancla aparece en ≥2 sesiones y las series por sesión difieren en ≤1 entre días (no "día 3 ligero").
Invariantes afectados: seguridad (volumen útil), simplicidad del modo entrenamiento.
Tests: `BlockPlannerRealCatalogTests` (rangos por duración, mínimo de series), `HardTimeOptimizerTests` integrado desde el planner.
Fuera de alcance: adaptación en vivo durante la sesión (Fase gym).
Riesgos: `trimToFit` desaparece; `tightTimeTrimsButKeepsEachExercise` cambia de semántica (recortar sí quita ejercicios) y hay que decirlo en el PR.

---

**PR-B005 — Selección por cobertura funcional, scoring y variación entre bloques**
EPIC: EPIC-04 · Prioridad: P0 · Estado: READY · Dependencias: PR-B004
Como usuario, quiero que el motor explore el catálogo según mi objetivo, experiencia, fase y equipo, para no recibir la misma rutina que todos.
Criterios de aceptación:
- Dado un músculo, cuando se asignan ejercicios para la semana, entonces se cubren sus slots funcionales (tabla por músculo en una `EvidenceRule`: p. ej. pecho = press horizontal + press inclinado + aislamiento) antes de repetir slot.
- Dado dos perfiles iguales salvo objetivo (fuerza vs hipertrofia), cuando se asigna, entonces el ancla de al menos 4 músculos difiere (fuerza prefiere barra/estable y compuesto; hipertrofia admite máquina/mancuerna).
- Dado experiencia novato vs avanzado, cuando se asigna, entonces el novato recibe anclas de estabilidad externa alta (máquina/Smith/prensa) y el avanzado barra libre donde el objetivo lo pida.
- Dado fase déficit, cuando se asigna, entonces el coste sistémico medio de la sesión es menor que en superávit con el mismo perfil (más máquinas/aislados, mismos slots).
- Dado el mismo perfil y dos `blockID` consecutivos, cuando se generan, entonces las anclas se conservan y ≥50 % de los rotables cambian; dado el mismo `blockID`, el resultado es idéntico (determinismo).
- Dado restricciones o equipo no disponible, cuando se asigna, entonces el scoring nunca elige un ejercicio prohibido ni con equipo ausente (allow-list sólo refina su propia restricción, Fase C).
Invariantes afectados: variación intencional nunca aleatoria; restricciones; mismo músculo ≠ ejercicio equivalente.
Tests: `ExerciseAssignmentTests` (scoring por eje), `BlockPlannerRealCatalogTests` (cobertura de slots), PR-B001 pasa.
Fuera de alcance: likes/dislikes del usuario (P1 posterior), especialización bodybuilding.
Riesgos: la ontología inferida por nombre (`pattern(name:)`) puede clasificar mal algunos ejercicios; medir cobertura de slots sobre los staples primero.

---

**PR-B006 — Técnicas de intensidad en la prescripción**
EPIC: EPIC-05 Intensidad y progresión · Prioridad: P1 · Estado: READY · Dependencias: PR-B005
Como usuario intermedio o avanzado, quiero que el plan use más de una forma de acercarme al fallo (top set/back-off, dropset, rest-pause, myo-reps, superserie antagonista, parciales alargadas) según ejercicio, tiempo y fase, para progresar sin alargar la sesión.
Criterios de aceptación:
- Dado `SetPrescription`, cuando se decodifica un plan anterior, entonces `technique` por defecto es `.straight` (fixture antiguo).
- Dado objetivo fuerza, cuando se prescribe el ancla, entonces usa `topSetBackoff` (top set a RIR 2 + back-offs −10 %) y nunca dropset.
- Dado hipertrofia, experiencia ≥ intermedio y un aislado estable al final de la sesión, cuando se prescribe, entonces la última serie lleva `dropSet` o `restPause` (uno, no ambos) y el coste de fatiga se suma en `FatigueInterference`.
- Dado presupuesto insuficiente, cuando se compone, entonces pares antagonistas compatibles se marcan `antagonistSuperset(pairID)` y el estimador descuenta el descanso compartido.
- Dado restricción activa, dolor moderado/alto o deload, cuando se prescribe, entonces la técnica es `.straight` (mismos bloqueadores que `IntensityAdvisor.dropset`).
- Dado el modo entrenamiento, cuando la serie tiene técnica, entonces la UI muestra una instrucción de una línea ("Dropset: baja 20–25 % y sigue al fallo") y el registro guarda la técnica realizada.
Invariantes afectados: dolor anula progresión; restricciones; el LLM no calcula.
Tests: `IntensityAdvisorTests` (matriz técnica × clase × experiencia × fase), `SetCompleterTests` (registro), UI test del modo entrenamiento.
Fuera de alcance: clusters, isométricos, pirámides (P2).
Riesgos: fatiga acumulada si se apilan técnicas; cap de 2 técnicas por sesión en la regla.

---

**PR-B007 — Calentamiento, series de aproximación y estimador honesto**
EPIC: EPIC-06 Tiempo · Prioridad: P1 · Estado: READY · Dependencias: PR-B003
Como usuario, quiero que el plan incluya calentamiento y aproximaciones en compuestos, para que "cabe en 60 min" sea verdad.
Criterios de aceptación:
- Dado un compuesto ancla, cuando se genera, entonces lleva 1–2 `PlannedSet.isWarmup` con `warmupMultiplier` y el estimador las cuenta.
- Dado una sesión, cuando se estima, entonces incluye un bloque fijo de calentamiento (constante versionada, 5–8 min) y el total usa el descanso del objetivo, no el mínimo.
- Dado historial con ≥10 muestras de un ejercicio, cuando se estima, entonces se usa el tiempo personal (EWMA ya implementado) y el resultado se muestra en "Hoy".
Tests: `DurationEstimatorTests`, integración `TodayPlanCoordinatorTests`.
Fuera de alcance: optimización en vivo.
Riesgos: baja el nº de series que cabe en 30 min; aceptable y coherente con B004.

---

## 8. Gate de salida de Fase B (propuesto)

- PR-B001 en verde con el motor real.
- `make ci` en verde; ningún test desactivado o debilitado sin nota en el PR.
- Revisión manual de 6 perfiles tipo en simulador: novato 3×45 full body, intermedio 4×60 U/L, avanzado 6×75 PPL, fuerza 3×60, déficit 5×45, énfasis hombros 4×60. Para cada uno: ≥5 ejercicios/sesión, ≥2 series/ejercicio, anclas presentes, pantorrilla y core presentes, duración estimada dentro de ±10 % de los minutos.
- Documentación, backlog y matriz de trazabilidad actualizados; ADR corto sobre "volumen por presupuesto y selección por cobertura".

---

## 9. Verificación honesta

- Ejecutado: lectura de código en `main`, simulación en Python sobre catálogo y staples reales, grep de referencias de motores.
- No ejecutado: `swift build`, `swift test`, `make ci`, ni ninguna vista en simulador (sin toolchain en esta sesión). Las cifras de minutos vienen de `DurationEstimator` reimplementado; los conjuntos de ejercicios siguen `ExerciseAssigner`+`BlockPlanner` línea por línea, pero son "no verificados por ejecución" hasta que PR-B001 lo confirme.
