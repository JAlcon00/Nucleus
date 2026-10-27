# ADR-0003 — Formato guardado por colección y migraciones

- **Fecha:** 2026-10-26
- **Estado:** Aceptado (criterios aprobados por Jesús en SCRUM-40)
- **Historia:** SCRUM-40 · PR-0118 Migraciones seguras de datos guardados
- **Ámbito:** Persistencia local (`LocalPersistence`, ADR-0001)

---

## Contexto

La persistencia es un almacén JSON propio: una carpeta por colección (SCRUM-23) y un
archivo por registro, con escritura atómica (ADR-0001). Antes de esta decisión:

- Los cambios que **solo agregan** un campo opcional ya se leían sin migrar (por
  ejemplo `trainingWeekdays`, `customOrders` o `timeBudget`).
- Un cambio **incompatible** (renombrar, quitar o cambiar el tipo de un campo) dejaba
  los registros guardados como "ilegibles": la lectura tolerante no los borraba, pero
  desaparecían del historial y de Progreso.
- Ningún test fallaba si un cambio de modelo rompía lo que ya estaba guardado.
- `StoredPlan.generatorVersion` resuelve otra cosa: regenerar el plan cuando cambia el
  **motor**. No sirve para cambios de **formato**.

## Decisión

1. **Versión por colección.**
   - Cada carpeta de colección guarda su versión en `.schema-version`, un archivo oculto
     con el JSON `{"version": N}`.
   - Sin marca es la versión 1: el formato de antes de SCRUM-40.
   - Una carpeta que crea la app actual se marca con la versión vigente. Las que crea la
     migración del layout antiguo se marcan con la 1.
   - La versión vigente de cada colección vive en `PersistenceSchemas`, con un `switch`
     exhaustivo.
2. **Migración en orden, una sola vez.**
   - Al arrancar, después de la migración del layout antiguo, `migrateSchemas()` lleva
     cada colección de la raíz a su versión vigente, paso a paso.
   - Las colecciones de cada usuario (`users/<clave>/workouts` y `pending-operations`)
     migran en `scoped(toUser:)`, antes de adoptar el historial sin dueño.
   - Un paso (`SchemaMigrationStep`) convierte un registro JSON de N a N+1. Es puro: sin
     disco, reloj ni red.
3. **Nunca se pierde el original.**
   - La colección migrada se escribe aparte, en `.<colección>.migrating`. La marca se
     escribe al final.
   - Luego se cambian las carpetas: la original pasa a `.<colección>.backup`, donde
     queda hasta la siguiente migración, y la migrada toma su lugar.
   - Un registro que no se puede convertir, o que no se lee completo con el modelo
     vigente, se guarda intacto en `.quarantine/v<N>/` y el resto sí migra.
   - Si algún archivo existe pero no se puede leer (por ejemplo, el disco está
     bloqueado), no se migra nada y se reintenta al siguiente arranque.
4. **Cortes a la mitad.**
   - Si la app se cierra antes del cambio de carpetas, la carpeta a medias se descarta y
     se rehace.
   - Si se cierra entre los dos movimientos, la colección vuelve a su lugar: la migrada
     si quedó completa (tiene marca) y, si no, el respaldo.
   - Esa recuperación también corre al abrir una colección (`store(for:)`), así nunca se
     crea una carpeta vacía encima.
5. **No se toca:**
   - una versión más nueva que la conocida (al bajar de versión);
   - una marca ilegible;
   - un paso faltante.
   Las tres se registran.
6. **Aviso.**
   - Lo que está en cuarentena cuenta como ilegible en `readAllEntries()`, así que
     Exportar y Progreso avisan "no pude leer N".
   - Un plan en cuarentena da "plan ilegible", no primer arranque.
   - El registro (`PersistenceLog`) guarda solo colección, versiones y conteos.
7. **Detector en CI.**
   - `Tests/PRCoreTests/Fixtures/Persistence/v<N>/<colección>.json` es un registro real,
     escrito por la app, de cada colección que la app escribe.
   - `PersistenceFormatTests` comprueba que la muestra vigente se lee y, al volver a
     guardarla, conserva cada campo; que las muestras anteriores migran; y que hay
     exactamente un paso por versión.

## Regla para cambiar un modelo guardado

| Cambio | Qué hacer |
|---|---|
| Agregar un campo opcional (o con valor por defecto al decodificar) | Nada más: la muestra vigente sigue pasando. |
| Renombrar, quitar o cambiar el tipo de un campo, o cambiar su significado | 1. Subir `current` de la colección en `PersistenceSchemas`. 2. Agregar el `SchemaMigrationStep` desde la versión anterior. 3. Guardar la muestra nueva con `PR_WRITE_PERSISTENCE_FIXTURES=1 swift test --filter PersistenceFormatTests` (la de la versión anterior se queda). 4. `make ci`. |

## Consecuencias

- **Para los usuarios no cambia nada hoy.** Todas las colecciones quedan en la versión
  1; al primer arranque solo se escribe la marca.
- **Espacio en disco.** Durante una migración la colección ocupa el doble, y después
  queda un respaldo de la versión anterior. Son archivos JSON pequeños.
- **Casos límite conocidos:**
  - La cuarentena del historial sin dueño (de antes de SCRUM-26, solo en dispositivos
    de desarrollo) se queda en la raíz y no entra al aviso de Exportar del usuario.
    Los datos no se pierden.
  - Un archivo del layout antiguo (antes de SCRUM-23) solo se mueve si decodifica con
    el modelo vigente; si no, se queda en la raíz como hoy.
  - Si un paso cambia el significado de un campo sin cambiar su forma (por ejemplo,
    unidades), hay que revisar este caso.
- **Fuera de alcance:**
  - impedir que la propia app escriba encima de datos más nuevos al bajar de versión;
  - el formato del archivo exportado (tiene su propio `schemaVersion`);
  - la sincronización en la nube.
