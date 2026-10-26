# Estado y prioridades de Nucleus — 2026-10-25

**Fuentes:**
- Jira, proyecto SCRUM: las 66 issues, leídas hoy.
- `mvp-plan.md` y el código en `main` @ `abfc740`.
- La auditoría del motor de rutinas del 24 oct (`docs/product/auditoria-motor-rutinas-2026-10-24.md`).

Todo lo marcado como "verificado en código" lo revisé hoy en el repo, no solo en Jira.

## En una frase

Lo funcional del POC está hecho y en verde. El demo se atora en tres cosas:
- **Tu revisión:** 14 historias esperan en "Revisar".
- **El soporte del demo:** datos demo, guion y pruebas de flujos.
- **Dos huecos de restricciones que hay que cerrar antes:** un bug de seguridad latente (SCRUM-31) y la pantalla Perfil › Restricciones vacía.

Después del demo, lo más importante es el motor de rutinas (Fase B).

## 1. Cómo se priorizó

**MoSCoW, respecto al próximo hito, el demo del POC (SCRUM-180):**
- **Must:** sin esto el demo no se puede dar o rompe una regla de seguridad o de datos.
- **Should:** mejora mucho el demo o su credibilidad.
- **Could:** suma, pero se puede dejar.
- **Won't (por ahora):** va después del demo. Su orden lo da RICE.

**RICE = (Alcance × Impacto × Confianza) ÷ Esfuerzo:**

| Factor | Escala |
|---|---|
| Alcance (R) | 10 = toda persona en cada sesión · 8 = toda persona, algunas veces · 5 = la mitad · 3 = algunos perfiles · 1 = interno o casi nadie |
| Impacto (I) | 3 = seguridad, datos o "el demo no se puede dar" · 2 = alto · 1 = medio · 0.5 = bajo · 0.25 = mínimo |
| Confianza (C) | 1.0 = verificado en código o con tests · 0.8 = especificación clara · 0.5 = falta una decisión o hay incógnitas |
| Esfuerzo (E) | Días del agente, con tests: 0.25 · 0.5 · 1 · 2 · 3 · 5 · 8 · 13 |

**Regla del repo que manda sobre RICE (AGENTS §2 y §5):** integridad de datos > seguridad > plan correcto > flujo > lo demás. Un bug que salta una restricción es P0 y bloquea lo demás. Por eso SCRUM-31 va primero en el orden de ejecución aunque su RICE sea bajo.

**Cómo queda en Jira:**

- **Etiquetas:**
  - MoSCoW: `moscow-must`, `moscow-should`, `moscow-could` o `moscow-wont`.
  - Hito: `hito-demo`, `hito-1.0` o `hito-posterior`.
- **Prioridad de Jira** (combina MoSCoW con el hito):

| MoSCoW | Hito demo | Hito 1.0 | Posterior |
|---|---|---|---|
| Must | Highest | High | — |
| Should | High | Medium | — |
| Could | Medium | Low | — |
| Won't | — | — | Low |

- **Comentario de priorización** en cada issue abierta: su RICE (R, I, C, E y el puntaje), el orden y el porqué. En las épicas es una nota corta de MoSCoW.

---

## 2. ✅ Hecho

### 2.1 Finalizadas en Jira (23)

- [x] **Fase A, integridad de datos:**
  - [x] SCRUM-25 · Cerrar bien la sesión al terminar.
- [x] **POC, UX y producto (SCRUM-180):**
  - [x] SCRUM-186 · Resumen y exportar historial.
  - [x] SCRUM-193 · Loaders reales.
  - [x] SCRUM-194 · Paleta Iron Energy.
  - [x] SCRUM-195 · App en español.
  - [x] SCRUM-196 · Elegir días.
  - [x] SCRUM-197 · Ver mi semana.
  - [x] SCRUM-198 · "Sobre ti".
  - [x] SCRUM-199 · Identidad visual v2.
  - [x] SCRUM-200 · RIR y dropset.
- [x] **IA personalizada (SCRUM-201):**
  - [x] SCRUM-202 · Consentimiento.
  - [x] SCRUM-203 · Check-in de sueño.
  - [x] SCRUM-204 · Llave solo local.
  - [x] SCRUM-205 · Plan personalizado; la explicación de la IA ya se muestra (8 de 8).
  - [x] SCRUM-206 · Apple Salud.
- [x] **Feedback del stakeholder (SCRUM-207):**
  - [x] SCRUM-208 · Modo claro y cerrar sesión.
  - [x] SCRUM-209 · Restricciones por zona.
  - [x] SCRUM-210 · Cuestionario por experiencia.
  - [x] SCRUM-211 · Reordenar.
  - [x] SCRUM-212 · Saltar o dejar para después.
  - [x] SCRUM-213 · 4 KPIs y gráfica.

### 2.2 Hecho por el agente, esperando tu revisión: "Revisar" (14)

El código está en `main` y con `make ci` en verde. Falta que tú lo revises y lo pases a Finalizada. Donde dice 👤, falta además una prueba tuya en dispositivo.

| Issue | Qué es | Qué falta |
|---|---|---|
| SCRUM-23 | Ver y exportar todo mi historial | Revisión |
| SCRUM-24 | No perder el entrenamiento si la app se cierra | Revisión |
| SCRUM-26 | Recordar perfil y plan | Revisión |
| SCRUM-27 | Días correctos de la semana | Revisión |
| SCRUM-28 | Volumen real y sesión distinta por día | Revisión |
| SCRUM-29 | Ejercicios en orden correcto | Revisión |
| SCRUM-30 | Duración real y ajuste a mi tiempo | Revisión + 👤 sesión larga en dispositivo |
| SCRUM-181 | F-01 Inicio de sesión y cuestionario | Revisión |
| SCRUM-182 | F-02 Plan semanal correcto | Revisión |
| SCRUM-183 | F-03 Pantalla Hoy | Revisión |
| SCRUM-184 | F-04 Registrar series sin internet | Revisión + 👤 modo avión |
| SCRUM-185 | F-05 Retomar tras cerrar la app | Revisión + 👤 cierre forzado en iPhone |
| SCRUM-187 | F-07 Ajustar a mi tiempo | Revisión |
| SCRUM-189 | S-02 CI en GitHub | Revisión + 👤 proteger `main` |

**Otras pruebas 👤 abiertas:**
- Íconos y arranque en frío (SCRUM-199).
- Salud con datos reales en iPhone (SCRUM-206).
- Modo claro en dispositivo (SCRUM-208).

---

## 3. 🔄 En curso

| Issue | Estado real | Siguiente paso |
|---|---|---|
| SCRUM-190 · S-03 Pruebas de los flujos | `docs/poc/pruebas-flujos.md` escrito con 31 pruebas; unidad e integración de los 4 flujos en verde. Las pruebas de UI no corren desde la terminal por el entorno del simulador; el mismo fallo aparece en el commit de SCRUM-213, así que no es una regresión (seguimiento en SCRUM-217) | Tú las corres en Xcode y me pasas el resultado; luego commit y cierre del Bloque 10 |
| SCRUM-5 · Fase A (épica) | 1 finalizada y 3 en Revisar | Se cierra cuando revises SCRUM-23, 24 y 26 |
| SCRUM-180 · POC (épica) | En progreso desde hoy | Ver §4.1 |
| SCRUM-6 · Fase B (épica) | En progreso desde hoy: 4 en Revisar y 5 nuevas | Ver §4.2 |

---

## 4. 📋 Por hacer, priorizado

### 4.1 Para el demo del POC

| Orden | Issue | MoSCoW | R | I | C | E | RICE | Por qué |
|---|---|---|---|---|---|---|---|---|
| 1 | **SCRUM-31** · Mis restricciones nunca se saltan | **Must** (regla P0) | 3 | 3 | 1.0 | 3 | 3.0 | Verificado en código: en `ExerciseAssigner.isPermitted` el permiso de cualquier restricción gana antes de revisar las demás, y no ignora las resueltas. `RestrictionPolicyEngine` deja que el permiso de una anule el patrón prohibido de otra. Hoy ninguna pantalla crea permisos ni resuelve restricciones (está latente), pero se vuelve alcanzable con SCRUM-36 y con el agente |
| 2 | **SCRUM-216** · Perfil › Restricciones muestra las que declaré (solo lectura) | **Must** | 5 | 2 | 1.0 | 1 | 10 | Verificado en código: `ProfileView` abre la pantalla con `restrictions: []` y acciones vacías. Quien declaró una molestia ve la lista vacía. Sale en el demo |
| 3 | **SCRUM-188** · S-01 Ambiente demo | **Must** | 10 | 3 | 0.8 | 2 | 12 | Por hacer (aún no existe en el código): datos demo con `-PRDemoData` (perfil + 2 semanas, en un directorio aparte) e instrucciones. 👤 firma o TestFlight, instalar en iPhone y video de respaldo |
| 4 | **SCRUM-192** · S-05 Guion del demo | **Must** | 10 | 3 | 1.0 | 0.5 | 60 | Por hacer: escribir `docs/poc/guion-demo.md` (≤10 min) con los datos demo de SCRUM-188. 👤 ensayo |
| 5 | **SCRUM-190** · S-03 Cerrar pruebas de los flujos | **Must** | 10 | 2 | 0.8 | 1 | 16 | Falta: resultados de UI en Xcode + 👤 modo avión, cierre forzado y abrir el CSV y el JSON |
| — | 👤 Revisar las 14 historias de §2.2 | **Must** | — | — | — | — | — | Sin esfuerzo de desarrollo; es el cuello de botella para cerrar Fase A y el POC |
| 6 | **SCRUM-214** · PR-B001 Test de caracterización del motor | **Should** | 10 | 1 | 1.0 | 1 | 10 | Barato y sin cambiar el motor. Deja medido el problema de "misma rutina para todos" antes de las preguntas del demo |
| 7 | 👤 SCRUM-189 · Proteger `main` en GitHub | **Should** | 1 | 2 | 1.0 | 0.25 | 8 | Cierra S-02 |
| 8 | **SCRUM-217** · Entorno de pruebas de UI estable | **Should** | 1 | 2 | 0.5 | 1 | 1.0 | El simulador desde la terminal no deja tocar "Continuar" y `xcodebuild` se cuelga. Sin esto, `make test-ui` no es confiable |
| 9 | SCRUM-191 · S-04 GitHub–Jira | **Could** | 1 | 0.5 | 1.0 | 0.25 | 2 | La parte del agente ya está (regla de claves en AGENTS). 👤 instalar "GitHub for Jira" |

**Orden de ejecución propuesto:**
- **Agente:** 1 → 2 → 3 → 4 → cierre de 5 → 6.
- **Tú, en paralelo:** revisión de §2.2, pruebas de UI en Xcode, pruebas en dispositivo y proteger `main`.

### 4.2 Después del demo, camino a 1.0 (ordenado por RICE)

| Orden | Issue | MoSCoW 1.0 | R | I | C | E | RICE | Depende de |
|---|---|---|---|---|---|---|---|---|
| 1 | **SCRUM-40** · Migraciones seguras de datos guardados | Must | 10 | 3 | 0.8 | 5 | 4.8 | — (antes de cambiar modelos en la Fase B) |
| 2 | **SCRUM-218** · PR-B004 Composición de sesión: nunca 1 serie, rango de ejercicios por duración | Must | 10 | 2 | 0.8 | 5 | 3.2 | SCRUM-214 |
| 3 | **SCRUM-215** · PR-B002 Prioridades para todos los niveles + pantorrilla y core | Must | 10 | 1 | 0.8 | 3 | 2.7 | SCRUM-214 · validar el paso nuevo con el stakeholder |
| 4 | **SCRUM-39** · Consultar realmente las feature flags | Should | 10 | 1 | 0.8 | 3 | 2.7 | — |
| 5 | **SCRUM-32** · Una sola escala de dolor | Must (seguridad) | 3 | 3 | 0.8 | 3 | 2.4 | SCRUM-31 |
| 6 | **SCRUM-221** · Llave de IA en un backend propio | Must si la IA va en TestFlight; si no, Should | 10 | 2 | 0.8 | 8 | 2.0 | Decisión D2 |
| 7 | **SCRUM-219** · PR-B005 Selección por cobertura, scoring y variación entre bloques | Must | 10 | 3 | 0.5 | 8 | 1.9 | SCRUM-218 · SCRUM-37 |
| 8 | **SCRUM-37** · Clasificación del catálogo | Should | 10 | 1 | 0.8 | 5 | 1.6 | — (prerrequisito de calidad para SCRUM-219) |
| 9 | PR-B007 · Calentamiento y estimador honesto (se crea después de D1) | Could | 10 | 0.5 | 0.8 | 3 | 1.3 | — |
| 10 | **SCRUM-34** · UTF-8 en las respuestas en streaming | Could | 1 | 1 | 1.0 | 1 | 1.0 | — |
| 11 | **SCRUM-36** · Restricciones en Perfil completas (crear, editar, resolver) | Should | 3 | 2 | 0.8 | 5 | 0.96 | SCRUM-31 |
| 12 | PR-B003 · Volumen por tiempo y experiencia (se crea después de D1) | Should | 5 | 1 | 0.5 | 3 | 0.8 | **SCRUM-220 · Decisión D1** |
| 13 | PR-B006 · Técnicas de intensidad (se crea después de D1) | Could | 5 | 1 | 0.5 | 5 | 0.5 | SCRUM-219 |

**SCRUM-220 · Decisión D1 (ADR)** es Must para 1.0 (High). No tiene RICE: es una decisión, no desarrollo, y desbloquea PR-B003.

**Won't por ahora** (se reactivan con su fase):

| Issue | R | I | C | E | RICE | Se reactiva |
|---|---|---|---|---|---|---|
| SCRUM-35 · Negar el ritmo cardiaco | 1 | 3 | 0.8 | 3 | 0.8 | P0 en cuanto empiece la Fase F (HealthKit real) |
| SCRUM-38 · Un solo cliente de IA | 1 | 0.5 | 1.0 | 2 | 0.25 | Junto con SCRUM-221 |
| SCRUM-33 · Agente que entiende o pregunta | 1 | 2 | 0.5 | 5 | 0.2 | Fase I |

**Épicas:**

| Épica | MoSCoW · hito | Prioridad | Nota |
|---|---|---|---|
| SCRUM-180 · POC | Must · demo | Highest | En progreso |
| SCRUM-5 · Fase A, integridad | Must · demo | Highest | Se cierra con tu revisión |
| SCRUM-7 · Fase C, restricciones | Must · demo | Highest | Por SCRUM-31 |
| SCRUM-6 · Fase B, plan correcto | Must · 1.0 | High | En progreso |
| SCRUM-9 · Deuda de integración | Must · 1.0 | High | |
| SCRUM-15 · Fase J, release 1.0 | Must · 1.0 | High | Al final, como gate |
| SCRUM-10 · Fase E, gimnasio real | Should · 1.0 | Medium | Historias por escribir |
| SCRUM-11 · Fase F, HealthKit real | Should · 1.0 | Medium | Historias por escribir |
| SCRUM-12 · Fase G, Apple Watch | Could · 1.0 | Low | |
| SCRUM-13 · Fase H, pestañas | Could · 1.0 | Low | Casi cubierta por SCRUM-197, 208 y 213; revisar su alcance o cerrarla |
| SCRUM-14 · Fase I, coach conversacional | Could · 1.0 | Low | |
| SCRUM-8 · Fase D, capa agéntica | Won't · posterior | Low | Va con la Fase I |
| SCRUM-16 · Fase K, después de 1.0 | Won't · posterior | Low | |

---

## 5. Desfases entre Jira y la realidad

Todos se corrigieron el 25 oct (ver §7).

| Issue | En Jira | En realidad | Ajuste aplicado |
|---|---|---|---|
| SCRUM-6 · Fase B (épica) | Tareas por hacer | 4 historias en Revisar y 2 nuevas | ✅ En progreso |
| SCRUM-180 · POC (épica) | Tareas por hacer | 9 finalizadas, 7 en Revisar, 1 en curso y 3 por hacer | ✅ En progreso |
| SCRUM-31 | Etiqueta BLOCKED (por PR-0106) | PR-0106 = SCRUM-28, ya hecha; el bug sigue en el código | ✅ BLOCKED quitada y evidencia comentada |
| SCRUM-36 | "La pantalla tiene funcionalidad parcial" | La pantalla no recibe datos: lista vacía y acciones vacías | ✅ Comentada; la parte de solo lectura pasó a SCRUM-216 |
| SCRUM-190 | En progreso | Bloqueada en la parte de UI por el entorno | ✅ Estado comentado; el entorno sigue en SCRUM-217 |
| Sin issue | — | Llave de IA a backend · entorno de UI · PR-B004 y B005 · decisión "más tiempo / más volumen" | ✅ Creadas: SCRUM-216 a 221. PR-B003, B006 y B007 esperan D1 |

Fuera de Jira: tu checkout `/Users/jalcon/Documents/Nucleus` va **15 commits atrás** de `origin/main`, y la auditoría del motor está ahí sin commitear.

---

## 6. Decisiones que necesito de ti

- **D1 · "Más tiempo no es más volumen"** (SCRUM-220). ¿Se queda como está (más minutos nunca suben series, como en SCRUM-28/30) o se reinterpreta como "nunca pasar del máximo del rango" (PR-B003 de la auditoría)? Pide una nota de decisión (ADR) y reescribir tests.
- **D2 · ¿La IA va en TestFlight?** Si sí, la llave tiene que vivir en un backend antes (hoy Release no la usa: la IA queda apagada).
- **D3 · Paso de prioridades para novatos (SCRUM-215).** Agrega un paso a su cuestionario; validarlo con el stakeholder.
- **D4 · Ajustes de la IA.** La IA nunca propone énfasis ni sustituciones: el flujo funciona, pero no cambia nada. ¿Así está bien para el POC?
- **D5 · SCRUM-31 antes que el soporte del demo.** La regla del repo lo pide. Confírmalo si estás de acuerdo.

---

## 7. Cambios aplicados en Jira (25 oct, aprobados por Jesús)

1. **Estados:**
   - SCRUM-6 y SCRUM-180 → En progreso.
   - BLOCKED quitada de SCRUM-31. SCRUM-32 la conserva, porque depende de SCRUM-31.
2. **Comentarios con evidencia** en SCRUM-31, SCRUM-36 y SCRUM-190.
3. **Creadas:**

| Clave | Qué es | Padre | MoSCoW · hito | Prioridad |
|---|---|---|---|---|
| SCRUM-216 | Perfil › Restricciones muestra las declaradas (solo lectura) | SCRUM-180 | Must · demo | Highest |
| SCRUM-217 | Entorno de pruebas de UI estable | SCRUM-180 | Should · demo | High |
| SCRUM-218 | PR-B004 · Composición de sesión | SCRUM-6 | Must · 1.0 | High |
| SCRUM-219 | PR-B005 · Selección por cobertura, scoring y variación | SCRUM-6 | Must · 1.0 | High |
| SCRUM-220 | Decisión D1: más tiempo / más volumen (ADR) | SCRUM-6 | Must · 1.0 | High |
| SCRUM-221 | Llave de IA en un backend propio | SCRUM-15 | Should · 1.0 (Must si D2 = sí) | Medium |

   PR-B003, B006 y B007 se crean después de D1.

4. **Prioridad de cada issue abierta y de las 13 épicas:**
   - Etiquetas MoSCoW e hito, y prioridad de Jira según la tabla de §1.
   - Comentario "Priorización 2026-10-25" con el RICE en 17 issues y una nota MoSCoW en las 13 épicas.
   - SCRUM-214 y SCRUM-215 quedan priorizadas pero **sin lanzar**, hasta que Jesús lo indique.
