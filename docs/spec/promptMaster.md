# promptMaster.md — PR Agentic Fitness Coach

> **Producto:** PR (codename temporal)
> **Tipo:** Aplicación nativa iOS + watchOS, Apple-first, agentic, science-based y local-first.
> **Objetivo del documento:** servir como contrato maestro para cualquier IA agente que implemente el producto. Si una decisión técnica, funcional o de dominio contradice este archivo, este archivo prevalece salvo que el Product Owner modifique explícitamente el requisito.

---

## 0. Contrato de ejecución para cualquier IA agente

La IA que trabaje sobre este repositorio DEBE comportarse como un **Staff/Senior iOS Engineer + Software Architect + QA Engineer + Product Engineer especializado en fitness**. No debe limitarse a generar código. Debe implementar, testear, compilar, verificar y documentar.

### 0.1 Regla operativa obligatoria

La filosofía de desarrollo es:

> **DESARROLLAR → TESTEAR → PROBAR**

Una feature NO está terminada porque compile. Una feature NO está terminada porque tenga tests. Una feature está terminada únicamente cuando:

1. La implementación está completa.
2. Existen pruebas unitarias del dominio y la lógica.
3. Existen pruebas de integración cuando intervienen persistencia, HealthKit, red o coordinación entre módulos.
4. Existen UI tests o pruebas de flujo para caminos críticos cuando aplique.
5. El proyecto compila sin errores ni warnings nuevos relevantes.
6. La feature fue validada manualmente o mediante un test end-to-end equivalente.
7. Los criterios de aceptación del backlog están satisfechos.
8. Se documentaron decisiones no obvias.

### 0.2 Antes de modificar código

La IA DEBE:

1. Inspeccionar la estructura real del repositorio.
2. Leer `README.md`, `promptMaster.md`, `plan.md`, `backlog.md`, `AGENTS.md` y `.agents/skills/swift-elite-coach/SKILL.md`.
3. Ejecutar `git status` y no sobrescribir trabajo ajeno.
4. Inspeccionar schemes y targets reales con `xcodebuild -list` antes de asumir nombres.
5. Identificar el estado actual del backlog.
6. Implementar la unidad vertical más pequeña que entregue valor comprobable.
7. No crear arquitecturas paralelas si ya existe una arquitectura establecida.

### 0.3 Prohibiciones absolutas

La IA NO DEBE:

- Inventar APIs de Apple.
- Inventar tipos de HealthKit, WorkoutKit o AuthenticationServices.
- Guardar secretos/API keys dentro de la app.
- Llamar un proveedor LLM directamente desde el cliente con una API key privilegiada.
- Permitir que un LLM modifique directamente persistencia o planes sin pasar por validación del dominio.
- Utilizar `fatalError`, `try!`, force unwraps o casts forzados como solución ordinaria.
- Perder una serie registrada por falta de internet.
- Duplicar calorías de dos fuentes que representan el mismo workout.
- Diagnosticar lesiones, enfermedades o condiciones médicas.
- Hacer que una racha obligue al usuario a entrenar en un día de descanso.
- Cambiar una rutina de forma aleatoria sólo para generar variedad.
- Agregar volumen simplemente porque el usuario dispone de más tiempo.
- Reemplazar un ejercicio sólo porque “trabaja el mismo músculo”; debe considerar patrón, función, prioridad, fatiga, equipo, restricciones y objetivo.
- Ocultar al usuario por qué ocurrió un ajuste significativo.
- Usar un LLM como calculadora principal de progresión, calorías, volumen, fatiga o tiempos.

### 0.4 En caso de ambigüedad futura

Aplicar esta prioridad:

1. Seguridad y restricciones del usuario.
2. Datos reales del usuario.
3. Reglas del Training Engine.
4. Objetivo y fase de entrenamiento.
5. Adherencia y tiempo disponible.
6. Evidencia registrada en el Evidence Registry.
7. Preferencias explícitas del usuario.
8. Preferencias aprendidas.
9. Variedad.
10. Estética/engagement de producto.

Si todavía hay empate, seleccionar la opción **más conservadora, reversible y explicable**.

---

# 1. Visión del producto

PR debe sentirse como:

> **un entrenador experto que encontrarías en un gimnasio de élite, disponible dentro del iPhone y Apple Watch.**

No es un simple tracker. El tracker es una de las herramientas del entrenador.

La aplicación debe:

- enseñar a un principiante a convertirse progresivamente en un usuario autónomo y competente;
- ayudar a un intermedio a comprender por qué progresa o se estanca;
- darle a un avanzado control granular y análisis longitudinal sobre sí mismo;
- administrar automáticamente la logística del entrenamiento;
- tomar decisiones explicables y conservadoras;
- adaptar el plan a la realidad del gimnasio, no exigir que la realidad se adapte al plan.

## 1.1 North Star

> **La primera semana, PR crea un buen entrenamiento. Meses después, PR crea TU entrenamiento.**

El moat del producto no será un LLM concreto. Será el **Training Model longitudinal del usuario + Exercise Knowledge Graph + Training Engine + historial de decisiones y respuesta individual**.

## 1.2 Promesa principal

> **Tú entrenas. PR administra el resto.**

Antes de entrenar: planifica.
Durante: adapta.
Después: aprende.
Entre bloques: reprograma.

## 1.3 Antipromesas

PR NO promete:

- “la rutina perfecta”;
- diagnosticar salud o lesiones;
- conocer calorías con precisión absoluta;
- detectar automáticamente peso o repeticiones;
- sustituir a un médico, fisioterapeuta, nutricionista o entrenador humano cuando sea necesaria valoración profesional;
- que más volumen siempre sea mejor;
- que un score de recuperación sea una verdad biológica.

---

# 2. Filosofía del producto

## 2.1 Science-based

Toda decisión relevante debe tener una de estas fuentes:

1. Regla científica versionada (`EvidenceRule`).
2. Dato histórico del usuario.
3. Restricción operativa real: tiempo, equipo, disponibilidad.
4. Preferencia explícita.
5. Regla de seguridad.

La frase “la IA decidió” NO es una justificación aceptable.

## 2.2 Consistency over perfection

Una sesión de 35 minutos completada con buena adherencia puede ser superior para ese usuario a un plan teóricamente óptimo de 90 minutos que abandona.

## 2.3 Progress over novelty

Variación controlada sí. Aleatoriedad no.

Los ejercicios se dividen funcionalmente en:

- `anchor`: se mantienen el tiempo suficiente para medir progreso;
- `rotatable`: pueden rotarse dentro de una familia compatible;
- `optional`: se incluyen sólo si tiempo/fase/prioridad lo justifican;
- `rehabRestrictionBound`: sólo cuando una restricción declarada lo permite; no implica prescripción clínica.

## 2.4 Honest recovery

El agente puede y debe decir:

- “entrena normal”;
- “entrena con menos volumen”;
- “mantén carga y evita fallo”;
- “haz sesión de recuperación”;
- “descansa hoy”.

Nunca debe premiar sobreentrenamiento o convertir una racha en presión contra el descanso.

## 2.5 Minimum effective friction

Durante el workout, el usuario sólo debe ingresar información que el sistema no puede conocer con certeza:

- peso real;
- repeticiones reales;
- feedback opcional cuando sea necesario;
- estado de equipo cuando esté ocupado/no exista;
- molestias/restricciones cuando aparezcan.

Todo lo demás debe precargarse.

## 2.6 Teach, then reveal complexity

Principiante: lenguaje simple.
Avanzado: lenguaje técnico y controles granulares.

Ejemplo:

Principiante: “Detente cuando creas que podrías hacer unas 2 reps más.”
Avanzado: “8–10 @ RIR 2”.

---

# 3. Usuarios, objetivos y fases

## 3.1 Niveles de experiencia

```swift
enum ExperienceLevel: String, Codable, Sendable, CaseIterable {
    case novice
    case beginner
    case intermediate
    case advanced
    case competitive
}
```

La app NO debe degradar a un usuario únicamente por tiempo registrado. La experiencia declarada puede modificarse y el nivel de UI puede evolucionar independientemente.

## 3.2 Objetivo primario

```swift
enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case generalHealth
    case hypertrophy
    case strength
    case powerbuilding
    case recomposition
    case bodybuilding
}
```

## 3.3 Fase energética / física

```swift
enum BodyCompositionPhase: String, Codable, Sendable, CaseIterable {
    case surplus
    case deficit
    case maintenance
    case unspecified
}
```

Objetivo y fase son independientes.

Ejemplos válidos:

- `hypertrophy + surplus`
- `strength + maintenance`
- `hypertrophy + deficit`
- `bodybuilding + surplus`
- `bodybuilding + deficit`
- `generalHealth + maintenance`

## 3.4 Prioridades musculares

Un usuario puede definir múltiples prioridades ordenadas.

```swift
struct MusclePriority: Codable, Sendable, Equatable {
    let muscleGroupID: MuscleGroup.ID
    var priority: PriorityTier
}

enum PriorityTier: Int, Codable, Sendable {
    case maintain = 0
    case normal = 1
    case emphasize = 2
    case specialize = 3
}
```

## 3.5 Preferencia de variedad

```swift
enum VarietyPreference: String, Codable, Sendable {
    case stable
    case balanced
    case varied
}
```

Regla inicial recomendada:

- stable: ~80% de ejercicios se mantienen dentro del bloque;
- balanced: ~65%;
- varied: ~50–60%;

Los porcentajes son límites configurables, NO reglas universales. Los anchors necesarios para evaluar progresión pueden permanecer aunque el usuario prefiera variedad alta.

---

# 4. Onboarding funcional

Objetivo: crear un primer plan útil sin cuestionario excesivo.

## 4.1 Flujo obligatorio

1. Welcome.
2. Sign in with Apple.
3. Objetivo principal.
4. Fase actual.
5. Días disponibles por semana.
6. Tiempo habitual por sesión.
7. Experiencia.
8. Lugar/equipamiento inicial.
9. Preferencia de variedad.
10. Lesiones/restricciones existentes, opcional pero visible.
11. Explicación de HealthKit.
12. Solicitud granular de permisos.
13. Generación del primer Training Block.
14. Mostrar inmediatamente `Today`.

El onboarding debe poder completarse sin HealthKit; HealthKit mejora el contexto, pero no bloquea el producto.

## 4.2 Datos mínimos

```swift
struct OnboardingProfile: Codable, Sendable {
    var goal: TrainingGoal
    var phase: BodyCompositionPhase
    var experience: ExperienceLevel
    var trainingDaysPerWeek: Int
    var usualSessionMinutes: Int
    var varietyPreference: VarietyPreference
    var defaultGymID: GymProfile.ID?
    var restrictions: [TrainingRestriction]
}
```

Validaciones:

- `trainingDaysPerWeek`: 2...7
- `usualSessionMinutes`: 20...240
- no inventar objetivos si el usuario omite uno;
- si `bodybuilding`, mostrar configuración avanzada posterior, no convertir onboarding inicial en un formulario enorme.

---

# 5. Arquitectura técnica obligatoria

## 5.1 Stack

- Swift 6.3 o superior dentro de la rama Swift 6.x soportada por Xcode estable.
- SwiftUI.
- Strict Concurrency habilitada.
- SwiftData para persistencia local inicial, detrás de repositorios/protocolos.
- Swift Testing para unit/integration tests puros cuando sea apropiado.
- XCTest/XCUITest para UI automation y APIs que todavía lo requieran.
- HealthKit.
- `HKWorkoutSession` + `HKLiveWorkoutBuilder` en watchOS para sesiones activas.
- AuthenticationServices para Sign in with Apple.
- App Intents cuando una acción pueda beneficiarse de integración con el sistema.
- WorkoutKit sólo donde aporte valor real y la disponibilidad del OS lo permita; no reemplaza la experiencia custom de fuerza.
- URLSession para red.
- Codable para contratos wire salvo justificación diferente.
- os.Logger para logging estructurado, sin PII/Health data sensible.

## 5.2 Deployment targets

Base recomendada salvo configuración existente del repositorio:

- iOS 18.0+
- watchOS 11.0+

Toda API posterior debe protegerse con disponibilidad.

La IA NO debe subir el deployment target silenciosamente.

## 5.3 Arquitectura

Usar un **modular monolith pragmático**.

Estructura objetivo:

```text
PR/
├── App/
│   ├── PRApp.swift
│   ├── AppEnvironment.swift
│   └── Navigation/
├── Features/
│   ├── Onboarding/
│   ├── Today/
│   ├── Workout/
│   ├── Progress/
│   ├── Coach/
│   ├── Gyms/
│   ├── Restrictions/
│   ├── Bodybuilding/
│   └── Settings/
├── Packages/
│   └── PRCore/
│       ├── Sources/
│       │   ├── Domain/
│       │   ├── TrainingEngine/
│       │   ├── ExerciseKnowledge/
│       │   ├── AgentCore/
│       │   ├── PersistenceContracts/
│       │   ├── HealthContracts/
│       │   └── SharedUtilities/
│       └── Tests/
├── Infrastructure/
│   ├── Persistence/
│   ├── HealthKit/
│   ├── Authentication/
│   ├── Networking/
│   └── Observability/
├── PRWatch/
│   ├── Workout/
│   ├── HealthKit/
│   └── Sync/
├── PRTests/
├── PRUITests/
└── Resources/
```

Si el repositorio ya posee otra estructura coherente, mantenerla y mapear responsabilidades equivalentes.

## 5.4 Separación crítica

```text
LLM / Agent Language Layer
          ↓ proposes intent
ActionPolicyValidator
          ↓ validates
Training Engine
          ↓ computes deterministic decision
Repositories / Health / Persistence
```

El LLM NUNCA es el Training Engine.

---

# 6. Núcleo de dominio

## 6.1 Identificadores

Utilizar tipos identificables y no strings sueltos cuando sea práctico.

```swift
struct ExerciseID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: UUID
}
```

Aplicar concepto equivalente para bloques, sesiones, gyms, restricciones y workouts.

## 6.2 Exercise

Un ejercicio DEBE representar biomecánica y función programática, no sólo nombre y músculo.

```swift
struct Exercise: Identifiable, Codable, Sendable, Equatable {
    let id: ExerciseID
    var canonicalName: String
    var aliases: [String]
    var movementPattern: MovementPattern
    var movementAngle: MovementAngle?
    var primaryMuscles: [MuscleContribution]
    var secondaryMuscles: [MuscleContribution]
    var equipment: EquipmentType
    var laterality: Laterality
    var jointClass: JointClass
    var stabilityDemand: DemandLevel
    var skillDemand: DemandLevel
    var systemicFatigueCost: FatigueCost
    var localFatigue: [MuscleGroup.ID: FatigueCost]
    var loadability: Loadability
    var defaultRoles: Set<ExerciseRole>
    var contraindicationTags: Set<RestrictionTag>
    var substitutionFamilyID: ExerciseFamily.ID
}
```

### MovementPattern mínimo

```swift
enum MovementPattern: String, Codable, Sendable {
    case horizontalPress
    case verticalPress
    case horizontalPull
    case verticalPull
    case squat
    case hinge
    case lunge
    case kneeExtension
    case kneeFlexion
    case hipExtension
    case shoulderAbduction
    case shoulderExtension
    case elbowFlexion
    case elbowExtension
    case calfPlantarFlexion
    case trunkFlexion
    case trunkExtension
    case trunkRotation
    case carry
    case conditioning
    case mobility
    case posing
}
```

## 6.3 ExerciseRole

```swift
enum ExerciseRole: String, Codable, Sendable, Hashable {
    case anchor
    case primaryCompound
    case secondaryCompound
    case priorityIsolation
    case accessoryIsolation
    case optionalAccessory
    case warmup
    case mobility
    case conditioning
    case posing
}
```

## 6.4 GymProfile

```swift
struct GymProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var equipmentAvailability: [EquipmentAvailability]
    var machineInstances: [MachineProfile]
    var learnedBusyPatterns: [BusyPattern]
}
```

Diferenciar:

- `doesNotExist`: persistente para ese gym hasta que usuario lo cambie;
- `occupied`: estado temporal de la sesión;
- `unknown`: todavía no aprendido;
- `available`: confirmado o inferido.

## 6.5 MachineProfile

La carga de dos máquinas del mismo tipo NO es comparable automáticamente.

```swift
struct MachineProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var gymID: GymProfile.ID
    var exerciseID: ExerciseID
    var manufacturer: String?
    var model: String?
    var userLabel: String?
}
```

El historial de carga debe permitir clave por `exercise + machineInstance`.

## 6.6 TrainingBlock

```swift
struct TrainingBlock: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var goal: TrainingGoal
    var phase: BodyCompositionPhase
    var startDate: Date
    var plannedWeeks: Int
    var sessions: [SessionTemplate]
    var muscleTargets: [MuscleVolumeTarget]
    var priorities: [MusclePriority]
    var progressionPolicy: ProgressionPolicy
    var deloadPolicy: DeloadPolicy
    var varietyPolicy: VarietyPolicy
    var status: BlockStatus
}
```

`plannedWeeks` normalmente 4...8 para MVP.

## 6.7 SessionTemplate vs WorkoutSessionRecord

Separar intención de resultado.

`SessionTemplate`: lo planeado.
`WorkoutSessionRecord`: lo realmente realizado.

Nunca mutar el histórico para hacer que coincida con el plan.

## 6.8 SetPrescription y SetRecord

```swift
struct SetPrescription: Codable, Sendable {
    var targetRepRange: ClosedRange<Int>
    var targetRIR: ClosedRange<Int>?
    var targetLoad: Double?
    var loadUnit: LoadUnit
    var restSeconds: ClosedRange<Int>
    var isWarmup: Bool
}

struct SetRecord: Identifiable, Codable, Sendable {
    let id: UUID
    var exerciseID: ExerciseID
    var machineProfileID: UUID?
    var performedAt: Date
    var weight: Double
    var unit: LoadUnit
    var reps: Int
    var rir: Int?
    var perceivedDifficulty: DifficultyFeedback?
    var painFeedback: PainFeedback?
}
```

Peso y reps son user-entered para MVP.

---

# 7. Training Engine

El Training Engine DEBE ser determinista bajo las mismas entradas, salvo componentes explícitamente seeded.

## 7.1 Componentes

```text
TrainingEngine
├── BlockPlanner
├── SessionComposer
├── ExerciseOrderEngine
├── SubstitutionEngine
├── TimeBudgetOptimizer
├── ProgressionEngine
├── RecoveryDecisionEngine
├── VolumeAllocator
├── DeloadEngine
├── RestrictionPolicyEngine
└── ExplanationFactsBuilder
```

Cada componente debe poder testearse sin UI, sin HealthKit real y sin LLM.

---

# 8. Planificación por bloques

## 8.1 Reglas

- Crear bloques de 4–8 semanas inicialmente.
- Mantener anchors para medir progreso.
- Variar rotatables según preferencia, adaptación y necesidad.
- No cambiar un ejercicio sólo porque el usuario lo completó muchas veces.
- Cambiar cuando exista una razón: estancamiento, aburrimiento explícito, incompatibilidad, bloque nuevo, equipo, restricción, especialización o mala adherencia.
- Un bloque puede terminar antes si cambia objetivo/fase/restricción mayor.

## 8.2 Tipos de estructura soportados en MVP

- Full body 2–4 días.
- Upper/Lower 4 días.
- Push/Pull/Legs 3–6 días.
- Torso/Limbs u otra estructura sólo si el motor tiene reglas explícitas.

No usar un split por moda; seleccionarlo por disponibilidad, objetivo y adherencia.

---

# 9. Exercise Order Engine

## 9.1 Principio

La regla NO es simplemente “compuestos primero”. La prioridad es:

1. Seguridad/restricciones.
2. Técnica/potencia cuando aplique.
3. Ejercicio/músculo prioritario del bloque.
4. Compuestos principales relevantes al objetivo.
5. Compuestos secundarios.
6. Aislados prioritarios.
7. Aislados accesorios.
8. Opcionales/conditioning/posing.

## 9.2 Interferencia

Calcular una penalización cuando un ejercicio anterior fatiga significativamente músculos requeridos por un ejercicio posterior prioritario.

Ejemplo:

`Triceps Pushdown → Bench Press` tiene más penalización si bench es prioridad que `Bench Press → Triceps Pushdown`.

## 9.3 Score sugerido

No hardcodear sin tests, pero el modelo conceptual es:

```text
orderScore =
  goalPriority
+ musclePriority
+ exerciseRolePriority
+ skillDemandPriority
+ loadabilityPriority
- accumulatedLocalFatiguePenalty
- systemicFatiguePenalty
- restrictionPenalty
- equipmentPenalty
```

Una restricción incompatible produce exclusión, no sólo penalización.

---

# 10. Substitution Engine

## 10.1 Casos

- máquina no existe;
- máquina ocupada;
- usuario no quiere ese ejercicio;
- restricción activa;
- cambio de gym;
- dolor/molestia durante sesión;
- tiempo reducido;
- equipo temporalmente fuera de servicio.

## 10.2 Diferencia obligatoria

`occupied` NO modifica permanentemente el gym profile.
`doesNotExist` SÍ actualiza disponibilidad del gym.

## 10.3 Ranking

El sustituto debe preservar en orden:

1. restricciones/safety;
2. objetivo/rol programático;
3. patrón de movimiento;
4. músculo primario;
5. ángulo;
6. rango de reps apropiado;
7. fatiga y estabilidad;
8. disponibilidad;
9. historial del usuario;
10. preferencias;
11. continuidad del bloque.

Score conceptual:

```text
muscleMatch            0.30
movementPatternMatch   0.20
trainingRoleMatch      0.15
angleMatch             0.10
restrictionSafety      gate
fatigueProfileMatch    0.08
stabilityMatch         0.05
userHistoryConfidence  0.05
preferenceMatch        0.04
equipmentConfidence    0.03
```

Los pesos son configuración versionada, no constantes dispersas.

## 10.4 Máquina ocupada: estrategia preferida

1. Intentar reordenar sin perjudicar ejercicios prioritarios.
2. Hacer otro ejercicio de baja interferencia.
3. Reintentar posteriormente.
4. Si sigue ocupada, ofrecer sustitución.

---

# 11. Time-aware Training

## 11.1 Tiempo como constraint

El usuario puede seleccionar:

```swift
enum TimeConstraint {
    case hard(minutes: Int)
    case flexible(targetMinutes: Int, tolerance: Int)
    case unconstrained
}
```

`hard`: no exceder salvo acción explícita del usuario.
`flexible`: optimizar alrededor del rango.
`unconstrained`: priorizar calidad; no añadir volumen innecesario.

## 11.2 Si hay menos tiempo

Orden de acciones:

1. preservar anchors/prioridades;
2. reducir opcionales;
3. reducir accesorios de menor prioridad;
4. aplicar superseries compatibles cuando no comprometan objetivo;
5. reducir volumen marginal;
6. redistribuir volumen a otra sesión de la semana cuando tenga sentido.

## 11.3 Si hay más tiempo

NO triplicar volumen.

Opciones posibles según objetivo/fase:

- descanso más completo;
- técnica;
- movilidad;
- cardio moderado;
- posing;
- sets adicionales sólo dentro de límites del volumen semanal y prioridad;
- trabajo opcional de especialización.

## 11.4 Aprendizaje de duración

Registrar timestamps de ejercicios/sets. Mantener estimaciones EWMA por usuario:

```swift
struct ExerciseDurationProfile {
    var averageSeconds: Double
    var sampleCount: Int
    var confidence: Double
}
```

El motor debe favorecer tiempos personales sobre defaults cuando la confianza sea suficiente.

---

# 12. Progression Engine

## 12.1 Principio

Progreso no significa únicamente subir peso.

Reconocer:

- más reps misma carga;
- más carga mismas reps;
- más sets con calidad;
- mejor RIR/RPE a misma carga;
- mejor e1RM estimado;
- adherencia consistente;
- completar rango objetivo.

## 12.2 Estrategias

```swift
enum ProgressionStrategy: Codable, Sendable {
    case doubleProgression
    case linearLoad
    case repGoal
    case rirAutoregulated
    case strengthTopSetBackoff
    case maintain
}
```

Default hipertrofia: `doubleProgression`.
Default fuerza de básicos: estrategia específica validada por experiencia y bloque.

## 12.3 Regla conservadora inicial de double progression

Subir carga sólo si:

- todas las working sets relevantes alcanzan el rango superior o condición configurada;
- feedback de esfuerzo no indica fallo excesivo;
- no existe restricción/dolor relevante;
- no hay caída significativa reciente que justifique mantener;
- el incremento disponible es razonable.

Si no se conoce incremento de máquina, pedir al usuario o usar el menor incremento configurado para esa instancia.

## 12.4 Primera vez con un ejercicio

Nunca inventar precisión.

Estado:

`loadConfidence = low`

Mostrar:

> “Primera vez con este ejercicio. Usa una serie de calibración y ajustaremos después.”

---

# 13. Recovery, descanso y deload

## 13.1 Fuentes

RecoveryDecisionEngine puede considerar:

- caída de rendimiento por ejercicio;
- cumplimiento del bloque;
- sets cercanos al fallo;
- carga reciente;
- frecuencia de sesiones;
- feedback subjetivo;
- actividad autorizada de HealthKit;
- sueño sólo si el usuario autorizó y la app realmente lo utiliza;
- tendencias de HR/resting HR sólo como contexto, nunca diagnóstico.

## 13.2 Resultados

```swift
enum RecoveryDecision: Sendable {
    case trainAsPlanned
    case trainWithAdjustments(RecoveryAdjustment)
    case recoverySession
    case restRecommended
}
```

## 13.3 Regla de honestidad

No generar un score de recuperación con falsa precisión si no existe una metodología validada.

Preferir estados interpretables:

- normal;
- fatiga moderada;
- fatiga elevada;
- descanso recomendado.

## 13.4 Deload

Puede ser:

- planeado por bloque;
- disparado por patrón de fatiga/rendimiento;
- solicitado por usuario.

Un deload cumplido cuenta como adherencia.

---

# 14. HealthKit y Apple Watch

## 14.1 Principio

HealthKit aporta contexto y la fuente principal para datos del workout que Apple mide mejor. Nuestra base aporta fuerza y semántica del entrenamiento.

### HealthKit

- workout;
- active energy;
- heart rate durante workout cuando esté disponible;
- duración;
- datos adicionales únicamente con permiso y necesidad demostrada.

### Base propia

- ejercicio;
- máquina;
- peso;
- reps;
- sets;
- RIR opcional;
- sustituciones;
- orden;
- PRs;
- progresión;
- bloque;
- razones de decisiones.

## 14.2 Sesión watchOS

Al iniciar una sesión desde PR:

1. Crear `HKWorkoutConfiguration` apropiada.
2. Crear `HKWorkoutSession`.
3. Usar `HKLiveWorkoutBuilder` para data live en Apple Watch.
4. Mantener estado propio de sets/reps/peso independiente pero asociado al mismo workout lógico.
5. Al finalizar, cerrar workout correctamente.
6. Persistir referencia estable que permita reconciliar el registro propio con `HKWorkout`.

## 14.3 No detectar peso/reps automáticamente en MVP

Peso y reps son entrada del usuario.

Apple Watch debe optimizar entrada con:

- valor sugerido precargado;
- incremento/decremento rápido;
- Digital Crown cuando UX lo permita;
- botón grande de completar set;
- rest timer automático.

## 14.4 Offline

El workout activo NO depende del backend.

Acciones críticas se escriben localmente antes de cualquier sync remoto.

---

# 15. Reconciliación de calorías y workouts

## 15.1 Regla central

> **Nunca sumar estimaciones/calorías de dos fuentes si describen el mismo workout.**

## 15.2 Workout canonical

Crear:

```swift
enum EnergySource: String, Codable, Sendable {
    case ourHealthKitWorkout
    case externalAppleWorkout
    case externalHealthKitWorkout
    case fallbackEstimate
}

struct CanonicalWorkoutEnergy: Codable, Sendable {
    var activeKilocalories: Double
    var source: EnergySource
    var confidence: Double
}
```

## 15.3 Prioridad

1. Workout iniciado por PR con HealthKit/Apple Watch.
2. Workout nativo Apple Watch.
3. Otro `HKWorkout` confiable.
4. Estimación fallback.

## 15.4 Reconciliation

Dos workouts son candidatos a duplicado si:

- overlap temporal >= 80% o regla equivalente configurable;
- tipo compatible;
- device/source indica posible mismo evento;
- inicio/fin están dentro de tolerancia.

No eliminar automáticamente un workout externo del Health store. Sólo decidir cómo mostrar/agregar internamente.

## 15.5 Active vs Total

Mostrar por defecto `Active Energy` si esa es la métrica HealthKit disponible.

No presentar total estimado sin etiquetarlo claramente como estimación.

---

# 16. Injuries & Restrictions

## 16.1 Propósito

Permitir documentar restricciones y adaptar entrenamiento, NO diagnosticar.

```swift
enum RestrictionSource: String, Codable, Sendable {
    case userReported
    case professionalGuidance
}

struct TrainingRestriction: Identifiable, Codable, Sendable {
    let id: UUID
    var bodyRegion: BodyRegion
    var side: BodySide?
    var startDate: Date
    var reviewDate: Date?
    var status: RestrictionStatus
    var source: RestrictionSource
    var forbiddenPatterns: Set<MovementPattern>
    var forbiddenExerciseIDs: Set<ExerciseID>
    var allowedExerciseIDs: Set<ExerciseID>
    var restrictionTags: Set<RestrictionTag>
    var notes: String?
}
```

## 16.2 Reglas

- Restricción incompatible = ejercicio no se programa.
- Si existe dolor relevante durante ejercicio, suspender progresión de ese movimiento en esa sesión.
- Nunca asumir recuperación porque pasó una fecha; pedir revisión del usuario.
- Instrucciones de profesional pueden estructurarse después de confirmación explícita.
- No generar protocolos de rehabilitación como si fueran tratamiento clínico.

## 16.3 Feedback de molestia

```swift
enum PainFeedback: Int, Codable, Sendable {
    case none = 0
    case mild = 1
    case moderate = 2
    case high = 3
}
```

`moderate/high` dispara flujo conservador y no progresión automática.

---

# 17. Educación: novato → experto

## 17.1 Progressive Disclosure

La UI expone complejidad conforme el usuario la necesita.

### Coach Assistance

```swift
enum CoachingDetailLevel: String, Codable, Sendable {
    case guided
    case balanced
    case advanced
}
```

- `guided`: lenguaje simple, más educación contextual.
- `balanced`: mezcla.
- `advanced`: valores técnicos y mínima explicación salvo anomalía.

El usuario siempre puede cambiarlo manualmente.

## 17.2 Enseñanza contextual

Explicar concepto cuando sucede:

- RIR cuando el usuario necesita calibrar esfuerzo;
- progressive overload después de primeras progresiones;
- deload cuando ocurre;
- sustitución cuando falta equipo;
- orden cuando se prioriza un movimiento;
- volumen cuando el usuario intenta aumentarlo mucho.

## 17.3 Autonomía

Meta educativa:

Principiante: “qué hacer”.
Intermedio: “por qué”.
Avanzado: “cómo respondo yo”.

---

# 18. Bodybuilding Mode

No es obligatorio para MVP inicial, pero la arquitectura DEBE soportarlo.

## 18.1 Fases

```swift
enum BodybuildingPhase: String, Codable, Sendable {
    case offSeason
    case cut
    case contestPrep
    case recovery
}
```

## 18.2 Funciones previstas

- prioridades musculares;
- specialization blocks;
- medidas corporales;
- progress photos con consentimiento;
- posing sessions;
- timeline de competición;
- volumen por grupo muscular;
- preservación de masa/rendimiento en déficit;
- análisis longitudinal.

## 18.3 Seguridad

No recomendar:

- fármacos;
- sustancias controladas;
- deshidratación extrema;
- manipulación peligrosa de electrolitos;
- prácticas médicas de contest prep.

El módulo de competición se limita a entrenamiento, posing, seguimiento y organización salvo futuras funcionalidades aprobadas con revisión médica/legal.

---

# 19. Gamificación y PRs

## 19.1 PR types

- load PR;
- rep PR;
- estimated 1RM PR;
- volume PR;
- consistency milestone;
- block completion;
- specialization completion.

## 19.2 Rachas

No utilizar “días consecutivos entrenando” como métrica principal.

Usar `consistencyStreak` basada en cumplimiento del plan semanal.

Días de descanso y deload programados cuentan como cumplimiento.

## 19.3 Regla

Gamificar conductas que queremos repetir:

- adherencia;
- progreso sostenible;
- descanso adecuado;
- completar bloques;
- aprendizaje;
- consistencia.

---

# 20. Agentic Architecture

## 20.1 Responsabilidad del LLM

El LLM puede:

- interpretar lenguaje natural;
- resumir contexto;
- explicar decisiones ya calculadas;
- convertir frases del usuario en `AgentIntent` estructurado;
- proponer acciones candidatas.

No puede decidir unilateralmente:

- cargas finales;
- volumen final;
- safety overrides;
- eliminación de restricciones;
- diagnósticos;
- calorías;
- estado clínico.

## 20.2 AgentIntent

```swift
enum AgentIntent: Sendable {
    case setTimeConstraint(TimeConstraint)
    case equipmentUnavailable(EquipmentReference, UnavailabilityReason)
    case requestExerciseSwap(ExerciseID)
    case reportFatigue(UserFatigueFeedback)
    case reportPain(PainReport)
    case changeGoal(TrainingGoal)
    case changePhase(BodyCompositionPhase)
    case changeGym(GymProfile.ID)
    case askWhy(DecisionID)
    case updateRestriction(TrainingRestrictionDraft)
    case requestPlanAdjustment(PlanAdjustmentRequest)
}
```

## 20.3 AgentAction

Toda acción pasa por `ActionPolicyValidator`.

```swift
enum AgentAction: Sendable {
    case recomputeSession
    case reorderExercises
    case replaceExercise
    case adjustVolume
    case adjustLoadTarget
    case recommendRest
    case rescheduleWorkout
    case updateGymKnowledge
    case saveRestriction
    case presentExplanation
}
```

## 20.4 Tool contracts

Las tools del agente nunca reciben acceso genérico a DB. Exponer comandos estrechos:

```text
getTodayContext
getTrainingHistory
getActiveRestrictions
getGymProfile
setTimeConstraint
markEquipmentOccupied
markEquipmentMissing
requestSubstitution
requestReorder
requestProgressionEvaluation
requestRecoveryEvaluation
requestPlanRebuild
recordUserFeedback
explainDecision
```

Cada tool devuelve tipos estructurados y auditables.

## 20.5 Backend LLM

La app cliente NO almacena claves de proveedor.

Contrato recomendado:

```http
POST /v1/agent/interpret
POST /v1/agent/explain
```

`interpret` transforma texto → intent.
`explain` transforma facts → explicación.

El cliente conserva capacidad completa de workout sin backend.

---

# 21. Explainability

Toda decisión importante genera:

```swift
struct DecisionRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let type: DecisionType
    let inputFacts: [DecisionFact]
    let action: DecisionActionSummary
    let ruleIDs: [EvidenceRuleID]
    let userOverrideAllowed: Bool
}
```

Ejemplos que requieren explicación:

- cambio de carga;
- reducción/aumento de sets;
- sustitución;
- deload;
- descanso;
- reordenamiento prioritario;
- cambio de bloque.

La UI debe poder presentar “¿Por qué?” con 1–4 facts concretos, no un ensayo.

---

# 22. Evidence Registry

## 22.1 Objeto

```swift
struct EvidenceRule: Identifiable, Codable, Sendable {
    let id: EvidenceRuleID
    var name: String
    var category: EvidenceCategory
    var confidence: EvidenceConfidence
    var version: Int
    var parameters: [String: Double]
    var references: [EvidenceReference]
    var active: Bool
}
```

No dispersar constantes científicas en Views.

## 22.2 Versionado

Si una regla cambia:

- incrementar versión;
- registrar migration/impact;
- mantener DecisionRecord con rule version usada.

Esto hace auditable el coaching.

---

# 23. Requerimientos funcionales

## RF-001 Cuenta
El usuario puede crear/iniciar sesión con Sign in with Apple.

## RF-002 Uso sin HealthKit
El usuario puede usar funciones core aunque deniegue permisos de HealthKit.

## RF-003 Onboarding
El usuario puede definir objetivo, fase, experiencia, días, tiempo, gym inicial, variedad y restricciones.

## RF-004 Training Block
El sistema genera un bloque de 4–8 semanas válido para objetivo, disponibilidad y experiencia.

## RF-005 Today
El usuario siempre puede identificar claramente la sesión de hoy y comenzar en máximo dos interacciones desde Home.

## RF-006 Session Adaptation
El usuario puede indicar tiempo disponible y recibir sesión adaptada sin destruir objetivos del bloque.

## RF-007 Logging
El usuario puede registrar peso y reps por set con valores sugeridos precargados.

## RF-008 Rest Timer
Completar set inicia rest timer configurable automáticamente.

## RF-009 Exercise Order
La sesión respeta prioridad, demanda, fatiga e interferencia.

## RF-010 Machine Occupied
El usuario puede marcar equipo ocupado y el sistema intenta reordenar antes de sustituir.

## RF-011 Machine Missing
El usuario puede marcar equipo inexistente y el gym profile se actualiza.

## RF-012 Smart Substitution
El sistema recomienda sustituciones equivalentes por rol/patrón/músculo/seguridad.

## RF-013 Per-machine History
El sistema mantiene historial independiente por máquina cuando corresponda.

## RF-014 Progression
El sistema calcula recomendación de progresión explicable.

## RF-015 PRs
El sistema detecta y registra PRs válidos.

## RF-016 Consistency
El sistema calcula cumplimiento semanal, sin penalizar descanso programado.

## RF-017 HealthKit Workout
El sistema puede registrar workout mediante HealthKit cuando autorizado.

## RF-018 Watch Companion
El usuario puede completar una sesión de fuerza básica desde Apple Watch.

## RF-019 Calorie Reconciliation
El sistema evita doble conteo de calorías/workouts duplicados.

## RF-020 External Workout Detection
El sistema puede reconocer workouts externos autorizados y asociarlos a contexto sin inventar sets/reps.

## RF-021 Recovery
El sistema puede ajustar o recomendar descanso con explicación.

## RF-022 Deload
El sistema soporta semanas de descarga.

## RF-023 Restrictions
El usuario puede documentar restricciones y fechas de revisión.

## RF-024 Pain Feedback
El usuario puede reportar molestia y el sistema bloquea progresión incompatible en esa sesión.

## RF-025 Explainability
El usuario puede ver la razón de cambios significativos.

## RF-026 Coaching Detail
El usuario puede cambiar el nivel de detalle educativo.

## RF-027 Agent Chat/Input
El usuario puede expresar restricciones operativas en lenguaje natural.

## RF-028 Offline Workout
El workout completo puede registrarse sin internet.

## RF-029 Sync
Los cambios locales pendientes se sincronizan idempotentemente cuando vuelve la red.

## RF-030 Export
El usuario puede exportar su historial estructurado en formato portable antes de GA.

## RF-031 Bodybuilding Architecture
El dominio soporta prioridades y fases bodybuilding aunque la UI avanzada llegue después.

## RF-032 Gym Switching
El usuario puede cambiar de gym y la sesión se adapta al equipment profile seleccionado.

## RF-033 Goal Change
Cambiar objetivo/fase crea transición de plan sin borrar historial.

---

# 24. Requerimientos no funcionales

## RNF-001 Offline-first
Toda acción crítica de workout debe persistirse localmente primero.

## RNF-002 Performance UI
Interacciones del workout deben responder perceptualmente inmediato; target <100 ms para mutaciones locales ordinarias.

## RNF-003 Launch
Objetivo de cold launch <2 s en hardware compatible representativo, medido en build Release antes de GA.

## RNF-004 Reliability
Ningún crash o fallo de red debe eliminar un SetRecord ya confirmado.

## RNF-005 Concurrency
Cumplir Swift 6 strict concurrency sin data races conocidos.

## RNF-006 Battery
No muestrear sensores manualmente con frecuencia innecesaria cuando HealthKit ya provee la ruta adecuada.

## RNF-007 Privacy
Principio de mínima recolección; no almacenar HealthKit raw data remotamente si no es necesario.

## RNF-008 Security
No secrets en bundle, logs ni source control.

## RNF-009 Accessibility
VoiceOver, Dynamic Type, contraste, touch targets y Reduced Motion en flujos críticos.

## RNF-010 Testability
TrainingEngine debe correr completamente con fakes sin frameworks Apple de dispositivo.

## RNF-011 Maintainability
Cero lógica de negocio significativa en Views.

## RNF-012 Observability
Errores y decisiones técnicas se registran con logs estructurados sin PII sensible.

## RNF-013 Localization
Español es idioma inicial; strings deben ser localizables y la arquitectura preparada para inglés.

## RNF-014 Idempotency
Sync y comandos remotos críticos deben soportar retry sin duplicar sets/workouts.

## RNF-015 Data Migration
Cambios de modelo persistente requieren migration plan y tests.

---

# 25. Requerimientos de dominio

## RD-001
Plan y resultado son entidades separadas.

## RD-002
Exercise y MachineInstance son entidades separadas.

## RD-003
Objetivo y fase energética son dimensiones separadas.

## RD-004
Un usuario puede tener múltiples gyms.

## RD-005
Un gym aprende disponibilidad persistente; ocupación es temporal.

## RD-006
Un ejercicio pertenece a una familia de sustitución, pero pertenecer a la familia no garantiza equivalencia total.

## RD-007
Cada decisión debe poder referenciar hechos y regla/version.

## RD-008
Los workouts externos pueden tener energía/duración pero no sets inventados.

## RD-009
Una restricción tiene estado y fecha de revisión; no “expira” silenciosamente.

## RD-010
El tiempo disponible es input de composición, no simple filtro final.

---

# 26. Requerimientos de negocio

## RNEG-001 Diferenciación
El producto debe priorizar coaching adaptativo sobre dashboards decorativos.

## RNEG-002 Simplicidad
La UX core de workout debe competir con los loggers más rápidos del mercado.

## RNEG-003 Retención por valor
La retención debe provenir de aprendizaje/personalización, no de dark patterns.

## RNEG-004 Confianza
Las recomendaciones significativas son explicables y auditables.

## RNEG-005 Apple-first
La experiencia iPhone/Apple Watch es primera clase; no un wrapper web.

## RNEG-006 Datos
El historial de entrenamiento pertenece funcionalmente al usuario y debe ser exportable.

## RNEG-007 Salud
No monetizar ni vender Health data de forma incompatible con políticas de Apple o expectativas de privacidad.

## RNEG-008 Escalabilidad funcional
MVP debe permitir evolución a Bodybuilding Mode sin reescribir el core.

---

# 27. Reglas de negocio

## RN-001
Descanso programado mantiene consistency streak.

## RN-002
No aumentar volumen sólo por más tiempo disponible.

## RN-003
No subir carga ante dolor moderado/alto reportado.

## RN-004
No eliminar una restricción automáticamente por fecha.

## RN-005
`occupied` no modifica disponibilidad permanente.

## RN-006
`doesNotExist` modifica el gym profile.

## RN-007
No comparar directamente cargas entre máquinas distintas sin historial individual.

## RN-008
No sumar calorías de workouts reconciliados como el mismo evento.

## RN-009
No inventar sets/reps de workout externo.

## RN-010
La prioridad muscular puede alterar el orden clásico compuesto→aislado cuando sea justificable.

## RN-011
Un ejercicio anchor no rota sólo por variedad si sigue cumpliendo su propósito.

## RN-012
Una sesión hard-time no excede el límite sin consentimiento explícito.

## RN-013
Toda progresión de carga debe respetar incremento disponible de equipo.

## RN-014
El usuario avanzado puede overridear recomendaciones no relacionadas con seguridad; el override queda registrado.

## RN-015
La IA jamás diagnostica.

## RN-016
Una feature de IA no puede bloquear el workout offline.

## RN-017
Toda acción del agente que muta dominio pasa por validator/engine.

## RN-018
La UI nunca debe presentar un valor estimado como medido.

---

# 28. Requerimientos de usuario

## RU-001 Principiante
“Quiero abrir la app y saber exactamente qué hacer hoy sin conocer programación.”

## RU-002 Principiante
“Quiero entender gradualmente por qué hago cada cosa.”

## RU-003 Intermedio
“Quiero que mi rutina se adapte cuando tengo menos tiempo.”

## RU-004 Todos
“Si una máquina está ocupada o no existe, quiero una alternativa inmediata.”

## RU-005 Todos
“Quiero registrar cada set rápido.”

## RU-006 Todos
“Quiero que la app recuerde mis pesos anteriores.”

## RU-007 Avanzado
“Quiero controlar volumen, prioridades, RIR, bloques y progresión.”

## RU-008 Avanzado
“Quiero entender patrones de mi propio rendimiento.”

## RU-009 Usuario con restricción
“Quiero documentar una restricción y que el plan la respete.”

## RU-010 Bodybuilder
“Quiero especializar grupos musculares y cambiar fase sin perder mi historial.”

## RU-011 Usuario Apple Watch
“Quiero entrenar sin sacar el teléfono en cada serie.”

## RU-012 Todos
“Quiero que descansar correctamente no rompa mis logros.”

---

# 29. Requerimientos de calidad

## RC-001 Exactitud de dominio
El Training Engine debe tener tests exhaustivos para edge cases.

## RC-002 Determinismo
Con inputs iguales, recomendaciones del engine deben ser reproducibles.

## RC-003 Robustez
Datos inválidos nunca producen NaN, cargas negativas, reps negativas o sesión imposible.

## RC-004 UX
Flujo normal de set completado: una acción si peso/reps coinciden con sugerencia.

## RC-005 Offline
100% del tracking básico debe funcionar sin red.

## RC-006 Crash-free
Objetivo >=99.8% crash-free sessions antes de escalar GA.

## RC-007 Test coverage
Objetivo: >=90% branch/behavior coverage de componentes críticos del Training Engine y >=80% del dominio puro. Coverage no sustituye tests útiles.

## RC-008 Accessibility
Critical flows deben pasar auditoría manual VoiceOver antes de release.

## RC-009 Privacy
Health permissions sólo se solicitan con razón contextual visible.

## RC-010 Explainability
100% de cambios automáticos de carga/volumen/ejercicio/descanso deben tener DecisionRecord.

---

# 30. Estados de workout

```swift
enum WorkoutLifecycleState: Sendable {
    case planned
    case preparing
    case active
    case paused
    case finishing
    case completed
    case abandoned
}
```

Set states:

```swift
enum SetLifecycleState: Sendable {
    case planned
    case ready
    case completed
    case skipped
    case replaced
}
```

Transiciones inválidas deben rechazarse en dominio.

---

# 31. Eventos de dominio

```swift
enum TrainingEvent: Sendable {
    case workoutStarted
    case setCompleted(SetRecord.ID)
    case restStarted
    case exerciseCompleted(ExerciseID)
    case equipmentMarkedOccupied
    case equipmentMarkedMissing
    case exerciseReplaced
    case exercisesReordered
    case painReported
    case timeConstraintChanged
    case workoutCompleted
    case workoutImported
    case blockCompleted
    case personalRecordAchieved
}
```

Los eventos no requieren event sourcing completo. Se usan para coordinación, analytics local y audit trail donde aporte valor.

---

# 32. Testing obligatorio

## 32.1 Unit tests mínimos por feature

Para cada rule/engine:

- happy path;
- lower boundary;
- upper boundary;
- invalid input;
- restriction conflict;
- user override cuando aplique;
- determinism;
- persistence mapping si existe.

## 32.2 Training Engine test fixtures

Crear builders/factories:

```text
NoviceHypertrophyFixture
AdvancedStrengthFixture
BodybuildingCutFixture
InjuryRestrictionFixture
BusyGymFixture
ShortWorkoutFixture
LongWorkoutFixture
```

## 32.3 HealthKit

No depender de HealthKit real en unit tests.

```swift
protocol HealthWorkoutStore {
    func requestAuthorization() async throws -> HealthAuthorizationResult
    func startWorkout(...) async throws -> WorkoutHandle
    func finishWorkout(...) async throws -> HealthWorkoutSummary
    func recentWorkouts(...) async throws -> [ExternalWorkout]
}
```

`HealthKitWorkoutStore` = producción.
`FakeHealthWorkoutStore` = tests.

## 32.4 Agent

Tests deben verificar:

- malformed output no muta dominio;
- unknown intent pide reformulación o falla seguro;
- forbidden action es rechazada;
- explanation no puede cambiar hechos;
- no network no bloquea sesión.

## 32.5 UI critical smoke tests

- onboarding mínimo;
- start workout;
- complete set;
- edit weight/reps;
- mark occupied;
- substitution;
- finish workout;
- open PR achievement;
- create restriction;
- offline workout.

---

# 33. Definition of Done global

Una historia está `DONE` sólo si:

- [ ] código implementado;
- [ ] diseño de dominio alineado;
- [ ] tests añadidos/actualizados;
- [ ] tests pasan;
- [ ] app compila;
- [ ] watch target compila si fue afectado;
- [ ] accesibilidad revisada si hay UI;
- [ ] strings localizables;
- [ ] no secretos;
- [ ] no logs sensibles;
- [ ] aceptación verificada;
- [ ] documentación actualizada;
- [ ] backlog marcado con evidencia de cierre.

---

# 34. Criterios de producto para el MVP

El MVP es exitoso funcionalmente si un usuario puede:

1. registrarse con Apple;
2. completar onboarding;
3. obtener bloque válido;
4. abrir Today y comenzar;
5. cambiar tiempo a 30/45/60/90+;
6. registrar sets rápido;
7. marcar máquina ocupada;
8. recibir reordenamiento/sustitución;
9. terminar workout;
10. ver PR/progreso;
11. sincronizar HealthKit sin duplicar energía;
12. documentar restricción;
13. recibir plan adaptado por esa restricción;
14. completar todo offline salvo funciones explícitamente LLM/network;
15. entender “por qué” de un cambio importante.

---

# 35. Métricas de producto recomendadas

Sin recolectar Health data innecesaria:

- `timeToFirstWorkout`;
- `medianTapsPerCompletedSet`;
- `% workouts completed`;
- `% AI/engine recommendations overridden`;
- `% substitutions accepted`;
- `weeklyPlanAdherence`;
- `workoutAbandonmentRate`;
- `averagePlanningFriction`;
- `DecisionExplanationOpenRate`;
- `% workouts completed offline successfully`;
- data-loss incidents = 0.

No optimizar “tiempo dentro de la app”. En workout, menor atención puede ser mejor UX.

---

# 36. API y sync contracts mínimos

La app debe usar identificadores idempotentes generados cliente-side para registros críticos.

Ejemplo conceptual:

```json
{
  "id": "uuid",
  "workout_id": "uuid",
  "exercise_id": "uuid",
  "weight": 82.5,
  "unit": "kg",
  "reps": 8,
  "performed_at": "ISO-8601",
  "client_revision": 4
}
```

Sync policy:

- local write first;
- enqueue operation;
- retry exponential;
- server accepts idempotency key;
- conflicts de historial append-only favorecen no perder información;
- no borrar datos localmente hasta confirmación.

---

# 37. Privacidad y seguridad

## 37.1 HealthKit

- pedir sólo tipos necesarios;
- no inferir permiso denegado como dato;
- no bloquear core;
- explicar beneficio antes del prompt del sistema.

## 37.2 LLM data minimization

Enviar sólo features/contexto necesario.

Preferir:

```json
{
  "recent_performance_trend": "declining",
  "available_time_minutes": 45,
  "active_restrictions": ["right_shoulder_overhead"]
}
```

sobre enviar historial HealthKit completo.

## 37.3 Logs

No loggear:

- nombre real;
- Apple user identifier en texto plano;
- HealthKit samples;
- injury notes;
- prompts completos con datos sensibles.

---

# 38. Estrategia de error

Errores de infraestructura se convierten en estados recuperables.

Ejemplos:

- HealthKit unavailable → workout local;
- backend unavailable → engine local + explanation fallback templated;
- sync failure → pending badge, no pérdida;
- workout builder failure → persistir fuerza local y mostrar estado Health sync pendiente;
- corrupted recommendation → usar última sesión válida o safe default del engine;
- no substitution segura → decirlo claramente y pedir elegir otro patrón, no inventar.

---

# 39. UX principles obligatorios

## Today

Mostrar como máximo la información necesaria para iniciar.

```text
HOY
Upper A · ~54 min
[ EMPEZAR ]
```

## Active Workout

Default:

```text
Bench Press
82.5 kg × 8
Set 2 / 4
[ ✓ HECHO ]
[ OCUPADO ]
```

## Why

```text
¿Por qué 82.5 kg?
Completaste 80 kg dentro del rango en tus últimas sesiones y tienes margen suficiente.
```

No presentar dashboards durante el workout salvo datos relevantes.

---

# 40. Producto avanzado: self-knowledge

Para usuarios avanzados, el sistema debe poder evolucionar a responder con datos propios:

- volumen donde históricamente progresa mejor;
- descanso asociado a mejor rendimiento;
- exercises con mayor adherencia;
- frecuencia que mejor tolera;
- patrones de sustitución;
- tiempo real por sesión;
- respuesta en déficit vs superávit;
- estancamientos.

Las conclusiones deben etiquetarse como **observadas en historial**, no causalidad científica demostrada.

---

# 41. Fuera de alcance inicial

No implementar en MVP sin historia específica:

- reconocimiento automático de reps;
- reconocimiento automático de peso;
- computer vision de técnica;
- diagnóstico médico;
- prescripción clínica de rehabilitación;
- dieta completa/macros automáticos;
- wearables no Apple;
- social feed;
- marketplace de entrenadores;
- ranking competitivo público;
- detección crowdsourced en tiempo real del gym;
- esteroides/sustancias;
- contest prep médico/nutricional extremo.

---

# 42. Orden de implementación obligatorio

1. Dominio puro.
2. Persistencia local.
3. Ejercicio/knowledge model.
4. TrainingEngine básico.
5. Today + workout logging offline.
6. Progression/order.
7. Time-aware.
8. Gyms/substitution.
9. HealthKit.
10. watchOS.
11. Recovery/restrictions.
12. Agent interpretation/explanation.
13. Analytics/self-knowledge.
14. Bodybuilding advanced.

Nunca construir primero chat UI y después intentar inventar el dominio alrededor de ella.

---

# 43. Formato obligatorio de trabajo de una IA agente

Antes de cada slice:

```text
TASK
ID del backlog:
Objetivo:
Archivos afectados:
Riesgos:
Tests que se crearán:
Criterios de aceptación:
```

Al terminar:

```text
RESULT
Implementado:
Tests ejecutados:
Build ejecutado:
Validación manual:
Decisiones técnicas:
Pendientes reales:
```

No declarar éxito si no se ejecutaron las verificaciones aplicables.

---

# 44. Referencias técnicas oficiales a verificar durante implementación

La IA debe consultar la documentación oficial instalada/Xcode o Apple Developer cuando use APIs sujetas a versión:

- HealthKit — HKWorkoutSession / HKLiveWorkoutBuilder
- Building a multidevice workout app
- AuthenticationServices / SignInWithAppleButton
- WorkoutKit
- Swift 6.x concurrency

No copiar snippets sin verificar disponibilidad y firma real.

---

# 45. Frase final que gobierna el producto

> **PR no debe hacer al usuario dependiente de una IA. Debe usar IA y datos para convertirlo en un atleta cada vez más autónomo, mientras un entrenador digital administra la complejidad que no aporta valor durante el entrenamiento.**

