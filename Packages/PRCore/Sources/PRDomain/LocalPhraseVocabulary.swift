//
//  LocalPhraseVocabulary.swift
//  PRDomain
//
//  SCRUM-271 (PR-I002, RF-027, RNF-003): lo que entiende el intérprete local, sin red. En
//  Release no hay IA, así que es lo que responde siempre ahí.
//  - Una tabla pequeña de palabras en español, versionada (`version`). Ante la duda pide
//    aclarar y dice sobre qué (`AgentClarification`), para que la pantalla ofrezca opciones.
//  - Nunca inventa IDs: el ejercicio actual, los gimnasios y las decisiones que se pueden
//    explicar salen del contexto (`AgentContext`).
//  - Sólo propone intenciones: la política y el motor deciden después.
//  - Puro y sin estado: nada se carga al abrir la app (arranque en frío, RNF-003).
//

import Foundation

// MARK: - Contexto que el intérprete puede usar

/// El ejercicio de la serie actual, dentro del entrenamiento.
public struct AgentExerciseContext: Sendable, Hashable {
    public let id: ExerciseID
    public let equipment: EquipmentType
    public let name: String?

    public init(id: ExerciseID, equipment: EquipmentType, name: String?) {
        self.id = id
        self.equipment = equipment
        self.name = name
    }
}

/// Un gimnasio de la persona, con el nombre que ella le puso.
public struct AgentGymContext: Sendable, Hashable {
    public let id: GymID
    public let name: String

    public init(id: GymID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Una decisión que se puede explicar ahora ("¿Por qué?", SCRUM-270).
public struct AgentDecisionContext: Sendable, Hashable {
    public let id: DecisionID
    public let topic: ExplainableTopic

    public init(id: DecisionID, topic: ExplainableTopic) {
        self.id = id
        self.topic = topic
    }
}

// MARK: - Aclaraciones

/// Sobre qué pide aclarar el intérprete local.
public enum AgentClarification: Sendable, Hashable {
    /// No se entendió.
    case general
    /// Cuántos minutos ("tengo poco tiempo", dos cantidades o fuera de rango).
    case minutes
    /// Qué máquina, fuera del entrenamiento.
    case equipment
    /// Cuánto duele; la zona si se dijo.
    case painLevel(region: BodyRegion?)
    /// Cuál de estas decisiones explicar.
    case whichDecision([AgentDecisionContext])
    /// Ahora no hay una decisión de ese tema que explicar (`nil`: de ninguno).
    case nothingToExplain(ExplainableTopic?)
    /// Cambiar de ejercicio sólo se puede dentro del entrenamiento.
    case exerciseSwapNeedsWorkout
    /// A cuál gimnasio (los de la persona).
    case whichGym([AgentGymContext])
    /// Dos pedidos en un mensaje: uno a la vez.
    case oneThingAtATime
}

/// Lo que entendió el intérprete local y, si pide aclarar, sobre qué.
public struct LocalInterpretation: Sendable, Equatable {
    public let interpretation: AgentInterpretation
    /// `nil` cuando entendió una intención.
    public let clarification: AgentClarification?

    public init(interpretation: AgentInterpretation, clarification: AgentClarification?) {
        self.interpretation = interpretation
        self.clarification = clarification
    }

    static func intent(_ intent: AgentIntent) -> LocalInterpretation {
        LocalInterpretation(interpretation: .intent(intent), clarification: nil)
    }

    static func clarify(_ clarification: AgentClarification) -> LocalInterpretation {
        LocalInterpretation(interpretation: .needsClarification, clarification: clarification)
    }
}

// MARK: - Vocabulario

/// Las palabras que entiende el intérprete local. Súbele la versión al cambiar cualquier
/// lista: las pruebas fijan el resultado de cada frase.
public enum LocalPhraseVocabulary {
    public static let version = 1

    /// Minúsculas, sin acentos, sin signos y con un solo espacio entre palabras.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    // Tiempo: de la frase más larga a la más corta, para no contar dos veces.
    static let minutePhrases: [(String, Int)] = [
        ("una hora y media", 90), ("hora y media", 90), ("tres cuartos de hora", 45),
        ("media hora", 30), ("dos horas", 120), ("una hora", 60),
    ]
    static let vagueTime = ["poco tiempo", "no tengo tiempo", "tengo prisa", "ando con prisa", "con prisa"]

    // Dolor.
    static let painWords = ["me duele", "duele", "dolor", "molestia", "me molesta", "lastim"]
    static let painNegations = ["no me duele", "sin dolor", "ya no duele", "ya no me duele"]
    static let painLevels: [(PainLevel, [String])] = [
        (.mild, ["no mucho", "no tanto", "no me duele mucho", "no me duele tanto", "no me molesta mucho"]),
        (.high, ["muchisimo", "mucho", "fuerte", "demasiado", "insoportable", "intenso"]),
        (.moderate, ["moderado", "moderada", "regular", "bastante", "medio"]),
        (.mild, ["un poco", "poquito", "tantito", "leve", "ligero", "ligera", "poco"]),
    ]
    static let bodyRegions: [(BodyRegion, [String])] = [
        (.lumbar, ["espalda baja", "zona lumbar", "lumbar"]),
        (.thoracic, ["espalda alta", "dorsal"]),
        (.shoulder, ["hombro"]), (.knee, ["rodilla"]), (.elbow, ["codo"]), (.wrist, ["muneca"]),
        (.hand, ["mano"]), (.neck, ["cuello"]), (.hip, ["cadera"]), (.groin, ["ingle"]),
        (.ankle, ["tobillo"]), (.foot, ["pie"]), (.core, ["abdomen", "abdominal"]),
    ]
    static let bodySides: [(BodySide, [String])] = [
        (.bilateral, ["ambos", "los dos", "las dos"]),
        (.left, ["izquierd"]),
        (.right, ["derech"]),
    ]

    // Fatiga: tabla fija de 1…5 (de la más fuerte a la más suave).
    static let fatigueLevels: [(Int, [String])] = [
        (5, ["exhausto", "exhausta", "no puedo mas", "muertisimo"]),
        (4, ["muy cansad", "agotad", "reventad", "fundid", "sin energia"]),
        (2, ["un poco cansad", "algo cansad", "medio cansad"]),
        (3, ["cansad"]),
    ]
    static let fatigueNegations = ["no estoy cansad", "no me siento cansad", "nada cansad"]

    // Cambiar de ejercicio.
    static let swapPhrases = [
        "cambia este ejercicio", "cambiame este ejercicio", "cambiar este ejercicio", "cambia el ejercicio",
        "cambiar el ejercicio", "otro ejercicio", "sustitu", "reemplaz", "no quiero hacer este",
    ]

    // Gimnasio.
    static let gymWords = ["gimnasio", "gym"]
    static let gymVerbs = ["estoy en", "cambia", "entreno en", "voy a", "gimnasio", "gym"]

    // Objetivo y fase.
    static let goals: [(TrainingGoal, [String])] = [
        (.strength, ["objetivo fuerza", "objetivo a fuerza", "ganar fuerza", "mas fuerza", "ser mas fuerte"]),
        (.hypertrophy, ["objetivo hipertrofia", "objetivo a hipertrofia", "ganar musculo", "masa muscular", "hipertrofia"]),
    ]
    static let phases: [(BodyCompositionPhase, [String])] = [
        (.deficit, ["fase de definicion", "definicion", "deficit", "bajar grasa", "perder grasa"]),
        (.surplus, ["superavit", "fase de volumen", "etapa de volumen"]),
        (.maintenance, ["mantenimiento"]),
    ]

    // "¿Por qué?" y su tema.
    static let whyTopics: [(ExplainableTopic, [String])] = [
        (.suggestedLoad, ["peso", "carga", "kilos", "kg", "libras"]),
        (.sessionOrder, ["orden", "primero", "antes que", "al final"]),
        (.timeFit, ["corta", "corto", "tiempo", "minutos", "quitaste", "quito", "menos ejercicios", "no agregas", "mas series"]),
        (.readiness, ["ligero", "ligera", "sueno", "dormi", "suave", "facil", "menos intens"]),
        (.gymChange, ["cambio", "cambiaste", "cambiado", "sustitu", "gimnasio", "no esta"]),
        (.pain, ["dolor", "recomendacion", "parar", "detener", "intensidad"]),
    ]
}

// MARK: - Análisis

extension LocalFallbackInterpreter {

    /// Lo que entiende de `text` y, si pide aclarar, sobre qué. Puro.
    public func analyze(text: String, context: AgentContext) -> LocalInterpretation {
        let phrase = LocalPhraseVocabulary.normalize(text)
        guard !phrase.isEmpty else { return .clarify(.general) }
        if isWhyQuestion(phrase, original: text) {
            return why(phrase, context: context)
        }
        let found = [
            time(phrase),
            equipment(phrase, context: context),
            pain(phrase),
            fatigue(phrase),
            swap(phrase, context: context),
            gym(phrase, context: context),
            goalOrPhase(phrase),
        ].compactMap { $0 }
        guard found.count <= 1 else { return .clarify(.oneThingAtATime) }
        return found.first ?? .clarify(.general)
    }

    // MARK: Tiempo

    private func time(_ phrase: String) -> LocalInterpretation? {
        var rest = " \(phrase) "
        var values: Set<Int> = []
        for (words, minutes) in LocalPhraseVocabulary.minutePhrases where rest.contains(" \(words) ") {
            values.insert(minutes)
            rest = rest.replacingOccurrences(of: " \(words) ", with: " ")
        }
        values.formUnion(numbers(in: rest, before: #"(min|minutos|minuto)"#))
        values.formUnion(numbers(in: rest, before: #"horas?\b"#).map { $0 * 60 })
        guard !values.isEmpty else {
            return LocalPhraseVocabulary.vagueTime.contains(where: phrase.contains) ? .clarify(.minutes) : nil
        }
        guard values.count == 1, let minutes = values.first else { return .clarify(.minutes) }
        let intent = AgentIntent.setTimeConstraint(.hard(minutes: minutes))
        return AgentIntentValidator.problem(in: intent) == nil ? .intent(intent) : .clarify(.minutes)
    }

    /// Las cantidades antes de `unit`: "30 min", "30 o 45 minutos" (las dos), "2 horas".
    private func numbers(in text: String, before unit: String) -> Set<Int> {
        let pattern = #"(\d+)\s*(o|y|a|-)?\s*(\d+)?\s*"# + unit
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var values: Set<Int> = []
        for match in regex.matches(in: text, range: range) {
            for group in [1, 3] {
                guard let groupRange = Range(match.range(at: group), in: text), let value = Int(text[groupRange]) else { continue }
                values.insert(value)
            }
        }
        return values
    }

    // MARK: Equipo

    private static let occupied = #"\b(esta|se encuentra)?\s*(ocupad[oa]|en uso|pillad[oa])"#
    private static let missing = #"\bno (tienen|hay|ten[cg]amos|cuentan)\b"#

    private func equipment(_ phrase: String, context: AgentContext) -> LocalInterpretation? {
        let isOccupied = phrase.range(of: Self.occupied, options: .regularExpression) != nil
        let isMissing = phrase.range(of: Self.missing, options: .regularExpression) != nil
        guard isOccupied || isMissing else { return nil }
        let reason: UnavailabilityReason = isOccupied ? .occupied : .doesNotExist
        if let type = equipmentType(in: phrase) {
            return .intent(.equipmentUnavailable(EquipmentReference(equipmentType: type), reason))
        }
        // "Está ocupada" sin nombrar la máquina: dentro del entrenamiento es la del ejercicio
        // actual. "Estoy ocupado" no habla de una máquina.
        guard isOccupied, !phrase.contains("estoy ocupad") else { return nil }
        guard context.todaySessionStarted, let current = context.currentExercise else { return .clarify(.equipment) }
        return .intent(.equipmentUnavailable(EquipmentReference(equipmentType: current.equipment), .occupied))
    }

    /// Mapeo determinista nombre → tipo (PR-1605). Devuelve el tipo; la instancia la
    /// resuelve quien llama.
    private func equipmentType(in phrase: String) -> EquipmentType? {
        let keywords: [(EquipmentType, [String])] = [
            (.barbell, ["barra", "barbell", "barra olimpica"]),
            (.dumbbell, ["mancuerna", "dumbbell", "mancuernas"]),
            (.smithMachine, ["smith", "smitch"]),
            (.cable, ["cable", "polea", "crossover"]),
            (.machine, ["maquina", "prensa", "hack squat", "hack", "ackly", "press machine", "leg press", "bench", "banco", "press de banca", "banca"]),
            (.kettlebell, ["kettlebell", "pesa rusa"]),
            (.bands, ["bandas", "goma", "resistencia"]),
            (.sled, ["trineo", "sled"]),
            (.plateLoaded, ["lastre", "discos"]),
        ]
        return keywords.first { _, words in words.contains(where: phrase.contains) }?.0
    }

    // MARK: Dolor

    private func pain(_ phrase: String) -> LocalInterpretation? {
        // "No me duele" no es un reporte; "no me duele mucho" sí (leve).
        let negated = LocalPhraseVocabulary.painNegations.contains(where: phrase.contains)
            && !LocalPhraseVocabulary.painLevels[0].1.contains(where: phrase.contains)
        guard LocalPhraseVocabulary.painWords.contains(where: phrase.contains), !negated else { return nil }
        let region = LocalPhraseVocabulary.bodyRegions.first { _, words in words.contains { containsWord($0, in: phrase) } }?.0
        guard let level = LocalPhraseVocabulary.painLevels.first(where: { _, words in words.contains { containsWord($0, in: phrase) } })?.0 else {
            return .clarify(.painLevel(region: region))
        }
        let side = region == nil ? nil : LocalPhraseVocabulary.bodySides.first { _, words in words.contains(where: phrase.contains) }?.0
        return .intent(.reportPain(PainReport(level: level, bodyRegion: region, side: side, notes: nil)))
    }

    // MARK: Fatiga

    private func fatigue(_ phrase: String) -> LocalInterpretation? {
        guard !LocalPhraseVocabulary.fatigueNegations.contains(where: phrase.contains),
              let severity = LocalPhraseVocabulary.fatigueLevels.first(where: { _, words in words.contains(where: phrase.contains) })?.0
        else { return nil }
        return .intent(.reportFatigue(UserFatigueFeedback(severity: severity)))
    }

    // MARK: Cambiar de ejercicio

    private func swap(_ phrase: String, context: AgentContext) -> LocalInterpretation? {
        guard LocalPhraseVocabulary.swapPhrases.contains(where: phrase.contains) else { return nil }
        guard context.todaySessionStarted, let current = context.currentExercise else { return .clarify(.exerciseSwapNeedsWorkout) }
        return .intent(.requestExerciseSwap(current.id))
    }

    // MARK: Gimnasio

    private func gym(_ phrase: String, context: AgentContext) -> LocalInterpretation? {
        let saysGym = LocalPhraseVocabulary.gymWords.contains { containsWord($0, in: phrase) }
        let matches = context.gyms.filter { gym in
            let name = LocalPhraseVocabulary.normalize(gym.name)
            return !name.isEmpty && containsWord(name, in: phrase)
        }
        let asksToSwitch = LocalPhraseVocabulary.gymVerbs.contains(where: phrase.contains)
        if matches.count == 1, asksToSwitch, let gym = matches.first {
            return .intent(.changeGym(gym.id))
        }
        // Sin un nombre que coincida, nunca se inventa un gimnasio.
        guard saysGym || matches.count > 1 else { return nil }
        return .clarify(.whichGym(context.gyms))
    }

    // MARK: Objetivo y fase

    private func goalOrPhase(_ phrase: String) -> LocalInterpretation? {
        let goal = LocalPhraseVocabulary.goals.first { _, words in words.contains(where: phrase.contains) }?.0
        let phase = LocalPhraseVocabulary.phases.first { _, words in words.contains(where: phrase.contains) }?.0
        switch (goal, phase) {
        case (let goal?, nil): return .intent(.changeGoal(goal))
        case (nil, let phase?): return .intent(.changePhase(phase))
        case (.some, .some): return .clarify(.oneThingAtATime)
        case (nil, nil): return nil
        }
    }

    // MARK: ¿Por qué?

    /// "¿Por qué…?", "explícame…". "Porque…" sólo si es pregunta: "porque estoy cansado" no.
    private func isWhyQuestion(_ phrase: String, original: String) -> Bool {
        phrase.hasPrefix("por que") || phrase.contains(" por que ") || phrase.hasPrefix("explicame")
            || (phrase.hasPrefix("porque") && original.contains("?"))
    }

    private func why(_ phrase: String, context: AgentContext) -> LocalInterpretation {
        let topics = Set(LocalPhraseVocabulary.whyTopics.filter { _, words in words.contains { containsWordPrefix($0, in: phrase) } }.map(\.0))
        let decisions = context.explainableDecisions
        let candidates = topics.isEmpty ? decisions : decisions.filter { topics.contains($0.topic) }
        switch candidates.count {
        case 0:
            return .clarify(.nothingToExplain(topics.count == 1 ? topics.first : nil))
        case 1:
            return .intent(.askWhy(candidates[0].id))
        default:
            return .clarify(.whichDecision(candidates))
        }
    }

    // MARK: Utilidades

    /// ¿`word` aparece como palabra (o frase) completa? "pie" no está en "pierna".
    private func containsWord(_ word: String, in phrase: String) -> Bool {
        " \(phrase) ".contains(" \(word) ")
    }

    /// ¿Alguna palabra empieza con `prefix`? "sustitu" está en "sustituiste".
    private func containsWordPrefix(_ prefix: String, in phrase: String) -> Bool {
        " \(phrase)".contains(" \(prefix)")
    }
}
