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
    /// `-PRFakeSignIn` (para probar sin Sign in with Apple) o en el build de prueba para
    /// iPhone (`PR_DEVICE_TEST`, SCRUM-262); en Release siempre `.appleID`.
    public let authMode: AuthLaunchMode
    /// Permisos de los entrenamientos en Salud (SCRUM-244). Con el flag apagado, no hace nada.
    public let healthWorkouts: HealthWorkoutsAccess

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
    /// Si la persona quiere guardar en Salud (SCRUM-248).
    public let healthPreference: HealthPreferenceCoordinator
    /// Cuánto le explica la app, si lo eligió en Perfil (SCRUM-267).
    public let coachingPreference: CoachingPreferenceCoordinator

    /// El gimnasio del usuario (SCRUM-235). Sin pasos nuevos: se crea solo al entrar.
    public let gym: GymCoordinator

    /// "Usar datos de Salud" en "Sobre ti" (SCRUM-206). Sólo lectura; en pruebas de UI no
    /// se ofrece (no hay diálogo de permisos que tocar).
    public let healthPrefill: HealthPrefillCoordinator
    /// Puente con el reloj (SCRUM-255). `nil` si este dispositivo no tiene WatchConnectivity.
    @ObservationIgnored private var watchBridge: PhoneWatchBridge?
    @ObservationIgnored private var simulatesSetConflict = false
    @ObservationIgnored private var watchWorkoutLauncher: WatchWorkoutLauncher?

    /// Check-in diario de sueño (SCRUM-203).
    public let sleepCheckIns: SleepCheckInCoordinator

    /// SCRUM-273: mide cada llamada a la IA (tokens y milisegundos, sin texto). Sin IA no hay
    /// llamadas que medir.
    let usageRecorder: AgentUsageRecorder?
    /// SCRUM-273: "Uso de la IA (pruebas)" en Perfil, sólo en Debug y nunca en pruebas de UI.
    let showsAIUsage: Bool

    /// SCRUM-275 y SCRUM-276: el entrenador de Hoy y el del entrenamiento, cada uno con su
    /// conversación en memoria (DI-5 A). `nil` si la política no se pudo leer (sin botón).
    public private(set) var todayCoach: CoachConversationCoordinator?
    public private(set) var workoutCoach: CoachConversationCoordinator?
    /// Lo que cada entrenador le pide a la app; el coordinador los guarda débiles.
    @ObservationIgnored private var coachBridges: [CoachBridge] = []

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

    /// SCRUM-274: "¿Por qué?" de lo que el motor cambió hoy, en palabras. Sale del registro
    /// de cada decisión (SCRUM-270), nunca de la IA. Con varios cambios del gimnasio, sus
    /// razones van juntas (hasta 4).
    var todayWhy: TodayWhy {
        let presenter = DecisionExplanationPresenter(locale: Self.presentationLocale)
        var why = TodayWhy()
        var gym: [DecisionExplanation] = []
        for decision in todayPlan.todayDecisions {
            let item = WhyItem(id: decision.id.rawValue.uuidString, explanation: presenter.explanation(for: decision))
            switch decision.topic {
            case .timeFit: why.time = item
            case .readiness: why.readiness = item
            case .gymChange: gym.append(item.explanation)
            case .sessionOrder, .suggestedLoad, .pain: break
            }
        }
        if let first = gym.first {
            why.gym = WhyItem(id: "gym", explanation: DecisionExplanation(
                title: first.title,
                reasons: Array(gym.flatMap(\.reasons).prefix(DecisionExplanationPresenter.maximumReasons))
            ))
        }
        return why
    }

    /// SCRUM-273: lee el resumen del uso de la IA para Perfil (sólo Debug y fuera de las
    /// pruebas de UI); `nil` = sin fila.
    var aiUsageLoader: (() async throws -> [AgentUsageRow])? {
        guard showsAIUsage, let usageRecorder else { return nil }
        return { try await usageRecorder.summary() }
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

    /// Escribe en Salud los entrenamientos terminados (SCRUM-246, SCRUM-247).
    private let healthWriter: any HealthWorkoutWriting
    /// Lee de Salud lo que registraron otras apps o el reloj (SCRUM-249).
    private let healthReader: any HealthWorkoutReading
    /// Una cola por cuenta: sólo ve las sesiones de esa cuenta.
    @ObservationIgnored private var healthWriteCoordinators: [String: HealthWriteCoordinator] = [:]
    /// Una reconciliación por cuenta.
    @ObservationIgnored private var healthEnergyCoordinators: [String: HealthEnergyCoordinator] = [:]
    /// Lo que Salud registró y no es una sesión de Nucleus (SCRUM-250).
    public private(set) var healthActivities: [HealthActivity] = []
    /// Energía de la sesión recién terminada, si Salud ya la tiene.
    public private(set) var lastFinishedEnergy: CanonicalWorkoutEnergy?
    /// Qué dice el resumen del último entrenamiento sobre Salud (SCRUM-247).
    public private(set) var healthSaveDisplay: HealthSaveDisplay = .hidden
    /// ¿El resumen propone guardar en Salud? (SCRUM-248)
    public private(set) var healthOfferVisible = false
    /// Estado del interruptor de Perfil (SCRUM-248).
    public private(set) var healthWriteSetting: HealthWriteSetting = .off
    /// El último entrenamiento terminado: se guarda si se acepta la tarjeta del resumen.
    @ObservationIgnored private var lastFinishedWorkoutID: WorkoutID?

    /// ¿La app ofrece guardar en Salud?
    public var offersHealthWrites: Bool { healthWorkouts.isEnabled && healthWorkouts.isAvailable }

    private func healthWriteCoordinator(for persistence: LocalPersistence) -> HealthWriteCoordinator? {
        guard healthWorkouts.isEnabled,
              let userID = onboarding.auth.profile?.userIdentifier else { return nil }
        if let existing = healthWriteCoordinators[userID] { return existing }
        do {
            let coordinator = HealthWriteCoordinator(
                repository: try persistence.workoutRepository(),
                writer: healthWriter,
                canWrite: { [weak self] in await self?.canWriteToHealth() ?? false }
            )
            healthWriteCoordinators[userID] = coordinator
            return coordinator
        } catch {
            persistence.log.saveFailed(.workouts)
            return nil
        }
    }

    private func healthEnergyCoordinator(for persistence: LocalPersistence) -> HealthEnergyCoordinator? {
        guard healthWorkouts.isEnabled,
              let userID = onboarding.auth.profile?.userIdentifier else { return nil }
        if let existing = healthEnergyCoordinators[userID] { return existing }
        do {
            let coordinator = HealthEnergyCoordinator(
                repository: try persistence.workoutRepository(),
                reader: HealthExternalWorkoutsReader(
                    reader: healthReader,
                    isEnabled: healthWorkouts.isEnabled,
                    ownBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
                ),
                canRead: { [weak self] in await self?.canReadFromHealth() ?? false }
            )
            healthEnergyCoordinators[userID] = coordinator
            return coordinator
        } catch {
            persistence.log.saveFailed(.workouts)
            return nil
        }
    }

    private func canReadFromHealth() -> Bool {
        healthWorkouts.isEnabled && healthPreference.allowsWriting
    }

    /// Reconcilia con Salud: la energía queda en cada sesión, una vez (SCRUM-250).
    public func refreshHealthEnergy() async {
        guard let persistence, let coordinator = healthEnergyCoordinator(for: persistence) else {
            healthActivities = []
            return
        }
        do {
            healthActivities = try await coordinator.refresh(now: clock())
            if let id = lastFinishedWorkoutID {
                lastFinishedEnergy = try await coordinator.energy(of: id)
            }
        } catch {
            persistence.log.saveFailed(.workouts)
        }
    }

    /// Lo que corre cuando la sesión quedó guardada: no retiene el cierre del entrenamiento,
    /// porque el coordinador avisa desde su propia tarea (SCRUM-246).
    private func healthWriteHook(
        for persistence: LocalPersistence
    ) -> @Sendable (Result<WorkoutID, any Error>) async -> Void {
        let coordinator = healthWriteCoordinator(for: persistence)
        let log = persistence.log
        return { [weak self] result in
            guard case .success(let id) = result, let coordinator else { return }
            do {
                let status = try await coordinator.sessionFinished(id: id)
                let goesToHealth = try await coordinator.goesToHealth(id: id)
                await self?.sessionReachedSummary(id: id, status: status, goesToHealth: goesToHealth)
            } catch {
                log.saveFailed(.workouts)
            }
        }
    }

    /// Salud falsa de las pruebas de UI.
    private static func fakeHealthProvider(_ mode: UITestFakeHealth) -> any HealthKitProvider {
        switch mode {
        case .granted, .watch: return InMemoryHealthKitProvider(initialStatus: [.workout: .granted])
        case .undecided: return InMemoryHealthKitProvider()
        case .refuses: return InMemoryHealthKitProvider(grantBehavior: .denyAll)
        }
    }

    private func canWriteToHealth() async -> Bool {
        guard healthPreference.allowsWriting else { return false }
        return await healthWorkouts.canWrite()
    }

    private func sessionReachedSummary(id: WorkoutID, status: HealthWriteStatus?, goesToHealth: Bool) async {
        lastFinishedWorkoutID = id
        healthSaveDisplay = HealthSaveDisplay(status: status, canWrite: await canWriteToHealth())
        healthOfferVisible = HealthPermissionOffer.shouldShow(
            isEnabled: healthWorkouts.isEnabled,
            isAvailable: healthWorkouts.isAvailable,
            preference: healthPreference.preference,
            writeStatus: await healthWorkouts.writeStatus(),
            sessionGoesToHealth: goesToHealth
        )
        await refreshHealthEnergy()
    }

    /// Cuánto le explica la app a la cuenta activa, al entrar (SCRUM-267).
    public func loadCoachingPreference() {
        coachingPreference.load(userID: onboarding.auth.profile?.userIdentifier)
    }

    /// Nivel de explicación efectivo y su origen para el perfil completado (SCRUM-267).
    /// Sin perfil todavía: guiado, sin inventar una elección.
    public var coachingPrefs: CoachingDetailPrefs {
        guard case .completed(let profile) = onboarding.phase else {
            return CoachingDetailPrefs(level: .guided)
        }
        return coachingPreference.prefs(for: profile.experience)
    }

    /// Lee la decisión de la cuenta activa, al entrar (SCRUM-248).
    public func loadHealthPreference() async {
        healthPreference.load(userID: onboarding.auth.profile?.userIdentifier)
        await refreshHealthSetting()
    }

    /// El permiso se puede cambiar en Ajustes: se relee al volver a primer plano.
    public func refreshHealthSetting() async {
        healthWriteSetting = HealthWriteSetting(
            preference: healthPreference.preference,
            writeStatus: await healthWorkouts.writeStatus()
        )
    }

    /// "Guardar en Salud" del resumen: pide el permiso y, si se concede, guarda este entrenamiento.
    public func acceptHealthOffer() async {
        healthOfferVisible = false
        await enableHealthWrites()
        guard let id = lastFinishedWorkoutID, let persistence,
              let coordinator = healthWriteCoordinator(for: persistence) else { return }
        do {
            let status = try await coordinator.sessionFinished(id: id)
            healthSaveDisplay = HealthSaveDisplay(status: status, canWrite: await canWriteToHealth())
        } catch {
            persistence.log.saveFailed(.workouts)
        }
        await refreshHealthEnergy()
    }

    /// "Ahora no" del resumen: no vuelve a salir y Perfil sigue ofreciendo la opción.
    public func declineHealthOffer() async {
        healthOfferVisible = false
        healthPreference.set(.disabled)
        await refreshHealthSetting()
    }

    /// El interruptor de Perfil. Apagar no borra lo que ya está en Salud.
    public func setHealthWrites(_ enabled: Bool) async {
        if enabled {
            await enableHealthWrites()
            await retryHealthWrites()
        } else {
            healthPreference.set(.disabled)
            await refreshHealthSetting()
        }
    }

    private func enableHealthWrites() async {
        healthPreference.set(.enabled)
        _ = await healthWorkouts.requestPermissions()
        await refreshHealthSetting()
    }

    /// Reintenta lo pendiente de Salud de la cuenta activa: al abrir y al volver a primer plano.
    public func retryHealthWrites() async {
        guard let persistence, let coordinator = healthWriteCoordinator(for: persistence) else { return }
        do {
            try await coordinator.retryPending()
        } catch {
            persistence.log.saveFailed(.workouts)
        }
    }

    /// Persistencia sin usuario (raíz). El historial de entrenamientos siempre se abre por
    /// `persistence`, que lo separa por cuenta (SCRUM-26).
    private let basePersistence: LocalPersistence?

    /// "Hoy" fijo para las pruebas de UI (sólo Debug); `nil` = reloj real.
    private let fixedDate: Date?
    /// Desde cuándo avanza el reloj fijo; `nil` = no avanza (pruebas de UI, SCRUM-247).
    private let fixedClockStart: Date?

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
                clock: clock,
                onPersisted: healthWriteHook(for: persistence)
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
        await refreshHealthEnergy()
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

    /// Abre el reloj al empezar (SCRUM-258). Si no responde, el iPhone sigue solo.
    public func startWatchWorkout() async {
        await watchWorkoutLauncher?.start()
    }

    /// Sólo en pruebas de UI: la primera serie llega dos veces, como si iPhone y reloj la
    /// hubieran hecho sin conexión (SCRUM-259).
    public func seedSetConflictForUITest(in coordinator: WorkoutSessionCoordinator) {
        guard simulatesSetConflict, let exercise = coordinator.currentExerciseID else { return }
        let slot = SetSlot(exerciseID: exercise, slotIndex: 1)
        for (weight, age) in [(60.0, 20.0), (62.5, 10.0)] {
            guard let set = try? SetRecord(
                exerciseID: exercise, performedAt: Date().addingTimeInterval(-age),
                weight: weight, unit: .kilograms, reps: 8, lifecycle: .completed
            ) else { continue }
            coordinator.applyRemoteSet(set, slot: slot, device: WorkoutDevice.watch)
        }
    }

    /// El entrenamiento terminó (resumen cerrado): Hoy vuelve a su estado normal.
    public func workoutEnded() {
        if case .finished? = activeWorkout?.phase { activeWorkout = nil }
        refreshTodayState()
    }

    func refreshTodayState() {
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
        let launchedAt = fixedClockStart
        return {
            guard let fixed else { return Date() }
            // Con Salud falsa el reloj avanza desde el arranque: un entrenamiento sin duración
            // no va a Salud (SCRUM-247).
            guard let launchedAt else { return fixed }
            return fixed.addingTimeInterval(Date().timeIntervalSince(launchedAt))
        }
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
        healthSaveDisplay = .hidden
        healthOfferVisible = false
        lastFinishedEnergy = nil
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
                    clock: clock,
                    onPersisted: healthWriteHook(for: persistence)
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
        // Sólo `make install-iphone` pone esta condición (SCRUM-262).
        #if PR_DEVICE_TEST
        let isDeviceTestBuild = true
        #else
        let isDeviceTestBuild = false
        #endif
        let mode = AuthLaunchMode.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            isDebugBuild: isDebugBuild,
            isDeviceTestBuild: isDeviceTestBuild
        )
        self.authMode = mode
        let testOptions = UITestLaunchOptions.resolve(
            arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild
        )
        let demoData = DemoDataLaunch.isRequested(arguments: ProcessInfo.processInfo.arguments, isDebugBuild: isDebugBuild)
        self.demoData = demoData
        // Con `-PRFixedDate` (sólo Debug) "hoy" es ese día; si no, el reloj real.
        let fixedDate = testOptions.fixedDate(timeZone: .current)
        self.fixedDate = fixedDate
        self.fixedClockStart = testOptions.fakeHealth == nil ? nil : Date()
        self.uiTestPlanDelay = testOptions.planDelay
        self.uiTestSeededProfile = testOptions.seededProfile
        var featureFlags = FeatureFlags.forApp(
            arguments: ProcessInfo.processInfo.arguments,
            isDebugBuild: isDebugBuild,
            isDeviceTestBuild: isDeviceTestBuild
        )
        let healthProvider: any HealthKitProvider
        var healthIsAvailable = true
        switch testOptions.fakeHealth {
        case .none:
            let system = HealthKitPermissionProvider()
            healthIsAvailable = system.isHealthDataAvailable
            healthProvider = HealthSystemPermissionProvider(system: system)
            let store = HealthKitWorkoutStore()
            self.healthWriter = store
            self.healthReader = store
        case .some(let mode):
            featureFlags = featureFlags.setting(.healthWorkoutsEnabled, to: true)
            healthProvider = Self.fakeHealthProvider(mode)
            let store = FakeHealthWorkoutStore()
            self.healthWriter = store
            self.healthReader = store
            if mode == .watch {
                let otherAppStart = (fixedDate ?? Date()).addingTimeInterval(-3 * 3600)
                Task {
                    await store.setEchoedWatchKilocalories(240)
                    await store.setOtherSamples([HealthWorkoutSample(
                        uuid: UUID(),
                        start: otherAppStart,
                        end: otherAppStart.addingTimeInterval(1800),
                        activityType: .running,
                        activeKilocalories: 180,
                        sourceBundleIdentifier: "com.otra.app",
                        sourceName: "Otra app"
                    )])
                }
            }
        }
        self.featureFlags = featureFlags
        self.healthWorkouts = HealthWorkoutsAccess(
            flags: featureFlags, provider: healthProvider, isAvailable: healthIsAvailable
        )
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
            isOffered: AIConsentCoordinator.isOffered(flags: featureFlags, connection: aiConnection.status),
            clock: { fixedDate ?? Date() }
        )
        self.aiConsent = aiConsent
        var healthPreferenceStore: HealthPreferenceStore?
        if let persistence = self.basePersistence {
            do {
                healthPreferenceStore = try persistence.healthPreferenceStore()
            } catch {
                persistence.log.saveFailed(.healthPreference)
            }
        }
        self.healthPreference = HealthPreferenceCoordinator(
            store: healthPreferenceStore, clock: { fixedDate ?? Date() }
        )
        var coachingStore: CoachingPreferenceStore?
        if let persistence = self.basePersistence {
            do {
                coachingStore = try persistence.coachingPreferenceStore()
            } catch {
                // Sin almacén se usa el nivel de la experiencia y elegir otro avisa que no se guardó.
                persistence.log.saveFailed(.coachingPreference)
            }
        }
        self.coachingPreference = CoachingPreferenceCoordinator(store: coachingStore, clock: { fixedDate ?? Date() })
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
        var usageStore: AgentUsageStore?
        if let persistence = self.basePersistence {
            do {
                usageStore = try persistence.agentUsageStore()
            } catch {
                persistence.log.saveFailed(.agentUsage)
            }
        }
        let usageLog = self.basePersistence?.log
        let usageRecorder = aiConnection.status.isLive
            ? AgentUsageRecorder(store: usageStore, onSaveFailure: { usageLog?.saveFailed(.agentUsage) })
            : nil
        self.usageRecorder = usageRecorder
        #if DEBUG
        self.showsAIUsage = !testOptions.isolatedPersistence
        #else
        self.showsAIUsage = false
        #endif
        self.sleepCheckIns = sleepCheckIns
        self.todayPlan = TodayPlanCoordinator(
            catalog: resolvedCatalog,
            planStore: planStore,
            clock: { fixedDate ?? Date() },
            // SCRUM-205: la IA personaliza sólo con conexión; sin consentimiento el contexto
            // es `nil` y no se manda nada.
            personalizer: aiConnection.status.isLive
                ? AIPlanPersonalizer(
                    coach: AICoach(connection: aiConnection.metered(.planPersonalization, by: usageRecorder)),
                    explainCoach: AICoach(connection: aiConnection.metered(.planRationale, by: usageRecorder))
                )
                : nil,
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
        self.simulatesSetConflict = testOptions.simulatesSetConflict
        // SCRUM-255: el reloj sólo se conecta en la app de verdad, nunca en pruebas de UI.
        if !testOptions.isolatedPersistence, let link = WatchConnectivityLink() {
            // SCRUM-258: apagado hasta pasar el gate. `make install-iphone` lo enciende para probarlo.
            #if DEBUG && PR_DEVICE_TEST
            let recordsHealth = true
            #else
            let recordsHealth = featureFlags.isEnabled(.watchHealthSessionEnabled)
            #endif
            self.watchWorkoutLauncher = recordsHealth ? WatchWorkoutLauncher() : nil
            let bridge = PhoneWatchBridge(link: link, recordsHealth: recordsHealth) { [weak self] in
                guard let persistence = self?.persistence else { return nil }
                return WatchBridgeStorage(
                    queue: try persistence.pendingOperationQueue(),
                    workouts: try persistence.workoutRepository()
                )
            }
            bridge.start()
            self.watchBridge = bridge
        }
        // SCRUM-275 y SCRUM-276: el entrenador, con la política real y la auditoría sin texto.
        var auditRepository: FileAgentAuditRepository?
        if let persistence = self.basePersistence {
            do {
                auditRepository = try persistence.agentAuditRepository()
            } catch {
                persistence.log.saveFailed(.agentAudit)
            }
        }
        let auditLog = self.basePersistence?.log
        do {
            let writer = AgentActionWriter(validator: try ActionPolicyValidator(config: ActionPolicyConfig(rule: ActionPolicyDefaults.makeRule())))
            let today = CoachBridge(environment: self, surface: .today)
            let workout = CoachBridge(environment: self, surface: .workout)
            coachBridges = [today, workout]
            func makeCoach(_ bridge: CoachBridge) -> CoachConversationCoordinator {
                CoachConversationCoordinator(
                    handler: bridge,
                    transport: { [weak self] in self?.coachTransport },
                    writer: writer,
                    audit: auditRepository,
                    onAuditFailure: { auditLog?.saveFailed(.agentAudit) },
                    presenter: CoachReplyPresenter(locale: Self.presentationLocale),
                    clock: { fixedDate ?? Date() }
                )
            }
            todayCoach = makeCoach(today)
            workoutCoach = makeCoach(workout)
        } catch {
            todayCoach = nil
            workoutCoach = nil
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
