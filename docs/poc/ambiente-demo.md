# Ambiente demo (SCRUM-188 · S-01)

Cómo arrancar Nucleus con un perfil de ejemplo y 2 semanas de historial, para mostrar la app sin hacer el cuestionario en vivo.

## Qué trae

**Perfil de ejemplo "Alex":**
- Intermedio, hipertrofia y mantenimiento.
- Entrena lunes, martes, jueves y viernes, 60 minutos.
- "Sobre ti" completo.
- Restricción de rodilla con la nota "Me molesta la rodilla al bajar escaleras". Sale en Perfil › Restricciones, y el plan evita lo que la carga.

**Historial:**
- 8 entrenamientos completos en las 2 semanas anteriores al primer arranque, en los días elegidos.
- Las cargas son datos de muestra fijos.
- La segunda semana sube un escalón, para que Progreso muestre avance.

**Inicio de sesión:** entra solo con el usuario simulado, sin Sign in with Apple.

**Primera pantalla:** "Personaliza tu plan con IA". El consentimiento queda sin decidir a propósito, para que lo decida quien presenta:
- "Ahora no" va directo a Hoy.
- "Sí, personalizar con IA" solo hace algo con la llave local de Debug.

## Seguridad de los datos

- **Solo en Debug con `-PRDemoData`.** En Release el argumento se ignora siempre, así que TestFlight y la App Store nunca cargan el demo.
- **Directorio aparte:** `Application Support/PR/demo`. Los datos reales viven en `Application Support/PR/persistence`, y ninguno está dentro del otro.
- **Arrancar sin el argumento** abre los datos reales de siempre, sin tocarlos.
- **La siembra pasa una sola vez.** Lo que hagas durante el demo, como un entrenamiento o un cambio de tiempo, se conserva al cerrar y reabrir.
- **Un plan demo ilegible nunca se sobrescribe.**
- **Tests:** `Packages/PRCore/Tests/PRCoreTests/DemoDataTests.swift`.

## Correrlo en el simulador

### Desde Xcode

1. Product › Scheme › Edit Scheme… › Run › Arguments.
2. En "Arguments Passed On Launch" agrega `-PRDemoData`.
3. Run (⌘R) con un simulador de iPhone.

Para volver a tus datos de prueba, desmarca el argumento.

### Desde la terminal

1. Compila e instala la versión Debug. `make test-ios` compila el scheme `PR`; la app queda en `DerivedData/…/Build/Products/Debug-iphonesimulator/PR.app`.

```bash
xcrun simctl install booted <ruta a PR.app>
```

2. Ábrela en modo demo:

```bash
xcrun simctl launch booted creadevs.PR -PRDemoData
```

**Fijar "hoy":** se combina con `-PRFixedDate`, por ejemplo para que el demo caiga en un día de entrenamiento:

```bash
xcrun simctl launch booted creadevs.PR -PRDemoData -PRFixedDate 2026-10-26
```

## Empezar el demo de cero

El historial se fecha respecto al **primer** arranque con `-PRDemoData`. Si sembraste días antes, vuelve a sembrar el mismo día del demo.

En el simulador, desinstalar la app borra el demo y también los datos de prueba de ese simulador:

```bash
xcrun simctl uninstall booted creadevs.PR
```

Después vuelve a instalar y a abrir con `-PRDemoData`.

## En el iPhone (👤 Jesús)

1. Necesitas firma de desarrollo (Xcode › Signing & Capabilities, con tu equipo) e instalar desde Xcode con el argumento `-PRDemoData` en el scheme.
2. Un build de TestFlight es Release: **no** carga el demo, por diseño.
3. Video de respaldo: con el simulador encendido y la app abierta en modo demo, graba con el comando de abajo y detén con Ctrl+C.

```bash
xcrun simctl io booted recordVideo demo-nucleus.mov
```
