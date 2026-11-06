# mvp-plan.md — Tablero activo de Nucleus

> **Fuente:** Jira `creadevs.atlassian.net`, proyecto **SCRUM** (épica del POC: SCRUM-180).
> **Actualizado:** 2026-11-06 (Fase G programada en la rama `SCRUM-12-fase-g`; falta el gate en dispositivo, SCRUM-261).
> **Lo terminado** hasta el 2026-11-02 está congelado en [`docs/archivo/mvp-plan-2026-10.md`](docs/archivo/mvp-plan-2026-10.md): el POC (F-01 a F-07, bloques 0 a 13), UX, IA, feedback y las Fases B, C y D, más la deuda. Ahí siguen la evidencia y los criterios de cada historia. No se edita: se cita.
> **Regla:** mientras quede un `[ ]` en la sección 1, **no se trabaja ninguna historia P1/P2 de `backlog.md`**.

---

## 0. Cómo usar este tablero

1. **Ciclo de cada historia:** `.agents/skills/siguiente-historia/SKILL.md`, que en Claude Code es `/siguiente-historia`.
2. **Qué tomar:** la primera historia de la sección 3 que esté READY y tenga sus dependencias en `main`.
3. **Qué guarda este archivo:** sólo lo abierto (sección 1), la cola 👤 (secciones 1 y 2) y lo que sigue (sección 3).
   - Una historia nueva entra aquí con su resumen y su estado.
   - Al terminarla, su detalle y su `Evidencia:` van al archivo del mes en `docs/archivo/`, y aquí queda una línea en la sección 4.
4. **Estado en el mismo PR:** la historia actualiza este archivo en su propio PR. No hay PR de cierre (plan de aceleración §5).
5. **Cuándo marcar `[x]`:** un criterio se marca sólo cuando su prueba pasó en `make ci`. Una prueba 👤 se marca sólo cuando Jesús la confirmó.
6. **Commits y ramas:** la clave de Jira va al inicio, por ejemplo `SCRUM-23 (P0): …`. La rama va en mayúsculas, `SCRUM-23-export-historial`, para que coincida con el permiso de push de AGENTS.md §6.
7. **IDs:** los `PR-01xx` de Jira **no son** los `PR-01xx` de `backlog.md`. Aquí y en los commits se usa siempre `SCRUM-XX`.
8. **Cola 👤:** son los pendientes de Jesús de las secciones 1 y 2. Si llegan a 5 o más, el agente no abre un epic nuevo (runbook, paso 0).

---

## 1. Abierto: lo que falta del POC

Las partes del agente están hechas en todas. Falta lo 👤.

- [ ] **SCRUM-190 · Pruebas de los flujos (S-03):** correr las pruebas manuales P1.8, P3.1, P3.7 y P4.7 de `docs/poc/pruebas-flujos.md` (cierre forzado, modo avión y iPhone real) y anotar pasó o falló, con fecha.
- [ ] **SCRUM-188 · Ambiente demo (S-01):**
  - firma de desarrollo o TestFlight (requiere cuenta de Apple Developer);
  - instalar en el iPhone;
  - grabar el video de respaldo en el simulador.
- [ ] **SCRUM-191 · GitHub–Jira (S-04):** instalar la app "GitHub for Jira" en `creadevs` y conectarla a `JAlcon00/Nucleus`.
  - Al instalarla, revisar si enlaza la rama en minúsculas `scrum-193-198-cierre-huecos`. Desde el 2026-11-02 las ramas nuevas ya van en mayúsculas.
  - Opcional: una automatización que mueva la historia a **TEST** al fusionar el PR.
- [ ] **SCRUM-192 · Presentación con demo (S-05):** ensayar al menos una vez con el demo real (`docs/poc/guion-demo.md`).
- [ ] **SCRUM-199 · Identidad visual:** revisar el ícono oscuro y tintado, el arranque en frío en iPhone SE y Pro Max, y el ícono del Watch.
- [ ] **SCRUM-201 · IA personalizada:** probar la IA real con la llave en `.env` (simulador) y Salud en un iPhone físico con datos reales.

## 2. Verificaciones 👤 pendientes (no bloquean)

Son de historias ya finalizadas en Jira; casi todas se hacen en una sola sesión con el iPhone. La única casilla, la de SCRUM-227, viene así del plan anterior.

| Historia | Qué revisar |
|---|---|
| SCRUM-23 | En el simulador, hacer 2 entrenamientos y en Export contar las sesiones y las filas del CSV. |
| SCRUM-27 | Cambiar la fecha del simulador a lunes y a domingo y revisar Hoy. |
| SCRUM-24 | Cierre forzado desde el selector de apps, en simulador y en iPhone, también en modo avión. |
| SCRUM-26 | Instalar, completar el cuestionario, cerrar y reabrir, también en modo avión. |
| SCRUM-28 | Generar planes de 2, 3, 4 y 6 días y revisar las series por sesión. |
| SCRUM-29 | La hoja "¿Por qué este orden?" de Hoy en el dispositivo. |
| SCRUM-30 | Una sesión larga en el dispositivo. |
| Asignación de ejercicios (2026-10-21) | Que las rutinas generadas con la lista curada (`exercise-staples.json`) parezcan razonables. |
| Bloque 0 | La calidad de los 678 nombres de ejercicios en español. |
| SCRUM-193 a 198 (UX) | VoiceOver real; sol directo; Liquid Glass del tab bar con Reduce Transparency e Increase Contrast, y la transparencia de iOS 27 en ambos extremos; layout en un iPhone pequeño. |
| SCRUM-222 | Hoy con "¿Cómo dormiste?" en un iPhone real, chico y grande. |
| SCRUM-40 | Actualizar la app en un iPhone con datos reales: el historial, el plan y Progreso se ven igual. |
| SCRUM-218 | El plan regenerado y el aviso "plan actualizado" en el iPhone. |
| SCRUM-32 | Reportar cada nivel de dolor y revisar la recomendación. Actualizar la app con entrenamientos guardados y revisar que el historial se vea igual. |
| SCRUM-215 | El paso nuevo del cuestionario como principiante, en claro y oscuro y con letra grande. |
| SCRUM-226 | Reportar cada nivel en el iPhone; legibilidad con Liquid Glass, Reduce Transparency e Increase Contrast; el háptico. |
| SCRUM-36 | En el iPhone, agregar, editar y resolver una restricción, con letra grande, Reduce Transparency e Increase Contrast. |
| SCRUM-227 | [ ] El cuestionario ya no dice "Más tiempo no suma series": verlo en el paso de minutos. |
| SCRUM-224 | Un entrenamiento con superset en el iPhone, con letra grande y Reduce Transparency. |
| SCRUM-35 | En un dispositivo físico, con HealthKit real: va en el gate SCRUM-251. |
| SCRUM-262 | `make install-iphone` en el iPhone: abre desde el ícono sin inicio de sesión, sigue igual tras cierre forzado, y al vencer el perfil renueva sin borrar datos. |
| SCRUM-248 | La tarjeta de Salud en el iPhone con letra grande, claro y oscuro, y VoiceOver. |
| SCRUM-241 | Con la IA real (SCRUM-201), un plan de 30 min con superset: si la IA cambia un ejercicio del par, Hoy y "Por qué tu plan es así" nombran al sustituto. |
| SCRUM-240 | Con la IA real (SCRUM-201), que cada ejercicio que cambie en el plan haga el mismo movimiento que el original. |
| SCRUM-233 | En el iPhone: en el descanso "Máquina ocupada" está sobre "Sigue: X"; con letra grande no tapa "Completar serie" y el aviso dice dónde quedó el ejercicio. |
| SCRUM-234 | En el iPhone, la hoja de sustitutos con una mano, en claro y oscuro, con Reduce Transparency e Increase Contrast. |
| SCRUM-235 | Perfil › Mi gimnasio con VoiceOver y letra grande; renombrar en el iPhone. |
| SCRUM-236 | Marcar "No hay esta máquina aquí" en un gimnasio real, ver la nota en Hoy y en Semana, y quitarla desde Perfil. |
| SCRUM-237 | En el iPhone, que la etiqueta "Tu último peso en esta máquina" se lea entre series, y medir cuánto tarda en abrir el entrenamiento con historial real. |
| SCRUM-238 | Dos gimnasios en el iPhone: "En: Oficina" legible en Hoy con Reduce Transparency e Increase Contrast; VoiceOver dice "Gimnasio activo: Oficina"; letra grande sin cortes y áreas de toque de 44 × 44 pt en Perfil. |

## 3. Lo que sigue

**Fase E · gimnasio real (SCRUM-10, Should): en `main` por el PR #38 desde el 2026-11-05.**
- **Decisiones DE-1 a DE-4:** en SCRUM-231. **DE-5** (planes guardados que dejan de cumplir una regla nueva): en SCRUM-239.
- **Excepción de Jesús (2026-11-05):** toda la Fase E se trabajó en una rama y un PR, un commit por historia, aunque la cola 👤 pasa de 5 y el runbook se detiene en el paso 0. Antes ya había autorizado SCRUM-232 y SCRUM-240 por no agregar pantallas. Las verificaciones de la sección 2 siguen pendientes.

**Fase F · HealthKit real (SCRUM-11, Should): programada en el PR #42, a la espera de Jesús.**
- **Decisiones DF-1 a DF-5:** en SCRUM-242. **Excepción de Jesús (2026-11-05):** toda la fase en una rama y un PR, un commit por historia, con la cola 👤 sobre 5.
- **Carril:** 🟡 amarillo (`Health*.swift`, `LocalPersistence.swift`, `Makefile`, `scripts/`). Se fusiona con merge commit, no squash.
- **Gate:** SCRUM-251, 👤 en iPhone y reloj, con `make install-iphone`. `health.workouts.enabled` sigue apagado hasta pasarlo; sólo el build de prueba lo enciende.

**Fase G · Apple Watch (SCRUM-12, Could): programada en el PR #41, a la espera de Jesús.**
- **Decisiones DG-1 a DG-5:** en SCRUM-243. **Excepción de Jesús (2026-11-05):** toda la fase en una rama, antes del gate de F y con la cola 👤 sobre 5.
- **SCRUM-258:** sus dos criterios pendientes entran en el PR #42: el iPhone no escribe si `healthRecording.watchOwnsHealthWorkout`, y se muestra esa energía.
- **Gate:** SCRUM-261, 👤 en iPhone y reloj. `watch.health_session.enabled` sigue apagada hasta pasarlo.

- **Antes de TestFlight:** mover la llave de la IA a un backend. La historia está por crear (SCRUM-201, SCRUM-204).
- **Fases de 1.0, sin historias escritas todavía** (prioridad MoSCoW del 2026-10-25, `docs/product/estado-y-prioridades-2026-10-25.md`):
  - Fase H, pestañas (SCRUM-13, Could): casi cubierta por SCRUM-197, 208 y 213, así que hay que revisar su alcance o cerrarla;
  - Fase I, coach conversacional (SCRUM-14, Could);
  - Fase J, release 1.0 (SCRUM-15, Must), que es el gate final.

  Para que el agente las tome, cada historia necesita la Definition of Ready (plan de aceleración §6) y un epic que Jesús autorizó.
- **Borradores, todavía no READY** (ideas de openGym; su código es AGPL-3.0 y no se copia):
  - **SCRUM-229 · PR-H001 Mapa muscular** (Should propuesto, Fase H): un mapa del cuerpo con MuscleMap (MIT) en Hoy, el detalle del día y Progreso. El conteo va en PRDomain, el mapa siempre lleva lista en texto y no entra en el entrenamiento activo.
  - **SCRUM-230 · PR-K001 Importar historial de Strong, Hevy y FitNotes** (Could propuesto, Fase K, después de 1.0):
    - importa el CSV con vista previa, sin duplicar, todo o nada y deshacible;
    - tiene 3 decisiones de Jesús pendientes;
    - 👤 hacen falta exportaciones reales anonimizadas.

  Las dos dependen de SCRUM-37 y SCRUM-213, que ya están en `main`. El detalle está en Jira y en el archivo.

## 4. Terminado desde el archivo

Una línea por historia terminada después del 2026-11-02: `SCRUM-XX · título · PR #N · fecha`. El detalle va en `docs/archivo/`.

- SCRUM-241 · PR-E009 Cambiar un ejercicio con IA no deshace su superset · PR #35 · 2026-11-03 ([detalle](docs/archivo/mvp-plan-2026-11.md#scrum-241--pr-e009-cambiar-un-ejercicio-con-ia-no-deshace-su-superset))
- SCRUM-232 · PR-E001 Sustituto equivalente de verdad (motor) · PR #36 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#scrum-232--pr-e001-sustituto-equivalente-de-verdad-motor))
- SCRUM-240 · PR-E008 La IA sólo propone sustitutos equivalentes de verdad · PR #37 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#scrum-240--pr-e008-la-ia-sólo-propone-sustitutos-equivalentes-de-verdad))
- SCRUM-235 · PR-E004 Mi gimnasio: el gimnasio activo se guarda por usuario · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-233 · PR-E002 Máquina ocupada: adelantar sin romper la sesión · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-234 · PR-E003 Sustituto equivalente durante el entrenamiento · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-237 · PR-E006 Mis cargas por máquina concreta · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-236 · PR-E005 "No hay esta máquina aquí", recordado y reversible · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-238 · PR-E007 Varios gimnasios · PR #38 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-e-en-un-solo-pr-pr-38))
- SCRUM-245 · PR-F002 La energía del mismo entrenamiento se cuenta una vez (motor) · PR #40 · 2026-11-05 ([detalle](docs/archivo/mvp-plan-2026-11.md#scrum-245--pr-f002-la-energía-del-mismo-entrenamiento-se-cuenta-una-vez-motor))
- SCRUM-252 · PR-G001 El reloj se instala con la app · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-253 · PR-G002 Qué le dice el iPhone al reloj · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-254 · PR-G003 Sincronización que no pierde series · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-255 · PR-G004 Puente iPhone ⇄ reloj · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-256 · PR-G005 El reloj guarda primero · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-257 · PR-G006 Entrenar desde el reloj · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-259 · PR-G008 Pausar y terminar desde el reloj · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-260 · PR-G009 Reportar dolor desde el reloj · PR #41 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-g-en-un-solo-pr))
- SCRUM-262 · PR-F009 Build de prueba para iPhone con cuenta gratuita · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-244 · PR-F001 Permisos de Salud reales · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-246 · PR-F003 Cola de escritura a Salud · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-247 · PR-F004 Guardar en Salud de verdad · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-248 · PR-F005 Pedir permiso en el momento correcto · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-249 · PR-F006 Leer entrenamientos externos · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))
- SCRUM-250 · PR-F007 Ver la energía una sola vez · PR #42 · 2026-11-06 ([detalle](docs/archivo/mvp-plan-2026-11.md#fase-f-en-un-solo-pr-pr-42))

---

**Definition of Done** de cada historia:
- cumple los criterios;
- tiene pruebas unitarias;
- tiene una prueba de integración con `AppEnvironment` y la infraestructura real compartida, en un directorio temporal;
- `make ci`, el smoke y los recorridos que toca están en verde;
- funciona sin internet;
- no viola invariantes;
- este tablero quedó actualizado en el mismo PR.
