# ADR-0005 — Una sola API para vender la app; los entrenamientos se quedan en el iPhone

- **Fecha:** 2026-11-06
- **Estado:** Propuesto. Falta la decisión de Jesús (PO); las preguntas están en "Lo que falta decidir".
- **Historia:** SCRUM-221 y decisión D2. Agrega historias a la Fase J (SCRUM-15) si se acepta.
- **Ámbito:** qué corre en un servidor propio, qué guarda y qué cambia en la app para poder venderla.

---

## Contexto

Para vender la app, la IA tiene que funcionar fuera de la Mac del desarrollador. La pregunta de partida fue si eso pide dos APIs: una para la IA y otra para una base de datos de usuarios.

### Lo que hay hoy

Revisado sobre `main` `d3668b9`, el 2026-11-06.

- **La IA está apagada en Release.** `AIConnection.resolve` ni siquiera busca la llave en esa compilación. En Debug, la llave sólo existe en la Mac del desarrollador.
- **La app usa la IA en un solo lugar.** `AIPlanPersonalizer` hace 2 llamadas (`propose` y `explain`) al crear un bloque o regenerarlo, no en cada entrenamiento (`TodayPlanCoordinator.personalize`).
- **El contrato del agente aún no está conectado.** `AgentGateway` y `LLMBackendTransport` (`interpret`, `explain`) existen y tienen pruebas, pero `PR/App` no los usa. Les toca con la Fase I.
- **Los prompts viven en la app:** en `AIPlanPersonalizer` y en `LLMBackendTransport`.
- **Con consentimiento viaja el perfil** (`AgentProfileContext`): edad, sexo, estatura, peso, objetivo, fase, experiencia, días, minutos, variedad, restricciones activas y sueño. Nunca van el nombre, el ID de Apple, los IDs internos ni las notas libres.
- **Los datos viven en el iPhone.** El perfil, el plan y los entrenamientos se guardan en archivos locales, y `DataExportCoordinator` exporta el historial.
- **La sesión no sirve todavía para hablar con un servidor.** `AppleIDAuthResult.success` sólo entrega el identificador y el nombre, sin token, y la app no usa el llavero (Keychain).
- **Release exige Sign in with Apple** (`AuthLaunchMode`), aunque todo funcione de forma local.
- **No encontré en `main` cómo borrar la cuenta** ni código de cobro.
- **En Jira,** la Fase J sólo tiene SCRUM-221 y sigue marcada `por-escribir`.

### Reglas externas

Revisadas el 2026-11-06 en las fuentes del final.

| Regla | Qué pide | Qué implica aquí |
|---|---|---|
| Apple 5.1.2(i) | Decir con claridad que los datos van a un tercero, incluida una IA de terceros, y pedir permiso explícito | `AIConsentView` dice "la IA", sin aclarar que es un tercero ni cuál |
| Apple 5.1.3(ii) | No guardar información personal de salud en iCloud | iCloud no es un atajo para respaldar o sincronizar |
| Apple 5.1.1(v), cuentas | Si la app crea cuentas, borrarlas dentro de la app; desactivarlas no basta | Falta esa función |
| Apple 5.1.1(v), inicio de sesión | Sin funciones de cuenta importantes, dejar usar la app sin iniciar sesión | Hoy se exige sesión para datos que son locales |
| Sign in with Apple | Revocar los tokens con su API REST, que pide `client_secret` | Ese secreto no puede ir en la app: la revocación necesita servidor |
| Apple 3.1.1 | Desbloquear funciones o suscripciones con compras dentro de la app | No hace falta un cobro propio |
| NVIDIA | El catálogo gratuito es una prueba. Servir a usuarios reales es producción, y pide NVIDIA AI Enterprise o el endpoint de un socio | El endpoint que usamos no sirve para vender |

## Opciones

### A · Sin servidor: la 1.0 sale sin IA

El motor local arma el plan y la explicación sale de `PlanRationalePresenter`, como en Release hoy.

- **A favor:**
  - sin costo mensual ni servicio que operar;
  - ningún dato sale del iPhone.
- **En contra:**
  - se vende sin la personalización ni la explicación de la IA;
  - borrar la cuenta sigue sin poder revocar los tokens de Apple, porque eso necesita un secreto de servidor.

### B · Una sola API pequeña, sin datos de entrenamiento (recomendada)

Un servicio se encarga de la sesión, la IA, los límites de uso y el borrado de la cuenta. Los entrenamientos no pasan por él.

- **A favor:**
  - cumple las reglas de la tabla con lo mínimo;
  - el perfil viaja sólo con consentimiento y el servidor no lo guarda;
  - el proveedor, el modelo y los prompts se cambian sin publicar otra versión de la app;
  - el trabajo en la app es acotado (ver "Qué cambia en la app").
- **En contra:**
  - hay que operar un servicio con secretos;
  - tiene costo mensual;
  - los datos no siguen al usuario a otros dispositivos.

### C · Dos APIs, o un backend con los entrenamientos

Una API para la IA y otra con una base de datos de usuarios y entrenamientos.

- **A favor:**
  - los datos siguen al usuario a otros dispositivos;
  - abre la puerta a una versión web o a entrenadores que vean a sus clientes.
- **En contra:**
  - datos de salud en un servidor propio: más riesgo y más obligaciones;
  - hay que construir sincronización y resolver conflictos, con riesgo para el dato que más protegemos;
  - dos servicios comparten la misma identidad, así que separarlos sólo duplica despliegue y autenticación;
  - nada de la 1.0 lo necesita.

## Recomendación

**B.** La IA necesita servidor porque la llave no puede ir en la app. La base de datos de usuarios no hace falta, porque lo único que el servidor necesita saber es quién llama y cuánto usa, y eso cabe en una tabla pequeña dentro de la misma API.

Si después se quiere sincronizar, serían más rutas en esta misma API, con su propio ADR. Elegir B ahora no cierra ese camino: `promptMaster` §36 ya define identificadores idempotentes para eso.

## Cómo sería la opción B

```text
iPhone ──HTTPS──► API de Nucleus ──► proveedor de IA
  │                    │
  │                    ├── tabla de cuentas y uso
  │                    └── Apple: identidad, revocación, suscripciones
  │
  └── perfil, plan y entrenamientos: se quedan aquí
```

El Apple Watch no habla con la API.

### Rutas

| Ruta | Para qué | Cuándo |
|---|---|---|
| `POST /v1/session` | Cambia el token de Apple por una sesión propia | 1.0 |
| `POST /v1/plan/propose` | Ajustes propuestos para el plan | 1.0 |
| `POST /v1/plan/explain` | Explicación "Por qué tu plan es así" | 1.0 |
| `DELETE /v1/account` | Borra la cuenta y revoca los tokens de Apple | 1.0 |
| `POST /v1/apple/notifications` | Avisos de Apple de servidor a servidor | 1.0 |
| `POST /v1/agent/interpret` y `/explain` | Entrenador conversacional (`promptMaster` §20.5) | Fase I |

**Son rutas por tarea, no un paso directo al modelo.** Con un paso directo, cualquiera con una sesión podría usar nuestra IA para lo que quisiera y a nuestro costo. Además, los prompts tendrían que seguir en la app. Las rutas de plan son nuevas frente a §20.5, porque son las que la app usa de verdad.

### Qué guarda el servidor

| Dato | Para qué |
|---|---|
| Identificador de cuenta: HMAC del `sub` de Apple | Aplicar límites y procesar avisos sin guardar el ID real |
| Llamadas y tokens por periodo | Límites por usuario y costo |
| Estado de la suscripción, si se cobra | Saber qué puede usar cada cuenta |

**No guarda:** perfil, entrenamientos, prompts, respuestas de la IA ni tokens de Apple. Los registros del servidor no incluyen el cuerpo de las solicitudes. Así sigue siendo cierto lo que promete `AIConsentView`: "No va a registros ni a publicidad".

### Identidad

1. Al iniciar sesión, la app manda una vez el `identityToken` de Apple a `POST /v1/session`. No lo guarda.
2. El servidor revisa la firma con las llaves públicas de Apple, el emisor, la audiencia (el bundle ID) y la fecha de vencimiento.
3. El servidor devuelve una sesión propia que se renueva sola y se guarda en el llavero.
4. Si la sesión se pierde, la app pide entrar con Apple otra vez sólo para usar la IA. El entrenamiento nunca se bloquea.

**App Attest queda para después.** Comprueba que la llamada viene de la app real, pero no todos los dispositivos lo soportan, así que el servidor no puede exigirlo siempre. Las rutas por tarea y los límites por usuario ya acotan el daño. Se agrega si aparece abuso.

### Borrar la cuenta

1. En Perfil, la app ofrece exportar el historial antes de seguir.
2. Si hay suscripción activa, avisa que el cobro continúa con Apple y cómo cancelarla.
3. La persona confirma y vuelve a entrar con Apple. Eso da un `authorizationCode` nuevo, así que no hace falta guardar tokens de Apple.
4. La app llama a `DELETE /v1/account` con ese código. El servidor genera el token, lo revoca y borra la cuenta.
5. La app borra los datos locales sólo cuando el servidor confirma (`promptMaster` §36: "no borrar datos localmente hasta confirmación").
6. Sin conexión no se borra nada y se le dice a la persona que lo intente de nuevo.

### Límites y costo

- **Límite por usuario y tope global.** Ambos son configuración del servidor. Con el tope global se puede apagar la IA para todos sin publicar nada: la app cae al motor local.
- **Costo mensual de la IA** ≈ usuarios activos × planes al mes × 2 llamadas × tokens por llamada × precio por token, más el hosting.
- **Faltan dos datos:** el precio del proveedor y los tokens reales por llamada. `AgentUsage` ya los reporta, así que se pueden medir. Este ADR no estima el costo.

### Si el servicio falla

Igual que hoy: `AICoach` responde "no disponible", el plan sale del motor y la explicación es la local. La app sigue revisando cada respuesta con `PlanPersonalizationValidator` y `PlanRationaleGuard`, porque el servidor no cambia quién decide: el LLM propone, el motor decide y el validador protege.

## Qué cambia en la app

- **`BackendPlanPersonalizer`:** nueva implementación de `PlanPersonalizing` que llama a la API. `AIPlanPersonalizer` y los proveedores de NVIDIA se quedan sólo para Debug.
- **`AIConnection.resolve`:** Release deja de quedar siempre apagado y se conecta si hay sesión y la flag está encendida.
- **Prompts:** los de `AIPlanPersonalizer` pasan al servidor.
- **`AppleIDAuthResult.success`:** agrega `identityToken` y `authorizationCode`, sólo en memoria y sin persistirlos.
- **Llavero:** primer uso en la app, para la sesión propia.
- **`AIConsentView` y Perfil:** el texto dice que los datos van a un proveedor externo y cuál es. Aún no se distribuye una versión Release, así que nadie aceptó el texto anterior fuera de las pruebas.
- **Perfil:** "Borrar cuenta", con el flujo de arriba.
- **Prueba de integración:** con la API caída, el plan se arma igual y no se pierde nada.

## Lo que falta decidir

| # | Pregunta | Recomendación |
|---|---|---|
| 1 | **D2:** ¿la IA va en la 1.0? | Sí, si el costo medido cabe en el precio. Si no, sale la 1.0 con la opción A y la IA se suma después |
| 2 | ¿Qué proveedor de IA en producción? | Comparar NVIDIA AI Enterprise y endpoints de socios por precio, retención de datos y región. SCRUM-221 hoy deja fuera cambiar de proveedor: hay que ajustarla |
| 3 | ¿La IA se cobra aparte? | Medir primero. Son 2 llamadas por plan, así que quizá no haga falta. La API deja lugar para la suscripción |
| 4 | ¿Se puede usar la app sin iniciar sesión? | Pedir la sesión sólo al activar la IA, para bajar el riesgo con la regla 5.1.1(v). No sé cómo lo juzgaría App Review. Cuesta trabajo, porque los datos locales van por usuario |

**Antes de empezar:** hace falta la cuenta de pago de Apple Developer para TestFlight y para publicar. Los secretos y el despliegue del servidor son carril 🔴: los maneja Jesús.

## Historias que saldrían

Ninguna está creada todavía, salvo SCRUM-221.

| Historia | Estado |
|---|---|
| API: sesión, rutas de plan, límites y tope global | SCRUM-221, hay que reescribirla |
| App: cliente de la API y sesión en el llavero | Nueva |
| Borrar la cuenta | Nueva. Hace falta para publicar mientras haya inicio de sesión, con o sin IA |
| Texto de consentimiento con el proveedor externo | Nueva |
| Usar la app sin iniciar sesión | Nueva, según la pregunta 4 |
| Suscripción con compras dentro de la app | Nueva, según la pregunta 3 |

## Lo que esta decisión no cubre

- **Sincronizar entrenamientos.** Sería otro ADR. Antes hay que aclarar si las series capturadas a mano cuentan como información de salud para la regla 5.1.3; lo que viene de HealthKit sí cuenta.
- **Lenguaje, hosting y repositorio del servidor.** Se eligen en la historia. Lo mínimo: HTTPS, manejo de secretos y registros sin contenido. El código no va en `PRCore`.
- **Revisión legal.** Hace falta aviso de privacidad y revisar la ley mexicana de datos personales, publicada en 2025. No verifiqué qué exige para datos de salud.
- **Precio de la app.**

## Decisión

Pendiente.

## Fuentes

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 3.1.1, 5.1.1(v), 5.1.2(i) y 5.1.3(ii).
- [Offering account deletion in your app](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).
- [Sign in with Apple REST API: Token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).
- [Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) (App Attest).
- [NVIDIA NIM FAQ](https://forums.developer.nvidia.com/t/nvidia-nim-faq/300317).
