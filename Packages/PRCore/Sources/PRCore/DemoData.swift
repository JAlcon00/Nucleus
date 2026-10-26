//
//  DemoData.swift
//  PRCore
//
//  SCRUM-188 (S-01): ambiente demo. Con `-PRDemoData` (sólo Debug) la app arranca con un
//  perfil de ejemplo y 2 semanas de historial, en un directorio de persistencia APARTE de
//  los datos reales (`PR/demo` junto a `PR/persistence`, nunca uno dentro del otro). En
//  Release el argumento se ignora siempre.
//  El historial se registra con el mismo coordinador de entrenamiento que usa la app: las
//  series se guardan igual que en un entrenamiento real. Las cargas son datos de muestra
//  fijos (`DemoLoads`), no una recomendación del motor.
//  Sembrar es idempotente: si el usuario demo ya tiene plan no se toca nada, así lo que
//  se haga durante el demo se conserva al reabrir; un plan ilegible nunca se sobrescribe.
//

import Foundation
import PRDomain

/// Dónde vive cada persistencia bajo Application Support. Ninguna dentro de la otra.
public enum PersistenceLocation {
    /// Datos reales de la persona.
    public static let realPath = "PR/persistence"
    /// Datos del demo (SCRUM-188).
    public static let demoPath = "PR/demo"

    public static func real(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(realPath, isDirectory: true)
    }

    public static func demo(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(demoPath, isDirectory: true)
    }
}

/// Argumento de arranque del demo. La decisión es pura; la app sólo pasa sus argumentos
/// y si es Debug.
public enum DemoDataLaunch {
    /// Edit Scheme › Run › Arguments, o `xcrun simctl launch … -PRDemoData`.
    public static let argument = "-PRDemoData"

    /// Sólo Debug y con el argumento. En Release nunca, aunque venga.
    public static func isRequested(arguments: [String], isDebugBuild: Bool) -> Bool {
        isDebugBuild && arguments.contains(argument)
    }
}

/// Qué hizo la siembra.
public enum DemoSeedOutcome: Equatable, Sendable {
    /// Se creó el plan y se registraron `workouts` entrenamientos completados.
    case seeded(workouts: Int)
    /// El usuario demo ya tenía plan: no se tocó nada.
    case alreadySeeded
    /// Hay un plan que no se pudo leer: no se sobrescribe (integridad de datos).
    case skippedUnreadable
}

public enum DemoDataError: Error, Equatable, Sendable {
    case planNotCreated
    case workoutNotSaved
}

/// Siembra el perfil demo y su historial en la persistencia que se le da.
@MainActor
public struct DemoDataSeeder {
    /// Días de historial antes de "hoy" (2 semanas).
    public static let historyDays = 14
    /// Hora local de cada entrenamiento del historial y segundos entre series.
    private static let workoutHour = 18
    private static let activationHour = 8
    private static let secondsPerSet: TimeInterval = 150

    private let catalog: ExerciseCatalog
    private let timeZone: TimeZone

    public init(catalog: ExerciseCatalog, timeZone: TimeZone) {
        self.catalog = catalog
        self.timeZone = timeZone
    }

    /// Crea el plan del usuario demo 14 días antes de `now` y registra un entrenamiento
    /// completo en cada día de entrenamiento hasta ayer. No hace nada si ya hay plan.
    public func seedIfNeeded(persistence: LocalPersistence, userID: String, now: Date) async throws -> DemoSeedOutcome {
        let planStore = try persistence.planStore()
        switch await planStore.loadPlan(userID: userID) {
        case .loaded: return .alreadySeeded
        case .unreadable: return .skippedUnreadable
        case .none: break
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = DemoClock(try Self.date(daysBefore: Self.historyDays, hour: Self.activationHour, from: now, calendar: calendar))
        let zone = timeZone
        let coordinator = TodayPlanCoordinator(
            catalog: catalog, planStore: planStore, clock: { clock.now }, timeZone: { zone }
        )
        guard await coordinator.activate(profile: try Self.profile(now: clock.now, calendar: calendar), userID: userID) else {
            throw DemoDataError.planNotCreated
        }

        let exercises = Dictionary(catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var workouts = 0
        for daysBefore in stride(from: Self.historyDays, through: 1, by: -1) {
            clock.now = try Self.date(daysBefore: daysBefore, hour: Self.workoutHour, from: now, calendar: calendar)
            guard case .restored = await coordinator.restore(userID: userID),
                  let template = coordinator.plan?.todayTemplate else { continue }
            let week = (Self.historyDays - daysBefore) / 7
            try await record(template, week: week, startingAt: clock.now, exercises: exercises, persistence: persistence)
            workouts += 1
        }
        return .seeded(workouts: workouts)
    }

    /// Un entrenamiento completo con el coordinador real; espera a que quede guardado.
    private func record(
        _ template: SessionTemplate,
        week: Int,
        startingAt start: Date,
        exercises: [ExerciseID: Exercise],
        persistence: LocalPersistence
    ) async throws {
        let clock = DemoClock(start)
        let (persisted, continuation) = AsyncStream<Result<WorkoutID, any Error>>.makeStream()
        let workout = try await persistence.makeWorkoutCoordinator(
            template: template, clock: { clock.now }, onPersisted: { continuation.yield($0) }
        )
        _ = workout.start(now: clock.now)
        while let set = workout.currentSet() {
            clock.now = clock.now.addingTimeInterval(Self.secondsPerSet)
            let exercise = exercises[template.plannedSets[set.index].exerciseID]
            let load = DemoLoads.set(for: exercise, week: week, isWarmup: set.isWarmup, targetReps: set.draft.targetReps)
            _ = try workout.recordEditedSet(weight: load.weight, reps: load.reps, unit: .kilograms, now: clock.now)
        }
        _ = try workout.complete(now: clock.now)
        for await result in persisted {
            _ = try result.get()
            return
        }
        throw DemoDataError.workoutNotSaved
    }

    /// Perfil de ejemplo: intermedio, hipertrofia, 4 días, con la rodilla declarada (para
    /// mostrar Perfil › Restricciones y que el plan la cuida) y "Sobre ti" completo.
    static func profile(now: Date, calendar: Calendar) throws -> OnboardingProfile {
        var draft = OnboardingDraft()
        let answers: [(OnboardingStep, OnboardingAnswer)] = [
            (.goal, .goal(.hypertrophy)),
            (.phase, .phase(.maintenance)),
            (.experience, .experience(.intermediate)),
            (.daysPerWeek, .trainingDays([.monday, .tuesday, .thursday, .friday])),
            (.sessionMinutes, .sessionMinutes(60)),
            (.variety, .variety(.balanced)),
            (.restrictions, .restrictions(RestrictionsAnswer(zones: [.knee], note: "Me molesta la rodilla al bajar escaleras"))),
        ]
        for (step, answer) in answers { draft = draft.settingAnswer(answer, for: step) }
        var profile = try OnboardingProfileBuilder(clock: { now }).build(from: draft)
        profile.aboutYou = try AboutYou(
            name: "Alex", birthYear: calendar.component(.year, from: now) - 29, sex: .undisclosed,
            heightCentimeters: 175, weight: 76, weightUnit: .kilograms
        )
        return profile
    }

    /// `hour` en punto, `daysBefore` días de calendario antes de `now` (nunca 86 400 s).
    private static func date(daysBefore: Int, hour: Int, from now: Date, calendar: Calendar) throws -> Date {
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: now)),
              let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else {
            throw DemoDataError.planNotCreated
        }
        return date
    }
}

/// Cargas de muestra del historial demo (kg). Datos de ejemplo fijos, no una
/// recomendación: el motor sigue decidiendo las cargas de los entrenamientos reales. La
/// segunda semana sube un escalón para que Progreso muestre avance.
enum DemoLoads {
    struct Load: Equatable {
        let weight: Double
        let reps: Int
    }

    static func set(for exercise: Exercise?, week: Int, isWarmup: Bool, targetReps: Int) -> Load {
        let (base, step) = baseAndStep(exercise?.equipment)
        let reps = max(1, targetReps)
        guard step > 0 else {
            // Peso corporal o bandas: sin carga; avanza con una repetición más por semana.
            return Load(weight: 0, reps: reps + (isWarmup ? 0 : week))
        }
        let scale = exercise?.jointClass == .singleJoint ? 0.5 : 1.0
        let working = rounded(base * scale + step * Double(week), to: step)
        return Load(weight: isWarmup ? rounded(working / 2, to: step) : working, reps: reps)
    }

    private static func baseAndStep(_ equipment: EquipmentType?) -> (base: Double, step: Double) {
        switch equipment {
        case .barbell: return (60, 2.5)
        case .smithMachine: return (50, 2.5)
        case .plateLoaded: return (80, 5)
        case .machine: return (45, 2.5)
        case .sled: return (40, 5)
        case .cable: return (25, 2.5)
        case .dumbbell: return (18, 1)
        case .kettlebell: return (16, 2)
        case .other, .none: return (20, 2.5)
        case .bodyweight, .bands: return (0, 0)
        }
    }

    private static func rounded(_ value: Double, to step: Double) -> Double {
        (value / step).rounded() * step
    }
}

/// Reloj que la siembra avanza a mano (el seeder es el único que lo toca, en el main actor).
private final class DemoClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
