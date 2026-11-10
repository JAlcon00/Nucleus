//
//  DecisionExplanationTests.swift
//  PRCoreTests
//
//  SCRUM-270 (PR-I001, RF-025): "¿Por qué?" en palabras, sólo con los hechos del registro.
//  - Tabla hechos → razones: de 1 a 4, sin números que no estén en los hechos; un hecho
//    desconocido se omite y sin hechos lo dice.
//  - El dolor dice lo mismo que la recomendación de "¿Te dolió?".
//  - Integración con `LocalPersistence` real: el plan con tiempo elegido y el check-in de
//    sueño corto dan los mismos registros al reabrir.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let zone = TimeZone(identifier: "America/Mexico_City") ?? .gmt
private let spanish = DecisionExplanationPresenter(locale: Locale(identifier: "es_MX"))
private let date = Date(timeIntervalSince1970: 1_792_000_000)

private func october(_ day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
}

private func decision(_ topic: ExplainableTopic, _ facts: [(String, String)]) -> ExplainableDecision {
    let facts = facts.map { DecisionFact(key: $0.0, value: $0.1) }
    return ExplainableDecision(topic: topic, record: DecisionRecord(
        id: StableDecisionID.make(topic: topic, facts: facts), date: date, type: .reorder,
        inputFacts: facts, action: DecisionActionSummary(title: "x")
    ))
}

/// Los números de un texto (para comprobar que ninguno se inventó).
private func numbers(in text: String) -> Set<String> {
    Set(text.split(whereSeparator: { !$0.isNumber && $0 != "." })
        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        .filter { !$0.isEmpty && Double($0) != nil })
}

@Suite("SCRUM-270 · \"¿Por qué?\" desde el registro de la decisión")
struct DecisionExplanationTests {

    @Test("El recorte por tiempo: minutos, quitados, reducidos y que los principales se quedan")
    func trimmedTime() {
        let explanation = spanish.explanation(for: decision(.timeFit, [
            ("time.budgetMinutes", "30"), ("time.originalMinutes", "52"), ("time.fit", "trimmed"),
            ("time.removed", "Elevaciones laterales"), ("time.reduced", "Curl"), ("time.noExtraVolume", "true"),
        ]))
        #expect(explanation.title == "Por qué tu sesión es más corta")
        #expect(explanation.reasons == [
            "Elegiste 30 min y la sesión duraba unos 52.",
            "Quitamos Elevaciones laterales.",
            "Dejamos menos series de Curl.",
            "Los ejercicios principales se quedan.",
        ])
    }

    @Test("Si la sesión ya cabía, dice que el tiempo no suma series (RN-002)")
    func fitsTime() {
        let explanation = spanish.explanation(for: decision(.timeFit, [
            ("time.budgetMinutes", "90"), ("time.originalMinutes", "55"), ("time.fit", "fits"),
            ("time.suggestion", "mobility"), ("time.noExtraVolume", "true"),
        ]))
        #expect(explanation.title == "Por qué no agregamos series")
        #expect(explanation.reasons == [
            "Tu sesión dura unos 55 min y cabe en los 90 que tienes.",
            "Más tiempo no suma series: el volumen lo marca tu plan.",
            "Con lo que sobra puedes sumar movilidad.",
        ])
    }

    @Test("Si no cabe ni recortada, dice cuánto necesita")
    func doesNotFit() {
        let explanation = spanish.explanation(for: decision(.timeFit, [
            ("time.budgetMinutes", "30"), ("time.originalMinutes", "70"), ("time.fit", "doesNotFit"), ("time.neededMinutes", "45"),
        ]))
        #expect(explanation.title == "Por qué tu sesión no cabe")
        #expect(explanation.reasons.first == "Aun recortada necesita unos 45 min y tienes 30.")
    }

    @Test("El día aligerado: motivo, RIR, series de aislados y que la carga no cambia")
    func readiness() {
        let explanation = spanish.explanation(for: decision(.readiness, [
            ("readiness.reason", "shortAndPoorSleep"), ("readiness.rirIncrease", "1"),
            ("readiness.isolationSetReduction", "1"), ("readiness.loadUnchanged", "true"),
        ]))
        #expect(explanation.title == "Por qué hoy es más ligero")
        #expect(explanation.reasons == [
            "Dormiste poco y mal.",
            "Cada serie termina 1 repetición más lejos del fallo.",
            "Los ejercicios aislados tienen 1 serie menos.",
            "El peso y las repeticiones no cambian.",
        ])
    }

    @Test("Plural correcto y en inglés (RNF-013)")
    func pluralAndEnglish() {
        let facts = [("readiness.reason", "poorSleep"), ("readiness.rirIncrease", "2"), ("readiness.isolationSetReduction", "2")]
        #expect(spanish.explanation(for: decision(.readiness, facts)).reasons == [
            "Dormiste mal.",
            "Cada serie termina 2 repeticiones más lejos del fallo.",
            "Los ejercicios aislados tienen 2 series menos.",
        ])
        let english = DecisionExplanationPresenter(locale: Locale(identifier: "en_US"))
        let explanation = english.explanation(for: decision(.readiness, [("readiness.reason", "poorSleep"), ("readiness.rirIncrease", "1")]))
        #expect(explanation.title == "Why today is lighter")
        #expect(explanation.reasons == ["You slept poorly.", "Each set ends 1 rep further from failure."])
    }

    @Test("El gimnasio: qué no hay y por qué se cambió o se quitó")
    func gym() {
        let replaced = spanish.explanation(for: decision(.gymChange, [
            ("gym.change", "replaced"), ("gym.original", "Hack squat"), ("gym.replacement", "Prensa"),
        ]))
        #expect(replaced.reasons == [
            "Marcaste que en este gimnasio no hay Hack squat.",
            "Lo cambiamos por Prensa, que hace el mismo movimiento.",
        ])
        let omitted = spanish.explanation(for: decision(.gymChange, [("gym.change", "omitted"), ("gym.original", "")]))
        #expect(omitted.reasons.first == "Marcaste que en este gimnasio no hay un ejercicio.", "Sin nombre inventado")
    }

    @Test("El peso precargado dice de dónde salió y que la app no lo sube sola",
          arguments: [
            ("lastTime", "true", "40 kg es lo que levantaste la última vez en Prensa en esta máquina."),
            ("lastTime", "false", "40 kg es lo que levantaste la última vez en Prensa."),
            ("prescription", "false", "40 kg es el peso que marca tu plan para Prensa."),
          ])
    func load(source: String, perMachine: String, expected: String) {
        let explanation = spanish.explanation(for: decision(.suggestedLoad, [
            ("load.source", source), ("load.exercise", "Prensa"), ("load.weight", "40"), ("load.unit", "kilograms"),
            ("load.perMachine", perMachine), ("load.warmup", "false"), ("load.progressionApplied", "false"),
        ]))
        #expect(explanation.title == "Por qué este peso")
        #expect(explanation.reasons == [
            expected,
            "La app no sube el peso por su cuenta: tú lo cambias si hoy puedes más.",
        ])
    }

    @Test("Sin peso anterior pide escribirlo; en libras dice lb")
    func loadWithoutData() {
        let none = spanish.explanation(for: decision(.suggestedLoad, [
            ("load.source", "none"), ("load.exercise", "Prensa"), ("load.perMachine", "true"), ("load.progressionApplied", "false"),
        ]))
        #expect(none.reasons.first == "No hay un peso anterior en esta máquina: escribe el que vayas a usar.")
        let pounds = spanish.explanation(for: decision(.suggestedLoad, [
            ("load.source", "lastTime"), ("load.exercise", "Curl"), ("load.weight", "25"), ("load.unit", "pounds"),
        ]))
        #expect(pounds.reasons == ["25 lb es lo que levantaste la última vez en Curl."])
    }

    @Test("El dolor dice lo mismo que la recomendación de \"¿Te dolió?\"", arguments: [PainLevel.mild, .moderate, .high])
    func painMatchesRecommendation(level: PainLevel) throws {
        let engine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
        let evaluation = try engine.evaluate(PainFeedbackInput(level: level, exerciseName: "Sentadilla"))
        let pain = try #require(ExplainableDecisionBuilder().pain(evaluation, date: date))
        let explanation = spanish.explanation(for: pain)
        let message = PainRecommendationPresenter(locale: Locale(identifier: "es_MX")).message(for: evaluation.recommendation)
        #expect(explanation.title == "Por qué esta recomendación")
        #expect(explanation.reasons.first?.hasPrefix("Reportaste dolor ") == true)
        if let message {
            #expect(explanation.reasons.contains(message), "Misma frase que la hoja de dolor")
        }
        #expect(explanation.reasons.contains("No se sube la carga de este ejercicio mientras haya dolor moderado o alto.") == evaluation.suspendsLoadProgression)
    }

    @Test("El orden: la persona eligió, los primeros con su motivo y la fatiga al final")
    func order() {
        let explanation = spanish.explanation(for: decision(.sessionOrder, [
            ("order.custom", "true"), ("order.reorderedByFatigue", "true"),
            ("order.entry", "1|Sentadilla"), ("order.reason", "1|functionalRole"),
            ("order.entry", "2|Curl"), ("order.reason", "2|musclePriority"),
            ("order.entry", "3|"), ("order.reason", "3|technicalDemand"),
        ]))
        #expect(explanation.reasons == [
            "Este orden lo elegiste tú; el motor recomienda el de abajo.",
            "1. Sentadilla: es compuesto y va con los músculos frescos.",
            "2. Curl: trabaja un músculo que priorizas.",
            "La fatiga acumulada cambió el orden para proteger los músculos prioritarios.",
        ], "Máximo 4; la fatiga no se pierde")
    }

    @Test("Un hecho desconocido se omite y sin hechos dice que no hay datos")
    func unknownAndEmpty() {
        let unknown = spanish.explanation(for: decision(.readiness, [("readiness.reason", "otra"), ("x.y", "9")]))
        #expect(unknown.reasons == ["No hay datos para explicar esta decisión."])
        let empty = spanish.explanation(for: decision(.timeFit, []))
        #expect(empty.reasons == ["No hay datos para explicar esta decisión."])
    }

    @Test("Ningún número de las razones falta en los hechos")
    func noInventedNumbers() {
        let samples = [
            decision(.timeFit, [("time.budgetMinutes", "30"), ("time.originalMinutes", "52"), ("time.fit", "trimmed"), ("time.removed", "Curl")]),
            decision(.readiness, [("readiness.reason", "shortSleep"), ("readiness.rirIncrease", "2"), ("readiness.isolationSetReduction", "1")]),
            decision(.suggestedLoad, [("load.source", "lastTime"), ("load.exercise", "Prensa"), ("load.weight", "42.5"), ("load.unit", "kilograms")]),
        ]
        for sample in samples {
            let factNumbers = Set(sample.record.inputFacts.flatMap { numbers(in: $0.value) })
            let explanation = spanish.explanation(for: sample)
            #expect(explanation.reasons.count <= DecisionExplanationPresenter.maximumReasons)
            for reason in explanation.reasons {
                #expect(numbers(in: reason).isSubset(of: factNumbers), "\"\(reason)\" trae un número que no está en los hechos")
            }
        }
    }

    // MARK: - Integración

    @MainActor
    @Test("Integración: con el tiempo elegido y el sueño corto, reabrir da los mismos registros y razones")
    func sameDecisionsAfterReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-why-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = try october(19)
        let profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
        )
        func open() throws -> (TodayPlanCoordinator, SleepCheckInCoordinator) {
            let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
            let today = TodayPlanCoordinator(
                catalog: try ExerciseCatalogLoader.loadBundled(), planStore: try persistence.planStore(),
                clock: { now }, timeZone: { zone }
            )
            let sleep = SleepCheckInCoordinator(store: try persistence.sleepCheckInStore(), clock: { now }, timeZone: { zone })
            sleep.load(userID: "u1")
            return (today, sleep)
        }

        let (first, firstSleep) = try open()
        #expect(await first.activate(profile: profile, userID: "u1"))
        #expect(await first.setTimeBudget(30))
        let adjustment = try #require(firstSleep.record(hours: 5, quality: .good))
        first.applyReadiness(adjustment)
        let before = first.todayDecisions
        #expect(Set(before.map(\.topic)).isSuperset(of: [.sessionOrder, .timeFit, .readiness]))
        #expect(before.first { $0.topic == .timeFit }?.value(ExplainableFactKey.timeBudgetMinutes) == "30")
        #expect(before.first { $0.topic == .readiness }?.value(ExplainableFactKey.readinessReason) == "shortSleep")
        #expect(before.allSatisfy { !$0.record.inputFacts.isEmpty })

        let (second, secondSleep) = try open()
        #expect(await second.restore(userID: "u1") == .restored(profile))
        second.applyReadiness(secondSleep.adjustment)
        let after = second.todayDecisions
        #expect(after == before, "Mismo estado guardado, mismos registros (IDs incluidos)")
        #expect(after.map { spanish.explanation(for: $0) } == before.map { spanish.explanation(for: $0) })
    }

    @MainActor
    @Test("Integración: en el entrenamiento, el peso precargado y el dolor reportado tienen su registro")
    func workoutDecisions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-why-w-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = try october(19)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        // Un ejercicio del catálogo con peso que no depende de la máquina: la sesión en curso
        // cuenta como "última vez".
        let exercise = try #require(try ExerciseCatalogLoader.loadBundled().exercises.first { !$0.equipment.loadIsPerMachine })
        let squat = exercise.id
        let work = try SetPrescription(targetRepRange: 8...12, loadUnit: .kilograms, restSeconds: 90...120)
        let template = SessionTemplate(title: "Pierna", plannedSets: [
            PlannedSet(exerciseID: squat, prescription: work),
            PlannedSet(exerciseID: squat, prescription: work),
        ])
        let workout = try await persistence.makeWorkoutCoordinator(template: template, catalog: [exercise], clock: { now })
        _ = workout.start()

        let first = try #require(workout.suggestedLoadDecision)
        #expect(first.topic == .suggestedLoad)
        #expect(first.value(ExplainableFactKey.loadSource) == SuggestedLoadSource.none.rawValue, "Sin historial no hay peso que explicar")
        #expect(try workout.painDecision() == nil, "Sin reporte no hay registro de dolor")

        _ = try workout.recordEditedSet(weight: 60, reps: 10)
        let second = try #require(workout.suggestedLoadDecision)
        #expect(second.value(ExplainableFactKey.loadSource) == SuggestedLoadSource.lastTime.rawValue)
        #expect(second.value(ExplainableFactKey.loadWeight) == "60")

        let recommendation = try workout.reportPain(.moderate)
        let pain = try #require(try workout.painDecision())
        #expect(pain.value(ExplainableFactKey.painLevel) == String(PainLevel.moderate.rawValue))
        #expect(pain.value(ExplainableFactKey.painRecommendation) == "reduceIntensityAndMonitor")
        #expect(recommendation == .reduceIntensityAndMonitor, "El registro es el mismo que decidió la recomendación")
        #expect(try workout.painDecision() == pain, "Mismo reporte, mismo registro")
        _ = try workout.reportPain(.none)
        #expect(try workout.painDecision() == nil, "\"Sin dolor\" no tiene registro")
    }

    @MainActor
    @Test("En descanso no hay decisiones que explicar")
    func restDayHasNone() async throws {
        let sunday = try october(25)
        let store = PlanStore(plans: MemoryRepositoryStore(), sessions: MemoryRepositoryStore(), blocks: MemoryRepositoryStore())
        let today = TodayPlanCoordinator(catalog: try ExerciseCatalogLoader.loadBundled(), planStore: store, clock: { sunday }, timeZone: { zone })
        let profile = try OnboardingProfile(
            goal: .hypertrophy, phase: .maintenance, experience: .intermediate,
            trainingDays: [.monday, .tuesday, .thursday, .friday], usualSessionMinutes: 90, varietyPreference: .balanced
        )
        #expect(await today.activate(profile: profile, userID: "u1"))
        #expect(today.plan?.todayTemplate == nil)
        #expect(today.todayDecisions.isEmpty)
    }
}
