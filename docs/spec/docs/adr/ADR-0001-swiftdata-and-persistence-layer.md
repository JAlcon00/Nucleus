# ADR-0001 — SwiftData y la capa de persistencia local

- **Fecha:** 2026-09-01
- **Estado:** Aceptado
- **PR:** PR-0202 (SwiftData/persistence adapters, EPIC-02)
- **Ámbito:** Persistencia local offline-first

---

## Contexto

EPIC-02 exige persistencia local offline-first: guardar profile, bloques, workouts
(incluyendo sus sets), gyms, restricciones y decisiones detrás de los protocolos
`Repository` (PR-0201). El criterio de aceptación de PR-0202 era "round-trip
integration con in-memory ModelContainer", es decir, SwiftData.

Durante la implementación se descubrió un límite del framework: **los tipos `@Model`
de SwiftData no pueden vivir en un target de librería Swift Package Manager (SPM)
compartido.** Al ejercitar el modelo (insert/save), el runtime de SwiftData aborta
con `fatalError`/`SIGTRAP` (EXC_BREAKPOINT) sin importar plataforma.

Se validó mediante reproducciones mínimas en `swift test` (macOS 26.5) y en un
hosted unit test de iOS Simulator:

| Variante | Setup (mismo `@Model`) | Resultado |
|---|---|---|
| `@Model` en librería SPM | `swift test` | ❌ SIGTRAP |
| `@Model` + `ModelContainer` + save todo dentro de la librería | `swift test` | ❌ SIGTRAP |
| `@Model` en el **módulo del test** (no librería) | `swift test` | ✅ pasa |
| `@Model` de la librería, hosted iOS Simulator | Xcode unit test | ❌ SIGTRAP |

Se descartaron como causa: acceso (`public`/`internal`), atributos (`.unique`,
blob `Data`; también choca un `@Model` con un único `String`), `#Predicate`,
tamaño del schema, `ModelConfiguration(bundle:)`, y hosting. El único factor
determinante es **el módulo donde se compila el `@Model`**: debe ser el módulo
del ejecutable/test bundle que lo usa, no una librería SPM.

Consecuencia: PRCore (paquete SPM compartido por iOS + watchOS, gate de tests vía
`swift test`) **no puede alojar SwiftData**. Mantener los `@Model` en PRCore dejaba
la suite roja (violando el desarrollo invariante *ninguna historia DONE sin tests*)
y el build del simulador abortando.

## Decisión

Implementar la persistencia local de PR-0202 con un **almacén Codable/JSON
respaldado por escritura atómica**, en lugar de SwiftData, **dentro de PRCore**:

- `RepositoryStore` (protocolo): `read`/`readAll`/`write`/`delete` por clave.
  - `MemoryRepositoryStore`: en memoria, determinista, para tests.
  - `AtomicFileRepositoryStore`: archivos JSON con escritura temp + rename
    (`replaceItemAt`), para producción (iOS + watchOS).
- 7 adaptadores `File*Repository` que satisfacen los protocolos `Repository`
  (PR-0201), codificando cada agregado de dominio como blob JSON tras su clave
  tipada (`id.rawValue.persistenceKey`).
- Save local **inmediato y autoritativo**: al confirmar un set se persiste la
  sesión completa (incluye sets) de forma atómica; un fallo de sync remoto jamás
  lo revierte (invariante del producto).
- Perfil único bajo clave fija (`scope.single`): guardar reemplaza, nunca duplica.

SwiftData queda reservado como **detalle de la capa de app** si algún día se desea,
con sus `@Model` definidos **en el target de la app** (que sí es un bundle de
ejecutable), no en la librería — y con ADR/migraciones adicionales según SKILL §10.

## Alternativas consideradas

1. **Mantener SwiftData en PRCore** (cuando se detectó el crash). Rechazado: crash
   SIGTRAP irreproducible dentro de un paquete SPM compartido; rompe el gate de
   tests y el build.
2. **Mover SwiftData a los targets de app (PR/PRWatch) y testear en un target de
   test iOS**. Rechazado como solución primaria: fragmenta la persistencia (iOS ≠
   watchOS), excluye la persistencia del flujo `swift test` (que cubre todo el
   dominio), y añade una pila de tests paralela. Se documenta como vía futura si
   la app necesita SwiftData específicamente.
3. **Almacén Codable/JSON en PRCore (elegida).** Mantiene la persistencia en el
   paquete compartido, la suite verde en `swift test`, y el comportamiento exigido
   por EPIC-02.

## Consecuencias

- **Positivas:**
  - Suite completa verde en `swift test` (dominio + repositorios), incluidos los
    nuevos tests de integración de persistencia.
  - Una única implementación de persistencia compartida por iOS y watchOS.
  - Save local atómico y autoritativo; sin dependencia de runtime de frameworks
    pesados en la librería.
- **Negativas / a vigilar:**
  - No es literalmente SwiftData; los `@Model`/queries/relaciones nativas de
    SwiftData no están disponibles.
  - Migraciones de schema se gestionan manualmente (versión + encoder) en vez de
    con `VersionedSchema`/`SchemaMigrationPlan` de SwiftData.
  - La persistencia por archivo requiere que el proveedor de directorio elija un
    destino correcto por plataforma (p. ej. `Application Support`) en producción;
    los tests usan el almacén en memoria o un directorio temporal.

## Rollback

- Revertir los 3 archivos del paquete (`RepositoryStore.swift`,
  `CodableRepositories.swift`, `CodableRepositoriesTests.swift`) y el cambio de la
  capa de app si la hubiera.
- Los protocolos `Repository` (PR-0201) no cambian, por lo que sustituir la capa de
  almacenamiento por SwiftData-en-app u otra tecnología es un cambio delimitado al
  interior del paquete sin tocar el dominio.
