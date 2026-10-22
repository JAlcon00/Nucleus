# Auditoría UI/UX y propuesta — Nucleus (iOS)

> **Fecha:** 2026-10-22 · **Autor:** PM/PO con la skill `swiftui-design-expert`.
> **Alcance:** `PR/App` (iOS) y `PRWatch/App` (solo revisión rápida).
> **Base:** código en `main` (último commit `af7923f`), referencias de Hevy, Alpha Progression y Fitbod, y el contraste medido con `scripts/contrast_check.py`.
> **Quién la ejecuta:** el agente de Xcode, como bloques U1–U6 de `mvp-plan.md` (sección 3.1).

---

## 1. Contexto de diseño (fijo)

- **Usuario:** persona en el gimnasio, entre series, con una mano y sudor, a veces con poca luz o sol directo.
- **Tarea principal de la app:** saber qué toca hoy y registrar cada serie sin pensar.
- **Plataforma:** la versión mínima es iOS 26.5, así que Liquid Glass del sistema funciona sin `#available`. En watchOS 11, cualquier API de watchOS 26 o 27 va con `#available`.
- **Marca:** paleta **Iron Energy** (sección 4.1), **tema oscuro**.

---

## 2. Hallazgos

### Bloqueantes

**B1. Hoy muestra "Día de descanso" mientras el plan todavía carga.**
- **Qué pasa:** `AppTabBarView` hace `environment.todayPlan.plan?.todayState ?? .restDay`. Mientras el plan no está listo (primer arranque, regeneración o lectura lenta), la pantalla afirma que hoy es descanso.
- **Por qué importa:** es información falsa. Alguien que abre la app el día que le toca entrenar puede irse sin entrenar. La pantalla no distingue entre "cargando" y "descanso".
- **Arreglo:** agregar el estado de carga a la pantalla y nunca usar `.restDay` como valor por defecto (bloque U2):

  ```swift
  enum TodayScreen { case loading, ready(TodayScreenState), failed(String) }
  ```

### Importantes

**I1. No hay paleta de marca.**
- **Qué pasa:**
  - `AccentColor.colorset` está vacío, así que la app usa el azul del sistema.
  - `secondaryAction` es `.gray`, y `success`/`warning` son colores del sistema.
  - La app sigue el modo claro/oscuro del sistema, y solo 3 previews fuerzan el oscuro.
- **Por qué importa:** la app no tiene identidad. Además, aplicar la paleta "a mano" pantalla por pantalla generaría inconsistencias.
- **Arreglo:** tokens Iron Energy como fuente única y tema oscuro fijo (bloque U1, sección 4.1).

**I2. El texto blanco sobre el acento no pasa contraste.** Es preventivo, para cuando se aplique la paleta.
- **Qué pasa:** `.borderedProminent` pinta la etiqueta en blanco sobre el `tint`.
  - Blanco hueso sobre `#FF3D2E` da **3.22:1** y falla AA para texto normal.
  - Sobre `#FF7A1A` da **2.39:1** y falla incluso para texto grande.
- **Por qué importa:** "Empezar" y "Completar serie" son las acciones críticas, y en el gimnasio se leen a distancia y con prisa.
- **Arreglo:** un `ButtonStyle` propio con la etiqueta en **negro carbón**: da 5.51:1 sobre el rojo y 7.44:1 sobre el naranja, y pasa en todo el degradado (sección 4.2).

**I3. La pestaña Plan dice "Todavía no tienes un plan semanal" aunque el usuario ya lo tiene.**
- **Por qué importa:** contradice lo que acaba de pasar en el onboarding y esconde el valor principal del producto, que es una semana armada para ti.
- **Arreglo:** la vista "Tu semana" (bloque U4, sección 4.4).

**I4. Los días de entrenamiento son consecutivos desde el lunes y no se pueden elegir.**
- **Qué pasa:** `TrainingWeek.sessionSlot` usa los primeros N días. Con 3 días se entrena lunes, martes y miércoles, y vienen 4 días seguidos de descanso.
- **Por qué importa:**
  - Recuperación: tres días seguidos y luego cuatro sin entrenar.
  - Vida real: la persona no puede decir "voy lunes, miércoles y viernes".
  - El ejemplo que pediste (lunes pull, miércoles push) es imposible hoy.
- **Arreglo:** elegir los días con chips (L M M J V S D) y un reparto espaciado por defecto. Es lógica de dominio primero (bloque U3, sección 4.3).

**I5. Las pestañas, los títulos y los nombres de sesión están en inglés.**
- **Qué pasa:** pestañas "Today/Progress/Plan/Profile" y sesiones "Push/Pull/Legs/Upper/Lower/Full Body", dentro de una app en español.
- **Por qué importa:** consistencia, y VoiceOver en español lee mal las palabras en inglés.
- **Arreglo:** bloque U6. Las pestañas pasan a Hoy, Progreso, Plan y Perfil. Las sesiones usan los nombres de la sección 4.4.

**I6. El onboarding no conoce a la persona y no cierra bien.**
- **Qué pasa:**
  - No pide nombre, edad, sexo, estatura ni peso.
  - El título se repite: el header y `choicesPicker` pintan el mismo `title(for:)`.
  - Al pulsar "Terminar" no hay transición ni presentación del plan.
  - Los pasos de Gimnasio y Restricciones solo tienen un botón "Omitir" o "Continuar sin añadir" y se sienten como callejones sin salida.
- **Arreglo:** paso "Sobre ti" (bloque U5, sección 4.5), quitar el título duplicado y pantalla "Armando tu semana" (bloque U2).

**I7. Hay cargas sin respuesta visual.**
- **Qué pasa:**
  - "Empezar" y "Continuar" lanzan `makeWorkoutCoordinator()`, que es async y lee historial, pero el botón no cambia mientras carga.
  - El inicio de sesión muestra un `ProgressView("Conectando…")` genérico, sin marca.
- **Por qué importa:** un toque sin respuesta lleva a un segundo toque. La protección contra doble toque ya existe; lo que falta es el feedback visual.
- **Arreglo:** estado "en curso" en el botón y loader de marca (bloque U2, sección 4.2).

**I8. El botón de Sign in with Apple es propio, no el oficial.**
- **Qué pasa:** es un `Button` con `apple.logo` y `.borderedProminent`, que toma el color de acento.
- **Por qué importa:**
  - Las guías de Apple piden el botón del sistema o uno que respete su estilo (negro o blanco).
  - Con el acento rojo, el botón quedaría fuera de norma y es riesgo de rechazo en App Review.
  - La pantalla dice "PR", no "Nucleus".
- **Arreglo:** `SignInWithAppleButton(.continue)` con `.signInWithAppleButtonStyle(.white)` sobre fondo carbón, y la marca "Nucleus" (bloque U6).

**I9. Hoy mezcla acciones terciarias con la principal.**
- **Qué pasa:** la barra de Hoy tiene Restricciones, Rehacer cuestionario y Exportar.
- **Arreglo:** pasar Restricciones, Rehacer cuestionario y Exportar a **Perfil**. Hoy queda con una sola acción: Empezar o Continuar (bloque U6).

### Mejoras

- **M1. Lista de ejercicios de Hoy.** Solo muestra "N × series". Hevy y similares muestran series × rango de reps y el peso sugerido. Agregar `3 × 8–12` y, si existe, "última vez: 60 kg × 10" (bloque U4).
- **M2. Celebración de récords.** Usa verde de éxito y acento al 12 %. Según la paleta, los logros y las rachas van en **naranja fuego** o en el degradado energía (U1).
- **M3. Iconos de las pestañas.** Hoy usa `checkmark.circle.fill`, que comunica "hecho" y no "entrenar". Propuesta (U6):
  - Hoy: `figure.strengthtraining.traditional`.
  - Progreso: `chart.line.uptrend.xyaxis`.
  - Plan: `calendar`.
  - Perfil: `person.crop.circle`.
- **M4. Tamaños fijos.** Los estados vacíos usan `.font(.system(size: 44))`, y el Watch usa `.system(size: 30)` en peso y reps. En iOS, cambiar a `@ScaledMetric` o estilos. En el Watch se acepta, pero sale de tokens.
- **M5. Futuro, después del POC: registro tipo Hevy.** Cada ejercicio como tabla de filas por serie (Serie · Anterior · kg · Reps · ✓), con la columna "Anterior" como referencia de progresión. No entra en el POC.

### No verificable aquí

- Rendimiento real en dispositivo, VoiceOver real y legibilidad con sol directo. Lo prueba Jesús en el iPhone.
- Liquid Glass del tab bar sobre el fondo carbón: revisar en dispositivo con Reduce Transparency y con el control de transparencia de iOS 27 en ambos extremos.

---

## 3. Referencias: cómo lo resuelven otras apps

| App | Cómo muestra la semana o las rutinas | Qué pide en el onboarding | Qué tomamos |
|---|---|---|---|
| **Hevy** | Rutinas guardadas, agrupadas en carpetas por programa. Cada rutina muestra sus ejercicios con series y rango de reps, y se empieza con **"Start Routine"**. No las ata a días de la semana; sus guías de PPL usan "Día 1 Push, Día 4 Pull, Día 6 Legs" con descanso intercalado. | Mínimo: es un tracker. | Tarjeta por sesión con los ejercicios visibles y un solo botón para empezar; descanso intercalado. |
| **Alpha Progression** | El plan va en secuencia, sin fechas de calendario. Splits: automático, full body, upper/lower, push/pull, PPL. | Sexo (con "Prefiero no decir"), experiencia y peso corporal (manual o desde Salud). | La opción "Prefiero no decir" y prellenar el peso desde Salud (más adelante, en Fase F). |
| **Fitbod** | Entrenamiento generado del día y mapa de recuperación muscular por porcentaje. | Objetivo, experiencia, equipo. Usa estatura, peso, sexo y edad para estimar calorías. | Chips de músculos por sesión; dejar claro para qué se usa cada dato. |

**Diferencia a propósito:** Nucleus sí ata las sesiones a días de la semana, porque la pantalla Hoy depende de eso. Por eso hacen falta los bloques U3 (elegir días) y U4 (ver la semana completa).

---

## 4. Propuesta

### 4.1 Tokens Iron Energy (bloque U1)

**Decisión:** tema oscuro fijo en la v1. Se aplica `.preferredColorScheme(.dark)` en la raíz y `UIUserInterfaceStyle = Dark` en `Info.plist`.
- **Trade-off:** se pierde el modo claro, pero la marca queda consistente y el contraste con sol directo sigue siendo alto (17.75:1 en el texto principal).
- **Fuente única:** `PR/App/DesignTokens.swift`. Ningún hex fuera de ese archivo.
- **`AccentColor.colorset`:** `#FF3D2E`, para que los controles del sistema hereden el acento.

| Rol (token) | Color | Uso | Contraste medido |
|---|---|---|---|
| `Color.appBackground` | Negro carbón `#0D0D0F` | Fondo de todas las pantallas | — |
| `Color.surface` | Gris grafito `#1C1C21` | Tarjetas, filas, hojas | 1.14:1 contra el fondo, así que necesita borde (`hairline`) |
| `Color.surfaceElevated` | `#26262D` | Campos de entrada, estado presionado | — |
| `Color.hairline` | Blanco al 8 % | Borde de tarjetas | Decorativo |
| `Color.textPrimary` | Blanco hueso `#F5F5F0` | Títulos y texto | 17.75 (fondo) · 15.52 (tarjeta) |
| `Color.textSecondary` | Gris acero `#8A8F98` | Texto secundario, iconos inactivos | 5.98 (fondo) · 5.22 (tarjeta). **No usar sobre `surfaceElevated`** (4.38) |
| `Color.primaryAction` | Rojo-naranja `#FF3D2E` | Fondo de CTA, progreso, selección, iconos activos | 5.51 (fondo) · 4.82 (tarjeta) |
| `Color.accentSecondary` | Naranja fuego `#FF7A1A` | Rachas, logros, récords, final del degradado | 7.44 (fondo) · 6.51 (tarjeta) |
| `Color.onAccent` | Negro carbón `#0D0D0F` | **Texto e icono sobre el rojo, el naranja o el degradado** | 5.51 sobre el rojo · 7.44 sobre el naranja |
| `Color.success` | `#30D158` | Serie completada, guardado | 8.39 (tarjeta) |
| `Color.warning` | Ámbar `#FFC53D` | Máquina ocupada, avisos | 10.75 (tarjeta). Distinto del naranja de logros |
| `Color.destructive` | `#FF6B6B` | Abandonar, borrar | 6.12 (tarjeta) |
| `LinearGradient.energy` | `#FF3D2E` → `#FF7A1A` | Anillos de progreso, rachas, el CTA principal | El texto encima va siempre en `onAccent` |

**Reglas:**
1. **Nunca texto blanco sobre el acento o el degradado.** Siempre `onAccent`.
2. **El destructivo se parece al acento.** El rojo de "Abandonar" y el de "Empezar" son casi el mismo tono, así que el significado lo cargan el texto, el icono (`xmark`/`trash`), la posición y el diálogo de confirmación. El destructivo nunca va relleno: se usa como texto o borde.
3. **El naranja fuego se reserva** para logros, rachas y récords; así esos momentos se reconocen al instante.
4. **Una sola acción rellena por pantalla.**
5. **Liquid Glass solo en la capa de navegación** (tab bar y toolbars del sistema). Nunca vidrio teñido de rojo sobre contenido.

Esqueleto de código (referencia para el agente; los nombres de rol mandan):

```swift
// DesignTokens.swift — Iron Energy (fuente única de color)
private enum IronEnergy {
    static let carbon   = Color(red: 13/255,  green: 13/255,  blue: 15/255)   // #0D0D0F
    static let graphite = Color(red: 28/255,  green: 28/255,  blue: 33/255)   // #1C1C21
    static let ember    = Color(red: 255/255, green: 61/255,  blue: 46/255)   // #FF3D2E
    static let fire     = Color(red: 255/255, green: 122/255, blue: 26/255)   // #FF7A1A
    static let steel    = Color(red: 138/255, green: 143/255, blue: 152/255)  // #8A8F98
    static let bone     = Color(red: 245/255, green: 245/255, blue: 240/255)  // #F5F5F0
}

extension Color {
    static let appBackground   = IronEnergy.carbon
    static let surface         = IronEnergy.graphite
    static let surfaceElevated = Color(red: 38/255, green: 38/255, blue: 45/255) // #26262D
    static let hairline        = Color.white.opacity(0.08)
    static let textPrimary     = IronEnergy.bone
    static let textSecondary   = IronEnergy.steel
    static let primaryAction   = IronEnergy.ember
    static let accentSecondary = IronEnergy.fire
    static let onAccent        = IronEnergy.carbon
    static let success         = Color(red: 48/255,  green: 209/255, blue: 88/255)  // #30D158
    static let warning         = Color(red: 255/255, green: 197/255, blue: 61/255)  // #FFC53D
    static let destructive     = Color(red: 255/255, green: 107/255, blue: 107/255) // #FF6B6B
}

extension LinearGradient {
    static let energy = LinearGradient(
        colors: [IronEnergy.ember, IronEnergy.fire],
        startPoint: .leading, endPoint: .trailing
    )
}

/// CTA principal: relleno de energía, etiqueta en negro carbón (≥ 5.5:1), feedback inmediato.
struct EnergyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(LinearGradient.energy, in: RoundedRectangle(cornerRadius: DRadius.medium))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
```

**Tipografía:** sigue siendo SF, con estilos de Dynamic Type.
- Cifras (peso, reps, temporizador, minutos): `.fontDesign(.rounded)` + `.monospacedDigit()`.
- Títulos de pantalla: `.bold()`.
- Etiquetas tipo "CALENTAMIENTO": `.caption.weight(.semibold)` con `tracking`.

**Migración:**
- Reemplazar `.tint`, `Color.accentColor`, `.secondary`, `Color(.secondarySystemBackground)`, `.green`, `.orange` y `Color(uiColor: .systemBackground)` por roles.
- `PrimaryActionButton` pasa a usar `EnergyButtonStyle`.

### 4.2 Estados de carga (bloque U2)

**Principio:** el loader solo aparece cuando hay espera real, nunca se alarga a propósito más de lo que tarda la operación, y siempre dice qué está pasando.

| Dónde | Hoy | Propuesta |
|---|---|---|
| Hoy, mientras llega el plan | Muestra "Día de descanso" (B1) | **Skeleton** con la forma de la tarjeta de hoy (título, chips, 4 filas) usando `.redacted(reason: .placeholder)` y un brillo suave. Con Reduce Motion, sin brillo. |
| Al terminar el onboarding | Nada | **"Armando tu semana"**: logo o anillo con el degradado y 3 pasos que se marcan conforme ocurren de verdad ("Repartiendo tu volumen", "Ordenando ejercicios", "Listo"). Mínimo 0.8 s para que no parpadee y nunca un retraso artificial más largo. Termina mostrando **"Tu semana"** (U4). |
| Inicio de sesión | `ProgressView("Conectando…")` genérico | Fondo carbón, marca Nucleus, `ProgressView` en el acento y el texto "Conectando con Apple…". Si tarda más de 10 s, mostrar "Reintentar". |
| Empezar o Continuar | El botón no cambia | El botón pasa a "en curso" (`ProgressView` dentro, sin texto que salte) y queda deshabilitado hasta que se abre el workout. Háptico `.impact(.light)` al tocar. |
| Exportar | (revisar) | Mismo patrón de botón "en curso". |

**Copy:** la rutina la arma el **motor de entrenamiento**, no la IA (invariante: el LLM interpreta y explica; el motor decide). El loader no dice "La IA está creando tu rutina". Dice "Armando tu semana".

### 4.3 Elegir días y reparto espaciado (bloque U3: primero lógica, después UI)

- **El paso del onboarding cambia.** "Días por semana" deja de ser un stepper y pasa a **"¿Qué días puedes entrenar?"**, con 7 chips (L M M J V S D). El número de días sale de los seleccionados (mínimo 2) y debajo se muestra "3 días por semana".
- **Selección por defecto según el número de días:**

| Días | Por defecto |
|---|---|
| 2 | L, J |
| 3 | L, Mi, V |
| 4 | L, M, J, V |
| 5 | L, M, Mi, V, S |
| 6 | L a S |
| 7 | todos |

- **En el dominio:** `TrainingWeek` guarda un `Set<Weekday>` y `sessionSlot(dayIndex:)` asigna los slots en orden a los días elegidos.
- **Compatibilidad:** los planes guardados con el entero N migran a los primeros N días, que es el comportamiento actual. Así ningún bloque cambia en silencio, y la persona puede editar sus días desde Perfil.
- **Fuera de alcance:** cambiar el día de una sola sesión ("hoy no puedo, muévelo"). El dominio ya tiene `AutoRescheduleEngine` para una historia posterior.

### 4.4 "Tu semana": vista semanal (bloque U4)

**Dónde se ve:**
- **Pestaña Plan:** la semana completa.
- **Hoy:** una tira compacta de 7 días arriba.
- **Al terminar el onboarding:** como pantalla de presentación.

**Tira de semana (en Hoy):** 7 círculos L M M J V S D.
- **Hoy:** anillo con el acento.
- **Día con sesión completada:** relleno con el degradado y ✓ (icono, no solo color).
- **Día de entrenamiento pendiente:** borde en gris acero.
- **Descanso:** punto tenue.
- **Al tocar un día:** se abre su detalle.

**Lista "Tu semana" (Plan):** una fila por día, de lunes a domingo.

```
LUNES · HOY                                   ~55 min
Pull                                          [ Empezar ]   ← solo el día de hoy
Espalda · Bíceps · Antebrazo
5 ejercicios · 16 series
────────────────────────────────────────
MARTES
Descanso
────────────────────────────────────────
MIÉRCOLES
Push                                          ~50 min
Pecho · Hombro · Tríceps
5 ejercicios · 15 series            ›
```

- **Tarjeta de entrenamiento:** fondo `surface`, borde `hairline`, radio `DRadius.large`. Muestra el día (en mayúsculas, `caption`, `textSecondary`), el nombre de la sesión (`title3.bold`), los chips de músculos, los ejercicios, las series y los minutos estimados.
- **Descanso:** una fila delgada con "Descanso", sin tarjeta, para que la vista se lea rápido.
- **Estado de cada día:**
  - Completado: ✓ y texto "Hecho".
  - Hoy: anillo con el acento.
  - Pasado sin hacer: "No realizado", en `textSecondary`. Nunca rojo: no es un error.
- **Detalle del día (push):**
  - Lista de ejercicios en orden, con `series × rango de reps` y "última vez" si existe.
  - El botón "¿Por qué este orden?" que ya existe.
  - El CTA "Empezar" **solo si el día es hoy**. Empezar otro día queda fuera del POC.

**Nombres de sesión.** Se usa el vocabulario del gimnasio en México, como en tu ejemplo:

| Split | Nombres |
|---|---|
| Push/Pull/Legs | **Push**, **Pull**, **Pierna** |
| Upper/Lower | **Torso**, **Pierna** |
| Full Body | **Cuerpo completo** |

Los chips de músculos van en español. Alternativa, si prefieres todo en español: Empuje, Jalón, Pierna. Es una sola tabla de strings localizables.

**Estados de la vista:**
- **Cargando:** skeleton de 3 tarjetas.
- **Vacío:** no aplica si existe plan. Sin plan, "Responde el cuestionario para armar tu semana" con CTA.
- **Error:** se reutiliza `PlanUnreadableView`.
- **Sin conexión:** no aplica; todo es local.

### 4.5 Paso "Sobre ti" en el onboarding (bloque U5)

**Una sola pantalla** al inicio del cuestionario, justo después del login: "Cuéntanos de ti".

| Campo | Control | ¿Obligatorio? | Para qué se usa (minimización de datos) |
|---|---|---|---|
| Nombre | `TextField`, prellenado si Apple lo entrega en el primer login | Opcional | Saludo ("Hola, Jesús"). No se envía al LLM. |
| Edad | Selector de rueda 16–90 (se guarda como año de nacimiento) | **Sí** | Elegibilidad y progresión más conservadora en edades altas. |
| Sexo | Segmentos: Hombre · Mujer · Prefiero no decir | Sí (con opción neutral) | Cargas iniciales de referencia. Nunca cambia las reglas de seguridad. |
| Estatura | Selector en cm (o pies y pulgadas según región) | Opcional | Contexto del perfil; hoy no la usa ningún motor. |
| Peso | Selector en kg/lb, con un decimal | **Sí** | Ejercicios con peso corporal (dominadas, fondos) y fases de definición o volumen. |

**Reglas:**
- **Dónde se guarda:** todo se guarda **solo en el dispositivo**, dentro del perfil del usuario.
- **Qué no se hace con los datos:**
  - No van a logs ni a analytics.
  - No se mandan al LLM salvo que la función lo necesite y esté documentado.
  - No se usan para calcular calorías (invariante).
- **Texto bajo el formulario:** "Se guarda solo en tu iPhone. Puedes cambiarlo en Perfil."
- **Migración:** `UserTrainingProfile` ya se persiste (SCRUM-26). Los campos nuevos son opcionales al decodificar (`decodeIfPresent`) y se prueban con un fixture de la versión anterior. Un perfil viejo sin estos datos pide "Completa tu perfil" una sola vez, sin bloquear Hoy.
- **Más adelante (Fase F, HealthKit):** prellenar edad, sexo, estatura y peso desde Salud con permiso explícito.
- **❓ Decisión pendiente de Jesús:** edad mínima. Recomiendo **18 años** en la v1, porque es una app de salud y el motor de progresión no está validado para menores. Con menos de 18, se muestra un mensaje y no se genera el plan.

### 4.6 Consistencia (bloque U6)

- **Idioma y marca:**
  - Pestañas: Hoy, Progreso, Plan, Perfil; con sus `navigationTitle`.
  - Marca "Nucleus" en el inicio de sesión.
  - Iconos de pestañas de M3.
- **Inicio de sesión:** botón oficial `SignInWithAppleButton(.continue)`, estilo `.white`.
- **Acciones de Hoy:** Restricciones, Rehacer cuestionario y Exportar pasan a **Perfil**, en secciones "Mi entrenamiento" y "Mis datos". Hoy queda con una sola acción.
- **Onboarding:** quitar el título duplicado en `OnboardingStepView.choicesPicker`.

---

## 5. Orden y encaje con la fase actual

- **Ritmo de la fase.** El plan MVP congela P1/P2 hasta cerrar los bloques P0. Los bloques 1 a 8 ya tienen sus criterios en `[x]` y solo faltan las pruebas manuales de Jesús. Por eso la UX entra **ahora**, como pulido del demo del POC (F-02, F-03 y la presentación).
- **Orden:** **U2 → U1 → U6 → U3 → U4 → U5**.
  - **U2 primero:** corrige un estado falso (B1).
  - **U1 y U6:** son de bajo riesgo y cambian toda la percepción.
  - **U3 antes que U4:** U4 necesita que los días sean correctos.
  - **U5 al final:** toca un modelo ya persistido y espera la decisión de edad mínima.
- **Riesgos:**
  - La migración del perfil y de la semana puede perder datos; cada bloque lleva su test con fixture de la versión anterior.
  - El tema oscuro forzado deja fuera a quien prefiere modo claro (aceptado en la v1).
  - El naranja de logros puede confundirse con el ámbar de aviso; por eso son tonos distintos y siempre van con icono.
