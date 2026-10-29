//
//  RestrictionListPresenter.swift
//  PRCore
//
//  SCRUM-216 / SCRUM-36: lo que muestra Perfil › Restricciones. Traduce las restricciones
//  del mismo perfil que usa el plan a palabras simples: zona, lado, quién la declaró, si tu
//  plan la sigue cuidando, la nota y los ejercicios concretos. Las resueltas van aparte, en
//  el historial. No decide nada: el estado sale de `TrainingRestriction.refreshed(asOf:)`
//  (una fecha de revisión vencida no es curación, RN-004) y los cambios los valida
//  `RestrictionEditor`. Nunca diagnostica ni promete recuperación. Textos en
//  `Localizable.xcstrings`.
//

import Foundation
import PRDomain

/// Un ejercicio concreto de una restricción (evitado o permitido).
public struct RestrictionExerciseLine: Identifiable, Equatable, Sendable {
    public let id: ExerciseID
    public let name: String
}

/// Una restricción tal como se ve en Perfil.
public struct RestrictionListItem: Identifiable, Equatable, Sendable {
    public let id: RestrictionID
    public let bodyRegion: BodyRegion
    /// Zona del cuerpo ("Codo").
    public let region: String
    /// Lado, si se declaró ("Lado derecho").
    public let side: String?
    /// Quién la declaró ("La declaraste tú").
    public let source: String
    public let sourceKind: RestrictionSource
    /// Qué hace el plan con ella ("Tu plan la cuida.").
    public let status: String
    public let statusKind: RestrictionStatus
    /// Nota de esta restricción, tal cual se escribió.
    public let note: String?
    /// "Revisión: 12 nov 2026", si tiene fecha de revisión y sigue en vigor.
    public let review: String?
    /// "Resuelta el 29 oct 2026", en el historial.
    public let resolved: String?
    /// Ejercicios que se evitan además de la zona.
    public let avoided: [RestrictionExerciseLine]
    /// Ejercicios permitidos pese a la zona (sólo con indicación profesional).
    public let allowed: [RestrictionExerciseLine]
    /// Lo que se puede editar, tal cual está guardado (para el formulario).
    public let details: RestrictionDetails
    /// ¿Se puede editar? Las resueltas son historial.
    public let isEditable: Bool
    /// ¿Se ofrece "permitir un ejercicio"? Sólo en vigor y con origen profesional.
    public let canAllowExercises: Bool
    /// Todo lo anterior en una frase para VoiceOver.
    public let accessibilityLabel: String
}

/// Una zona que se puede agregar desde la pantalla.
public struct RestrictionZoneOption: Identifiable, Equatable, Sendable {
    public var id: BodyRegion { region }
    public let region: BodyRegion
    public let name: String
    /// Restricción en vigor de esa zona: se abre esa en vez de duplicarla.
    public let existing: RestrictionID?
}

/// Estado de la pantalla. No hay "cargando" ni "error": el perfil ya está en memoria.
public enum RestrictionListState: Equatable, Sendable {
    /// Sin restricciones (ni en vigor ni resueltas). `note` es la nota del paso
    /// "Restricciones" (SCRUM-209).
    case empty(note: String?)
    /// `current`: las que tu plan cuida, las que toca revisar arriba. `history`: las resueltas,
    /// la más reciente primero. Cualquiera de las dos puede venir vacía.
    case loaded(current: [RestrictionListItem], history: [RestrictionListItem], note: String?)
}

/// Textos de las confirmaciones y avisos de la pantalla.
public struct RestrictionCopy: Equatable, Sendable {
    public let title: String
    public let message: String
    public let confirm: String
}

public struct RestrictionListPresenter: Sendable {
    private let locale: Locale
    private let timeZone: TimeZone
    private let vocabulary: TrainingVocabularyPresenter

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
        self.vocabulary = TrainingVocabularyPresenter(locale: locale)
    }

    /// Sin perfil contestado, vacía. `exerciseNames` nombra los ejercicios concretos (los que
    /// no estén se omiten: nunca se inventa un nombre).
    public func state(
        for profile: OnboardingProfile?,
        now: Date,
        exerciseNames: [ExerciseID: String] = [:]
    ) -> RestrictionListState {
        let note = Self.nonEmpty(profile?.restrictionNote)
        let restrictions = (profile?.restrictions ?? []).map { $0.refreshed(asOf: now) }
        guard !restrictions.isEmpty else { return .empty(note: note) }
        let current = restrictions.enumerated().filter { $0.element.isInForce }.sorted { lhs, rhs in
            let left = (Self.rank(lhs.element.status), Self.regionOrder(lhs.element.bodyRegion), lhs.offset)
            let right = (Self.rank(rhs.element.status), Self.regionOrder(rhs.element.bodyRegion), rhs.offset)
            return left < right
        }
        let history = restrictions.enumerated().filter { !$0.element.isInForce }.sorted { lhs, rhs in
            let left = lhs.element.resolvedDate ?? .distantPast
            let right = rhs.element.resolvedDate ?? .distantPast
            return left != right ? left > right : lhs.offset > rhs.offset
        }
        return .loaded(
            current: current.map { item(for: $0.element, names: exerciseNames) },
            history: history.map { item(for: $0.element, names: exerciseNames) },
            note: note
        )
    }

    /// Las 8 zonas del formulario, de la cabeza a los pies, con la restricción en vigor de
    /// cada una (si la hay) para abrirla en vez de duplicarla.
    public func zoneOptions(for profile: OnboardingProfile?) -> [RestrictionZoneOption] {
        let inForce = (profile?.restrictions ?? []).filter(\.isInForce)
        return BodyRegionRestrictionRule.selectableRegions.map { region in
            RestrictionZoneOption(
                region: region,
                name: vocabulary.bodyRegionName(region),
                existing: inForce.first { $0.bodyRegion == region }?.id
            )
        }
    }

    // MARK: - Confirmaciones

    /// Antes de guardar una restricción de origen profesional (RN-020).
    public func professionalConfirmation() -> RestrictionCopy {
        RestrictionCopy(
            title: resource("¿Te lo indicó un profesional?", "Restricciones: confirmar origen profesional, título"),
            message: resource(
                "Tu plan seguirá esta indicación tal cual la guardes. Revísala antes de confirmar.",
                "Restricciones: confirmar origen profesional, mensaje"
            ),
            confirm: resource("Sí, me lo indicó", "Restricciones: confirmar origen profesional, botón")
        )
    }

    /// Antes de permitir un ejercicio pese a la zona (sólo origen profesional).
    public func allowConfirmation(exercise: String) -> RestrictionCopy {
        RestrictionCopy(
            title: resource("¿Tu profesional lo permite?", "Restricciones: confirmar permitir un ejercicio, título"),
            message: resource(
                "Tu plan podrá incluir \(exercise) aunque cuide esta zona. Hazlo sólo si te lo indicaron.",
                "Restricciones: confirmar permitir un ejercicio, mensaje con el nombre del ejercicio"
            ),
            confirm: resource("Sí, lo permite", "Restricciones: confirmar permitir un ejercicio, botón")
        )
    }

    /// "Ya no me molesta" (siempre con confirmación; con origen profesional, el alta).
    public func resolveConfirmation(for item: RestrictionListItem) -> RestrictionCopy {
        switch item.sourceKind {
        case .userReported:
            return RestrictionCopy(
                title: resource("¿Ya no te molesta?", "Restricciones: confirmar resolver, título"),
                message: resource(
                    "Tu plan volverá a incluir lo que carga esta zona: \(item.region). Quedará en tu historial.",
                    "Restricciones: confirmar resolver, mensaje con la zona"
                ),
                confirm: resource("Ya no me molesta", "Restricciones: confirmar resolver, botón")
            )
        case .professionalGuidance:
            return RestrictionCopy(
                title: resource("¿Tu profesional te dio de alta?", "Restricciones: confirmar resolver una indicación profesional, título"),
                message: resource(
                    "Tu plan volverá a incluir lo que carga esta zona: \(item.region). Hazlo sólo si te lo indicaron. Quedará en tu historial.",
                    "Restricciones: confirmar resolver una indicación profesional, mensaje con la zona"
                ),
                confirm: resource("Sí, me dio de alta", "Restricciones: confirmar resolver una indicación profesional, botón")
            )
        }
    }

    /// Aviso de un cambio que no se aplicó o no se guardó. `nil` si salió bien.
    public func message(for outcome: RestrictionUpdateOutcome) -> String? {
        switch outcome {
        case .saved:
            return nil
        case .notSaved:
            return resource(
                "Tu plan de hoy ya lo respeta, pero no se pudo guardar. Inténtalo de nuevo para que no se pierda al cerrar la app.",
                "Restricciones: el cambio aplica pero el guardado falló"
            )
        case .planFailed:
            return resource(
                "No pudimos armar tu plan con este cambio. No se cambió nada.",
                "Restricciones: no se pudo generar el plan, nada cambió"
            )
        case .rejected(.noteTooLong(let maximum)):
            return resource("La nota puede tener hasta \(maximum) caracteres.", "Restricciones: nota demasiado larga, con el máximo")
        case .rejected(.alreadyInForce), .rejected(.notFound), .rejected(.alreadyResolved),
             .rejected(.needsExplicitConfirmation), .rejected(.allowRequiresProfessional):
            return resource("No se pudo hacer ese cambio. No se cambió nada.", "Restricciones: cambio rechazado, nada cambió")
        }
    }

    // MARK: - Filas

    private func item(for restriction: TrainingRestriction, names: [ExerciseID: String]) -> RestrictionListItem {
        let region = vocabulary.bodyRegionName(restriction.bodyRegion)
        let side = restriction.side.map(sideName)
        let source = sourceName(restriction.source)
        let status = statusSentence(restriction.status)
        let note = Self.nonEmpty(restriction.notes)
        let review = restriction.isInForce ? restriction.reviewDate.map { reviewLabel(date($0)) } : nil
        let resolved = restriction.isInForce ? nil : restriction.resolvedDate.map { resolvedLabel(date($0)) }
        let avoided = lines(restriction.forbiddenExerciseIDs, names: names)
        let allowed = lines(restriction.allowedExerciseIDs, names: names)
        let spoken = [
            region, side, source, status, review, resolved, note.map(noteLabel),
            avoided.isEmpty ? nil : avoidedLabel(avoided.map(\.name).formatted(.list(type: .and).locale(locale))),
            allowed.isEmpty ? nil : allowedLabel(allowed.map(\.name).formatted(.list(type: .and).locale(locale))),
        ].compactMap { $0 }.map(Self.endingSentence)
        return RestrictionListItem(
            id: restriction.id,
            bodyRegion: restriction.bodyRegion,
            region: region,
            side: side,
            source: source,
            sourceKind: restriction.source,
            status: status,
            statusKind: restriction.status,
            note: note,
            review: review,
            resolved: resolved,
            avoided: avoided,
            allowed: allowed,
            details: RestrictionDetails(
                side: restriction.side, source: restriction.source,
                reviewDate: restriction.reviewDate, notes: restriction.notes
            ),
            isEditable: restriction.isInForce,
            canAllowExercises: restriction.isInForce && restriction.source == .professionalGuidance,
            accessibilityLabel: spoken.joined(separator: " ")
        )
    }

    /// En orden alfabético del nombre; los que el catálogo no conoce se omiten.
    private func lines(_ ids: Set<ExerciseID>, names: [ExerciseID: String]) -> [RestrictionExerciseLine] {
        ids.compactMap { id in names[id].map { RestrictionExerciseLine(id: id, name: $0) } }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
    }

    private func date(_ value: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        style.timeZone = timeZone
        return value.formatted(style)
    }

    /// Cada parte se lee como frase: punto final sólo si no trae ya uno (ni "?" o "!").
    private static func endingSentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }

    private func sideName(_ side: BodySide) -> String {
        switch side {
        case .left: return resource("Lado izquierdo", "Restricciones: lado del cuerpo")
        case .right: return resource("Lado derecho", "Restricciones: lado del cuerpo")
        case .bilateral: return resource("Ambos lados", "Restricciones: lado del cuerpo")
        }
    }

    private func sourceName(_ source: RestrictionSource) -> String {
        switch source {
        case .userReported: return resource("La declaraste tú", "Restricciones: origen, la persona la declaró")
        case .professionalGuidance: return resource("Indicación de un profesional", "Restricciones: origen, la indicó un profesional de la salud")
        }
    }

    private func statusSentence(_ status: RestrictionStatus) -> String {
        switch status {
        case .active:
            return resource("Tu plan la cuida.", "Restricciones: activa, el plan evita lo que la carga")
        case .reviewNeeded:
            return resource(
                "Llegó su fecha de revisión; tu plan la sigue cuidando.",
                "Restricciones: venció la fecha de revisión; sigue aplicando hasta que se confirme que se resolvió"
            )
        case .resolved:
            return resource("Resuelta: ya no limita tu plan.", "Restricciones: resuelta, ya no aplica")
        }
    }

    private func noteLabel(_ note: String) -> String {
        resource("Nota: \(note)", "Restricciones: VoiceOver lee la nota de la persona")
    }

    private func reviewLabel(_ date: String) -> String {
        resource("Revisión: \(date)", "Restricciones: fecha de revisión")
    }

    private func resolvedLabel(_ date: String) -> String {
        resource("Resuelta el \(date)", "Restricciones: fecha en que la persona la resolvió")
    }

    private func avoidedLabel(_ names: String) -> String {
        resource("También evita: \(names)", "Restricciones: VoiceOver lee los ejercicios que se evitan")
    }

    private func allowedLabel(_ names: String) -> String {
        resource("Permitidos: \(names)", "Restricciones: VoiceOver lee los ejercicios permitidos por un profesional")
    }

    /// Las que toca revisar arriba, luego las activas y al final las resueltas.
    private static func rank(_ status: RestrictionStatus) -> Int {
        switch status {
        case .reviewNeeded: return 0
        case .active: return 1
        case .resolved: return 2
        }
    }

    /// De la cabeza a los pies, en el orden de `BodyRegion`.
    private static func regionOrder(_ region: BodyRegion) -> Int {
        BodyRegion.allCases.firstIndex(of: region) ?? BodyRegion.allCases.count
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
