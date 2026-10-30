//
//  RestrictionScreenModel.swift
//  PRCore
//
//  SCRUM-36: lo que necesita Perfil › Restricciones para editar. La View sólo muestra el
//  estado y envía intenciones; aquí se decide cuándo pedir confirmación (origen profesional,
//  permitir un ejercicio, resolver), cuándo abrir la restricción en vigor de una zona en vez
//  de duplicarla y qué aviso mostrar. Los cambios los valida `RestrictionEditor` (que vuelve
//  a exigir la confirmación) y los aplica `AppSessionCoordinator.updateRestrictions`, que
//  regenera el mismo bloque y guarda.
//

import Foundation
import Observation
import PRDomain

@MainActor
@Observable
public final class RestrictionScreenModel {
    /// Qué hacer después de una intención.
    public enum Result: Equatable, Sendable {
        case done
        /// Hay que confirmar: la pantalla lo pregunta y repite la intención con `confirmed: true`.
        case needsConfirmation(RestrictionCopy)
        /// La zona ya tiene una restricción en vigor: se abre esa en vez de duplicarla.
        case openExisting(RestrictionID)
        /// No se aplicó o no se guardó: se muestra el aviso.
        case failed(String)
    }

    /// ¿Hay un cambio guardándose? La pantalla no deja enviar otro mientras tanto.
    public private(set) var isSaving = false

    private let session: AppSessionCoordinator
    private let profile: () -> OnboardingProfile?
    private let clock: () -> Date
    private let presenter: RestrictionListPresenter
    private let editor = RestrictionEditor()
    private let searchEngine: ExerciseSearchEngine
    private let names: [ExerciseID: String]

    /// Máximo de resultados al buscar un ejercicio.
    public static let searchLimit = 25

    public init(
        session: AppSessionCoordinator,
        profile: @escaping () -> OnboardingProfile?,
        catalog: [Exercise],
        presenter: RestrictionListPresenter = RestrictionListPresenter(),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.session = session
        self.profile = profile
        self.clock = clock
        self.presenter = presenter
        self.searchEngine = ExerciseSearchEngine(exercises: catalog)
        self.names = Dictionary(catalog.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Estado

    public var state: RestrictionListState {
        presenter.state(for: profile(), now: clock(), exerciseNames: names)
    }

    /// Las zonas que se pueden agregar, con la que ya está en vigor para abrirla.
    public var zones: [RestrictionZoneOption] {
        presenter.zoneOptions(for: profile())
    }

    /// Una restricción (en vigor o del historial) para su pantalla de detalle.
    public func item(_ id: RestrictionID) -> RestrictionListItem? {
        switch state {
        case .empty: return nil
        case .loaded(let current, let history, _): return (current + history).first { $0.id == id }
        }
    }

    /// Ejercicios del catálogo cuyo nombre coincide (en español o en inglés). Sin texto, nada.
    public func exercises(matching text: String) -> [RestrictionExerciseLine] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return searchEngine.search(matching: ExerciseSearchQuery(text: trimmed))
            .prefix(Self.searchLimit)
            .map { RestrictionExerciseLine(id: $0.exercise.id, name: $0.exercise.canonicalName) }
    }

    // MARK: - Intenciones

    /// Agrega una zona. Con origen profesional, antes se confirma (RN-020).
    public func add(_ region: BodyRegion, details: RestrictionDetails, confirmed: Bool = false) async -> Result {
        let now = clock()
        let confirmation = details.source == .professionalGuidance ? presenter.professionalConfirmation() : nil
        return await apply(confirmation: confirmation, confirmed: confirmed) { [editor] in
            try editor.adding(region, details: details, to: $0, explicitlyConfirmed: confirmed, now: now)
        }
    }

    /// Cambia lado, origen, revisión o nota. Si era o pasa a ser profesional, se confirma.
    public func update(_ id: RestrictionID, details: RestrictionDetails, confirmed: Bool = false) async -> Result {
        let professional = item(id)?.sourceKind == .professionalGuidance || details.source == .professionalGuidance
        return await apply(confirmation: professional ? presenter.professionalConfirmation() : nil, confirmed: confirmed) { [editor] in
            try editor.updating(id, details: details, in: $0, explicitlyConfirmed: confirmed)
        }
    }

    /// Evita un ejercicio concreto. En una profesional, se confirma.
    public func avoid(_ exercise: ExerciseID, in id: RestrictionID, confirmed: Bool = false) async -> Result {
        await apply(confirmation: professionalConfirmation(for: id), confirmed: confirmed) { [editor] in
            try editor.avoiding(exercise, in: id, restrictions: $0, explicitlyConfirmed: confirmed)
        }
    }

    /// Permite un ejercicio pese a la zona: sólo con origen profesional y siempre confirmando.
    public func allow(_ exercise: ExerciseID, in id: RestrictionID, confirmed: Bool = false) async -> Result {
        let name = names[exercise] ?? ""
        return await apply(confirmation: presenter.allowConfirmation(exercise: name), confirmed: confirmed) { [editor] in
            try editor.allowing(exercise, in: id, restrictions: $0, explicitlyConfirmed: confirmed)
        }
    }

    /// Quita un ejercicio de los evitados o los permitidos. En una profesional, se confirma.
    public func remove(_ exercise: ExerciseID, from id: RestrictionID, confirmed: Bool = false) async -> Result {
        await apply(confirmation: professionalConfirmation(for: id), confirmed: confirmed) { [editor] in
            try editor.removing(exercise, from: id, restrictions: $0, explicitlyConfirmed: confirmed)
        }
    }

    /// "Ya no me molesta": siempre se confirma (con origen profesional, el alta).
    public func resolve(_ id: RestrictionID, confirmed: Bool = false) async -> Result {
        guard let item = item(id) else { return .failed(presenter.message(for: .rejected(.notFound)) ?? "") }
        let now = clock()
        return await apply(confirmation: presenter.resolveConfirmation(for: item), confirmed: confirmed) { [editor] in
            try editor.resolving(id, in: $0, explicitlyConfirmed: confirmed, now: now)
        }
    }

    // MARK: - Helpers

    private func professionalConfirmation(for id: RestrictionID) -> RestrictionCopy? {
        item(id)?.sourceKind == .professionalGuidance ? presenter.professionalConfirmation() : nil
    }

    /// Pide la confirmación si hace falta; si no, aplica el cambio y traduce el resultado.
    private func apply(
        confirmation: RestrictionCopy?,
        confirmed: Bool,
        _ change: ([TrainingRestriction]) throws -> [TrainingRestriction]
    ) async -> Result {
        if let confirmation, !confirmed { return .needsConfirmation(confirmation) }
        guard !isSaving else { return .failed(presenter.message(for: .rejected(.notFound)) ?? "") }
        isSaving = true
        defer { isSaving = false }
        let outcome = await session.updateRestrictions(change)
        switch outcome {
        case .saved:
            return .done
        case .rejected(.alreadyInForce(let existing)):
            return .openExisting(existing)
        case .rejected(.needsExplicitConfirmation):
            return .needsConfirmation(confirmation ?? presenter.professionalConfirmation())
        case .notSaved, .planFailed, .rejected:
            return .failed(presenter.message(for: outcome) ?? "")
        }
    }
}
