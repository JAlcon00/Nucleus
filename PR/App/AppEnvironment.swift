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

    /// Modo de inicio de sesión resuelto al arrancar. `.simulated` sólo en Debug con
    /// `-PRFakeSignIn` (para probar sin Sign in with Apple); en Release siempre `.appleID`.
    public let authMode: AuthLaunchMode

    /// Intent de arranque: en modo simulado inicia sesión sola (salta la pantalla de
    /// login). En modo Apple no hace nada; el usuario toca el botón.
    public func startIfNeeded() async {
        guard authMode.signsInAutomatically, onboarding.phase == .signedOut else { return }
        await onboarding.signIn()
    }

    /// Coordinador del plan de hoy (PR-0601 wiring): a partir del perfil de onboarding
    /// genera un bloque real y deriva el estado de la pantalla "Hoy".
    public let todayPlan: TodayPlanCoordinator

    /// Catálogo de ejercicios resolvido (inmutable; fallback vacío documentado).
    public let catalog: ExerciseCatalog

    /// Persistencia local (SCRUM-23): una colección por subdirectorio bajo
    /// `Application Support/PR/persistence`. `nil` sólo si Application Support no está
    /// disponible (el workout sigue funcionando en memoria).
    public let persistence: LocalPersistence?

    /// Construye un coordinador de WORKOUT MODE para la sesión planeada hoy.
    /// Usa la plantilla del plan de hoy (si la hay) y los nombres del catálogo.
    /// Devuelve `nil` para un día de descanso (sin sesión).
    /// La persistencia (cola de pendientes, baselines de PR, guardado al terminar) la
    /// cablea `LocalPersistence`. Si no hay almacén durable, el coordinador funciona igual
    /// en memoria (nunca se pierde la sesión viva).
    public func makeWorkoutCoordinator() async -> WorkoutSessionCoordinator? {
        guard let template = todayPlan.plan?.todayTemplate else { return nil }
        var names: [ExerciseID: String] = [:]
        for exercise in catalog.exercises {
            names[exercise.id] = exercise.canonicalName
        }
        let presenter = PRCelebrationPresenter(locale: Self.presentationLocale)
        if let persistence {
            do {
                return try await persistence.makeWorkoutCoordinator(
                    template: template,
                    exerciseNames: names,
                    celebrationPresenter: presenter
                )
            } catch {
                persistence.log.saveFailed(.workouts)
            }
        }
        return WorkoutSessionCoordinator(
            template: template,
            exerciseNames: names,
            celebrationPresenter: presenter
        )
    }

    public init(
        coreVersion: String = PRCore.version,
        authProvider: (any AppleIDAuthProviding)? = nil,
        catalog: ExerciseCatalog? = nil,
        persistence: LocalPersistence? = nil
    ) {
        self.coreVersion = coreVersion
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        let mode = AuthLaunchMode.resolve(arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild)
        self.authMode = mode
        self.onboarding = OnboardingCoordinator(
            authProvider: authProvider ?? mode.provider(appleID: SignInWithAppleProvider())
        )
        self.persistence = persistence ?? Self.makeDefaultPersistence()
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

    /// Locale para textos generados fuera de las Views (PR-1004): idioma que resolvió la
    /// app (development region `es` mientras no haya otras traducciones de la app) con el
    /// formato regional del usuario.
    static var presentationLocale: Locale {
        PRCelebrationPresenter.presentationLocale(
            appLanguage: Bundle.main.preferredLocalizations.first,
            userLocale: .current
        )
    }

    /// Crea la persistencia por defecto en Application Support/PR/persistence y migra
    /// una sola vez el layout antiguo (todo en la raíz). Devuelve `nil` si el directorio
    /// no puede resolverse (fallback en memoria del app).
    private static func makeDefaultPersistence() -> LocalPersistence? {
        let persistence: LocalPersistence
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            persistence = try LocalPersistence(
                rootURL: base.appendingPathComponent("PR/persistence", isDirectory: true)
            )
        } catch {
            PersistenceLog.standard.migrationFailed()
            return nil
        }
        do {
            try persistence.migrateLegacyLayout()
        } catch {
            // Los archivos antiguos siguen intactos en la raíz: se reintenta al próximo
            // arranque. Las colecciones nuevas son utilizables igualmente.
            persistence.log.migrationFailed()
        }
        return persistence
    }
}
