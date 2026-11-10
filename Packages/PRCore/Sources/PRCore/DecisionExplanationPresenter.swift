//
//  DecisionExplanationPresenter.swift
//  PRCore
//
//  SCRUM-270 (PR-I001, RF-025): "¿Por qué?" en palabras, sólo con los hechos del registro de
//  la decisión (`ExplainableDecision`). No decide nada ni agrega números: cada número sale de
//  un hecho, un hecho que no conoce se omite y, sin hechos, lo dice. Nunca usa el LLM.
//  Textos en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

/// Lo que muestra "¿Por qué?": un título y de 1 a 4 razones.
public struct DecisionExplanation: Equatable, Sendable {
    public let title: String
    public let reasons: [String]

    public init(title: String, reasons: [String]) {
        self.title = title
        self.reasons = reasons
    }
}

public struct DecisionExplanationPresenter: Sendable {
    /// Máximo de razones que se muestran.
    public static let maximumReasons = 4

    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func explanation(for decision: ExplainableDecision) -> DecisionExplanation {
        let reasons: [String]
        let title: String
        switch decision.topic {
        case .sessionOrder:
            title = resource("Por qué este orden", "¿Por qué?: título del orden de la sesión")
            reasons = orderReasons(decision)
        case .timeFit:
            title = timeTitle(decision)
            reasons = timeReasons(decision)
        case .readiness:
            title = resource("Por qué hoy es más ligero", "¿Por qué?: título del día aligerado por el sueño")
            reasons = readinessReasons(decision)
        case .gymChange:
            title = resource("Por qué cambió este ejercicio", "¿Por qué?: título del cambio por el gimnasio")
            reasons = gymReasons(decision)
        case .suggestedLoad:
            title = resource("Por qué este peso", "¿Por qué?: título del peso precargado")
            reasons = loadReasons(decision)
        case .pain:
            title = resource("Por qué esta recomendación", "¿Por qué?: título de la recomendación por dolor")
            reasons = painReasons(decision)
        }
        let kept = Array(reasons.prefix(Self.maximumReasons))
        return DecisionExplanation(
            title: title,
            reasons: kept.isEmpty
                ? [resource("No hay datos para explicar esta decisión.", "¿Por qué?: el registro no trae hechos que se puedan explicar")]
                : kept
        )
    }

    // MARK: - Orden

    private func orderReasons(_ decision: ExplainableDecision) -> [String] {
        var reasons: [String] = []
        if decision.value(ExplainableFactKey.orderCustom) == "true" {
            reasons.append(resource(
                "Este orden lo elegiste tú; el motor recomienda el de abajo.",
                "¿Por qué?: el orden de la sesión lo eligió la persona"
            ))
        }
        let byRank = Dictionary(grouping: decision.values(ExplainableFactKey.orderReason).compactMap(Self.pair), by: \.0)
        for entry in decision.values(ExplainableFactKey.orderEntry).compactMap(Self.pair) {
            guard let reason = byRank[entry.0]?.first.flatMap({ orderReasonText($0.1) }) else { continue }
            let name = entry.1.isEmpty ? exerciseFallback : entry.1
            reasons.append(resource("\(entry.0). \(name): \(reason)", "¿Por qué?: posición del ejercicio y su motivo"))
        }
        if decision.value(ExplainableFactKey.orderReorderedByFatigue) == "true" {
            // La fatiga va al final: es lo último en la precedencia.
            reasons = Array(reasons.prefix(Self.maximumReasons - 1))
            reasons.append(resource(
                "La fatiga acumulada cambió el orden para proteger los músculos prioritarios.",
                "¿Por qué?: la fatiga reordenó la sesión"
            ))
        }
        return reasons
    }

    private func orderReasonText(_ reason: String) -> String? {
        switch reason {
        case "functionalRole":
            return resource("es compuesto y va con los músculos frescos.", "¿Por qué?: motivo del orden, rol funcional")
        case "musclePriority":
            return resource("trabaja un músculo que priorizas.", "¿Por qué?: motivo del orden, prioridad muscular")
        case "technicalDemand":
            return resource("es técnicamente exigente y conviene sin fatiga.", "¿Por qué?: motivo del orden, demanda técnica")
        default:
            return nil
        }
    }

    // MARK: - Tiempo

    private func timeTitle(_ decision: ExplainableDecision) -> String {
        switch decision.value(ExplainableFactKey.timeFit) {
        case "fits":
            return resource("Por qué no agregamos series", "¿Por qué?: título cuando la sesión ya cabía en el tiempo")
        case "doesNotFit":
            return resource("Por qué tu sesión no cabe", "¿Por qué?: título cuando la sesión no cabe ni recortada")
        default:
            return resource("Por qué tu sesión es más corta", "¿Por qué?: título de la sesión recortada por tiempo")
        }
    }

    private func timeReasons(_ decision: ExplainableDecision) -> [String] {
        guard let budget = decision.value(ExplainableFactKey.timeBudgetMinutes) else { return [] }
        var reasons: [String] = []
        let original = decision.value(ExplainableFactKey.timeOriginalMinutes)
        switch decision.value(ExplainableFactKey.timeFit) {
        case "fits":
            if let original {
                reasons.append(resource("Tu sesión dura unos \(original) min y cabe en los \(budget) que tienes.", "¿Por qué?: la sesión ya cabía"))
            }
            if decision.value(ExplainableFactKey.timeNoExtraVolume) == "true" {
                reasons.append(resource("Más tiempo no suma series: el volumen lo marca tu plan.", "¿Por qué?: el tiempo nunca agrega series (RN-002)"))
            }
            let extras = decision.values(ExplainableFactKey.timeSuggestion).compactMap(activityName)
            if !extras.isEmpty {
                reasons.append(resource("Con lo que sobra puedes sumar \(list(extras)).", "¿Por qué?: qué hacer con el tiempo que sobra"))
            }
        case "doesNotFit":
            if let needed = decision.value(ExplainableFactKey.timeNeededMinutes) {
                reasons.append(resource("Aun recortada necesita unos \(needed) min y tienes \(budget).", "¿Por qué?: la sesión no cabe ni recortada"))
            }
            reasons.append(contentsOf: trimmedReasons(decision))
        case "trimmed":
            if let original {
                reasons.append(resource("Elegiste \(budget) min y la sesión duraba unos \(original).", "¿Por qué?: minutos elegidos contra la duración original"))
            }
            reasons.append(contentsOf: trimmedReasons(decision))
        default:
            break
        }
        return reasons
    }

    private func trimmedReasons(_ decision: ExplainableDecision) -> [String] {
        var reasons: [String] = []
        let removed = names(decision.values(ExplainableFactKey.timeRemoved))
        if !removed.isEmpty {
            reasons.append(resource("Quitamos \(list(removed)).", "¿Por qué?: ejercicios quitados por tiempo"))
        }
        let reduced = names(decision.values(ExplainableFactKey.timeReduced))
        if !reduced.isEmpty {
            reasons.append(resource("Dejamos menos series de \(list(reduced)).", "¿Por qué?: ejercicios con menos series por tiempo"))
        }
        let pairs = zip(
            names(decision.values(ExplainableFactKey.timeJoinedFirst)),
            names(decision.values(ExplainableFactKey.timeJoinedSecond))
        ).map { resource("\($0) con \($1)", "Superset: un ejercicio con su pareja") }
        if !pairs.isEmpty {
            reasons.append(resource("Haces \(list(pairs)) en superset para ahorrar tiempo.", "¿Por qué?: pares juntados en superset por tiempo"))
        }
        reasons.append(resource("Los ejercicios principales se quedan.", "¿Por qué?: el recorte por tiempo conserva los principales"))
        return reasons
    }

    private func activityName(_ raw: String) -> String? {
        switch ExtraTimeActivity(rawValue: raw) {
        case .mobility: return resource("movilidad", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra")
        case .cardio: return resource("cardio", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra")
        case .posing: return resource("práctica de poses", "Ajuste de tiempo: actividad sugerida con el tiempo que sobra (culturismo)")
        case nil: return nil
        }
    }

    // MARK: - Sueño

    private func readinessReasons(_ decision: ExplainableDecision) -> [String] {
        var reasons: [String] = []
        switch decision.value(ExplainableFactKey.readinessReason).flatMap(ReadinessReason.init(rawValue:)) {
        case .shortSleep?:
            reasons.append(resource("Dormiste poco.", "¿Por qué?: motivo del día aligerado, sueño corto"))
        case .poorSleep?:
            reasons.append(resource("Dormiste mal.", "¿Por qué?: motivo del día aligerado, sueño malo"))
        case .shortAndPoorSleep?:
            reasons.append(resource("Dormiste poco y mal.", "¿Por qué?: motivo del día aligerado, sueño corto y malo"))
        case nil:
            break
        }
        if let rir = decision.value(ExplainableFactKey.readinessRIRIncrease).flatMap(Int.init), rir > 0 {
            reasons.append(resource("Cada serie termina \(rir) repeticiones más lejos del fallo.", "¿Por qué?: el día aligerado sube el RIR"))
        }
        if let sets = decision.value(ExplainableFactKey.readinessIsolationSetReduction).flatMap(Int.init), sets > 0 {
            reasons.append(resource("Los ejercicios aislados tienen \(sets) series menos.", "¿Por qué?: el día aligerado quita series de aislados"))
        }
        if decision.value(ExplainableFactKey.readinessLoadUnchanged) == "true" {
            reasons.append(resource("El peso y las repeticiones no cambian.", "¿Por qué?: el día aligerado no toca carga ni repeticiones"))
        }
        return reasons
    }

    // MARK: - Gimnasio

    private func gymReasons(_ decision: ExplainableDecision) -> [String] {
        let original = decision.value(ExplainableFactKey.gymOriginal).map(nameOrFallback) ?? exerciseFallback
        switch decision.value(ExplainableFactKey.gymChange) {
        case "replaced":
            let replacement = decision.value(ExplainableFactKey.gymReplacement).map(nameOrFallback) ?? exerciseFallback
            return [
                resource("Marcaste que en este gimnasio no hay \(original).", "¿Por qué?: el gimnasio no tiene el ejercicio"),
                resource("Lo cambiamos por \(replacement), que hace el mismo movimiento.", "¿Por qué?: sustituto equivalente por el gimnasio"),
            ]
        case "omitted":
            return [
                resource("Marcaste que en este gimnasio no hay \(original).", "¿Por qué?: el gimnasio no tiene el ejercicio"),
                resource("No hay un sustituto equivalente y seguro, así que no se programa.", "¿Por qué?: sin sustituto equivalente por el gimnasio"),
            ]
        default:
            return []
        }
    }

    // MARK: - Peso

    private func loadReasons(_ decision: ExplainableDecision) -> [String] {
        var reasons: [String] = []
        let exercise = decision.value(ExplainableFactKey.loadExercise).map(nameOrFallback) ?? exerciseFallback
        let perMachine = decision.value(ExplainableFactKey.loadPerMachine) == "true"
        let weight = decision.value(ExplainableFactKey.loadWeight).map { weight in
            "\(weight) \(unitSymbol(decision.value(ExplainableFactKey.loadUnit)))"
        }
        if decision.value(ExplainableFactKey.loadWarmup) == "true" {
            reasons.append(resource("Es una serie de calentamiento: va más ligera que las de trabajo.", "¿Por qué?: el peso es de calentamiento"))
        }
        switch decision.value(ExplainableFactKey.loadSource).flatMap(SuggestedLoadSource.init(rawValue:)) {
        case .lastTime?:
            if let weight {
                reasons.append(perMachine
                    ? resource("\(weight) es lo que levantaste la última vez en \(exercise) en esta máquina.", "¿Por qué?: peso de la última vez en esta máquina")
                    : resource("\(weight) es lo que levantaste la última vez en \(exercise).", "¿Por qué?: peso de la última vez"))
            }
        case .prescription?:
            if let weight {
                reasons.append(resource("\(weight) es el peso que marca tu plan para \(exercise).", "¿Por qué?: peso de la prescripción"))
            }
        case .none?:
            reasons.append(perMachine
                ? resource("No hay un peso anterior en esta máquina: escribe el que vayas a usar.", "¿Por qué?: sin peso anterior en esta máquina")
                : resource("No hay un peso anterior: escribe el que vayas a usar.", "¿Por qué?: sin peso anterior"))
        case nil:
            break
        }
        if decision.value(ExplainableFactKey.loadProgressionApplied) == "false", !reasons.isEmpty {
            reasons.append(resource("La app no sube el peso por su cuenta: tú lo cambias si hoy puedes más.", "¿Por qué?: el peso precargado no aplica progresión"))
        }
        return reasons
    }

    private func unitSymbol(_ raw: String?) -> String {
        switch raw.flatMap(LoadUnit.init(rawValue:)) {
        case .pounds?: return resource("lb", "Unidad de peso: libras")
        case .kilograms?, nil: return resource("kg", "Unidad de peso: kilogramos")
        }
    }

    // MARK: - Dolor

    private func painReasons(_ decision: ExplainableDecision) -> [String] {
        let painPresenter = PainRecommendationPresenter(locale: locale)
        var reasons: [String] = []
        if let level = decision.value(ExplainableFactKey.painLevel).flatMap(Int.init).flatMap(PainLevel.init(rawValue:)) {
            let name = painPresenter.levelName(level)
            reasons.append(resource("Reportaste dolor \(name.lowercased(with: locale)).", "¿Por qué?: nivel de dolor reportado"))
        }
        switch decision.value(ExplainableFactKey.painRecommendation) {
        case "continueNormal":
            reasons.append(resource("Con ese nivel puedes seguir con normalidad.", "¿Por qué?: el dolor leve no cambia la sesión"))
        case "reduceIntensityAndMonitor":
            if let message = painPresenter.message(for: .reduceIntensityAndMonitor) { reasons.append(message) }
        case "stopAndRest":
            if let message = painPresenter.message(for: .stopAndRest) { reasons.append(message) }
        default:
            break
        }
        if decision.value(ExplainableFactKey.painSuspendsLoadProgression) == "true" {
            reasons.append(resource("No se sube la carga de este ejercicio mientras haya dolor moderado o alto.", "¿Por qué?: el dolor suspende la progresión de carga"))
        }
        return reasons
    }

    // MARK: - Privado

    private var exerciseFallback: String {
        resource("un ejercicio", "Ajuste de tiempo: ejercicio sin nombre en el catálogo")
    }

    private func nameOrFallback(_ name: String) -> String {
        name.isEmpty ? exerciseFallback : name
    }

    private func names(_ values: [String]) -> [String] {
        values.map(nameOrFallback)
    }

    private func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and).locale(locale))
    }

    /// "rank|texto" → (rank, texto).
    private static func pair(_ value: String) -> (String, String)? {
        let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, Int(parts[0]) != nil else { return nil }
        return (parts[0], parts[1])
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
