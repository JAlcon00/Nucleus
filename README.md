# PR — Agentic Fitness Coach

PR es una aplicación nativa para **iPhone y Apple Watch** diseñada para comportarse como **un entrenador experto de gimnasio de élite**: science-based, adaptable, honesto con la recuperación y capaz de aprender cómo entrena cada usuario.

> **Tú entrenas. PR administra el resto.**

## Estado

MVP / POC en desarrollo activo. El plan vivo está en [`mvp-plan.md`](./mvp-plan.md), sincronizado con Jira.

- 74 de 93 historias de [`backlog.md`](./backlog.md) terminadas; la Fase A está cerrada.
- ~810 tests en verde: 662 de Swift Testing y ~150 de XCTest.
- CI local con `make ci`: guards, SwiftPM, tests y builds de iOS y watchOS.
- Ya funciona: Sign in with Apple, cuestionario de onboarding, plan semanal, pantalla Hoy, registro de series de un toque, temporizador de descanso, resumen y export JSON/CSV.

Documentos principales:

- [`mvp-plan.md`](./mvp-plan.md) — plan activo del MVP/POC.
- [`promptMaster.md`](./promptMaster.md) — contrato funcional/técnico maestro.
- [`backlog.md`](./backlog.md) — backlog ejecutable y priorizado.
- [`plan.md`](./plan.md) — secuencia de implementación y gates.
- [`requirements-traceability.md`](./requirements-traceability.md) — trazabilidad requisito ↔ historia.
- [`AGENTS.md`](./AGENTS.md) — instrucciones rápidas para agentes.
- [`.agents/skills/swift-elite-coach/SKILL.md`](./.agents/skills/swift-elite-coach/SKILL.md) — skill de desarrollo Swift.

---

# Visión

PR no pretende ser otro logger con un chatbot agregado.

La aplicación debe:

- crear bloques de entrenamiento de varias semanas;
- adaptar cada sesión al tiempo real disponible;
- recordar pesos/reps y facilitar logging de un toque;
- ordenar ejercicios correctamente según objetivo/prioridad/fatiga;
- resolver máquinas ocupadas o inexistentes;
- aprender equipo por gimnasio;
- manejar progresión y deload;
- respetar restricciones/lesiones declaradas sin diagnosticar;
- usar HealthKit/Apple Watch correctamente;
- evitar doble conteo de calorías;
- enseñar a un novato y dar control a un avanzado;
- evolucionar hacia bodybuilding competitivo de forma segura;
- explicar por qué cambia una decisión.

---

# Filosofía

## Science-based
Las decisiones de entrenamiento proceden del Training Engine + Evidence Registry + datos reales del usuario.

## Adaptive
El plan se adapta a tiempo, gym, restricciones, fase, objetivo y comportamiento.

## Honest
A veces la mejor recomendación es descansar.

## Progressive
Variación sin aleatoriedad.

## Simple outside, sophisticated inside
La UX de entrenamiento debe ser extremadamente sencilla aunque el motor sea complejo.

## Develop → Test → Prove
Ninguna feature se considera lista sin implementación, tests y validación funcional.

---

# Stack

## Apple platforms

- Swift 6.3+ (Swift 6.x estable soportado por Xcode actual)
- SwiftUI
- SwiftData
- Swift Testing
- XCTest / XCUITest cuando aplique
- HealthKit
- `HKWorkoutSession`
- `HKLiveWorkoutBuilder`
- AuthenticationServices / Sign in with Apple
- App Intents
- WorkoutKit cuando aporte valor y disponibilidad lo permita
- os.Logger
- URLSession

## Deployment recommendation

- iOS 18+
- watchOS 11+

No elevar targets sin una decisión explícita.

---

# Arquitectura

```text
                    SwiftUI
                       │
              ┌────────┴────────┐
              │                 │
            iPhone           Apple Watch
              │                 │
              └────────┬────────┘
                       │
                 Application Layer
                       │
          ┌────────────┼────────────┐
          │            │            │
          ▼            ▼            ▼
   TrainingEngine  AgentCore   HealthIntegration
          │            │            │
          ├────────────┼────────────┤
          ▼            ▼            ▼
       Domain      Repositories   HealthKit
          │
          ▼
       SwiftData
```

El LLM **NO** reemplaza al Training Engine.

```text
User language
   ↓
LLM interprets
   ↓
AgentIntent
   ↓
Policy Validator
   ↓
Training Engine decides
   ↓
DecisionRecord
   ↓
LLM/template explains
```

---

# Estructura del repositorio

Estructura estándar Swift/Xcode (grupos sincronizados con el sistema de archivos):

```text
PR/
├── PR.xcodeproj               ← proyecto iOS + watchOS
├── PR/                        ← target iOS (grupo sincronizado)
│   ├── App/
│   │   ├── PRApp.swift
│   │   ├── AppEnvironment.swift
│   │   └── ContentView.swift
│   └── Resources/
│       └── Assets.xcassets
├── PRWatch/                   ← target watchOS (grupo sincronizado)
│   ├── App/
│   │   ├── PRWatchApp.swift
│   │   └── WatchContentView.swift
│   └── Resources/
│       └── Assets.xcassets
├── Packages/
│   └── PRCore/                ← paquete Swift Package Manager
│       ├── Package.swift
│       ├── Sources/
│       │   ├── PRCore/        ← boundary/portes públicos (sin HealthKit real)
│       │   └── PRDomain/      ← dominio puro
│       └── Tests/
│           ├── PRCoreTests/
│           └── PRDomainTests/
├── promptMaster.md
├── backlog.md
├── plan.md
├── requirements-traceability.md
├── AGENTS.md
├── .agents/
│   └── skills/swift-elite-coach/SKILL.md
└── install_to_repo.sh
```

Regla clave: `PRCore` y `PRDomain` NO importan HealthKit/SwiftUI/SwiftData. Son la frontera pública; la app produce los adaptadores reales (p. ej. `HKWorkoutConfiguration`, `HKWorkoutSession`) y los tests usan fakes.

---

# Core concepts

## Training goal

- general health
- hypertrophy
- strength
- powerbuilding
- recomposition
- bodybuilding

## Phase

- surplus
- deficit
- maintenance

Goal y phase son independientes.

## Training block

Plan estable de 4–8 semanas con:

- weekly structure;
- muscle targets;
- priorities;
- anchors;
- rotatable exercises;
- progression policy;
- deload policy.

## Exercise ontology

Cada ejercicio contiene información de:

- movement pattern;
- angle;
- primary/secondary muscles;
- equipment;
- fatigue;
- stability;
- skill;
- role;
- substitution family;
- restriction tags.

Eso permite sustituciones inteligentes en lugar de `same muscle = same exercise`.

---

# Experiencia de workout

Normal:

```text
Bench Press
82.5 kg × 8
Set 2 / 4

[ ✓ HECHO ]
[ OCUPADO ]
```

Si el target se cumplió, registrar una serie debe requerir un toque.

Peso y reps son introducidos por el usuario; PR no pretende detectarlos automáticamente en MVP.

---

# Time-aware

Antes/durante la sesión:

```text
30m | 45m | 60m | 90m | Sin prisa
```

El motor preserva prioridad y reduce elementos marginales.

Tener 3 horas NO implica triplicar volumen.

---

# Gym intelligence

Diferenciar:

- `occupied` → temporal;
- `doesNotExist` → se aprende para ese gym.

Cuando equipment está ocupado:

1. reordenar si es seguro;
2. volver más tarde;
3. sustituir si hace falta.

Las cargas entre máquinas distintas se almacenan por separado.

---

# HealthKit

HealthKit aporta:

- workout;
- active energy;
- HR durante workout cuando disponible;
- duration;
- otros contextos sólo con permiso/justificación.

PR aporta:

- exercise;
- weight;
- reps;
- sets;
- progression;
- substitutions;
- training block;
- decision history.

## Calorías

Nunca sumar calorías de dos registros que representan el mismo workout.

Usar un `WorkoutReconciliationEngine` y una única canonical energy source.

---

# Lesiones / restricciones

PR puede almacenar y respetar una restricción declarada.

PR no diagnostica.

Una restricción puede venir de:

- usuario;
- indicaciones profesionales documentadas por el usuario.

Una fecha de revisión NO significa curación automática.

---

# Recovery

Resultados posibles:

- train as planned;
- train with adjustments;
- recovery session;
- rest recommended.

No se debe inventar un recovery score con falsa precisión.

---

# Principiante → experto

## Guided
Lenguaje sencillo y educación contextual.

## Balanced
Explicaciones selectivas.

## Advanced
Controles técnicos y mínima intervención.

Meta:

```text
Novice:      What should I do?
Intermediate: Why am I doing this?
Advanced:    How do I personally respond?
```

---

# Bodybuilding

Arquitectura preparada para:

- off-season;
- cut;
- contest prep training;
- specialization blocks;
- measurements;
- progress photos;
- posing;
- competition timeline.

No se incluyen protocolos médicos, sustancias ni prácticas extremas.

---

# Setup de desarrollo

> Los comandos concretos deben ajustarse a los schemes reales detectados con `xcodebuild -list`.

## Requisitos

- macOS compatible con Xcode actual.
- Xcode estable.
- Apple Developer team para device testing de HealthKit/Watch.
- iPhone simulator para flujos generales.
- Apple Watch físico recomendado/obligatorio antes de validar workout live para release.

## Primeros comandos

```bash
git status
xcodebuild -list
```

## Tests del paquete

```bash
cd Packages/PRCore
swift build
swift test
```

Después ejecutar el scheme real, por ejemplo:

```bash
xcodebuild \
  -scheme PR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

No asumir que ese simulator existe; listar destinations si falla.

## CI local reproducible (PR-0002)

Pipeline reproducible de build + unit tests, sin dependencia de rutas absolutas y con
exit code no cero ante fallo:

```bash
make ci          # pipeline completo: guard + swift build + swift test + builds iOS y watchOS
make test        # solo unit tests del paquete PRCore
make test-ios    # solo build Debug del scheme iOS
make test-watch  # solo build Debug del scheme watchOS
make guards      # solo guard del pbxproj (spec excluida del target)
```

Notas de entorno:

- Si `xcode-select -p` apunta a CommandLineTools, el script usa `/Applications/Xcode.app`
  (define `DEVELOPER_DIR` para elegir otro Xcode).
- Los artefactos de SwiftPM van a `$TMPDIR/prcore-ci-build` (override: `PR_CI_SCRATCH`).
  Al ejecutar `swift test` a mano dentro de `~/Documents`, usa
  `swift test --scratch-path "$TMPDIR/prcore-build"` para evitar el error de codesign
  *"resource fork, Finder information, or similar detritus not allowed"*.
- Sin runtime de Simulator instalado, los builds usan `generic/platform=... Simulator`.
- Tareas de compilación a la vez (SCRUM-228): `PR_BUILD_JOBS=N make ci` las limita. Por
  defecto no hay límite: se midió y ningún límite mejoró (ver "Cuidar la memoria al correr
  pruebas").

También se puede invocar el script directamente (misma función, logs en `.ci/`):

```bash
./scripts/ci.sh all
```

Cualquier gate que falle hace fallar el pipeline (exit != 0). Los logs reproducibles de
cada fase quedan en `.ci/` (ignorados por git).

## Pruebas de UI por recorrido (SCRUM-217, SCRUM-228)

```bash
make test-ui-smoke   # 3 recorridos, ~3 min: al cerrar cada historia
make test-ui         # los 9 recorridos, ~8 min: al cerrar una fase o antes de una entrega
make test-ui-journey RECORRIDO="TodayJourney ProfileJourney"   # los elegidos, sin recompilar
make test-ui-build   # sólo compila las pruebas de UI (con el simulador apagado)
make test-ui-erase   # borra el simulador de pruebas a propósito
```

Qué correr y cuándo está en [`AGENTS.md`](./AGENTS.md) §4.1: mientras programas, `make test`
(todas las unitarias); al cerrar cada historia, `make ci`, el smoke y los recorridos que toca;
la E2E completa, al cerrar una fase o antes de una entrega.

- **Recorridos.** Cada uno es una clase de `PRUITests/Journeys/` y se puede correr solo. Cada
  paso es una actividad con nombre: si algo falla, el resultado dice en qué paso.

  | Recorrido | Qué recorre | Smoke |
  |---|---|---|
  | `IntermediateQuestionnaireJourney` | Sobre ti, cuestionario intermedio a mano, consentimiento de la IA en Perfil, reabrir | ✔ |
  | `BeginnerQuestionnaireJourney` | Cuestionario de principiante (RIR en palabras) y de avanzado (prioritarios) | |
  | `PendingPlanJourney` | "Armando tu semana" sin "Día de descanso"; "Tu semana" explica el hombro | |
  | `WorkoutRecoveryJourney` | Primera serie, cierre forzado y continuar, dolor que sigue al reabrir, saltar y retomar | ✔ |
  | `FirstWorkoutJourney` | Exportar y Progreso vacíos, primer entrenamiento, Progreso y Exportar con esa sesión | ✔ |
  | `ProfileJourney` | Restricción agregada y resuelta, cerrar sesión, rehacer el cuestionario | |
  | `TodayJourney` | Hoy con "¿Cómo dormiste?", pestañas, volumen, reordenar, la semana, "Dormí mal" | |
  | `SundayJourney` | El domingo es descanso | |
  | `SupersetJourney` | Superset en Hoy y en "Por qué tu plan"; una ronda A1 → A2 → descanso (SCRUM-224) | |

- **Perfil sembrado.** Sólo los recorridos del cuestionario lo contestan a mano. Los demás
  arrancan con `-PRUITestProfile intermedio-lmv` (sólo Debug y sólo con `-PRUITestReset`): la
  app contesta sola el cuestionario con el mismo coordinador que la pantalla y arma el plan
  igual que al terminarlo. `UITestProfileSeederTests` (en `make ci`) comprueba que da el mismo
  perfil y el mismo plan que contestarlo a mano.
- **Simulador propio.** Corren en `PR UI Tests`, un iPhone que el script crea la primera vez.
  No lo uses para otra cosa. `PR_UI_SIMULATOR=<udid> make test-ui` usa otro tal cual (nunca lo
  borra; si ya estaba arrancado, lo deja arrancado).
- **Teclado físico.** Un simulador que alguna vez "vio" un teclado físico minimiza el teclado
  en pantalla y el texto que escriben las pruebas no llega (así fallaban todas en "Sobre ti").
  iOS lo marca con `HardwareKeyboardLastSeen = true` en
  `Library/Preferences/com.apple.keyboard.preferences.plist` de los datos del simulador. El
  script lo borra sólo si tiene esa marca; si no, lo reutiliza (arranca mucho más rápido que
  uno recién borrado). Verificado: con la marca puesta a mano, el recorrido del cuestionario
  falla igual que en SCRUM-217, y el script la detecta, lo borra y pasa.
  (`AutomaticMinimizationEnabled` no sirve de marca: aparece también en uno limpio.) En
  Simulator.app, con otro simulador, desactiva
  *I/O › Keyboard › Connect Hardware Keyboard*.
- **Compilar antes de arrancar y apagar al terminar.** El script compila con el simulador
  apagado (`build-for-testing`), lo arranca y corre lo ya compilado (`test-without-building`).
  En la E2E completa, antes de correr espera a que iOS termine de levantar sus servicios (la
  CPU de la Mac libre en dos lecturas, como mucho 2 min; ver abajo). Al terminar lo apaga,
  también si una prueba falla o lo detienes con Ctrl+C. Nunca corre pruebas en paralelo.
- **Tareas de compilación.** `PR_BUILD_JOBS=N` limita las tareas a la vez de `make ci` y de
  las pruebas de UI. Por defecto no hay límite: medido, ningún límite mejoró (abajo).
- **Resultado.** Al terminar se imprime cada recorrido con OK/FAIL, su duración y, si falló,
  el paso donde falló y el mensaje. El detalle queda en `.ci/test-ui*.log` y en `.ci/test-ui.xcresult`,
  que se abre con Xcode (ahí se ven los pasos).
- **Si se cuelga.** El script pasa `-collect-test-diagnostics never`: antes, cuando una
  prueba fallaba, `xcodebuild` se quedaba esperando a `simctl diagnose`. Si aun así se queda
  colgado, detenlo con Ctrl+C (el simulador se apaga solo) y vuelve a correrlo.
- **Desde Xcode.** *Product › Test* sobre `PRUITests` (o sobre una clase) sigue funcionando
  con cualquier simulador. Si las pruebas fallan en "Sobre ti", revisa el teclado físico.

### Cuidar la memoria al correr pruebas (Mac de 16 GB)

Antes, `make test-ui` borraba y arrancaba el simulador mientras compilaba: la MacBook Air
(16 GB) llegaba a 15 GB usados, 6.6 GB comprimidos, 4.9 GB de swap y carga 24.8.

- Una sola sesión de agente por historia; nada de varias corriendo pruebas a la vez.
- Cierra el panel del navegador y lo pesado (otros simuladores, Xcode con previews, videos)
  durante `make test-ui`.
- Para medir lo que cuesta un comando: `./scripts/measure_resources.sh make test-ui` imprime
  la duración, la carga máxima de 1 minuto, la memoria comprimida y usada máximas y el swap al
  empezar y al terminar (muestras en `.ci/resources-*.csv`).

Medido el 2026-10-30 en la MacBook Air M5 de 16 GB (`scripts/measure_resources.sh`):

| Corrida | Duración | Carga 1 min máx. | Carga 15 min máx.¹ | Comprimida máx. | Swap al empezar → al terminar |
|---|---|---|---|---|---|
| **Antes:** `make test-ui` (32 pruebas en una clase; borraba y arrancaba el simulador mientras compilaba) | 28 min 43 s | 225 | ≈ 46 | 7.1 GB | 1.6 → 6.2 GB (máx. 6.4) |
| `make test-ui`, corrida A | 7 min 8 s | 74 | ≈ 14 | 6.6 GB | 3.2 → 2.8 GB (máx. 3.2) |
| `make test-ui`, corrida B | 7 min 59 s | 117 | ≈ 21 | 6.9 GB | 2.8 → 3.7 GB (máx. 3.7) |
| `make test-ui-smoke` | 2 min 48 s | 131 | ≈ 20 | 6.7 GB | 3.1 → 3.1 GB |
| `make test-ui-erase` y después el smoke (primer arranque tras borrar) | 6 min 13 s | 252 | ≈ 46 | 7.0 GB | 3.6 → 3.7 GB (máx. 5.4) |

¹ Reconstruida desde la de 1 minuto partiendo de 6, la carga con la que empezó la corrida de
antes, para comparar corridas que empezaron con distinta carga. La línea base de SCRUM-228
era 24.8.

- **Arrancar el simulador es lo caro, no compilar.** `make ci` desde cero tarda 65–66 s, con
  carga máxima de 10–21, y el swap no crece. Por eso no se limitan las tareas de compilación:
  con 6 tarda 81 s y con 4, 109 s, sin menos swap.
- **Después de arrancar, iOS tiene la CPU al 100% unos 110 s** (PosterBoard,
  intelligenceflowd, ScreenTimeAgent, remindd…), aun con el simulador reutilizado. La E2E
  completa espera a que se calme: sin la espera, el primer recorrido tardó el doble y la carga
  llegó a 337 (7 min 11 s en total; con la espera, 7 min 8 s). El smoke y los recorridos
  sueltos no esperan, para no duplicar su duración. `PR_UI_SETTLE=1` (o `0`) lo fuerza.
- **Con la Mac cargada, el smoke se alarga.** Justo después de otros dos arranques del
  simulador tardó 3 min 57 s, con carga máxima de 253. Recién borrado, el primer arranque es
  el más pesado.

## IA en desarrollo (SCRUM-204)

La IA (NVIDIA) sólo se conecta en compilaciones **Debug** y con una llave que vive en tu
Mac, nunca en el repo. En **Release** la IA queda apagada y la app ni siquiera busca la
llave: el plan lo arma el motor local. Antes de TestFlight la llave se mueve a un backend.

- **Simulador:** crea un `.env` en la raíz del repo (ya está en `.gitignore`) con
  `NVIDIA_API_KEY=<tu llave>`.
- **iPhone físico:** en Xcode, *Product › Scheme › Manage Schemes…*, duplica `PR`, desmarca
  *Shared* (queda en `xcuserdata/`, ignorado) y en *Run › Arguments › Environment Variables*
  agrega `NVIDIA_API_KEY`. Nunca en el scheme compartido.
- Perfil › Inteligencia artificial › Conexión muestra "Conectada (desarrollo)" o
  "Modo local". Cualquier falla de la IA (sin red, cuota, respuesta inválida) es "no
  disponible" y la app sigue con el motor local.
- `make guards` corre `scripts/check_secrets.sh`: falla si hay algo con forma de llave
  `nvapi-…`, una asignación literal de `NVIDIA_API_KEY` o esa variable en un scheme
  versionado.

---

# Entitlements y privacidad

Antes de HealthKit/Sign in with Apple:

- habilitar capabilities en targets correctos;
- añadir usage descriptions requeridas;
- revisar permisos mínimos;
- no guardar API keys en plist/source;
- no loggear Health data sensible.

---

# Testing

## Unit
Training Engine y Domain deben tener la mayor cobertura.

## Integration
SwiftData, reconciliation, adapters.

## UI
Flujos críticos:

- onboarding;
- start workout;
- complete set;
- occupied/missing;
- substitution;
- finish;
- restriction;
- offline.

## Device
HealthKit/watchOS live workout.

---

# Definition of Done

```text
implementation
+ tests
+ build
+ manual/e2e validation
+ documentation
= DONE
```

Consultar `promptMaster.md` para checklist completa.

---

# Cómo trabajar como IA agente

1. Leer documentación principal.
2. Inspeccionar repo.
3. Seleccionar primera historia READY compatible.
4. Implementar slice pequeño.
5. Crear tests.
6. Ejecutar tests.
7. Ejecutar build.
8. Validar flujo.
9. Actualizar backlog/docs.

No saltar al chatbot/LLM antes de tener Training Engine funcional.

---

# Product mantra

> **PR no debe reemplazar el criterio del atleta: debe desarrollarlo.**
