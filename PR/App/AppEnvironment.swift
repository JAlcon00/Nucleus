//
//  AppEnvironment.swift
//  PR
//
//  Created by PR.
//
//  Composition root: construye y expone las dependencias del dominio/core.
//  Mantiene `PRApp.swift` libre de lógica de negocio (PR-0001).
//

import Foundation
import Observation
import PRCore
import PRDomain

/// Porta las dependencias compartidas de la aplicación.
/// Es el punto único de composición de la capa de infraestructura.
@MainActor
@Observable
public final class AppEnvironment {
    /// Version del core embebido (para diagnóstico sin datos sensibles).
    public let coreVersion: String

    /// Proveedor LLM con la API key inyectada en runtime (NVIDIAKeyLoader).
    /// NUNCA embebe la key: se lee de entorno/.env en runtime (§22/§42). Es un shim
    /// de prototipado; en producción la app habla con nuestro backend.
    public var llmProvider: any LLMProvider {
        NVIDIAHostedProvider()
    }

    /// Coordinador de onboarding (EPIC-04, PR-0401 + PR-0402 wiring): gate de Sign in
    /// with Apple + flujo de pasos + perfil mínimo. Usa el provider real de producción;
    /// los tests/previews inyectan un fake. No persiste tokens inseguros ni requiere HealthKit.
    public let onboarding: OnboardingCoordinator

    /// Coordinador del plan de hoy (PR-0601 wiring): a partir del perfil de onboarding
    /// genera un bloque real y deriva el estado de la pantalla "Hoy".
    public let todayPlan: TodayPlanCoordinator

    /// Catálogo de ejercicios resolvido (inmutable; fallback vacío documentado).
    public let catalog: ExerciseCatalog

    /// Almacén persistente local durabile (PR-0203 wiring): respalda la cola de
    /// operaciones pendientes Y el repositorio de workouts con escritura atómica.
    /// `nil` sólo si la infraestructura de Application Support no está disponible.
    public let localRepositoryStore: AtomicFileRepositoryStore?

    /// Construye un coordinador de WORKOUT MODE para la sesión planeada hoy.
    /// Usa la plantilla del plan de hoy (si la hay) y los nombres del catálogo.
    /// Devuelve `nil` para un día de descanso (sin sesión).
    /// Cablea la persistencia offline-first (PR-0203): cada set completado se encola
    /// como operación crítica durabile y, al cerrar la sesión, el registro se persiste
    /// en el repositorio local. Si no hay almacén durable, el coordinador funciona igual
    /// en memoria (nunca se pierde la sesión viva).
    public func makeWorkoutCoordinator() -> WorkoutSessionCoordinator? {
        guard let template = todayPlan.plan?.todayTemplate else { return nil }
        var names: [ExerciseID: String] = [:]
        for exercise in catalog.exercises {
            names[exercise.id] = exercise.canonicalName
        }
        let pendingQueue = localRepositoryStore.map {
            PendingOperationQueueStore(store: $0)
        }
        let workoutRepository = localRepositoryStore.map {
            FileWorkoutRepository(store: $0)
        }
        return WorkoutSessionCoordinator(
            template: template,
            exerciseNames: names,
            pendingQueue: pendingQueue,
            onSessionFinished: { [workoutRepository] session in
                // Persiste el registro final en el repositorio local (async, best-effort).
                // Un fallo aquí NO pierde el dato: la cola de operaciones queda intacta.
                try? await workoutRepository?.save(session)
            }
        )
    }

    public init(
        coreVersion: String = PRCore.version,
        authProvider: (any AppleIDAuthProviding)? = nil,
        catalog: ExerciseCatalog? = nil,
        repositoryStore: AtomicFileRepositoryStore? = nil
    ) {
        self.coreVersion = coreVersion
        self.onboarding = OnboardingCoordinator(authProvider: authProvider ?? SignInWithAppleProvider())
        self.localRepositoryStore = repositoryStore ?? Self.makeDefaultRepositoryStore()
        let resolvedCatalog: ExerciseCatalog
        if let catalog {
            resolvedCatalog = catalog
        } else if let loaded = try? ExerciseCatalogLoader.loadBundled() {
            resolvedCatalog = loaded
        } else {
            // Fallback mínimo sin inventar ejercicios: catálogo vacío (el planificador
            // no generará sesiones, la pantalla hoy muestra descanso sin CTA).
            resolvedCatalog = ExerciseCatalog(
                source: ExerciseCatalogSource(name: "empty", version: "0", url: "", license: "none"),
                families: [],
                exercises: []
            )
        }
        self.catalog = resolvedCatalog
        self.todayPlan = TodayPlanCoordinator(catalog: resolvedCatalog)
    }

    /// Crea el almacén durable por defecto en Application Support/PR (API real de Apple).
    /// Devuelve `nil` si el directorio no puede resolverse (fallback en memoria del app).
    private static func makeDefaultRepositoryStore() -> AtomicFileRepositoryStore? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return try? AtomicFileRepositoryStore(
            directoryProvider: AppSupportPersistenceDirectory(baseURL: base)
        )
    }
}

/// Provee el subdirectorio de persistencia del app dentro de Application Support.
private struct AppSupportPersistenceDirectory: @unchecked Sendable, RepositoryDirectoryProviding {
    let baseURL: URL
    func directoryURL() throws -> URL {
        baseURL.appendingPathComponent("PR/persistence", isDirectory: true)
    }
}
