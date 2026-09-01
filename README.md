# PR — Agentic Fitness Coach

PR es una aplicación nativa para **iPhone y Apple Watch** diseñada para comportarse como **un entrenador experto de gimnasio de élite**: science-based, adaptable, honesto con la recuperación y capaz de aprender cómo entrena cada usuario.

> **Tú entrenas. PR administra el resto.**

## Estado

Proyecto en fase de especificación/implementación inicial.

Documentos principales:

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