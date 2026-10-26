//
//  RestrictionListPresenter.swift
//  PRCore
//
//  SCRUM-216: lo que muestra Perfil › Restricciones (solo lectura). Traduce las
//  restricciones del mismo perfil que usa el plan a palabras simples: zona, lado, quién la
//  declaró, si tu plan la sigue cuidando y la nota. No decide nada: el estado sale de
//  `TrainingRestriction.refreshed(asOf:)` (una fecha de revisión vencida no es curación,
//  RN-004). Nunca diagnostica. Textos en `Localizable.xcstrings`.
//

import Foundation
import PRDomain

/// Una restricción tal como se ve en Perfil.
public struct RestrictionListItem: Identifiable, Equatable, Sendable {
    public let id: RestrictionID
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
    /// Todo lo anterior en una frase para VoiceOver.
    public let accessibilityLabel: String
}

/// Estado de la pantalla. No hay "cargando" ni "error": el perfil ya está en memoria.
public enum RestrictionListState: Equatable, Sendable {
    /// Sin restricciones declaradas. `note` es la nota del paso "Restricciones" (SCRUM-209).
    case empty(note: String?)
    /// Primero las que tu plan cuida (las que toca revisar arriba), al final las resueltas.
    case loaded([RestrictionListItem], note: String?)
}

public struct RestrictionListPresenter: Sendable {
    private let locale: Locale
    private let vocabulary: TrainingVocabularyPresenter

    public init(locale: Locale = .current) {
        self.locale = locale
        self.vocabulary = TrainingVocabularyPresenter(locale: locale)
    }

    /// `nil` sin perfil contestado (no hay restricciones que mostrar).
    public func state(for profile: OnboardingProfile?, now: Date) -> RestrictionListState {
        let note = Self.nonEmpty(profile?.restrictionNote)
        let restrictions = (profile?.restrictions ?? []).map { $0.refreshed(asOf: now) }
        guard !restrictions.isEmpty else { return .empty(note: note) }
        let ordered = restrictions.enumerated().sorted { lhs, rhs in
            let left = (Self.rank(lhs.element.status), Self.regionOrder(lhs.element.bodyRegion), lhs.offset)
            let right = (Self.rank(rhs.element.status), Self.regionOrder(rhs.element.bodyRegion), rhs.offset)
            return left < right
        }
        return .loaded(ordered.map { item(for: $0.element) }, note: note)
    }

    private func item(for restriction: TrainingRestriction) -> RestrictionListItem {
        let region = vocabulary.bodyRegionName(restriction.bodyRegion)
        let side = restriction.side.map(sideName)
        let source = sourceName(restriction.source)
        let status = statusSentence(restriction.status)
        let note = Self.nonEmpty(restriction.notes)
        let spoken = [region, side, source, status, note.map(noteLabel)].compactMap { $0 }.map(Self.endingSentence)
        return RestrictionListItem(
            id: restriction.id,
            region: region,
            side: side,
            source: source,
            sourceKind: restriction.source,
            status: status,
            statusKind: restriction.status,
            note: note,
            accessibilityLabel: spoken.joined(separator: " ")
        )
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
