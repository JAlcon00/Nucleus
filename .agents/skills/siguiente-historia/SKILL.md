---
name: siguiente-historia
description: Ciclo único para llevar una historia de Nucleus de READY a main (elegir, rama, TDD, make test, make ci, smoke, PR, auto-merge si es carril verde, vigilar el CI y reportar). Úsala cuando Jesús diga "siguiente historia", "continúa con el epic" o invoque /siguiente-historia, y antes de empezar cualquier historia SCRUM-XX.
---

# Siguiente historia (PR-X004)

Este runbook sólo ordena los pasos; las reglas de AGENTS.md mandan sobre él. Viene del plan de aceleración (`docs/product/plan-aceleracion-desarrollo-2026-11-02.md`, §3, §5 y §6).

Cada paso deja evidencia real: la línea que imprimió el comando, no "pasó". Si un paso no se pudo correr, se dice **"no verificado por ejecución"** y por qué.

## 0. ¿Se puede empezar?

No empezar, y avisar a Jesús con el dato, si pasa cualquiera de estas cosas:

- **`main` está en rojo:** `gh run list --branch main --limit 1`. No se construye sobre rojo.
- **Ya hay 2 PRs abiertos del agente:** `gh pr list --state open`. Es el límite de WIP.
- **La cola 👤 llegó a 5 pendientes** en `mvp-plan.md`: se termina lo que hay y no se abre un epic nuevo.
- **No hay historia READY** que cumpla el paso 1.

## 1. Elegir la historia

1. **Qué tomar:** el primer bloque abierto de `mvp-plan.md` con sus dependencias en `[x]` (AGENTS.md §5). Si Jesús autorizó un epic, la primera historia READY de ese epic en orden de dependencias.
2. **Leer la tarjeta de Jira completa** (proyecto SCRUM). Si el chat no tiene acceso a Jira, pedir el texto.
3. **Revisar la Definition of Ready** (plan §6). Si falta algo, no se empieza: se reporta qué falta.
   - criterios "Dado/cuando/entonces" que se comprueban con una prueba;
   - dependencias ya en `main`;
   - carril previsto y rutas que espera tocar;
   - 1 día de agente o menos; si es más, se propone cómo partirla;
   - ninguna decisión de producto abierta; si la hay, se propone una tarjeta de decisión, como SCRUM-220.
4. **Escribir el bloque `## Task`** de AGENTS.md §7 en el chat.

## 2. Rama, línea base y carril

1. `git fetch origin`
2. `git switch -c SCRUM-XX-<tema> --no-track origin/main`. Las mayúsculas importan: el permiso de push es para `SCRUM-*` (AGENTS.md §6). Las historias del plan de aceleración sin tarjeta usan `PR-X00N-<tema>`.
3. `make test` → anotar la línea de resumen. Si algo ya falla en `main`, detenerse y avisar.
4. **Carril:** comparar las rutas que espera tocar con `.github/CODEOWNERS`.
   - Ninguna coincide → 🟢 verde.
   - Alguna coincide → 🟡 amarillo.
   - Toca algo del carril rojo (AGENTS.md §6) → detenerse y preguntar.

## 3. Programar con pruebas primero

- **Skill de estilo** según AGENTS.md §3: lógica primero, con sus pruebas en verde; después la UI que la consume.
- **Por cada criterio:** prueba que falla → código → `make test` en verde.
- **Límite de atasco:** 3 intentos sin avance sobre la misma falla → detenerse y reportar con evidencia.
- **Nunca** borrar, desactivar ni debilitar una prueba. El guard del agente lo revisa en `make ci`.
- **Si la historia cambia un flujo de la app,** ajustar su paso en el recorrido de `PRUITests/Journeys/` que corresponde.

## 4. Cierre local (AGENTS.md §4.1)

1. `make ci` → copiar las líneas reales:
   - `✔ Test run with …` (las dos) y `Executed N tests` de XCTest;
   - `OK: ninguna prueba se borra, desactiva ni reduce (base …, N → M pruebas).`
2. `make test-ui-smoke`. Después, los recorridos que toca: `make test-ui-journey RECORRIDO="…"`.
   - Una sola corrida de UI a la vez.
   - El script apaga el simulador al terminar; confirmarlo en el log.
3. **Recalcular el carril** con lo que de verdad cambió: `git diff --name-only origin/main...HEAD` contra `.github/CODEOWNERS`.
4. **Estado en el mismo PR** (plan §5): no hay PR de cierre.
   - En `mvp-plan.md`, marcar `[x]` sólo los criterios cuya prueba pasó en `make ci`.
   - Agregar la línea `Evidencia:` y la de "finalizada el <fecha>".
   - Lo 👤 queda abierto para Jesús.

## 5. Commit, push y PR

1. **Commit:** `SCRUM-XX (P0): …`, con el `Co-Authored-By` que indique el entorno.
2. **Push:** `git push -u origin SCRUM-XX-<tema>`, sin preguntar (AGENTS.md §6).
3. **PR:** `gh pr create --base main --title "SCRUM-XX: …" --body-file <cuerpo>`. El cuerpo sigue `.github/pull_request_template.md` y lleva las líneas reales del paso 4.
4. **Jira:** mientras no esté instalado GitHub for Jira (S-04), mover la tarjeta a **Revisar**.

## 6. Merge según el carril

| Carril | Qué hace el agente |
|---|---|
| 🟢 Verde, dentro de un epic que Jesús autorizó | `gh pr merge <n> --auto --squash --delete-branch` |
| 🟢 Verde, sin epic autorizado | Sin `--auto`: avisa a Jesús que el PR está listo |
| 🟡 Amarillo | Sin `--auto`. Explica el riesgo en el PR, avisa a Jesús y sigue con otra historia verde que no dependa de esta |
| 🔴 Rojo | Se detiene y pregunta |

## 7. Vigilar el CI hasta `main`

- **Cómo vigilar:**
  - en la app de Claude Code: Auto-fix del PR, que avisa si falla el CI, hay conflictos o llegan comentarios;
  - en otro entorno: `gh pr checks <n> --watch`.
- **Si falla el CI:**
  1. leer el log con `gh run view <id> --log-failed`;
  2. reproducirlo en local, arreglarlo y volver a correr `make ci`;
  3. hacer push.

  Tres fallas seguidas por la misma causa → detenerse y avisar.
- **Si `main` queda en rojo después de un merge propio:** `git revert` del commit en una rama nueva, PR y aviso a Jesús.
- **Al entrar a `main` con el CI en verde:** mover la tarjeta de Jira a **Finalizada** mientras no esté S-04.

## 8. Reporte

- **Bloque `## Result`** de AGENTS.md §7, con el link del PR y las líneas reales.
- **Lo que no se pudo verificar,** y los pendientes 👤 para Jesús.
- **Después:** volver al paso 0 con la siguiente historia.
- **Al acabarse el epic autorizado:**
  1. correr la E2E completa (`make test-ui`);
  2. publicar el reporte del epic: historias mergeadas, evidencia, riesgos, pendientes 👤 y lo no verificado;
  3. detenerse hasta que Jesús autorice el siguiente.

## Cuándo se detiene solo (plan §3)

- El CI falla 3 veces seguidas por la misma causa.
- `main` queda en rojo por un merge propio. Primero el revert, después el aviso.
- La historia necesita una decisión de producto o crece fuera de su alcance.
- El guard del agente falla y la causa no es un error propio que se arregla en la misma rama.
- Se acaba el epic autorizado, o se llega al límite de WIP o de la cola 👤.
