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

    /// Conexión con la IA (SCRUM-204). Debug: llave leída en runtime sólo de la Mac del
    /// desarrollador (`NVIDIA_API_KEY` o `.env` ignorado). Release: apagada, sin buscar
    /// la llave. NUNCA embebe la llave (§22/§42); antes de TestFlight va a un backend.
    /// En pruebas de UI queda apagada (deterministas y sin red).
    public let aiConnection: AIConnection

    /// Feature flags de la app (SCRUM-39), armadas una vez al arrancar: IA y Salud
    /// encendidas como hoy; en Debug, `-PRFeatureFlag clave=0|1` las cambia.
    public let featureFlags: FeatureFlags

    /// Fachada de la IA: nunca lanza; una falla es "no disponible" y la app sigue local.
    public var aiCoach: AICoach { AICoach(connection: aiConnection) }

    /// ¿Al armar el plan se le pregunta a la IA? Sólo con conexión y consentimiento (SCRUM-205).
    public var personalizesWithAI: Bool {
        aiConnection.status.isLive && aiConsent.consent.allowsSharing
    }

    /// Coordinador de onboarding (EPIC-04, PR-0401 + PR-0402 wiring): gate de Sign in
    /// with Apple + flujo de pasos + perfil mínimo. Usa el provider real de producción;
    /// los tests/previews inyectan un fake. No persiste tokens inseguros ni requiere HealthKit.
    public let onboarding: OnboardingCoordinator

    /// Modo de inicio de sesión resuelto al arrancar. `.simulated` sólo en Debug con
    /// `-PRFakeSignIn` (para probar sin Sign in with Apple); en Release siempre `.appleID`.
    public let authMode: AuthLaunchMode

    /// Intent de arranque: recupera la sesión y el plan guardados; en modo simulado inicia
    /// sesión sola (salta la pantalla de login). En modo Apple, sin sesión guardada, el
    /// usuario toca el botón. Con `-PRDemoData` primero siembra el demo (SCRUM-188).
    public func startIfNeeded() async {
        if demoData { await seedDemoDataIfNeeded() }
        await session.start(autoSignIn: authMode.signsInAutomatically)
        // SCRUM-228: con `-PRUITestProfile` el cuestionario se contesta solo; el plan lo arma
        // la activación de siempre, como al terminarlo. Con un plan guardado no toca nada.
        if let uiTestSeededProfile {
            UITestProfileSeeder(profile: uiTestSeededProfile).answer(onboarding: onboarding, aiConsent: aiConsent)
        }
    }

    /// SCRUM-188: ¿arrancó en modo demo? Sólo Debug con `-PRDemoData`; usa su propio
    /// directorio (`PR/demo`), nunca los datos reales.
    public let demoData: Bool

    /// Siembra el perfil de ejemplo y las 2 semanas de historial en el directorio demo antes
    /// de recuperar la sesión. Si ya estaban, no toca nada. Una falla no detiene la app (abre
    /// sin datos demo) y queda registrada.
    private func seedDemoDataIfNeeded() async {
        guard let basePersistence else { return }
        do {
            _ = try await DemoDataSeeder(catalog: catalog, timeZone: .current)
                .seedIfNeeded(persistence: basePersistence, userID: AuthLaunchMode.simulatedUserIdentifier, now: now)
        } catch {
            basePersistence.log.saveFailed(.plans)
        }
    }

    /// Coordinador del plan de hoy (PR-0601 wiring): a partir del perfil de onboarding
    /// genera un bloque real y deriva el estado de la pantalla "Hoy".
    public let todayPlan: TodayPlanCoordinator

    /// Arranque y sesión (SCRUM-26): recuerda al usuario y su plan entre arranques.
    public let session: AppSessionCoordinator

    /// Perfil › Restricciones (SCRUM-216 / SCRUM-36): ver, agregar, editar y resolver, sobre
    /// el mismo perfil con el que se arma el plan.
    public let restrictionScreen: RestrictionScreenModel

    /// Consentimiento para compartir el perfil con la IA (SCRUM-202).
    public let aiConsent: AIConsentCoordinator

    /// El gimnasio del usuario (SCRUM-235). Sin pasos nuevos: se crea solo al entrar.
    public let gym: GymCoordinator

    /// "Usar datos de Salud" en "Sobre ti" (SCRUM-206). Sólo lectura; en pruebas de UI no
    /// se ofrece (no hay diálogo de permisos que tocar).
    public let healthPrefill: HealthPrefillCoordinator
    /// Puente con el reloj (SCRUM-255). `nil` si este dispositivo no tiene WatchConnectivity.
    @ObservationIgnored private var watchBridge: PhoneWatchBridge?

    /// Check-in diario de sueño (SCRUM-203).
    public let sleepCheckIns: SleepCheckInCoordinator

    /// ¿Hoy pregunta "¿Cómo dormiste?"? Sólo en día de entrenamiento y sin entrenamiento vivo.
    public var asksSleepCheckIn: Bool {
        sleepCheckIns.needsCheckIn && activeWorkout == nil && todayPlan.plan?.todayTemplate != nil
    }

    /// SCRUM-211: ¿se puede reordenar la sesión? No la que está en curso (dentro del
    /// entrenamiento se usa "dejar en espera").
    public func canReorderSession(_ templateID: SessionTemplate.ID) -> Bool {
        activeWorkout?.template.id != templateID
    }

    /// SCRUM-211: guarda el orden propio de una sesión (el coordinador valida y guarda).
    public func reorderSession(_ templateID: SessionTemplate.ID, to order: [ExerciseID]) async -> Bool {
        guard canReorderSession(templateID) else { return false }
        let saved = await todayPlan.reorderSession(templateID, to: order)
        if saved { refreshTodayState() }
        return saved
    }

    /// SCRUM-211: vuelve al orden recomendado de la sesión.
    public func resetSessionOrder(_ templateID: SessionTemplate.ID) async -> Bool {
        guard canReorderSession(templateID) else { return false }
        let saved = await todayPlan.resetSessionOrder(templateID)
        if saved { refreshTodayState() }
        return saved
    }

    /// "Cerrar sesión" (SCRUM-208): suelta de memoria el entrenamiento en curso (sigue
    /// guardado y se retoma al volver a entrar) y vuelve al login sin borrar datos.
    public func signOut() {
        activeWorkout = nil
        healthPrefill.reset()
        gym.reset()
        session.signOut()
    }

    /// SCRUM-30: ajusta la sesión de hoy al tiempo elegido (`nil` = sesión completa). No
    /// con un entrenamiento vivo: esa sesión ya empezó con su plantilla.
    public func setTimeBudget(_ minutes: Int?) async {
        guard activeWorkout == nil else { return }
        if await todayPlan.setTimeBudget(minutes) { refreshTodayState() }
    }

    /// SCRUM-224: qué va hoy en superset y por qué, ya traducido; `nil` si nada.
    public var supersetNote: String? {
        SupersetPresenter(locale: Self.presentationLocale).todayNote(for: todayPlan.plan?.todayTemplate) { exerciseNames[$0] }
    }

    /// SCRUM-30: la frase del ajuste de hoy, ya traducida; `nil` sin tiempo elegido.
    public var timeNote: String? {
        todayPlan.plan?.timeAdjustment.map { adjustment in
            SessionTimePresenter(locale: Self.presentationLocale).sentence(for: adjustment) { exerciseNames[$0] }
        }
    }


    /// Registra el check-in y aplica el ajuste del día que decide el motor.
    public func recordSleep(hours: Double, quality: SleepQuality) {
        guard let adjustment = sleepCheckIns.record(hours: hours, quality: quality) else { return }
        todayPlan.applyReadiness(adjustment)
        refreshTodayState()
    }

    /// Catálogo de ejercicios resolvido (inmutable; fallback vacío documentado).
    public let catalog: ExerciseCatalog

    /// Persistencia local (SCRUM-23): una colección por subdirectorio bajo
    /// `Application Support/PR/persistence`. `nil` sólo si Application Support no está
    /// disponible (el workout sigue funcionando en memoria).
    public var persistence: LocalPersistence? {
        guard let basePersistence, let userID = onboarding.auth.profile?.userIdentifier else { return nil }
        do {
            return try basePersistence.scoped(toUser: userID)
        } catch {
            // Sin la vista del usuario no se toca el historial (no se mezclaría con otra cuenta).
            basePersistence.log.saveFailed(.workouts)
            return nil
        }
    }

    /// Persistencia sin usuario (raíz). El historial de entrenamientos siempre se abre por
    /// `persistence`, que lo separa por cuenta (SCRUM-26).
    private let basePersistence: LocalPersistence?

    /// "Hoy" fijo para las pruebas de UI (sólo Debug); `nil` = reloj real.
    private let fixedDate: Date?

    /// Demora de la activación del plan para las pruebas de UI (sólo Debug, SCRUM-193).
    public let uiTestPlanDelay: Duration?

    /// Perfil con el que se contesta solo el cuestionario en las pruebas de UI (sólo Debug y
    /// con datos temporales, SCRUM-228); `nil` = a mano.
    private let uiTestSeededProfile: UITestSeededProfile?

    /// Entrenamiento vivo (retomado tras un cierre o empezado ahora). `nil` si no hay ninguno.
    /// Hoy muestra "Continuar" mientras exista y no haya terminado (SCRUM-24).
    public private(set) var activeWorkout: WorkoutSessionCoordinator?

    /// Carga el gimnasio de la cuenta (SCRUM-235). Sin almacén sigue con uno en memoria.
    public func loadGym() async {
        var repository: FileGymRepository?
        do {
            repository = try persistence?.gymRepository()
        } catch {
            basePersistence?.log.saveFailed(.gyms)
        }
        await gym.load(repository: repository)
        applyGym()
    }

    /// SCRUM-236: lo que no hay en el gimnasio activo se aplica a Hoy y a Semana. La sesión en
    /// curso sigue con su plantilla.
    public func applyGym() {
        todayPlan.applyGym(gym.activeGym)
        refreshTodayState()
    }

    /// "No hay esta máquina aquí": se guarda antes de cambiar la pantalla. Si no se pudo
    /// guardar, hoy se sigue con el sustituto, el gimnasio no queda marcado y `gym.notice`
    /// avisa. Sin sustituto, hoy se salta.
    public func markMissing(replacement: ExerciseID?) async {
        guard let workout = activeWorkout, let exercise = workout.currentExerciseID else { return }
        await gym.markMissing(exercise, replacement: replacement)
        if let replacement {
            _ = try? workout.substituteCurrentExercise(with: replacement, reason: .notAvailable)
        } else {
            _ = try? workout.skipCurrentExercise()
        }
        applyGym()
    }

    /// Perfil › Gimnasio: quita la marca. La sesión activa no cambia.
    public func removeMissing(_ exercise: ExerciseID) async {
        await gym.removeMissing(exercise)
        applyGym()
    }

    /// SCRUM-238: con un entrenamiento en curso no se cambia de gimnasio.
    public var canChangeGym: Bool {
        guard let activeWorkout else { return true }
        if case .finished = activeWorkout.phase { return true }
        return false
    }

    /// SCRUM-238: elige el gimnasio activo; Hoy y Semana se arman con lo suyo.
    public func selectGym(_ id: GymID) async {
        guard await gym.select(id, duringWorkout: !canChangeGym) else { return }
        applyGym()
    }

    /// SCRUM-238: "En: Oficina" en Hoy; con un solo gimnasio no se muestra.
    public var activeGymLabel: String? {
        gym.gyms.count > 1 ? gym.activeGym?.name : nil
    }

    /// SCRUM-236: la nota de Hoy sobre lo que el gimnasio cambió; `nil` si nada.
    public var gymNote: String? {
        guard let today = todayPlan.plan?.todayTemplate, let name = gym.activeGym?.name,
              let notes = todayPlan.plan?.gymNotes[today.id], !notes.isEmpty else { return nil }
        return Self.gymSentences(notes, gym: name, exerciseName: { exerciseNames[$0] ?? "" }).joined(separator: " ")
    }

    /// Lo que el gimnasio cambió en toda la semana, sin repetir (SCRUM-236).
    public var gymWeekNotes: [String] {
        guard let name = gym.activeGym?.name, let plan = todayPlan.plan else { return [] }
        let notes = plan.sessions.flatMap { plan.gymNotes[$0.id] ?? [] }
        var seen: Set<String> = []
        return Self.gymSentences(notes, gym: name, exerciseName: { exerciseNames[$0] ?? "" }).filter { seen.insert($0).inserted }
    }

    private static func gymSentences(_ notes: [GymAdaptationNote], gym: String, exerciseName: (ExerciseID) -> String) -> [String] {
        notes.map { note in
            switch note {
            case .replaced(let original, let replacement):
                return String(localized: "En \(gym) no hay \(exerciseName(original)): haces \(exerciseName(replacement)).")
            case .omitted(let original):
                return String(localized: "\(exerciseName(original)) no va hoy: no hay un sustituto equivalente y seguro en este gimnasio.")
            }
        }
    }

    /// Nombre visible de un ejercicio (lista de Perfil › Gimnasio).
    public func exerciseName(_ id: ExerciseID) -> String {
        exerciseNames[id] ?? ""
    }

    /// Al abrir: drena la cola de pendientes y retoma el entrenamiento que quedó abierto
    /// ("Tienes un entrenamiento en curso"). Si hay dos activas por error retoma la más
    /// reciente y abandona la otra sin tocar sus series.
    public func recoverWorkout() async {
        guard activeWorkout == nil, let persistence else { return }
        let templates = await todayPlan.allKnownTemplates()
        do {
            switch try await persistence.recoverWorkout(
                templates: templates,
                exerciseNames: exerciseNames,
                dropsetAdvice: dropsetAdvice,
                exerciseMuscles: exerciseMuscles,
                catalog: catalog.exercises,
                restrictions: completedProfile?.restrictions ?? [],
                gymID: gym.activeGym?.id,
                celebrationPresenter: PRCelebrationPresenter(locale: Self.presentationLocale),
                clock: clock
            ) {
            case .none: activeWorkout = nil
            case .restored(let coordinator):
                activeWorkout = coordinator
                watchBridge?.attach(coordinator)
            }
        } catch {
            persistence.log.saveFailed(.workouts)
        }
        refreshTodayState()
    }

    /// Lee el historial del usuario para "Tu semana" y "última vez" (SCRUM-197). Si no se
    /// puede leer, la semana se muestra igual, sólo sin días marcados como hechos (es una
    /// lectura: no se pierde ni se escribe nada).
    public func refreshHistory() async {
        guard let persistence else {
            todayPlan.historyLoadFailed()
            return
        }
        do {
            let result = try await persistence.workoutRepository().loadAllSessions()
            todayPlan.updateHistory(
                result.items,
                unreadable: result.unreadableCount,
                knownTemplates: await todayPlan.allKnownTemplates()
            )
        } catch {
            // Se conserva el historial anterior en memoria; Progreso ofrece reintentar.
            todayPlan.historyLoadFailed()
        }
    }

    /// El entrenamiento terminó (resumen cerrado): Hoy vuelve a su estado normal.
    public func workoutEnded() {
        if case .finished? = activeWorkout?.phase { activeWorkout = nil }
        refreshTodayState()
    }

    private func refreshTodayState() {
        var record: WorkoutSessionRecord?
        if let activeWorkout, case .finished = activeWorkout.phase {} else {
            record = try? activeWorkout?.snapshot().session
        }
        todayPlan.refreshState(activeSession: record)
    }

    /// "Hoy" del reloj de la app (fijo en las pruebas de UI).
    public var now: Date { clock() }

    /// Perfil de la sesión ya contestado; `nil` mientras no hay plan.
    public var completedProfile: OnboardingProfile? {
        if case .completed(let profile) = onboarding.phase { return profile }
        return nil
    }

    private var exerciseNames: [ExerciseID: String] {
        Dictionary(catalog.exercises.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
    }

    /// Músculos de cada ejercicio para decir dónde dolió (SCRUM-226).
    private var exerciseMuscles: [ExerciseID: [MuscleGroup.ID]] {
        PainMuscleOptions.byExercise(catalog.exercises)
    }

    /// Consejo de dropset por ejercicio para la persona (lo decide el dominio; SCRUM-200).
    private var dropsetAdvice: [ExerciseID: DropsetAdvice] {
        guard let profile = completedProfile else { return [:] }
        return IntensityAdvisor().dropsetAdvice(for: catalog.exercises, profile: profile)
    }

    private var clock: () -> Date {
        let fixed = fixedDate
        return { fixed ?? Date() }
    }

    /// Construye un coordinador de WORKOUT MODE para la sesión planeada hoy.
    /// Usa la plantilla del plan de hoy (si la hay) y los nombres del catálogo.
    /// Devuelve `nil` para un día de descanso (sin sesión).
    /// La persistencia (cola de pendientes, baselines de PR, guardado al terminar) la
    /// cablea `LocalPersistence`. Si no hay almacén durable, el coordinador funciona igual
    /// en memoria (nunca se pierde la sesión viva).
    public func makeWorkoutCoordinator() async -> WorkoutSessionCoordinator? {
        // Si ya hay un entrenamiento vivo (retomado o empezado) se continúa ese: nunca dos.
        if let activeWorkout {
            switch activeWorkout.phase {
            case .finished: break
            case .idle, .active, .resting, .paused: return activeWorkout
            }
        }
        guard let template = todayPlan.plan?.todayTemplate else { return nil }
        let presenter = PRCelebrationPresenter(locale: Self.presentationLocale)
        let coordinator: WorkoutSessionCoordinator
        if let persistence {
            do {
                coordinator = try await persistence.makeWorkoutCoordinator(
                    template: template,
                    exerciseNames: exerciseNames,
                    dropsetAdvice: dropsetAdvice,
                    exerciseMuscles: exerciseMuscles,
                    catalog: catalog.exercises,
                    restrictions: completedProfile?.restrictions ?? [],
                    gymID: gym.activeGym?.id,
                    celebrationPresenter: presenter,
                    clock: clock
                )
            } catch {
                persistence.log.saveFailed(.workouts)
                coordinator = WorkoutSessionCoordinator(
                    template: template, exerciseNames: exerciseNames, dropsetAdvice: dropsetAdvice,
                    exerciseMuscles: exerciseMuscles, catalog: catalog.exercises,
                    restrictions: completedProfile?.restrictions ?? [], celebrationPresenter: presenter, clock: clock
                )
            }
        } else {
            coordinator = WorkoutSessionCoordinator(
                template: template, exerciseNames: exerciseNames, dropsetAdvice: dropsetAdvice,
                exerciseMuscles: exerciseMuscles, catalog: catalog.exercises,
                    restrictions: completedProfile?.restrictions ?? [], celebrationPresenter: presenter, clock: clock
            )
        }
        activeWorkout = coordinator
        watchBridge?.attach(coordinator)
        return coordinator
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
        let testOptions = UITestLaunchOptions.resolve(
            arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild
        )
        let demoData = DemoDataLaunch.isRequested(arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild)
        self.demoData = demoData
        // Con `-PRFixedDate` (sólo Debug) "hoy" es ese día; si no, el reloj real.
        let fixedDate = testOptions.fixedDate(timeZone: .current)
        self.fixedDate = fixedDate
        self.uiTestPlanDelay = testOptions.planDelay
        self.uiTestSeededProfile = testOptions.seededProfile
        let featureFlags = FeatureFlags.forApp(arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild)
        self.featureFlags = featureFlags
        let aiConnection: AIConnection
        if testOptions.isolatedPersistence {
            aiConnection = AIConnection(status: .offline(.uiTesting), provider: OfflineLLMProvider())
        } else {
            #if DEBUG
            aiConnection = AIConnection.resolve(build: .debug, flags: featureFlags)
            #else
            aiConnection = AIConnection.resolve(build: .release, flags: featureFlags)
            #endif
        }
        self.aiConnection = aiConnection
        self.healthPrefill = HealthPrefillCoordinator(
            reader: testOptions.isolatedPersistence ? nil : HealthKitProfileReader(),
            isEnabled: featureFlags.isEnabled(.healthPrefillEnabled),
            clock: { fixedDate ?? Date() }
        )
        self.onboarding = OnboardingCoordinator(
            authProvider: authProvider ?? mode.provider(appleID: SignInWithAppleProvider()),
            clock: { fixedDate ?? Date() }
        )
        self.basePersistence = persistence ?? Self.makeDefaultPersistence(
            isolated: testOptions.isolatedPersistence ? testOptions.isolatedDirectoryName : nil,
            demo: demoData
        )
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
        var planStore: PlanStore?
        if let persistence = self.basePersistence {
            do {
                planStore = try persistence.planStore()
            } catch {
                // Sin almacén del plan la app funciona en memoria, pero no recuerda al usuario.
                persistence.log.saveFailed(.plans)
            }
        }
        var consentStore: AIConsentStore?
        if let persistence = self.basePersistence {
            do {
                consentStore = try persistence.aiConsentStore()
            } catch {
                // Sin almacén la decisión vive sólo en memoria: se vuelve a preguntar al reabrir.
                persistence.log.saveFailed(.aiConsent)
            }
        }
        let aiConsent = AIConsentCoordinator(
            store: consentStore,
            isOffered: featureFlags.isEnabled(.agentNvidiaEnabled),
            clock: { fixedDate ?? Date() }
        )
        self.aiConsent = aiConsent
        self.gym = GymCoordinator(defaultName: String(localized: "Mi gimnasio"), clock: { fixedDate ?? Date() })
        var checkInStore: SleepCheckInStore?
        if let persistence = self.basePersistence {
            do {
                checkInStore = try persistence.sleepCheckInStore()
            } catch {
                persistence.log.saveFailed(.checkIns)
            }
        }
        let sleepCheckIns = SleepCheckInCoordinator(store: checkInStore, clock: { fixedDate ?? Date() })
        self.sleepCheckIns = sleepCheckIns
        self.todayPlan = TodayPlanCoordinator(
            catalog: resolvedCatalog,
            planStore: planStore,
            clock: { fixedDate ?? Date() },
            // SCRUM-205: la IA personaliza sólo con conexión; sin consentimiento el contexto
            // es `nil` y no se manda nada.
            personalizer: aiConnection.status.isLive ? AIPlanPersonalizer(coach: AICoach(connection: aiConnection)) : nil,
            profileContext: { profile in aiConsent.context(for: profile, sleep: sleepCheckIns.today) }
        )
        self.session = AppSessionCoordinator(
            onboarding: self.onboarding,
            todayPlan: self.todayPlan,
            planStore: planStore,
            aiConsent: self.aiConsent,
            sleepCheckIns: self.sleepCheckIns,
            clock: { fixedDate ?? Date() }
        )
        let onboarding = self.onboarding
        self.restrictionScreen = RestrictionScreenModel(
            session: self.session,
            profile: {
                if case .completed(let profile) = onboarding.phase { return profile }
                return nil
            },
            catalog: resolvedCatalog.exercises,
            presenter: RestrictionListPresenter(locale: Self.presentationLocale),
            clock: { fixedDate ?? Date() }
        )
        // SCRUM-255: el reloj sólo se conecta en la app de verdad, nunca en pruebas de UI.
        if !testOptions.isolatedPersistence, let link = WatchConnectivityLink() {
            let bridge = PhoneWatchBridge(link: link) { [weak self] in
                guard let persistence = self?.persistence else { return nil }
                return WatchBridgeStorage(
                    queue: try persistence.pendingOperationQueue(),
                    workouts: try persistence.workoutRepository()
                )
            }
            bridge.start()
            self.watchBridge = bridge
        }
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

    /// Crea la persistencia por defecto en Application Support/PR/persistence, migra
    /// una sola vez el layout antiguo (todo en la raíz) y lleva cada colección a su
    /// formato vigente (SCRUM-40). Devuelve `nil` si el directorio
    /// no puede resolverse (fallback en memoria del app).
    /// `isolated` (sólo pruebas de UI en Debug): nombre de un directorio temporal, nunca los datos reales.
    /// `demo` (sólo Debug, SCRUM-188): Application Support/PR/demo, aparte de los datos reales.
    private static func makeDefaultPersistence(isolated isolatedName: String?, demo: Bool) -> LocalPersistence? {
        let persistence: LocalPersistence
        do {
            let root: URL
            if let isolatedName {
                root = FileManager.default.temporaryDirectory
                    .appendingPathComponent(isolatedName, isDirectory: true)
            } else {
                let base = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                root = demo ? PersistenceLocation.demo(in: base) : PersistenceLocation.real(in: base)
            }
            persistence = try LocalPersistence(rootURL: root)
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
        // Cada colección a su formato vigente (SCRUM-40). Una que falla queda intacta y se
        // registra; las de cada usuario migran al entrar (`scoped(toUser:)`).
        persistence.migrateSchemas()
        return persistence
    }
}
