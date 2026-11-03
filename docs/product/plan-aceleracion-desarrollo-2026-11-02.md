# Plan para acelerar el desarrollo de Nucleus con un agente autónomo

**Fecha:** 2026-11-02 · **Base:** `origin/main` @ `aa48151` (PR #27) · **Autor:** PM/PO de Nucleus con Claude (skills senior-fullstack y senior-pm) · **Estado:** propuesta, pendiente de que Jesús la apruebe

> **Avance de la fase 0 (2026-11-02):** `main` quedó protegida con el ruleset `main protegido`: PR obligatorio, `make ci` obligatorio con la rama al día, sin force push, sin borrado y sin bypass. También se activaron el auto-merge y el borrado de la rama al fusionar. Falta `nucleus-bot` (D-3) y GitHub for Jira (S-04). Los datos de las secciones 1 y 12 son de antes de este cambio.

---

## 0. Decisiones que necesito de Jesús (antes de empezar)

| # | Decisión | Recomendación | Por qué |
|---|---|---|---|
| D-1 | ¿El agente hace automerge sin revisión humana por historia? | **Sí, en el "carril verde"** (sección 3), sólo dentro de un epic autorizado y con `make ci` obligatorio en verde. Al cerrar el epic se para y pide tu revisión. | Los datos (sección 1) muestran que lo que más frena hoy es esperar el merge, no programar. |
| D-2 | ¿Las historias se mergean directo a `main` o a una rama `epic/*`? | **Directo a `main`** (trunk-based), PRs chicos con squash. | Una rama de epic acumula días de cambios, choca con el trabajo de Gael y Joss y termina en una revisión gigante que nadie lee bien. `main` protegido con CI da el mismo control. |
| D-3 | ¿Con qué identidad de GitHub firma el agente? | **Una cuenta máquina (`nucleus-bot`)** o la app de Claude para GitHub, no tu cuenta. | GitHub no te deja aprobar tus propios PRs. Si el agente usa tu cuenta, el carril amarillo (cambios sensibles que tú apruebas) no se puede exigir, sólo pedir. |
| D-4 | ¿Dónde corre el agente? | **En tu Mac** (Claude Code con Xcode y simuladores). | El iOS sólo compila y se prueba en macOS. Una sesión en la nube (como esta) no tiene Swift: sólo podría mandar código a ciegas y esperar al CI. |
| D-5 | ¿Runner de CI propio en tu Mac? | **No, mientras el repo sea público.** | El repo es público: un PR desde un fork podría correr código en tu Mac, y GitHub desaconseja runners propios en repos públicos. Tampoco ahorra dinero: en repos públicos los runners de GitHub no cobran minutos, y el CI ya tarda unos 5 min. Sólo se reconsidera si el repo pasa a privado. |

---

## 1. Diagnóstico: dónde se pierde el tiempo hoy

Medido con `git log` sobre los 17 PRs de producto mergeados desde el 2026-10-25:

| Métrica | Valor |
|---|---|
| Historias de producto a `main` | 17 en 8 días ≈ **2.1 por día** |
| Espera entre el último commit y el merge | mediana **12 min**, p75 **5 h**, p90 **16 h**, máximo **23 h** |
| PRs que esperaron más de 3 h | **6 de 17**, que suman **77 h** paradas |
| PRs "cierre" que sólo actualizan `mvp-plan.md` | **4** (más el commit de cierre dentro de casi todos los demás) |
| Commits a `mvp-plan.md` en 8 días | **40** (el archivo mide 1 456 líneas); `requirements-traceability.md`: 18 |
| Pendientes 👤 en `mvp-plan.md` | **15**, todos tuyos (proteger `main`, instalar GitHub for Jira, pruebas en iPhone, ensayo de la demo…) |
| Duración del CI (`make ci` en `macos-26`, 54 corridas desde el 2026-10-26) | mediana **4.8 min**, p90 **6.1 min**, máximo 8 min; nunca esperó runner; 53 en verde y 1 en rojo |
| Merges sin `make ci` en verde (26 PRs) | **3**: #1 con el CI en rojo; #6 (migraciones) 3.5 min y #9 (escala de dolor) 5 min antes de que terminara |

Conclusión: **el agente ya programa rápido; lo lento está alrededor de él.**

1. **Espera humana para el merge.** Un PR verde puede quedarse parado toda la noche. El agente tampoco empieza la siguiente historia hasta que mergea la anterior, así que la espera bloquea todo el flujo.
2. **Cola 👤 acumulada.** El POC tiene sus criterios del agente en `[x]` desde hace días, pero no cierra porque faltan validaciones tuyas.
3. **Papeleo por historia.** Cada historia toca `mvp-plan.md` y la matriz de trazabilidad, que son el archivo más editado del repo. Eso genera PRs de cierre, conflictos (ya hubo un merge sólo para resolver `mvp-plan.md`) y mucho contexto que el agente tiene que leer en cada sesión.
4. **Confirmación manual para cada `git push`** (AGENTS.md §6).
5. **`main` no está protegido** (verificado con `gh` el 2026-11-02; S-02 dice "falta 👤 proteger `main`").
   - No hay reglas de protección ni rulesets.
   - El auto-merge está apagado y las ramas no se borran al mergear.
   - 3 de los 26 PRs se mergearon sin el CI en verde:
     - #1 con el CI en rojo;
     - #6 (migraciones, 23 archivos) y #9 (escala de dolor), antes de que el CI terminara. El CI pasó después.
   - El #25 también aparece mergeado antes de su CI, pero no cuenta: su commit entró con el #26, que estaba en verde.
   - Los otros 22 se mergearon después del verde, casi siempre segundos después.
6. **El repo es público** (`JAlcon00/Nucleus`). Los runners de GitHub no cobran minutos en repos públicos, y un runner propio sería riesgoso: un PR desde un fork podría correr código en tu Mac (ver D-5).

---

## 2. Objetivo y metas medibles

**Objetivo:** que el agente lleve cada historia de un epic autorizado desde READY hasta `main` sin esperar a una persona, y que Jesús sólo intervenga en el arranque y el cierre de cada epic y en los cambios sensibles.

| KPI | Línea base (hoy) | Meta a 3 semanas | Cómo se mide |
|---|---|---|---|
| Espera de merge (último commit → merge), p90 | 16 h | **≤ 15 min** (el CI tarda 4.8 min en la mediana y 6.1 en el p90) | `git log` (script de la sección 10) |
| Historias de producto a `main` por día hábil | 2.1 | **≥ 3** sin subir las fallas | Jira / `git log` semanal |
| Fallas de cambio (PR en `main` seguido de revert o hotfix) | sin medir | **≤ 10 %** | etiqueta `revert`/`hotfix` en PRs |
| Tiempo con `main` en rojo | sin medir | **≤ 1 h** por incidente | historial del check `make ci` en `main` |
| Pendientes 👤 abiertos | 15 | **≤ 5**, ninguno de más de 7 días | conteo en el tablero |
| PRs que sólo actualizan documentación de estado | 4 + commits sueltos | **0** | títulos de PR |
| Merges sin `make ci` en verde | **3 de 26** (#1, #6 y #9) | **0** (lo garantiza la protección de rama) | configuración de la rama y `gh pr checks` |

Si a las 3 semanas las fallas de cambio pasan del 10 %, se reduce el carril verde (más rutas a revisión) antes de seguir acelerando.

---

## 3. El modelo: autonomía por carriles

| Carril | Qué entra | Qué hace el agente | Qué haces tú |
|---|---|---|---|
| 🟢 **Verde** | Historias del epic autorizado que **no** tocan rutas sensibles: dominio, UI, coordinadores, tests nuevos, recorridos E2E, docs | rama → TDD → `make test` → `make ci` local → commit → push → PR → `gh pr merge --auto --squash --delete-branch` → vigila el CI → siguiente historia | Nada por historia. Lees el reporte del epic. |
| 🟡 **Amarillo** | Cualquier PR que toque rutas sensibles (lista abajo) | Igual, pero **sin** `--auto`; deja el PR listo con el riesgo explicado y sigue con otra historia del carril verde que no dependa de él | Apruebas como CODEOWNER (requiere D-3) y se mergea solo |
| 🔴 **Rojo** | Nunca autónomo: force push, reescribir historial, cambiar la protección de rama o los permisos, borrar ramas ajenas, tocar secretos o `.env`, releases/TestFlight, decisiones de producto abiertas | Se detiene y te pregunta | Decides |

**Rutas del carril amarillo** (van en `CODEOWNERS` con `@JAlcon00`):

```
# Gates del propio agente: no puede cambiarlos solo
/.github/                      @JAlcon00
/Makefile                      @JAlcon00
/scripts/                      @JAlcon00
/AGENTS.md                     @JAlcon00
/.claude/                      @JAlcon00
/.agents/                      @JAlcon00
/CODEOWNERS                    @JAlcon00
# Integridad de datos (prioridad 1)
/Packages/PRCore/Sources/PRCore/LocalPersistence.swift      @JAlcon00
/Packages/PRCore/Sources/PRCore/CodableRepositories.swift   @JAlcon00
/Packages/PRCore/Sources/PRCore/PersistenceMigration.swift  @JAlcon00
/Packages/PRCore/Sources/PRCore/PendingOperationStore.swift @JAlcon00
/Packages/PRCore/Sources/PRDomain/StoredPlan.swift          @JAlcon00
# Seguridad del usuario (prioridad 2)
/Packages/PRCore/Sources/PRDomain/Restriction*.swift        @JAlcon00
/Packages/PRCore/Sources/PRDomain/PainFeedbackEngine.swift  @JAlcon00
# Salud, IA y secretos
/Packages/PRCore/Sources/PRCore/Health*.swift               @JAlcon00
/Packages/PRCore/Sources/PRCore/NVIDIA*.swift               @JAlcon00
/Packages/PRCore/Sources/PRCore/LLMBackendTransport.swift   @JAlcon00
# Proyecto y dependencias
/Packages/PRCore/Package.swift @JAlcon00
*.pbxproj                      @JAlcon00
```

**Ciclo de un epic:**

1. **Arranque (tú, 10 min):** marcas el epic como "Autorizado para agente" en Jira. Debe tener sus historias en READY con criterios verificables (Definition of Ready, sección 6).
2. **Ejecución (agente):** toma las historias en orden de dependencias y repite el ciclo verde. Si una cae en amarillo, la deja lista y sigue con la siguiente independiente.
3. **Cierre (agente):** corre la E2E completa (`make test-ui`), actualiza el tablero una sola vez y publica el **reporte del epic**: historias mergeadas, evidencia de tests, riesgos, pendientes 👤 y lo que no pudo verificar.
4. **Gate (tú, 30–45 min):** pruebas 👤 en el iPhone, apruebas los amarillos que queden y autorizas el siguiente epic.

**Cuándo se detiene el agente solo:**
- El CI falla 3 veces seguidas por la misma causa.
- `main` queda en rojo después de un merge suyo: hace revert de su PR (está permitido y es seguro) y te avisa.
- La historia necesita una decisión de producto (como fue D1 en SCRUM-220) o crece fuera de su alcance.
- El guard del agente (sección 4) falla.
- Se acaba el epic autorizado.

---

## 4. Guardarraíles técnicos (lo que hace seguro el automerge)

1. **Proteger `main`:** check obligatorio `make ci`, "Require branches to be up to date", sin push directo, sin force push, revisión de CODEOWNERS obligatoria. Activar en el repo "Allow auto-merge" y "Automatically delete head branches". Con esto también se cierra S-02 (SCRUM-189).
2. **Nuevo job de CI `guard-agente`, obligatorio,** que compara el PR contra `main` y falla si:
   - baja el número de tests (`@Test` y `func test…`);
   - aparece un test desactivado o saltado (`.disabled`, `withKnownIssue`, `XCTSkip`, `.enabled(if: false)`);
   - se borra un archivo de `Tests/` o de `PRUITests/` sin la etiqueta `test-retirado` y una explicación en el PR;
   - cambia un modelo `Codable` persistido sin tocar un test con fixture de versión anterior;
   - `scripts/check_secrets.sh` encuentra algo (ese guard ya existe; aquí se vuelve obligatorio en el PR).
3. **UI en CI:** probar `make test-ui-smoke` en el runner de GitHub como check **no obligatorio**. Cuando lleve 10 corridas estables, pasa a obligatorio. Mientras tanto, el cierre de epic corre la E2E completa en tu Mac.
4. **Plantilla de PR** con: historia de Jira, carril, criterios de aceptación con su test, comandos corridos y su resultado real, invariantes tocados y riesgos. El agente nunca escribe "los tests pasan" sin pegar la línea real del resultado.
5. **Permisos del agente en tu Mac** (`.claude/settings.json`, carril amarillo). **Lo crea Jesús, no el agente:** al escribirlo, el agente estaría cambiando sus propios permisos, y el modo automático de Claude Code lo bloquea (PR-X003, 2026-11-02). La sintaxis sigue la versión vigente de Claude Code: `Bash(git status *)` con espacio y asterisco. La forma `:*` es la anterior.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git show *)",
      "Bash(git fetch *)", "Bash(git switch *)", "Bash(git checkout -b *)",
      "Bash(git add *)", "Bash(git commit *)", "Bash(git pull --rebase *)", "Bash(git revert *)",
      "Bash(git push -u origin SCRUM-*)", "Bash(git push origin SCRUM-*)",
      "Bash(git push -u origin PR-X*)", "Bash(git push origin PR-X*)",
      "Bash(make test)", "Bash(make ci)", "Bash(make guards)", "Bash(make test-ui-smoke)",
      "Bash(make test-ui-journey *)", "Bash(make test-ui)",
      "Bash(gh pr create *)", "Bash(gh pr view *)", "Bash(gh pr checks *)", "Bash(gh pr list *)",
      "Bash(gh pr merge *)", "Bash(gh pr update-branch *)",
      "Bash(gh run view *)", "Bash(gh run list *)"
    ],
    "ask": [
      "Bash(git reset --hard *)", "Bash(rm *)", "Bash(curl *)", "Bash(wget *)",
      "Bash(gh api *)", "Bash(gh label *)", "Bash(gh pr edit *)"
    ],
    "deny": [
      "Bash(git push --force *)", "Bash(git push -f *)", "Bash(git push --force-with-lease *)",
      "Bash(git push origin main *)", "Bash(git push -u origin main *)",
      "Bash(git push origin --delete *)",
      "Bash(gh repo edit *)", "Bash(gh secret *)", "Bash(gh pr review *)", "Bash(sudo *)",
      "Read(./.env)", "Read(./.env.*)"
    ]
  }
}
```

   - **Push sólo a ramas de historia.** Antes el `allow` permitía `git push origin` a cualquier rama.
   - **`ask` en vez de `deny`** para lo que AGENTS.md §6 manda confirmar (`rm`, `curl`, `wget`, `git reset --hard`, `gh api`, `gh label`, `gh pr edit`). Con `deny` ni Jesús podría aprobarlo desde el chat, y se perderían las lecturas con `gh api` que sirvieron para verificar este plan (protección de rama, check-runs por commit, errores del CODEOWNERS). En `deny` queda el carril rojo.
   - Estas reglas son defensa en profundidad, no la garantía. La garantía es la protección de rama, más que el agente firme con su propia identidad (D-3). Con la cuenta de Jesús, el agente técnicamente podría hacer lo mismo que él. Hoy la sesión de desarrollo firma como `JAlcon00` (verificado con `gh api user`).

6. **AGENTS.md §6:** se cambia "pedir confirmación antes de `git push`" por "push permitido a ramas `SCRUM-*` (y `PR-X*`); nunca a `main`".

---

## 5. Menos papeleo, mismo control

- **Se acaban los PRs de cierre.** El estado de la historia se actualiza en el mismo PR, en una sola línea.
- **Jira es la fuente del estado.** Con "GitHub for Jira" instalado (S-04), el PR con `SCRUM-XX` en el título mueve la tarjeta solo. Ya no hay commits de "mvp-plan anota que está en main".
- **`mvp-plan.md` a dieta:** el tablero activo queda en menos de 150 líneas (epic activo, historias abiertas, pendientes 👤). Los bloques terminados se mueven a `docs/archivo/mvp-plan-2026-10.md`. Así baja el contexto que el agente lee en cada sesión y casi desaparecen los conflictos.
- **Matriz de trazabilidad:** se actualiza una vez por epic, al cerrarlo, no por historia.

---

## 6. Definition of Ready (para que el agente nunca espere)

Una historia sólo entra a un epic autorizado si tiene:
- plantilla PR-XXXX completa, con criterios "Dado/cuando/entonces" que se comprueban con un test;
- dependencias ya en `main`;
- carril previsto (verde o amarillo) y lista de rutas que espera tocar;
- tamaño de **1 día o menos** de agente. Si es más grande, se parte;
- ninguna decisión de producto abierta. Si la hay, primero va una tarjeta de decisión (como SCRUM-220).

**Límite de WIP:** como máximo **2 PRs abiertos del agente** a la vez y **5 pendientes 👤**. Si la cola 👤 llega a 5, el agente termina lo que tiene y no abre un epic nuevo.

---

## 7. Fases y calendario

| Fase | Qué | Quién | Duración | Salida (gate) |
|---|---|---|---|---|
| **0 · Preparar** | Proteger `main` y activar auto-merge (S-02); crear `nucleus-bot` con acceso de escritura (D-3); instalar GitHub for Jira (S-04); borrar ramas mergeadas y `git worktree prune` (hoy hay 7 worktrees y 20+ ramas locales, y tu `main` local va 22 commits atrás) | Jesús | **1 sesión de 45 min** | Un PR de prueba no se puede mergear con el CI en rojo |
| **1 · Guardarraíles** | `CODEOWNERS`, job `guard-agente`, plantilla de PR, `.claude/settings.json`, AGENTS.md §6, runbook del ciclo verde como comando `/siguiente-historia` | Agente (carril **amarillo**: lo apruebas tú) | 1–2 días | Un PR que borra un test lo bloquea el guard; un PR que toca `scripts/` espera tu aprobación |
| **2 · Dieta de docs** | Partir `mvp-plan.md`, archivo, regla de "estado en el mismo PR" | Agente (amarillo, toca AGENTS.md) | 0.5 día | Tablero activo < 150 líneas |
| **3 · Piloto** | Un epic chico (3–5 historias) completamente en carril verde | Agente | 2–4 días | KPIs de la sección 2 medidos; 0 merges sin CI; reporte de epic revisado |
| **4 · Escalar** | 2 agentes en paralelo en worktrees (uno de lógica y uno de UI; las pruebas de UI usan un candado porque con 16 GB sólo cabe un simulador); UI smoke en el CI con el runner de GitHub (sin runner propio mientras el repo sea público, D-5) | Agente + Jesús | continuo | Fallas de cambio ≤ 10 % durante 2 semanas seguidas |

**Antes del piloto, 1 hora tuya para vaciar la cola 👤 actual (15 pendientes).** Es lo que más rápido acerca el cierre del POC, y ningún agente lo puede hacer por ti.

---

## 8. Registro de riesgos

Puntaje = probabilidad (1–5) × impacto (1–5) × peso de la categoría (técnico 1.2, recurso 1.1, financiero 1.4, calendario 1.0, seguridad 1.2, negocio 1.0). Más de 18 → evitar; 12–18 → mitigar; menos de 12 → controlar con un disparador.

| ID | Riesgo | P | I | Puntaje | Respuesta | Disparador | Dueño |
|---|---|---|---|---|---|---|---|
| R1 | Merge a `main` sin el CI en verde (`main` no protegido; ya pasó en 3 de 26 PRs) | 4 | 5 | **24.0** | **Evitar:** no se activa ningún automerge hasta terminar la fase 0. Sin checks obligatorios, `--auto` no tiene nada que esperar | PR mergeado con un check pendiente o en rojo | Jesús |
| R2 | El agente debilita o borra tests para ponerse en verde | 3 | 5 | **18.0** | Mitigar: job `guard-agente` obligatorio y `Tests/` cuidado por el guard | Baja el número de tests en un PR | Agente / Jesús |
| R8 | La cola 👤 crece y bloquea los cierres | 5 | 3 | **16.5** | Mitigar: límite de WIP de 5 y una sesión 👤 fija por semana | Más de 5 pendientes o alguno de más de 7 días | Jesús |
| R3 | Una regresión de UI entra por automerge (la E2E no está en el CI) | 4 | 3 | **14.4** | Mitigar: smoke en CI (primero opcional) y E2E completa al cerrar cada epic | Falla de la E2E al cerrar el epic | Agente |
| R6 | El carril amarillo no se puede exigir con una sola identidad | 4 | 3 | **13.2** | Mitigar: cuenta `nucleus-bot` (D-3) | PR amarillo mergeado sin tu aprobación | Jesús |
| R4 | El agente cambia sus propios gates | 2 | 5 | **12.0** | Mitigar: CODEOWNERS sobre `.github/`, `scripts/`, `Makefile`, `AGENTS.md`, `.claude/` | PR que toca esas rutas | Jesús |
| R5 | Un bug que pierde datos entra por automerge | 2 | 5 | **12.0** | Mitigar: persistencia en carril amarillo y fixture de versión anterior obligatorio | Cambio en un `Codable` persistido sin fixture | Agente / Jesús |
| R12 | Un runner propio en un repo público corre código de un fork en tu Mac | 2 | 5 | 12.0 | Mitigar: no usar runner propio mientras el repo sea público (D-5) | Alguien propone un runner `self-hosted` | Jesús |
| R11 | Se construye rápido lo que no aporta | 3 | 3 | 9.0 | Controlar: sólo epics autorizados con DoR y gate humano al cierre | Historia fuera del epic activo | PO (Claude) |
| R7 | Conflictos o `main` roto con 2 agentes en paralelo | 4 | 2 | 8.0 | Controlar: dieta de docs, "up to date" obligatorio, `gh pr update-branch` | Más de 1 conflicto por semana | Agente |
| R10 | Un secreto se filtra en un commit autónomo | 1 | 5 | 6.0 | Aceptar con control: `.env` en `.gitignore`, `check_secrets.sh` obligatorio, `deny Read(.env)` | El guard de secretos falla | Agente |
| R9 | Xcode del runner distinto al local (el costo no aplica: en repos públicos los minutos no se cobran) | 2 | 2 | 4.8 | Controlar: `concurrency` ya cancela corridas viejas; el CI tarda unos 5 min | CI de más de 15 min o un build que pasa local y falla en el runner | Jesús |

R1 está por encima de 18: es el primer paso y bloquea todo lo demás.

---

## 9. RACI

R = hace · A = responde y aprueba (una sola por fila) · C = consultado · I = informado

| Actividad | Jesús | Claude PO/PM | Agente de código | Gael y Joss |
|---|---|---|---|---|
| Autorizar un epic | **A** | R (prepara historias y DoR) | I | I |
| Escribir y priorizar historias | A | **R** | C | C |
| Implementar, probar y abrir el PR (verde) | I | I | **A/R** | — |
| Automerge del carril verde | I | I | **A/R** (lo ejecuta el CI) | — |
| Aprobar un PR del carril amarillo | **A/R** | C | R (lo prepara) | C |
| Revert si `main` queda en rojo | I | I | **A/R** | I |
| Cierre de epic: E2E y reporte | I | C | **A/R** | I |
| Gate del epic y pruebas 👤 en el iPhone | **A/R** | C | I | C |
| Cambiar los guardarraíles (CI, CODEOWNERS, permisos) | **A** | C | R (sólo vía PR amarillo) | I |

**Escalamiento:** el agente se detiene y avisa en el PR o en Jira → si en 24 h no hay respuesta, sigue con otra historia independiente del mismo epic → nunca abre un epic nuevo sin tu autorización.

---

## 10. Revisión semanal (15 min, los lunes)

1. KPIs de la sección 2 con el script de abajo.
2. Riesgos: ¿alguno subió de puntaje? Cualquiera por encima de 18 se atiende antes de seguir.
3. Cola 👤 y WIP.
4. Siguiente epic a autorizar.

```bash
# Espera de merge por PR (en minutos) desde una fecha
for m in $(git log origin/main --merges --since=2026-11-02 --format='%H'); do
  mt=$(git log -1 --format=%ct $m); lt=$(git log --format=%ct $m^1..$m^2 | head -1)
  echo "$(git log -1 --format=%s $m) | $(( (mt-lt)/60 )) min"
done
```

---

## 11. Historias para ejecutar el plan

**PR-X001 — Proteger `main` y activar auto-merge** · EPIC: EPIC-00 Entrega · P0 · READY · Dependencias: ninguna
Como dueño del producto, quiero que nada entre a `main` sin `make ci` en verde, para que el automerge sea seguro.
Criterios: dado un PR con `make ci` en rojo, cuando se intenta mergear, entonces GitHub lo bloquea · dado un PR en verde con `--auto`, cuando el check termina, entonces se mergea con squash y se borra la rama · dado un push directo a `main`, entonces se rechaza.
Hace: Jesús (fase 0; no es delegable porque es un cambio de permisos). Cierra S-02 / SCRUM-189.

**PR-X002 — Job `guard-agente` en el CI** · EPIC-00 · P0 · READY · Dep.: PR-X001
Criterios: un PR que baja el número de tests falla · un PR que agrega `.disabled`/`XCTSkip` falla · un PR que borra un archivo de `Tests/` sin la etiqueta `test-retirado` falla · un PR que cambia un `Codable` persistido sin un test con fixture falla · el job tiene tests de sus propias reglas con diffs de ejemplo.
Carril: amarillo. Riesgo: falsos positivos que frenen el flujo; se ajustan las reglas en la primera semana.
**Estado (2026-11-02): en `main` (PR #30).** En GitHub comparó contra `main` (base `d4e7654`) y contó 1412 → 1412 pruebas. Faltan las etiquetas `test-retirado` y `muestra-cambiada` (Jesús).
- **Dónde corre:** dentro de `make ci`, que ya es el check obligatorio, así que no hace falta otro check en la regla de `main`; y también en la Mac antes del push.
- **Ajuste a la regla del `Codable`:** `PersistenceFormatTests` ya falla si un modelo guardado cambia de forma incompatible. Lo que el guard protege es la muestra: falla si se edita, renombra o borra una muestra existente (etiqueta `muestra-cambiada`), porque eso escondería el cambio.

**PR-X003 — CODEOWNERS, plantilla de PR, permisos del agente y AGENTS.md §6** · EPIC-00 · P0 · READY · Dep.: PR-X001
Criterios: un PR que toca `scripts/` queda esperando la aprobación del CODEOWNER · la plantilla aparece al crear un PR · el agente puede hacer push a `SCRUM-*` y no a `main`.
Carril: amarillo.
**Estado (2026-11-02): en rama `PR-X003-codeowners`.**
- **Hecho:** `.github/CODEOWNERS`, `.github/pull_request_template.md` y AGENTS.md §6 (push a ramas de historia, carriles, confirmar y nunca).
- **CODEOWNERS:** agrega a la lista de §3 `Persistence*.swift` (esquemas y contratos), las muestras de `Fixtures/Persistence/`, `ActionPolicyValidator.swift` (el Policy Validator) y `PR/PR.entitlements` (HealthKit).
- **Falta (Jesús):**
  - crear `.claude/settings.json` con el bloque de §4.5;
  - con `nucleus-bot` (D-3), activar "Require review from Code Owners" en el ruleset. Sin el bot la regla bloquearía todo, porque GitHub no deja aprobar un PR propio. El primer criterio se prueba entonces.

**PR-X004 — Runbook `/siguiente-historia`** · EPIC-00 · P1 · READY · Dep.: PR-X002, PR-X003
Como agente, quiero un procedimiento único (tomar historia → rama → TDD → `make test` → `make ci` → PR → `--auto` → vigilar el CI → reporte) para que cada historia siga el mismo ciclo verificable.
Criterios: en el piloto, 3 historias seguidas pasan de READY a `main` sin intervención humana y con la evidencia completa en el PR.

**PR-X005 — Dieta de `mvp-plan.md`** · EPIC-00 · P1 · READY · Dep.: PR-X003
Criterios: tablero activo de menos de 150 líneas · bloques terminados en `docs/archivo/` sin perder contenido (diff de líneas conservadas) · AGENTS.md §5 apunta al tablero nuevo.

**PR-X006 — UI smoke en el CI (opcional al inicio)** · EPIC-00 · P1 · READY · Dep.: PR-X001
Criterios: `make test-ui-smoke` corre en el runner de GitHub · 10 corridas seguidas estables antes de hacerlo obligatorio · si no es estable en el runner hospedado, se documenta y se evalúa el runner propio (D-5).

---

## 12. Verificación honesta

- **Medido:** espera de merge, volumen de commits y cola 👤 salen de `git log origin/main` y de `mvp-plan.md` en tu Mac.
- **Verificado con `gh` el 2026-11-02**, desde la sesión de desarrollo con la cuenta `JAlcon00`:
  - `gh api repos/JAlcon00/Nucleus/branches/main/protection` → "Branch not protected" (404); `rulesets` → vacío;
  - repo público, `allow_auto_merge: false` y `delete_branch_on_merge: false`;
  - CI: 54 corridas desde el 2026-10-26, con duración mediana de 4.8 min, p90 de 6.1 min y máximo de 8 min, sin cola de runner; 53 en verde y 1 en rojo;
  - merge contra el check `make ci` del commit de cada PR: 22 de 26 después del verde, #6 y #9 antes de que terminara, #1 con el CI en rojo y #25 sin merge propio (entró con el #26).
- La sintaxis de `.claude/settings.json` debe verificarse con la versión de Claude Code instalada en tu Mac antes de aplicarla.
