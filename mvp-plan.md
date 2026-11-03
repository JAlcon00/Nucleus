# mvp-plan.md — Tablero activo de Nucleus

> **Fuente:** Jira `creadevs.atlassian.net`, proyecto **SCRUM** (épica del POC: SCRUM-180).
> **Actualizado:** 2026-11-02 (PR-X005: el tablero queda en menos de 150 líneas).
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
| SCRUM-35 | En un dispositivo físico, cuando exista HealthKit real (EPIC-25, Fase F). |

## 3. Lo que sigue

- **Antes de TestFlight:** mover la llave de la IA a un backend. La historia está por crear (SCRUM-201, SCRUM-204).
- **Fases de 1.0, sin historias escritas todavía** (prioridad MoSCoW del 2026-10-25, `docs/product/estado-y-prioridades-2026-10-25.md`):
  - Fase E, gimnasio real (SCRUM-10, Should);
  - Fase F, HealthKit real (SCRUM-11, Should);
  - Fase G, Apple Watch (SCRUM-12, Could);
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

- (ninguna todavía)

---

**Definition of Done** de cada historia:
- cumple los criterios;
- tiene pruebas unitarias;
- tiene una prueba de integración con `AppEnvironment` y la infraestructura real compartida, en un directorio temporal;
- `make ci`, el smoke y los recorridos que toca están en verde;
- funciona sin internet;
- no viola invariantes;
- este tablero quedó actualizado en el mismo PR.
