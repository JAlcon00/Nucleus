# ADR-0004 — ¿Más tiempo puede dar más series? (decisión D1)

- **Fecha:** 2026-10-30
- **Estado:** Aceptado: opción B, decidida por Jesús (PO) el 2026-10-30 en SCRUM-220.
- **Historia:** SCRUM-220 · Decisión D1. Desbloquea PR-B003 y fija el criterio pendiente de PR-B004 (SCRUM-218).
- **Ámbito:** volumen semanal por músculo (`VolumeAllocator`, `VolumeDefaults`) y composición de sesión (`BlockPlanner`).

---

## Contexto

La regla del producto es "más tiempo no es más volumen". Hoy el motor la cumple de la forma más estricta:

- **El volumen es siempre el mínimo del rango.** `VolumeAllocator.representativeSets` devuelve `range.lowerBound` (auditoría, H2). Los rangos de `VolumeDefaults` (regla `volume.weeklySetsPerMuscle` v1) son:
  - mantener: 4–6 series por semana;
  - normal: 8–12;
  - enfatizar: 12–16;
  - especializar: 16–20.
- **Sin énfasis, todos reciben 72 series por semana** (8 músculos × 8, más pantorrilla y core × 4). Da igual el nivel, los días o los minutos.
- **El tiempo sólo recorta.** La composición de SCRUM-218 baja series o quita ejercicios si no caben, pero nunca agrega.
- **Lo fijan estas pruebas:**
  - `BlockPlannerRealCatalogTests.moreTimeDoesNotAddSets` (con 180 min, las mismas series que con 90);
  - `SessionTimeFitTests.extraTimeNeverAddsVolume` (ajuste del día);
  - el texto del cuestionario: "Más tiempo no suma series".

### Lo que se mide hoy

Motor real con el catálogo real, el 2026-10-30, sobre `main` `dd91a49`. Son 15 perfiles por fila: 2 a 6 días × novato, intermedio y avanzado, en mantenimiento. "Uso del tiempo" es lo que el estimador calcula para la sesión entre los minutos elegidos.

| Objetivo y minutos | Series por semana | Uso del tiempo (medio / mínimo) | Sesiones bajo el mínimo de ejercicios | Sin pantorrilla o core |
|---|---|---|---|---|
| Hipertrofia 30 | 24–68 | 93 % / 65 % | 0 de 60 | 8 de 15 |
| Hipertrofia 60 | 48–72 | 65 % / 40 % | 0 de 60 | 3 de 15 |
| Hipertrofia 90 | 56–72 | 46 % / 27 % | 24 de 60 | 0 de 15 |
| Hipertrofia 120 | 56–72 | 35 % / 20 % | 24 de 60 | 0 de 15 |
| Fuerza 60 | 36–72 | 88 % / 65 % | 1 de 60 | 5 de 15 |
| Fuerza 90 | 42–72 | 69 % / 43 % | 24 de 60 | 3 de 15 |
| Fuerza 120 | 56–72 | 56 % / 32 % | 24 de 60 | 0 de 15 |

**En palabras simples:**
- quien elige 90 o 120 minutos recibe sesiones que usan entre un quinto y la mitad de ese tiempo, iguales a las de 60;
- con 90 o 120 minutos, 4 de cada 10 sesiones quedan bajo el mínimo de ejercicios de su duración (SCRUM-218);
- un novato y un avanzado reciben el mismo volumen.

## Opciones

### A · Se queda como está

Más minutos nunca suben las series. El volumen es el mínimo del rango para todos.

- **A favor:**
  - es lo más simple y conservador;
  - no cambia ningún plan ni ninguna prueba;
  - menos riesgo de fatiga.
- **En contra:**
  - con 90–120 min la sesión dura una fracción del tiempo elegido ("tengo 90 min y la app me da 30");
  - el nivel no cambia el volumen: un avanzado entrena como un novato;
  - el mínimo de ejercicios de SCRUM-218 se queda sin cumplir en sesiones largas.
- **Qué se hace:**
  - se descarta PR-B003;
  - en SCRUM-218, "el mínimo del rango se cumple sólo si el volumen alcanza" queda como regla permanente;
  - el tiempo sobrante sigue siendo movilidad o cardio.

### B · El volumen sale de la experiencia; el tiempo sólo pone el techo (recomendada)

Las series semanales de cada músculo se eligen **dentro del rango de su nivel de prioridad** según la experiencia:
- novato: el mínimo;
- principiante: un cuarto del rango;
- intermedio: la mitad;
- avanzado y competitivo: el máximo.

Después se recortan a lo que cabe en los minutos, como ya pasa hoy. **Nunca pasan del máximo del rango**, aunque sobre tiempo.

- **El invariante se reescribe así:** "Más tiempo no es más volumen **por sí solo**: el volumen lo marcan la experiencia y la evidencia; el tiempo sólo lo limita". Es lo que ya dice `swift-elite-coach` ("more time != more volume automatically").
- **Volumen sin énfasis:** novato 72, intermedio 90 y avanzado 108 series por semana, antes del recorte por tiempo.
- **Estimado** con el mismo costo por serie del estimador (2.5 min en hipertrofia y 4 en fuerza), no con el motor:

  | | 60 min | 90 min | 120 min |
  |---|---|---|---|
  | Hipertrofia, uso medio del tiempo | A 77 % → B 85 % | A 58 % → B 67 % | A 43 % → B 53 % |
  | Fuerza, uso medio del tiempo | A 95 % → B 98 % | A 80 % → B 88 % | A 65 % → B 75 % |

  Las sesiones largas siguen sin llenarse con muchos días por semana, porque el máximo del rango manda. Las sesiones bajo el mínimo de ejercicios bajarían; falta medirlo con el motor.
- **A favor:**
  - el nivel cambia el volumen, como pide la evidencia: quien entrena hace más tiempo responde a más series, con rendimientos decrecientes; quien empieza progresa con poco;
  - el tiempo elegido se aprovecha más, sin inflar sin límite;
  - destraba PR-B003 y el mínimo de SCRUM-218.
- **En contra:**
  - los planes guardados de intermedios y avanzados se regeneran con más series: sesiones más largas (generador 7 → 8, con el aviso "plan actualizado");
  - más trabajo: una historia (PR-B003) y pruebas que reescribir.
- **Qué cambia en el código:**
  - `VolumeDefaults` v2 agrega la posición dentro del rango por experiencia, como parámetros versionados, sin números en el código;
  - `VolumeAllocator` recibe la experiencia;
  - `BlockPlanner` se la pasa;
  - el recorte por tiempo de SCRUM-218 se queda igual;
  - `StoredPlan.currentGeneratorVersion` 7 → 8.
- **Qué pruebas cambian:**
  - `moreTimeDoesNotAddSets` pasa a ser `moreTimeNeverExceedsTierMax` (con 180 min nunca se pasa del máximo) más "con 90 min, al menos lo de 60";
  - `weeklyVolumeEqualsTarget`, `sessionFitsTheTime` y `testTodaySessionHasRealisticVolume` se quedan;
  - `SessionCompositionTests` (el tope de ejercicios por duración) se queda;
  - **el ajuste del día no cambia:** "Ajustar a mi tiempo" sólo recorta, nunca agrega series, así que `extraTimeNeverAddsVolume` y los textos de SCRUM-30 se quedan;
  - el texto del cuestionario "Más tiempo no suma series" cambia a algo como "Ajustamos cuántas series y ejercicios caben, sin pasar lo que tu nivel aguanta".

### Lo que esta decisión no cubre

- **Los valores de los rangos.** El rango normal es de 8 a 12 series por semana, conservador frente a lo que suele recomendarse para personas entrenadas. Revisarlo es otra decisión (sería D1b), con su propia evidencia.
- **La fase:** si el déficit debe bajar el volumen. Hoy no lo hace.
- **El ajuste del día ("Ajustar a mi tiempo"):** sigue sólo recortando, con A o con B.

## Recomendación

**B.** "Más tiempo no es más volumen" protege contra inflar sin límite, y B lo sigue cumpliendo con el tope del rango. Lo que corrige es que hoy el nivel no cuenta y que las sesiones largas usan menos de la mitad del tiempo elegido. Si se prefiere ir con cuidado, B se puede soltar en dos pasos:
1. sólo la experiencia (intermedio y avanzado), con el mismo tope;
2. revisar los rangos aparte (D1b).

## Decisión

**B**, decidida por Jesús (PO) el 2026-10-30.

**El volumen semanal de cada músculo lo marca la experiencia dentro del rango de su nivel de prioridad:**
- novato: el mínimo;
- principiante: un cuarto del rango;
- intermedio: la mitad;
- avanzado y competitivo: el máximo.

**Los minutos sólo lo recortan:** la composición de SCRUM-218 se queda igual, y nunca se pasa del máximo del rango.

**El porqué:** "más tiempo no es más volumen" protege contra inflar sin límite, y el tope del rango lo sigue cumpliendo. Hoy el nivel no cuenta y las sesiones largas usan menos de la mitad del tiempo elegido.

Consecuencias:
- **`promptMaster`:** su redacción ya es compatible ("No aumentar volumen **sólo** por más tiempo disponible", RN-002, y "sets adicionales sólo dentro de límites del volumen semanal", §11.3). RN-002 agrega una referencia a este ADR. `AGENTS.md` no lo menciona.
- **PR-B003:** se creó como SCRUM-227 con los criterios de la opción B. Ahí se reescriben las pruebas que se listan arriba y el generador sube de 7 a 8.
- **"Ajustar a mi tiempo"** (SCRUM-30) sigue sólo recortando.
- **Los valores de los rangos** (D1b) y **la fase** quedan para decisiones aparte.
